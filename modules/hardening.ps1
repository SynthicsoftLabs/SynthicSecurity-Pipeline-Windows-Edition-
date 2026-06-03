#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enhanced System Hardening Module v2.1
    Applies security baselines and mitigations for Windows endpoints.
    Optimized for PowerShell 5.1 compatibility.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Hardening_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = "$EvidencePath\hardening.log"

function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','HARDENED')] 
        [string]$Level = 'INFO'
    )
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $Output = "[$Level] $Message"
    
    $Color = "Cyan"
    if ($Level -eq 'SUCCESS' -or $Level -eq 'HARDENED') { $Color = "Green" }
    elseif ($Level -eq 'WARNING') { $Color = "Yellow" }
    elseif ($Level -eq 'FAILURE') { $Color = "Red" }

    Write-Host $Output -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "[$Timestamp] [$Level] $Message"
}

Write-Log "Starting Enhanced System Hardening Module v2.1..." -Level INFO

# ============================================================================
# PHASE 1: NETWORK HARDENING
# ============================================================================

Write-Log "Phase 1: Network Service Hardening..." -Level INFO

# Disable LLMNR
try {
    $LlmnrPath = "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $LlmnrPath)) { New-Item $LlmnrPath -Force | Out-Null }
    Set-ItemProperty -Path $LlmnrPath -Name "EnableMulticast" -Value 0 -Type DWord
    Write-Log "LLMNR Disabled (Prevents credential spoofing)." -Level HARDENED
} catch {}

# Disable NetBIOS over TCP/IP
try {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
    Get-ChildItem $RegPath | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord
    }
    Write-Log "NetBIOS over TCP/IP Disabled." -Level HARDENED
} catch {}

# ============================================================================
# PHASE 2: ATTACK SURFACE REDUCTION (ASR)
# ============================================================================

Write-Log "Phase 2: Attack Surface Reduction..." -Level INFO

# Enable Windows Defender Real-time Monitoring
Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue
Write-Log "Windows Defender Real-time Monitoring and Sample Submission Enabled." -Level HARDENED

# ============================================================================
# PHASE 3: AUDIT POLICY ENHANCEMENT
# ============================================================================

Write-Log "Phase 3: Audit Policy Enhancement..." -Level INFO

# Enable Command Line Auditing
try {
    $AuditPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $AuditPath)) { New-Item $AuditPath -Force | Out-Null }
    Set-ItemProperty -Path $AuditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    Write-Log "Command Line Auditing Enabled (Crucial for TTP detection)." -Level HARDENED
} catch {}

# Enable PowerShell Script Block Logging
try {
    $PsLogPath = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (-not (Test-Path $PsLogPath)) { New-Item $PsLogPath -Force | Out-Null }
    Set-ItemProperty -Path $PsLogPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
    Write-Log "PowerShell Script Block Logging Enabled." -Level HARDENED
} catch {}

Write-Log "System Hardening Cycle Complete." -Level SUCCESS
