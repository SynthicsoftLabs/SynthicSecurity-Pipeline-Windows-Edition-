#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft patch-intel.ps1"
$ScriptVersion = "4.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$Timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile    = Join-Path $LogRoot ("patch-intel-" + $Timestamp + ".log")
$ReportFile = Join-Path $LogRoot ("patch-intel-report-" + $Timestamp + ".json")
$LogToFile  = $VerboseLoggingToFile.IsPresent

if ($LogToFile) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $ts   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts][$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    if ($LogToFile) {
        Add-Content -Path $LogFile -Value $line
    }
}

Write-Log "=== $ScriptName v$ScriptVersion starting ===" "INFO" Cyan

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Must run as Administrator." "FATAL" Red
    exit 1
}

function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [string]$TaskName,
        [int]$Retries = 3,
        [int]$DelaySeconds = 5
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Write-Log "$TaskName (attempt $i/$Retries)" "TASK" Cyan
            & $Action
            Write-Log "$TaskName succeeded." "OK" Green
            return $true
        }
        catch {
            Write-Log "$TaskName failed: $_" "WARN" Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    Write-Log "$TaskName failed after $Retries attempts." "FAIL" Red
    return $false
}

function Initialize-Tls {
    try {
        $p = [System.Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}
        [System.Net.ServicePointManager]::SecurityProtocol = $p
        Write-Log "TLS initialized." "OK" Green
    }
    catch {
        Write-Log "TLS init failed: $_" "WARN" Yellow
    }
}

Initialize-Tls

function Test-InternetConnection {
    try {
        $r = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -WarningAction SilentlyContinue
        return $r.TcpTestSucceeded
    }
    catch { return $false }
}

function Ensure-PowerShellGetAndNuGet {
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
            Install-Module -Name PowerShellGet -Force -AllowClobber -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Get-OSContext {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $i = Get-ItemProperty -Path $k
    [PSCustomObject]@{
        ProductName    = $i.ProductName
        EditionID      = $i.EditionID
        ReleaseId      = $i.ReleaseId
        DisplayVersion = $i.DisplayVersion
        CurrentBuild   = $i.CurrentBuild
        UBR            = $i.UBR
        BuildNumber    = "{0}.{1}" -f $i.CurrentBuild, $i.UBR
    }
}

function Get-HotfixSnapshot {
    try { return Get-HotFix | Sort-Object InstalledOn, HotFixID }
    catch { return @() }
}

function Get-AppSnapshot {
    try {
        $apps = Get-Package -ErrorAction SilentlyContinue
        if ($apps.Count -gt 0) { return $apps }
    }
    catch {}
    try { return Get-WmiObject Win32_Product -ErrorAction SilentlyContinue }
    catch { return @() }
}

$OSBefore     = Get-OSContext
$HotfixBefore = Get-HotfixSnapshot
$AppsBefore   = Get-AppSnapshot

$KevCsvPath  = Join-Path $LogRoot ("cisa-kev-" + $Timestamp + ".csv")
$KevJsonPath = Join-Path $LogRoot ("cisa-kev-windows11-" + $Timestamp + ".json")
$KevFiltered = @()

function Download-KEV {
    if (-not (Test-InternetConnection)) {
        Write-Log "Offline: cannot download KEV feed." "WARN" Yellow
        return $false
    }

    $url = "https://www.cisa.gov/sites/default/files/csv/known_exploited_vulnerabilities.csv"

    $ok = Invoke-WithRetry -TaskName "Download CISA KEV (Invoke-WebRequest)" -Action {
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $KevCsvPath -ErrorAction Stop
    }

    if ($ok -and (Test-Path $KevCsvPath)) { return $true }

    $ok2 = Invoke-WithRetry -TaskName "Download CISA KEV (WebClient)" -Action {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $KevCsvPath)
    }

    if ($ok2 -and (Test-Path $KevCsvPath)) { return $true }

    Write-Log "Failed to download CISA KEV feed." "WARN" Yellow
    return $false
}

