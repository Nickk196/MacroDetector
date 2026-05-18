#Requires -Version 5.1
<#
.SYNOPSIS
    Instant Mouse Macro & File Deletion Monitor
.DESCRIPTION
    Ultra-fast file system monitor with zero-delay detection, sound alerts, and process tracking.
.NOTES
    Press Ctrl+C to stop monitoring.
#>

# ─── Configuration ────────────────────────────────────────────────────────────
# Safely get the script directory (fixes log being created at C:\ when pasting directly)
 $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
 $LogFile = Join-Path -Path $ScriptDir -ChildPath "MacroMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Session Statistics
 $Script:Stats = @{
    Deleted = 0
    Created = 0
    Changed = 0
    Macros  = 0
    Filtered = 0
}

# Pre-compiled regex patterns
 $Script:RxMacroTiming = [regex]::new('"delay"\s*:\s*\d+', 'Compiled')
 $Script:RxRepeat      = [regex]::new('"repeat"', 'Compiled')
 $Script:RxSequence    = [regex]::new('"sequence"', 'Compiled')
 $Script:RxOnboard     = [regex]::new('"onboard"', 'Compiled')
 $Script:RxDevice      = [regex]::new('"device"', 'Compiled')
 $Script:RxEngine      = [regex]::new('"engine"', 'Compiled')

# ─── NOISE FILTERS ────────────────────────────────────────────────────────────
 $Script:IgnorePaths = @(
    "\sentry\", "\User Data\", "\Cache\", "\GPUCache\", "\Code Cache\",
    "\Session Storage\", "\Local Storage\", "\IndexedDB\", "\Dictionaries\",
    "\Crashpad\", "\GrpcChann", "\logs\", "\Log\", "\CrashReports\"
)

function Test-IsNoise {
    param([string]$Path)
    $upperPath = $Path.ToUpper()
    foreach ($ignore in $Script:IgnorePaths) {
        if ($upperPath.Contains($ignore.ToUpper())) { return $true }
    }
    return $false
}

 $Script:FileCache = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()

