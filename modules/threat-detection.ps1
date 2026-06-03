#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Advanced Threat Detection Engine v5.1 (Aegis Edition)
    Professional-grade detection using Sigma-inspired logic, signature verification, and behavioral analysis.
    Optimized for PowerShell 5.1 compatibility. No special characters.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Detection_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$VerboseLoggingToFile,
    [switch]$IncludeIntelFeeds,
    [switch]$IncludeHeuristics
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION & WHITELISTS
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "detection.log"
$DetectionReport = Join-Path $EvidencePath "detection_report.json"

# Professional Whitelist (Anti-False Positive)
$GlobalWhitelist = @{
    Paths = @(
        "$env:LOCALAPPDATA\BraveSoftware",
        "$env:LOCALAPPDATA\Programs\Greenshot",
        "$env:ProgramFiles",
        "$env:ProgramFiles(x86)",
        "C:\Windows\System32",
        "C:\Windows\SysWOW64"
    )
    Companies = @("Microsoft Corporation", "Google LLC", "Brave Software, Inc.", "Greenshot")
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','CRITICAL','DETECTED')]
        [string]$Level = 'INFO'
    )
    
    $Color = "Cyan"
    $Prefix = "[*]"
    
    if ($Level -eq 'SUCCESS') { 
        $Color = "Green"
        $Prefix = "[+]"
    }
    elseif ($Level -eq 'WARNING') { 
        $Color = "Yellow"
        $Prefix = "[!]"
    }
    elseif ($Level -eq 'FAILURE') { 
        $Color = "Red"
        $Prefix = "[-]"
    }
    elseif ($Level -eq 'CRITICAL') { 
        $Color = "Magenta"
        $Prefix = "[!!!]"
    }
    elseif ($Level -eq 'DETECTED') { 
        $Color = "Red"
        $Prefix = "[DETECTED]"
    }

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Write-Host "$Prefix $Message" -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "[$Timestamp] [$Level] $Message"
}

function Test-IsWhitelisted {
    param([string]$Path, [string]$Company)
    foreach ($WhitePath in $GlobalWhitelist.Paths) {
        if ($Path -like "$WhitePath*") { return $true }
    }
    foreach ($WhiteCompany in $GlobalWhitelist.Companies) {
        if ($Company -match $WhiteCompany) { return $true }
    }
    return $false
}

Write-Log "Starting Professional Threat Detection Engine v5.1 (Aegis Edition)..." -Level INFO

$Detections = @()
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BadHashes = @()

# ============================================================================
# PHASE 0: INTELLIGENCE & HEURISTICS INTEGRATION
# ============================================================================

if ($IncludeIntelFeeds) {
    Write-Log "Phase 0.1: Integrating Global Intelligence Feeds..." -Level INFO
    $IntelScript = Join-Path $ScriptRoot "intelligence.ps1"
    if (Test-Path $IntelScript) {
        & $IntelScript | Out-Null
        $IntelPath = "C:\ProgramData\SynthicSecurity\Intelligence"
        if (Test-Path $IntelPath) {
            Get-ChildItem $IntelPath -Filter "*.txt" | ForEach-Object {
                $BadHashes += Get-Content $_.FullName | Where-Object { $_ -notmatch "^#" }
            }
        }
    }
}

if ($IncludeHeuristics) {
    Write-Log "Phase 0.2: Integrating Behavioral Heuristics..." -Level INFO
    $HeuristicsScript = Join-Path $ScriptRoot "heuristics.ps1"
    if (Test-Path $HeuristicsScript) {
        $HResults = & $HeuristicsScript -EvidencePath (Join-Path $EvidencePath "Heuristics")
        if ($null -ne $HResults) { $Detections += $HResults }
    }
}

# ============================================================================
# PHASE 1: PERSISTENCE DETECTION (REGISTRY & WMI)
# ============================================================================

Write-Log "Phase 1: Deep Persistence Scanning..." -Level INFO

$RegistryTargets = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnceEx",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ShellServiceObjectDelayLoad"
)

foreach ($KeyPath in $RegistryTargets) {
    if (Test-Path $KeyPath) {
        $Props = Get-ItemProperty -Path $KeyPath -ErrorAction SilentlyContinue
        foreach ($Prop in $Props.PSObject.Properties) {
            $SkipProps = @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")
            if ($SkipProps -contains $Prop.Name) { continue }

            # Known-good Winlogon values that are part of standard Windows - never flag these
            $KnownGoodWinlogon = @(
                "VMApplet","AutoRestartShell","Background","CachedLogonsCount","DebugServerCommand",
                "DefaultDomainName","DefaultUserName","DisableCAD","ForceUnlockLogon","LegalNoticeCaption",
                "LegalNoticeText","PasswordExpiryWarning","PowerdownAfterShutdown","PredesktopTimeout",
                "ReportBootOk","SFCScan","ShutdownWithoutLogon","SynchronousGINAEnabled",
                "WinStationsDisabled","scremoveoption","AutoAdminLogon","DefaultPassword",
                "DCacheMinInterval","DCacheUpdate"
            )
            if ($KnownGoodWinlogon -contains $Prop.Name) { continue }
            
            $Value = $Prop.Value.ToString()
            if ($Value -match "powershell|cmd|mshta|cscript|wscript|temp|appdata|encodedcommand|bypass|-e ") {
                
                $FilePath = ($Value -split " ")[0].Replace('"', '')
                $IsSigned = $false
                if (Test-Path $FilePath) {
                    $Sig = Get-AuthenticodeSignature $FilePath -ErrorAction SilentlyContinue
                    if ($Sig.Status -eq "Valid") { $IsSigned = $true }
                }

                if (-not $IsSigned -and -not (Test-IsWhitelisted -Path $Value -Company "")) {
                    $Detections += [PSCustomObject]@{
                        Type = "Suspicious Registry Persistence"
                        Path = $KeyPath
                        ValueName = $Prop.Name
                        Value = $Value
                        Severity = "High"
                        Evidence = "Unsigned binary or suspicious command in persistence key"
                    }
                    Write-Log "DETECTED: Suspicious Registry Entry [$($Prop.Name)] in $KeyPath" -Level DETECTED
                }
            }
        }
    }
}