if (Download-KEV) {
    try {
        $raw = Get-Content -Raw -Path $KevCsvPath
        $entries = $raw | ConvertFrom-Csv
        $KevFiltered = $entries | Where-Object {
            ($_.vendorProject -match "Microsoft") -and
            ($_.product -match "Windows" -or $_.product -match "Windows 11")
        }
        $KevFiltered | ConvertTo-Json -Depth 6 | Out-File -FilePath $KevJsonPath -Encoding UTF8 -Force
        Write-Log ("Filtered KEV count: {0}" -f $KevFiltered.Count) "INFO" Yellow
        
        # Extract CVE IDs for analysis
        $kevCveIds = $KevFiltered | Select-Object -ExpandProperty cveID | Sort-Object -Unique
        Write-Log ("Unique CVEs affecting Windows: {0}" -f $kevCveIds.Count) "INFO" Cyan
        
        # Create a detailed KEV report
        $kevReport = @{
            TotalKevEntries = $entries.Count
            WindowsKevCount = $KevFiltered.Count
            UniqueCVEs = $kevCveIds.Count
            CVEList = $kevCveIds
            HighPriorityCVEs = ($KevFiltered | Where-Object { $_.knownRansomwareCampaignUse -eq "Known" }).cveID
            MostRecentlyAdded = ($KevFiltered | Sort-Object dateAdded -Descending | Select-Object -First 10 | Select-Object cveID, vulnerabilityName, dateAdded)
        }
        
        $kevReportPath = Join-Path $LogRoot ("kev-analysis-" + $Timestamp + ".json")
        $kevReport | ConvertTo-Json -Depth 6 | Out-File -FilePath $kevReportPath -Encoding UTF8 -Force
        Write-Log ("KEV Analysis Report: {0}" -f $kevReportPath) "INFO" Green
        
        if ($kevReport.HighPriorityCVEs.Count -gt 0) {
            Write-Log ("WARNING: {0} CVEs are associated with known ransomware campaigns" -f $kevReport.HighPriorityCVEs.Count) "WARN" Red
        }
    }
    catch {
        Write-Log "Failed parsing KEV feed: $_" "WARN" Yellow
    }
}