# ─── Software Definitions (Cleaned Up Paths) ──────────────────────────────────
 $SoftwareProfiles = @(
    @{
        Name         = "Logitech G HUB"
        Paths        = @("$env:LOCALAPPDATA\LGHUB", "$env:APPDATA\LGHUB", "$env:PROGRAMDATA\LGHUB")
        Extensions   = @("*.json")
        Parser       = "Parse-LGHUB"
        MacroKeys    = @("macros", "assignments", "commands")
        ProcessNames = @("LGHUB", "LGHUB Agent")
    },
    @{
        Name         = "Logitech Gaming Software (Legacy)"
        Paths        = @("$env:APPDATA\Logitech\Logitech Gaming Software", "$env:LOCALAPPDATA\Logitech")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "assignment", "script")
        ProcessNames = @("LCore")
    },
    @{
        Name         = "Razer Synapse 3"
        Paths        = @(
            "$env:APPDATA\Razer\Synapse3",
            "$env:APPDATA\Razer\Synapse",
            "$env:LOCALAPPDATA\Razer\Synapse3",
            "$env:PROGRAMDATA\Razer\Synapse3"
        )
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Razer"
        MacroKeys    = @("Macro", "Action", "Script", "macro")
        ProcessNames = @("Razer Synapse", "RazerCentralService", "RazerStats")
    },
    @{
        Name         = "Razer Synapse 2 (Legacy)"
        Paths        = @("$env:APPDATA\Razer\Synapse2")
        Extensions   = @("*.json", "*.xml", "*.dat")
        Parser       = "Parse-Razer"
        MacroKeys    = @("Macro", "Action", "Script", "macro")
        ProcessNames = @("Razer Synapse", "RazerCentralService")
    },
    @{
        Name         = "SteelSeries GG"
        Paths        = @("$env:APPDATA\SteelSeries\SteelSeries GG", "$env:LOCALAPPDATA\SteelSeries\SteelSeries GG", "$env:LOCALAPPDATA\SteelSeries")
        Extensions   = @("*.json")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesGG", "SteelSeriesEngine")
    },
    @{
        Name         = "SteelSeries Engine 3 (Legacy)"
        Paths        = @("$env:APPDATA\SteelSeries Engine 3")
        Extensions   = @("*.json")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesEngine3")
    },
    @{
        Name         = "SteelSeries Engine 2 (Legacy)"
        Paths        = @("$env:APPDATA\SteelSeries Engine 2")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-SteelSeries"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("SteelSeriesEngine2")
    },
    @{
        Name         = "Corsair iCUE"
        Paths        = @("$env:APPDATA\Corsair\CUE5", "$env:APPDATA\Corsair\CUE4", "$env:APPDATA\Corsair", "$env:LOCALAPPDATA\Corsair")
        Extensions   = @("*.cueprofile", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "command")
        ProcessNames = @("iCUE", "CorsairService")
    },
    @{
        Name         = "Corsair CUE 3 (Legacy)"
        Paths        = @("$env:APPDATA\Corsair\CUE3")
        Extensions   = @("*.cueprofile", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "command")
        ProcessNames = @("Cue")
    },
    @{
        Name         = "ASUS Armoury Crate"
        Paths        = @("$env:LOCALAPPDATA\ASUS\ArmouryCrate", "$env:LOCALAPPDATA\ASUS\AURA", "$env:APPDATA\ASUS\ArmouryCrate", "$env:PROGRAMDATA\ASUS\ArmouryCrate")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "key", "action")
        ProcessNames = @("ArmouryCrate", "ASUSOptimization")
    },
    @{
        Name         = "HyperX NGENUITY"
        Paths        = @("$env:LOCALAPPDATA\HyperX NGENUITY", "$env:APPDATA\HyperX NGENUITY", "$env:LOCALAPPDATA\HyperX")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "action", "binding")
        ProcessNames = @("NGENUITY")
    },
    @{
        Name         = "Wooting"
        Paths        = @("$env:LOCALAPPDATA\Wooting", "$env:APPDATA\Wooting")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "analog", "action")
        ProcessNames = @("WootingUACHelper", "Wooting")
    },
    @{
        Name         = "Glorious CORE"
        Paths        = @("$env:LOCALAPPDATA\Glorious\Glorious CORE", "$env:APPDATA\Glorious", "$env:LOCALAPPDATA\Glorious")
        Extensions   = @("*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "key", "assignment", "sequence")
        ProcessNames = @("GloriousCORE")
    },
    @{
        Name         = "Bloody / A4Tech"
        Paths        = @("$env:LOCALAPPDATA\Bloody", "$env:PROGRAMDATA\Bloody", "$env:LOCALAPPDATA\A4Tech", "$env:PROGRAMDATA\A4Tech")
        Extensions   = @("*.dat", "*.json", "*.xml", "*.bin")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "Macro", "script", "Script", "shot")
        ProcessNames = @("Bloody7", "A4Tech")
    },
    @{
        Name         = "Cooler Master MasterPlus+"
        Paths        = @("$env:LOCALAPPDATA\Cooler Master", "$env:APPDATA\Cooler Master")
        Extensions   = @("*.json", "*.xml")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "assignment", "action")
        ProcessNames = @("MasterPlus")
    },
    @{
        Name         = "Roccat Swarm / Titan"
        Paths        = @("$env:APPDATA\Roccat", "$env:LOCALAPPDATA\Roccat")
        Extensions   = @("*.xml", "*.json")
        Parser       = "Parse-Generic"
        MacroKeys    = @("macro", "Macro", "sequence", "command")
        ProcessNames = @("Roccat Swarm", "Titan")
    }
)

# ─── Parsers ──────────────────────────────────────────────────────────────────
function Parse-Generic {
    param([string]$FilePath, [string[]]$MacroKeys)
    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked/unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    if ($hits.Count -gt 0) { return ,$hits }
    return @()
}

function Parse-LGHUB {
    param([string]$FilePath, [string[]]$MacroKeys)
    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked/unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    try {
        $json = $text | ConvertFrom-Json -ErrorAction Stop
        if ($json.macros) {
            $hits.Add("  [!] $($json.macros.Count) macro(s) defined")
            foreach ($m in $json.macros) {
                if ($m.name) { $hits.Add("      - '$($m.name)'") }
            }
        }
        if ($json.assignments) { $hits.Add("  [!] $($json.assignments.Count) button assignments") }
    } catch {}
    return ,$hits
}