try {
    $WmiConsumers = Get-WmiObject -Namespace root\subscription -Class __EventConsumer
    foreach ($Consumer in $WmiConsumers) {
        if ($Consumer.Name -notmatch "BcastDVR|SCM Event Log Consumer") {
            $Detections += [PSCustomObject]@{
                Type = "WMI Event Consumer"
                Name = $Consumer.Name
                Class = $Consumer.__CLASS
                Severity = "Medium"
                Evidence = "Non-standard WMI event consumer detected"
            }
            Write-Log "DETECTED: Non-standard WMI Event Consumer [$($Consumer.Name)]" -Level WARNING
        }
    }
} catch {}

$StartupFolders = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
    "$env:AppData\Microsoft\Windows\Start Menu\Programs\StartUp"
)
foreach ($Folder in $StartupFolders) {
    if (Test-Path $Folder) {
        Get-ChildItem -Path $Folder -File | ForEach-Object {
            $Sig = Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue
            if ($Sig.Status -ne "Valid" -and -not (Test-IsWhitelisted -Path $_.FullName -Company "")) {
                $Detections += [PSCustomObject]@{
                    Type = "Suspicious Startup File"
                    Path = $_.FullName
                    Severity = "High"
                    Evidence = "Unsigned file in startup folder"
                }
                Write-Log "DETECTED: Unsigned file in startup folder: $($_.Name)" -Level DETECTED
            }
        }
    }
}

# ============================================================================
# PHASE 2: BEHAVIORAL ANALYSIS (EVENT LOGS)
# ============================================================================

Write-Log "Phase 2: Behavioral Analysis (Sigma-mapped Event Logs)..." -Level INFO

try {
    $PsLogs = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational'; ID=4104} -MaxEvents 200 -ErrorAction SilentlyContinue
    if ($null -ne $PsLogs) {
        foreach ($Log in $PsLogs) {
            if ($Log.Message -match "Net.WebClient|DownloadString|IEX|Invoke-Expression|EncodedCommand|FromBase64String|GzipStream|New-Object System.Net.Sockets.TCPClient") {
                $Detections += [PSCustomObject]@{
                    Type = "Malicious PowerShell Behavior"
                    EventID = 4104
                    Timestamp = $Log.TimeCreated
                    Message = $Log.Message.Substring(0, [Math]::Min(500, $Log.Message.Length))
                    Severity = "Critical"
                }
                Write-Log "DETECTED: Suspicious PowerShell Block at $($Log.TimeCreated)" -Level DETECTED
            }
        }
    }
} catch {}

# ============================================================================
# PHASE 3: PROCESS & SIGNATURE INTEGRITY + INTEL MATCHING
# ============================================================================

Write-Log "Phase 3: Process Integrity & Intelligence Matching..." -Level INFO

$Processes = Get-Process | Where-Object { $_.Path }
foreach ($Proc in $Processes) {
    $ProcPath = $Proc.Path
    $ProcHash = ""
    try { $ProcHash = (Get-FileHash $ProcPath -Algorithm MD5).Hash } catch {}

    if ($null -ne $BadHashes -and $BadHashes -contains $ProcHash) {
        $Detections += [PSCustomObject]@{
            Type = "Known Malicious Binary (IOC Match)"
            ProcessName = $Proc.ProcessName
            Path = $ProcPath
            Hash = $ProcHash
            Severity = "Critical"
            Evidence = "Binary MD5 matches known malware in open-source intelligence feeds"
        }
        Write-Log "CRITICAL DETECTED: Known malware [$($Proc.ProcessName)] running! (IOC Match)" -Level CRITICAL
    }

    if ($ProcPath -match "Temp|AppData|Downloads|Public") {
        $Company = ""
        try { $Company = $Proc.Company } catch {}
        
        if (-not (Test-IsWhitelisted -Path $ProcPath -Company $Company)) {
            $Sig = Get-AuthenticodeSignature $ProcPath -ErrorAction SilentlyContinue
            if ($Sig.Status -ne "Valid") {
                $Detections += [PSCustomObject]@{
                    Type = "Unsigned Process in Suspicious Path"
                    ProcessName = $Proc.ProcessName
                    Path = $ProcPath
                    Id = $Proc.Id
                    Severity = "High"
                    Evidence = "Unsigned binary running from user-writable directory"
                }
                Write-Log "DETECTED: Unsigned process [$($Proc.ProcessName)] in $ProcPath" -Level DETECTED
            }
        }
    }
}

# ============================================================================
# REPORTING
# ============================================================================

$Report = @{
    ScanTime = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    TotalDetections = $Detections.Count
    Detections = $Detections
}
$Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $DetectionReport -Encoding UTF8 -Force

Write-Log "Detection Scan Complete. Found $($Detections.Count) potential threats." -Level SUCCESS

if ($null -eq $Detections) { return @() }
return $Detections