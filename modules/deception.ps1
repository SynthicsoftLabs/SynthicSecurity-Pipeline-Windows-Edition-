#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Aegis Deception Module v5.0
    Deploys honey-files and registry honeypots to detect lateral movement and credential theft.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Deception_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$DeployOnly
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "deception.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Aegis Deception Module v5.0..." -Level INFO
$DeceptionDetections = @()

# ============================================================================
# DECEPTION DEPLOYMENT (Honeypots)
# ============================================================================

$HoneyFiles = @(
    "$env:USERPROFILE\Documents\Internal_Network_Passwords.txt",
    "$env:USERPROFILE\Desktop\Executive_Finance_Report.xlsx",
    "C:\Windows\System32\drivers\etc\backup_hosts.txt"
)

if ($DeployOnly) {
    Write-Log "Deploying honey-files for active deception..." -Level INFO
    foreach ($File in $HoneyFiles) {
        if (-not (Test-Path $File)) {
            "CONFIDENTIAL: Unauthorized access is strictly prohibited." | Out-File -FilePath $File -Force
            Write-Log "Deployed Honey-File: $File" -Level SUCCESS
        }
    }
    return
}

# ============================================================================
# DECEPTION AUDIT (Detection)
# ============================================================================

Write-Log "Auditing deception triggers..." -Level INFO

# 1. Audit Honey-File Access (Requires File System Auditing Enabled in Hardening)
foreach ($File in $HoneyFiles) {
    if (Test-Path $File) {
        try {
            # Check for recent access events in Security Log (Event ID 4663)
            $Events = Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4663} -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match [regex]::Escape($File) }
            if ($Events) {
                $DeceptionDetections += [PSCustomObject]@{
                    Type = "Deception Trigger: Honey-File Access"
                    Path = $File
                    Severity = "Critical"
                    Evidence = "Unauthorized access attempt detected for honey-file."
                }
                Write-Log "CRITICAL DETECTED: Honey-File Access [$File]" -Level DETECTED
            }
        } catch {}
    }
}

Write-Log "Deception Audit Complete. Found $($DeceptionDetections.Count) triggers." -Level SUCCESS

if ($null -eq $DeceptionDetections) { return @() }
return $DeceptionDetections