function Parse-Razer {
    param([string]$FilePath, [string[]]$MacroKeys)
    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked/unreadable") }
    if ([System.IO.Path]::GetExtension($FilePath) -eq ".xml") {
        $hits = [System.Collections.Generic.List[string]]::new()
        try {
            [xml]$xml = $text
            $nodes = $xml.SelectNodes("//Macro")
            if ($nodes.Count -gt 0) {
                $hits.Add("  [!] $($nodes.Count) Razer macro(s)")
                foreach ($n in $nodes) { $hits.Add("      - $($n.Name): $($n.ChildNodes.Count) steps") }
            }
        } catch {}
        if ($hits.Count -eq 0) { return @() }
        return ,$hits
    }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    return ,$hits
}

function Parse-SteelSeries {
    param([string]$FilePath, [string[]]$MacroKeys)
    $text = Get-FileContentFast $FilePath
    if (-not $text) { return @("  [~] File locked/unreadable") }
    $hits = Test-MacroStringsFast -Text $text -Keys $MacroKeys
    if ($Script:RxDevice.IsMatch($text)) { $hits.Add("  [i] Device profile") }
    if ($Script:RxEngine.IsMatch($text)) { $hits.Add("  [i] Engine-linked") }
    return ,$hits
}

# ─── Map Parsers to ScriptBlocks ──────────────────────────────────────────────
 $Script:ParserMap = @{
    "Parse-Generic"      = ${function:Parse-Generic}
    "Parse-LGHUB"        = ${function:Parse-LGHUB}
    "Parse-Razer"        = ${function:Parse-Razer}
    "Parse-SteelSeries"  = ${function:Parse-SteelSeries}
}
foreach ($sw in $SoftwareProfiles) { $sw.ParserBlock = $Script:ParserMap[$sw.Parser] }

# ─── Native .NET MD5 ──────────────────────────────────────────────────────────
function Get-MD5Fast {
    param([string]$Path)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = $md5.ComputeHash($bytes)
        $md5.Dispose()
        return [System.BitConverter]::ToString($hash).Replace("-", "").ToUpper()
    } catch { return $null }
}

# ─── Fast Helpers ─────────────────────────────────────────────────────────────
function Get-FileContentFast {
    param([string]$Path)
    try { return [System.IO.File]::ReadAllText($Path) }
    catch { return $null }
}

function Test-MacroStringsFast {
    param([string]$Text, [string[]]$Keys)
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $Keys) {
        if ($Text.Contains($k)) { $hits.Add("  [!] Key: '$k'") }
    }
    if ($Script:RxMacroTiming.IsMatch($Text)) { $hits.Add("  [!] Timed delays detected") }
    if ($Script:RxRepeat.IsMatch($text))      { $hits.Add("  [!] Repeat/loop detected") }
    if ($Script:RxSequence.IsMatch($text))    { $hits.Add("  [!] Key sequence detected") }
    if ($Script:RxOnboard.IsMatch($text))     { $hits.Add("  [!] Onboard memory flag") }
    return ,$hits
}

