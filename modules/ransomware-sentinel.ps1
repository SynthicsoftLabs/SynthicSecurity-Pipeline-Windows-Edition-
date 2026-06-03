#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ransomware Sentinel Module v5.0
    Deploys canary files and monitors for unauthorized mass-file modifications.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Ransomware_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$DeployOnly
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "ransomware_sentinel.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Ransomware Sentinel Module v5.0..." -Level INFO
$RansomwareDetections = @()

# ============================================================================
# CANARY DEPLOYMENT
# ============================================================================

$CanaryPaths = @(
    "$env:USERPROFILE\Documents\!_canary.txt",
    "$env:USERPROFILE\Pictures\!_canary.jpg",
    "C:\Users\Public\Documents\!_canary.pdf"
)

if ($DeployOnly) {
    Write-Log "Deploying canary files for ransomware monitoring..." -Level INFO
    foreach ($Path in $CanaryPaths) {
        if (-not (Test-Path $Path)) {
            $ParentDir = Split-Path -Parent $Path
            if (-not (Test-Path $ParentDir)) {
                New-Item -Path $ParentDir -ItemType Directory -Force | Out-Null
                Write-Log "Created missing directory: $ParentDir" -Level INFO
            }
            try {
                [System.IO.File]::WriteAllText($Path, "CANARY_DATA_DO_NOT_DELETE", [System.Text.Encoding]::ASCII)
                Write-Log "Deployed Canary: $Path" -Level SUCCESS
            } catch {
                Write-Log "WARNING: Could not deploy canary at $Path - $_" -Level WARNING
            }
        }
    }
    return
}

# ============================================================================
# CANARY AUDIT
# ============================================================================

Write-Log "Auditing canary file integrity..." -Level INFO

foreach ($Path in $CanaryPaths) {
    if (-not (Test-Path $Path)) {
        $RansomwareDetections += [PSCustomObject]@{
            Type = "Ransomware Indicator: Canary Deleted"
            Path = $Path
            Severity = "Critical"
            Evidence = "Canary file has been deleted. Possible mass-encryption in progress."
        }
        Write-Log "CRITICAL DETECTED: Canary Deleted [$Path]" -Level DETECTED
    } else {
        $Content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII).Trim()
        if ($Content -ne "CANARY_DATA_DO_NOT_DELETE") {
            $RansomwareDetections += [PSCustomObject]@{
                Type = "Ransomware Indicator: Canary Modified"
                Path = $Path
                Severity = "Critical"
                Evidence = "Canary file content has been modified/encrypted."
            }
            Write-Log "CRITICAL DETECTED: Canary Modified [$Path]" -Level DETECTED
        }
    }
}

Write-Log "Ransomware Sentinel Audit Complete. Found $($RansomwareDetections.Count) indicators." -Level SUCCESS

if ($null -eq $RansomwareDetections) { return @() }
return $RansomwareDetections