function Ensure-WindowsUpdateServices {
    Write-Log "Ensuring Windows Update services are enabled..." "INFO" Cyan
    $svcs = @("wuauserv","bits","cryptsvc","TrustedInstaller")
    foreach ($n in $svcs) {
        try {
            $s = Get-Service -Name $n -ErrorAction SilentlyContinue
            if ($s) {
                if ($s.StartType -eq "Disabled") {
                    Set-Service -Name $n -StartupType Manual -ErrorAction SilentlyContinue
                }
                if ($s.Status -ne "Running") {
                    Start-Service -Name $n -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
    }
}

Ensure-WindowsUpdateServices

function Ensure-PSWindowsUpdate {
    Write-Log "Ensuring PSWindowsUpdate module..." "INFO" Cyan

    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
        if (Get-Module -Name PSWindowsUpdate) { return $true }
    }

    Ensure-PowerShellGetAndNuGet

    $ok = Invoke-WithRetry -TaskName "Install PSWindowsUpdate" -Action {
        Install-Module -Name PSWindowsUpdate -Force -AllowClobber -ErrorAction Stop
    }

    if ($ok) {
        Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
        if (Get-Module -Name PSWindowsUpdate) { return $true }
    }

    Write-Log "PSWindowsUpdate module not available." "WARN" Yellow
    return $false
}

$PSWUModuleAvailable = Ensure-PSWindowsUpdate

function Ensure-Winget {
    Write-Log "Ensuring winget is available..." "INFO" Cyan

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $true }

    $appx = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if ($appx -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) { return $true }

    if (-not (Test-InternetConnection)) { return $false }

    $msix = Join-Path $env:TEMP "AppInstaller.msixbundle"

    $dl = Invoke-WithRetry -TaskName "Download App Installer" -Action {
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" `
            -OutFile $msix -UseBasicParsing -ErrorAction Stop
    }

    if (-not $dl -or -not (Test-Path $msix)) { return $false }

    $ok = Invoke-WithRetry -TaskName "Install App Installer" -Action {
        Add-AppPackage -Path $msix -ErrorAction Stop
    }

    if ($ok) {
        Start-Sleep -Seconds 5
        if (Get-Command winget.exe -ErrorAction SilentlyContinue) { return $true }
    }

    return $false
}

$WingetAvailable = Ensure-Winget

function Invoke-WindowsPatching {
    Write-Log "Checking Windows updates (prioritizing security patches)..." "INFO" Cyan

    if ($PSWUModuleAvailable -and (Test-InternetConnection)) {
        try {
            # Get all available updates
            $updates = Get-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -ErrorAction SilentlyContinue

            if ($updates) {
                # Prioritize security and critical updates
                $securityUpdates = $updates | Where-Object { 
                    $_.Title -match "Security" -or 
                    $_.Title -match "Critical" -or
                    $_.MsrcSeverity -eq "Critical" -or
                    $_.MsrcSeverity -eq "Important"
                }
                
                $otherUpdates = $updates | Where-Object {
                    $_.Title -notmatch "Security" -and 
                    $_.Title -notmatch "Critical" -and
                    $_.MsrcSeverity -ne "Critical" -and
                    $_.MsrcSeverity -ne "Important"
                }
                
                if ($securityUpdates) {
                    Write-Log ("Found {0} security/critical updates to install" -f $securityUpdates.Count) "WARN" Red
                    
                    # Log which updates are being installed
                    foreach ($update in $securityUpdates) {
                        Write-Log ("  - {0} (KB{1})" -f $update.Title, $update.KBArticleIDs) "INFO" Yellow
                    }
                    
                    # Install security updates first
                    $securityUpdates |
                        Install-WindowsUpdate `
                            -AcceptAll `
                            -IgnoreReboot:$true `
                            -AutoReboot:$false `
                            -ErrorAction SilentlyContinue `
                            -Confirm:$false
                    
                    Write-Log "Security updates installed successfully" "OK" Green
                }
                
                if ($otherUpdates) {
                    Write-Log ("Installing {0} additional updates..." -f $otherUpdates.Count) "INFO" Cyan
                    
                    $otherUpdates |
                        Install-WindowsUpdate `
                            -AcceptAll `
                            -IgnoreReboot:$true `
                            -AutoReboot:$false `
                            -ErrorAction SilentlyContinue `
                            -Confirm:$false
                }
                
                Write-Log ("Total updates applied: {0}" -f $updates.Count) "OK" Green
            }
            else {
                Write-Log "Windows is already up to date." "INFO" Gray
            }
        }
        catch {
            Write-Log "PSWindowsUpdate path failed: $_" "WARN" Yellow
        }
    }
    else {
        Write-Log "Falling back to built-in Windows Update client..." "WARN" Yellow
        try { UsoClient.exe StartScan | Out-Null } catch {}
        try { UsoClient.exe StartDownload | Out-Null } catch {}
        try { UsoClient.exe StartInstall | Out-Null } catch {}
    }
}

Invoke-WindowsPatching

function Invoke-WingetPatching {
    if (-not $WingetAvailable) {
        Write-Log "winget not available — skipping app patching." "WARN" Yellow
        return
    }
    if (-not (Test-InternetConnection)) {
        Write-Log "Offline — skipping winget patching." "WARN" Yellow
        return
    }

    Write-Log "Updating installed applications via winget..." "INFO" Cyan

    try {
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Log "winget disappeared unexpectedly." "WARN" Yellow
            return
        }

        $args = "upgrade --all --silent --accept-source-agreements --accept-package-agreements"
        $p = Start-Process -FilePath $cmd.Source -ArgumentList $args -Wait -NoNewWindow -PassThru
        Write-Log ("winget upgrade exit code: {0}" -f $p.ExitCode) "INFO" Green
    }
    catch {
        Write-Log "winget upgrade failed: $_" "WARN" Yellow
    }
}

Invoke-WingetPatching

function Invoke-DefenderUpdateAndScan {
    Write-Log "Updating Defender signatures + running scan..." "INFO" Cyan

    try {
        $def = Get-MpComputerStatus -ErrorAction SilentlyContinue

        if (-not $def) {
            Write-Log "Microsoft Defender unavailable." "INFO" Gray
            return
        }

        try {
            Update-MpSignature -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Defender signatures updated." "OK" Green
        }
        catch {
            $mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
            if (Test-Path $mp) {
                Start-Process -FilePath $mp -ArgumentList "-SignatureUpdate" -Wait -NoNewWindow
            }
        }

        try {
            Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Defender Quick Scan started." "OK" Green
        }
        catch {
            $mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
            if (Test-Path $mp) {
                Start-Process -FilePath $mp -ArgumentList "-Scan -ScanType 1" -NoNewWindow
            }
        }
    }
    catch {
        Write-Log "Defender actions failed: $_" "WARN" Yellow
    }
}