function Get-FileSizeString {
    param([long]$Bytes)
    if ($Bytes -gt 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -gt 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-RunningSoftwareProcess {
    param([string[]]$Names)
    foreach ($p in $Names) {
        if (Get-Process -Name $p -ErrorAction SilentlyContinue) { return $p }
    }
    return $null
}

function Invoke-AlertSound {
    param([string]$Type = "Info")
    try {
        if ($Type -eq "Critical") { [System.Media.SystemSounds]::Hand.Play() }
        else { [System.Media.SystemSounds]::Asterisk.Play() }
    } catch {}
}

function Update-WindowTitle {
    $host.UI.RawUI.WindowTitle = "Meow!! | Del:$($Script:Stats.Deleted) Mod:$($Script:Stats.Changed) Macros:$($Script:Stats.Macros) Filtered:$($Script:Stats.Filtered)"
}

# ─── Ultra-Fast Logging ───────────────────────────────────────────────────────
 $Script:LogLock = [System.Threading.SpinLock]::new()
function Write-Log {
    param([string]$Message, [string]$Level = "INFO", [ConsoleColor]$Color = [ConsoleColor]::White)
    $ts = [datetime]::Now.ToString("HH:mm:ss.fff")
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    $taken = $false
    try {
        $Script:LogLock.Enter($taken)
        [System.IO.File]::AppendAllText($LogFile, "$line`r`n")
    } finally { if ($taken) { $Script:LogLock.Exit() } }
}

# ─── Fast Startup Scan ───────────────────────────────────────────────────────
function Invoke-FastSnapshot {
    param($SoftwareList)
    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($sw in $SoftwareList) {
        foreach ($bp in $sw.Paths) {
            if (-not (Test-Path $bp)) { continue }
            foreach ($ext in $sw.Extensions) {
                try {
                    $files = [System.IO.Directory]::GetFiles($bp, $ext, [System.IO.SearchOption]::AllDirectories)
                    foreach ($f in $files) {
                        if (-not (Test-IsNoise -Path $f)) {
                            $results.Add("SCAN|$($sw.Name)|$f")
                        }
                    }
                } catch {}
            }
        }
    }
    return ,$results
}

# ─── Fast File Available Check ───────────────────────────────────────────────
function Wait-FileAvailable {
    param([string]$Path, [int]$MaxMs = 50)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $MaxMs) {
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $fs.Close()
            return $true
        } catch { [System.Threading.Thread]::Sleep(1) }
    }
    return $false
}

# ─── Build Initial Cache ─────────────────────────────────────────────────────
function Build-InitialCache {
    param($SoftwareList)
    foreach ($sw in $SoftwareList) {
        foreach ($bp in $sw.Paths) {
            if (-not (Test-Path $bp)) { continue }
            foreach ($ext in $sw.Extensions) {
                try {
                    $files = [System.IO.Directory]::GetFiles($bp, $ext, [System.IO.SearchOption]::AllDirectories)
                    foreach ($f in $files) {
                        if (Test-IsNoise -Path $f) { continue }
                        $hash = Get-MD5Fast -Path $f
                        if ($hash) {
                            $size = (New-Object System.IO.FileInfo($f)).Length
                            $null = $Script:FileCache.TryAdd($f.ToUpper(), "$hash|$size")
                        }
                    }
                } catch {}
            }
        }
    }
}

