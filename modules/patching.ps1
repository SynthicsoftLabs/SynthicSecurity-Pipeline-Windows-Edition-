#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Preemptive & Post-Patching Module v2.1
    Vulnerability management via CISA KEV and automated patching verification.
    Optimized for PowerShell 5.1 compatibility.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Patching_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$SkipThirdParty
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = "$EvidencePath\patching.log"

function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','CRITICAL')] 
        [string]$Level = 'INFO'
    )
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $Output = "[$Level] $Message"
    
    $Color = "Cyan"
    if ($Level -eq 'SUCCESS') { $Color = "Green" }
    elseif ($Level -eq 'WARNING') { $Color = "Yellow" }
    elseif ($Level -eq 'FAILURE') { $Color = "Red" }

    Write-Host $Output -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "[$Timestamp] $Output"
}

Write-Log "Starting Preemptive & Post-Patching Module..." -Level INFO

# ============================================================================
# PHASE 1: VULNERABILITY INTELLIGENCE (CISA KEV)
# ============================================================================

Write-Log "Phase 1: Fetching CISA Known Exploited Vulnerabilities (KEV)..." -Level INFO

$KevUrl = "https://www.cisa.gov/sites/default/files/csv/known_exploited_vulnerabilities.csv"
$KevPath = Join-Path $EvidencePath "cisa_kev.csv"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $KevUrl -OutFile $KevPath -UseBasicParsing -ErrorAction Stop
    $KevData = Import-Csv $KevPath
    $WindowsKev = $KevData | Where-Object { $_.vendorProject -match "Microsoft" -and $_.product -match "Windows" }
    Write-Log "Intelligence: Found $($WindowsKev.Count) exploited vulnerabilities for Windows in CISA feed." -Level SUCCESS
    $WindowsKev | Select-Object cveID, product, vulnerabilityName, dateAddedKev | 
        Export-Csv (Join-Path $EvidencePath "targeted_vulnerabilities.csv") -NoTypeInformation
} catch {
    Write-Log "Intelligence FAILURE: Could not download CISA KEV. Proceeding with standard updates." -Level WARNING
}

# ============================================================================
# PHASE 2: AUTOMATED PATCHING
# ============================================================================

Write-Log "Phase 2: Executing Automated Patching..." -Level INFO

# 2.1 OS Updates (PSWindowsUpdate)
# 2.1 OS Updates (PSWindowsUpdate)
$NetworkAvailable = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    if ($NetworkAvailable) {
        Write-Log "Installing PSWindowsUpdate module..." -Level INFO
        try {
            # Suppress all confirmations including the internal NuGet bootstrap prompt
            $env:POWERSHELLGET_NONINTERACTIVE = "1"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Confirm:$false -ErrorAction Stop | Out-Null
        } catch {
            Write-Log "Module installation failed. Falling back to native UsoClient." -Level WARNING
        }
    } else {
        Write-Log "Network unavailable. Skipping PSWindowsUpdate install. Falling back to native UsoClient." -Level WARNING
    }
}

if ((Get-Module -ListAvailable -Name PSWindowsUpdate) -and $NetworkAvailable) {
    try {
        Import-Module PSWindowsUpdate
        Write-Log "Scanning for critical security updates..." -Level INFO
        $Updates = Get-WindowsUpdate -MicrosoftUpdate -Category "Security Updates", "Critical Updates" -ErrorAction SilentlyContinue
        if ($Updates) {
            Write-Log "Applying $($Updates.Count) security updates..." -Level INFO
            Install-WindowsUpdate -MicrosoftUpdate -Category "Security Updates", "Critical Updates" -AcceptAll -IgnoreReboot -AutoReboot:$false -Confirm:$false | Out-Null
            Write-Log "OS Patching Complete." -Level SUCCESS
        } else {
            Write-Log "System is already patched against known vulnerabilities." -Level SUCCESS
        }
    } catch {
        Write-Log "PSWindowsUpdate execution failed: $_" -Level FAILURE
    }
} else {
    Write-Log "Triggering native Windows Update scan..." -Level INFO
    Start-Process "UsoClient.exe" -ArgumentList "StartScan"
}

# 2.2 Third-Party Patching (Winget)
if (-not $SkipThirdParty) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Updating third-party applications via Winget..." -Level INFO
        Start-Job -ScriptBlock { winget upgrade --all --silent --accept-source-agreements --accept-package-agreements } | Out-Null
        Write-Log "Third-party update job triggered." -Level SUCCESS
    }
}

# ============================================================================
# PHASE 3: POST-PATCH VERIFICATION
# ============================================================================

Write-Log "Phase 3: Post-Patch Verification Loop..." -Level INFO

$CriticalServices = @("wuauserv", "bits", "cryptsvc", "WinDefend")

foreach ($Svc in $CriticalServices) {
    $Status = Get-Service -Name $Svc -ErrorAction SilentlyContinue
    if ($Status -and $Status.Status -eq "Running") {
        Write-Log "Verified: Service $Svc is operational." -Level SUCCESS
    } else {
        Write-Log "ALERT: Service $Svc is NOT running post-patch!" -Level WARNING
        Start-Service $Svc -ErrorAction SilentlyContinue
        # Wait up to 30 seconds for the service to reach Running state
        $Waited = 0
        do {
            Start-Sleep -Seconds 3
            $Waited += 3
            $Status = Get-Service -Name $Svc -ErrorAction SilentlyContinue
        } while ($Status.Status -ne "Running" -and $Waited -lt 30)

        if ($Status.Status -eq "Running") {
            Write-Log "Verified: Service $Svc started successfully." -Level SUCCESS
        } else {
            Write-Log "FAILURE: Service $Svc could not be started after $Waited seconds. Manual intervention may be required." -Level FAILURE
        }
    }
}

$RebootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
if (Test-Path $RebootKey) {
    Write-Log "SYSTEM REQUIREMENT: A reboot is required to finalize security patches." -Level WARNING
}

Write-Log "Patching & Verification Cycle Complete." -Level SUCCESS