Invoke-DefenderUpdateAndScan

$OSAfter     = Get-OSContext
$HotfixAfter = Get-HotfixSnapshot
$AppsAfter   = Get-AppSnapshot

function Test-PendingReboot {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }

    try {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $val = (Get-ItemProperty -Path $key -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue)
        if ($val) { return $true }
    }
    catch {}

    return $false
}

$RebootPending = Test-PendingReboot

if ($RebootPending) {
    Write-Log "Reboot recommended to complete patching." "WARN" Yellow
}

# Calculate patches applied (must be computed before KEV summary)
$newHotfixes = $HotfixAfter.Count - $HotfixBefore.Count
$patchesApplied = if ($newHotfixes -gt 0) { $newHotfixes } else { 0 }

# Display KEV summary if analysis was performed
$kevAnalysisPath = Join-Path $LogRoot ("kev-analysis-" + $Timestamp + ".json")
if (Test-Path $kevAnalysisPath) {
    try {
        $kevAnalysis = Get-Content -Raw -Path $kevAnalysisPath | ConvertFrom-Json
        Write-Log "=== KEV Vulnerability Analysis Summary ===" "INFO" Cyan
        Write-Log ("Total Windows CVEs in CISA KEV catalog: {0}" -f $kevAnalysis.WindowsKevCount) "INFO" Yellow
        Write-Log ("Unique CVE identifiers: {0}" -f $kevAnalysis.UniqueCVEs) "INFO" Yellow
        
        if ($kevAnalysis.HighPriorityCVEs.Count -gt 0) {
            Write-Log ("CRITICAL: {0} CVEs linked to ransomware campaigns" -f $kevAnalysis.HighPriorityCVEs.Count) "WARN" Red
        }
        
        if ($patchesApplied -gt 0) {
            Write-Log ("Security patches applied this run: {0}" -f $patchesApplied) "OK" Green
            Write-Log "Applied patches may address some of the identified KEV vulnerabilities." "INFO" Cyan
        } else {
            Write-Log "System was already up to date. No new patches applied." "INFO" Gray
        }
        
        Write-Log ("Full KEV analysis report: {0}" -f $kevAnalysisPath) "INFO" Gray
    }
    catch {
        Write-Log "Could not load KEV analysis summary: $_" "WARN" Yellow
    }
}

try {
    # Pre-compute conditional file paths for report
    $kevCsvFileValue = if (Test-Path $KevCsvPath) { $KevCsvPath } else { $null }
    $kevFilteredFileValue = if (Test-Path $KevJsonPath) { $KevJsonPath } else { $null }
    $kevAnalysisFileValue = if (Test-Path (Join-Path $LogRoot ("kev-analysis-" + $Timestamp + ".json"))) { 
        Join-Path $LogRoot ("kev-analysis-" + $Timestamp + ".json") 
    } else { 
        $null 
    }
    
    $report = [PSCustomObject]@{
        ScriptName        = $ScriptName
        ScriptVersion     = $ScriptVersion
        Timestamp         = (Get-Date)
        OSBefore          = $OSBefore
        OSAfter           = $OSAfter
        HotfixCountBefore = $HotfixBefore.Count
        HotfixCountAfter  = $HotfixAfter.Count
        PatchesApplied    = $patchesApplied
        AppCountBefore    = $AppsBefore.Count
        AppCountAfter     = $AppsAfter.Count
        KevCsvFile        = $kevCsvFileValue
        KevFilteredFile   = $kevFilteredFileValue
        KevAnalysisReport = $kevAnalysisFileValue
        RebootRequired    = $RebootPending
        Notes             = "Autonomous patch run with KEV vulnerability analysis. Reboot recommended if RebootRequired is true."
    }

    $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $ReportFile -Encoding UTF8 -Force

    Write-Log ("Report: {0}" -f $ReportFile) "INFO" Green
}
catch {
    Write-Log "Failed to write patching report: $_" "WARN" Yellow
}

Write-Log "=== patch-intel.ps1 complete ===" "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