# ─── Instant Event Handler ───────────────────────────────────────────────────
function New-InstantHandler {
    param($Software)

    return {
        $filePath    = $Event.SourceEventArgs.FullPath
        $changeType  = $Event.SourceEventArgs.ChangeType
        $sw          = $Event.MessageData.SW
        $logFile     = $Event.MessageData.Log
        $parserBlock = $Event.MessageData.ParserBlock
        $ts          = [datetime]::Now.ToString("HH:mm:ss.fff")

        if (Test-IsNoise -Path $filePath) {
            $Script:Stats.Filtered++
            return
        }

        if ($changeType -eq "Deleted") {
            $Script:Stats.Deleted++
            
            $oldVal = $null
            $sizeStr = "Unknown"
            if ($Script:FileCache.TryRemove($filePath.ToUpper(), [ref]$oldVal)) {
                if ($oldVal -match '\|(\d+)$') {
                    $sizeStr = Get-FileSizeString -Bytes ([long]$Matches[1])
                }
            }

            $msg = "[$ts] [DELETED] [$($sw.Name)] $filePath (Size: $sizeStr)"
            Write-Host $msg -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$msg`r`n")
            
            $proc = Get-RunningSoftwareProcess -Names $sw.ProcessNames
            $procMsg = if ($proc) { "    ⚠ Process '$proc.exe' is ACTIVELY RUNNING!" } else { "    ⚠ Software process is NOT running." }
            Write-Host $procMsg -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$procMsg`r`n")

            $warn = "    ⚠ EVIDENCE REMOVAL — Macro pushed to onboard memory?"
            Write-Host $warn -ForegroundColor Red
            [System.IO.File]::AppendAllText($logFile, "$warn`r`n")

            Invoke-AlertSound -Type "Critical"
            Update-WindowTitle
            return
        }

        if (-not [System.IO.File]::Exists($filePath)) { return }

        if ($changeType -eq "Created") { $Script:Stats.Created++ }
        else { $Script:Stats.Changed++ }

        $color = if ($changeType -eq "Created") { "Green" } else { "Magenta" }
        $msg = "[$ts] [$changeType] [$($sw.Name)] $filePath"
        Write-Host $msg -ForegroundColor $color
        [System.IO.File]::AppendAllText($logFile, "$msg`r`n")

        if (-not (Wait-FileAvailable -Path $filePath -MaxMs 50)) { Update-WindowTitle; return }

        try {
            $newHash = Get-MD5Fast -Path $filePath
            $fileSize = (New-Object System.IO.FileInfo($filePath)).Length
            if (-not $newHash) { Update-WindowTitle; return }
            
            $oldVal = $null
            $oldHash = $null
            if ($Script:FileCache.TryGetValue($filePath.ToUpper(), [ref]$oldVal)) {
                $oldHash = $oldVal -split '\|', 2 | Select-Object -First 1
                if ($oldHash -eq $newHash) { return }
            }
            $null = $Script:FileCache.AddOrUpdate($filePath.ToUpper(), "$newHash|$fileSize", { "$newHash|$fileSize" })
        } catch { Update-WindowTitle; return }

        try {
            if ($null -ne $parserBlock) {
                $results = & $parserBlock -FilePath $filePath -MacroKeys $sw.MacroKeys
                if ($results.Count -gt 0) {
                    $Script:Stats.Macros++
                    Invoke-AlertSound -Type "Info"
                    
                    $proc = Get-RunningSoftwareProcess -Names $sw.ProcessNames
                    if ($proc) {
                        $pMsg = "    💻 Software process '$proc.exe' is running."
                        Write-Host $pMsg -ForegroundColor DarkMagenta
                        [System.IO.File]::AppendAllText($logFile, "$pMsg`r`n")
                    }

                    $m = "    🔥 MACROS DETECTED:"
                    Write-Host $m -ForegroundColor Yellow
                    [System.IO.File]::AppendAllText($logFile, "$m`r`n")
                    foreach ($r in $results) {
                        Write-Host $r -ForegroundColor Yellow
                        [System.IO.File]::AppendAllText($logFile, "$r`r`n")
                    }
                }
            }
        } catch {}
        
        Update-WindowTitle
    }
}

# ─── Create Optimized Watcher ─────────────────────────────────────────────────
function New-FastWatcher {
    param([string]$Path, [string]$Filter, $Software)

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path                  = $Path
    $watcher.Filter                = $Filter
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter          = [System.IO.NotifyFilters]::FileName `
                                   -bor [System.IO.NotifyFilters]::LastWrite `
                                   -bor [System.IO.NotifyFilters]::Size
    $watcher.InternalBufferSize    = 65536
    $watcher.EnableRaisingEvents   = $true

    $msgData = @{ SW = $Software; Log = $LogFile; ParserBlock = $Software.ParserBlock }
    $handler = New-InstantHandler -Software $Software

    Register-ObjectEvent -InputObject $watcher -EventName "Deleted" -Action $handler -MessageData $msgData | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $handler -MessageData $msgData | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $handler -MessageData $msgData | Out-Null

    return $watcher
}

# ═══════════════════════════════════════════════════════════════════════════════
# ─── MAIN ─────────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
Clear-Host
 $host.UI.RawUI.WindowTitle = "Meow!! 🐾 Initializing..."
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║                     Meow!! 🐾                      ║" -ForegroundColor Magenta
Write-Host "║          Macro Monitor — Zero-Delay               ║" -ForegroundColor Magenta
Write-Host "║       made by Nick discord : mecz.exe             ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host "Log: $LogFile`n" -ForegroundColor DarkGray

# Phase 1: Path discovery
Write-Host "[*] Probing paths..." -ForegroundColor Cyan
 $foundAnySoftware = $false
foreach ($sw in $SoftwareProfiles) {
    $livePaths = @()
    foreach ($p in $sw.Paths) {
        if (Test-Path $p) {
            $livePaths += $p
            Write-Host "  [+] $($sw.Name) -> $p" -ForegroundColor DarkGreen
        }
    }
    if ($livePaths.Count -gt 0) {
        $sw._LivePaths = $livePaths
        $foundAnySoftware = $true
    } else {
        Write-Host "  [ ] $($sw.Name) — no paths found" -ForegroundColor DarkGray
        $sw._LivePaths = @()
    }
}
Write-Host ""

if (-not $foundAnySoftware) {
    Write-Log "No mouse software directories found. Exiting." -Level "WARN" -Color Yellow
    Start-Sleep -Seconds 3
    exit
}

# Phase 2 & 3: Fast scan & cache
Write-Host "[*] Scanning files & building cache..." -ForegroundColor Cyan
 $scanResults = Invoke-FastSnapshot -SoftwareList $SoftwareProfiles
Build-InitialCache -SoftwareList $SoftwareProfiles
Write-Host "[*] Found $($scanResults.Count) relevant file(s)`n" -ForegroundColor Cyan

