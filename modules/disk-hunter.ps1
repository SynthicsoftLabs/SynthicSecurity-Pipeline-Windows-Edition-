#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deep Disk IOC Hunter v4.0 (Titan Edition)
    Recursive disk scanning for known malicious hashes and file patterns.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Disk_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [string[]]$ScanPaths = @("$env:TEMP", "$env:APPDATA", "C:\Users\Public")
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "disk_hunter.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Deep Disk IOC Hunter v4.0 (Titan Edition)..." -Level INFO
$DiskDetections = @()

# ============================================================================
# INTEL INGESTION (Hashes)
# ============================================================================

$IntelPath = "C:\ProgramData\SynthicSecurity\Intelligence"
$BadHashes = @()
if (Test-Path $IntelPath) {
    Write-Log "Loading Hash Intelligence..." -Level INFO
    Get-ChildItem $IntelPath -Filter "*Hash*.txt" | ForEach-Object {
        $BadHashes += Get-Content $_.FullName | Where-Object { $_ -match "^[a-fA-F0-9]{32,64}$" }
    }
}

# ============================================================================
# DISK SCAN
# ============================================================================

foreach ($Path in $ScanPaths) {
    if (Test-Path $Path) {
        Write-Log "Scanning Path: $Path" -Level INFO
        $Files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            try {
                # Only scan small executables to keep it fast
                if ($File.Length -lt 10MB -and $File.Extension -match "exe|dll|sys|ps1|vbs|js") {
                    $Hash = (Get-FileHash $File.FullName -Algorithm MD5).Hash
                    if ($BadHashes -contains $Hash) {
                        $DiskDetections += [PSCustomObject]@{
                            Type = "Dormant Malware (Disk IOC Match)"
                            Path = $File.FullName
                            Hash = $Hash
                            Severity = "Critical"
                            Evidence = "File hash matches known malware in intelligence feeds"
                        }
                        Write-Log "CRITICAL DETECTED: Malware found on disk: $($File.FullName)" -Level DETECTED
                    }
                }
            } catch {}
        }
    }
}

Write-Log "Disk Scan Complete. Found $($DiskDetections.Count) dormant threats." -Level SUCCESS

if ($null -eq $DiskDetections) { return @() }
return $DiskDetections