# Phase 4: Initial macro scan
Write-Host "[*] Scanning for existing macros..." -ForegroundColor DarkCyan
 $macroFoundCount = 0
foreach ($entry in $scanResults) {
    $parts = $entry -split '\|', 3
    if ($parts.Count -lt 3) { continue }
    $swName   = $parts[1]
    $filePath = $parts[2]
    $sw = $SoftwareProfiles | Where-Object { $_.Name -eq $swName } | Select-Object -First 1
    if (-not $sw -or $null -eq $sw.ParserBlock) { continue }

    $results = & $sw.ParserBlock -FilePath $filePath -MacroKeys $sw.MacroKeys
    if ($results.Count -gt 0) {
        $macroFoundCount++
        $Script:Stats.Macros++
        Write-Host "  [$swName] " -ForegroundColor White -NoNewline
        Write-Host "$(Split-Path $filePath -Leaf)" -ForegroundColor Yellow -NoNewline
        Write-Host " — MACROS FOUND" -ForegroundColor Yellow
        foreach ($r in $results) { Write-Host $r -ForegroundColor DarkYellow }
    }
}
if ($macroFoundCount -eq 0) { Write-Host "  No active macros found." -ForegroundColor DarkGray }

Write-Host ""
Write-Host "[*] Scan complete." -ForegroundColor Magenta
Write-Host ""

# Phase 5: Watchers
 $activeWatchers = @()
 $watcherCreated = $false

foreach ($sw in $SoftwareProfiles) {
    if ($sw._LivePaths.Count -eq 0) { continue }
    Write-Host "  [+] $($sw.Name)" -ForegroundColor Green
    foreach ($path in $sw._LivePaths) {
        foreach ($ext in $sw.Extensions) {
            $w = New-FastWatcher -Path $path -Filter $ext -Software $sw
            $activeWatchers += $w
            Write-Host "      -> $ext @ $path" -ForegroundColor DarkGray
        }
    }
    $watcherCreated = $true
}
Write-Host ""

if (-not $watcherCreated) { exit }

Write-Host "Meow!! 🐾 Press Ctrl+C to stop monitoring.`n" -ForegroundColor Magenta
Update-WindowTitle

try {
    while ($true) { [System.Threading.Thread]::Sleep(50) }
} finally {
    foreach ($w in $activeWatchers) {
        try { $w.EnableRaisingEvents = $false; $w.Dispose() } catch {}
    }
    Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue
    
    $host.UI.RawUI.WindowTitle = "Meow!! 🐾 Stopped."
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║                   Session Ended                     ║" -ForegroundColor Magenta
    Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  Files Created  : $($Script:Stats.Created.ToString().PadLeft(5))                          ║" -ForegroundColor Magenta
    Write-Host "║  Files Modified : $($Script:Stats.Changed.ToString().PadLeft(5))                          ║" -ForegroundColor Magenta
    Write-Host "║  Files Deleted  : $($Script:Stats.Deleted.ToString().PadLeft(5))                          ║" -ForegroundColor Red
    Write-Host "║  Macros Found   : $($Script:Stats.Macros.ToString().PadLeft(5))                          ║" -ForegroundColor Yellow
    Write-Host "║  Noise Filtered : $($Script:Stats.Filtered.ToString().PadLeft(5))                          ║" -ForegroundColor DarkGray
    Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  made by Nick discord : mecz.exe             ║" -ForegroundColor Magenta
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Log "Session Ended. Log saved to: $LogFile" -Color Magenta
}
