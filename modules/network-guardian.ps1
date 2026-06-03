#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Network Guardian Module v4.0 (Titan Edition)
    Live connection auditing against global threat intelligence blacklists.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Network_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "network_guardian.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Network Guardian Module v4.0 (Titan Edition)..." -Level INFO
$NetworkDetections = @()

# ============================================================================
# INTEL INGESTION (IP Blacklists)
# ============================================================================

$IntelPath = "C:\ProgramData\SynthicSecurity\Intelligence"
$BadIPs = @()
if (Test-Path $IntelPath) {
    Write-Log "Loading IP Intelligence..." -Level INFO
    Get-ChildItem $IntelPath -Filter "*IP*.txt" | ForEach-Object {
        $BadIPs += Get-Content $_.FullName | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" }
    }
}

# ============================================================================
# LIVE AUDIT
# ============================================================================

Write-Log "Auditing live network connections..." -Level INFO
$Connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue

foreach ($Conn in $Connections) {
    $RemoteIP = $Conn.RemoteAddress
    if ($BadIPs -contains $RemoteIP) {
        $Proc = Get-Process -Id $Conn.OwningProcess -ErrorAction SilentlyContinue
        $NetworkDetections += [PSCustomObject]@{
            Type = "Malicious Network Connection"
            RemoteIP = $RemoteIP
            Process = $Proc.ProcessName
            PID = $Conn.OwningProcess
            Severity = "Critical"
            Evidence = "Established connection to known malicious IP in intelligence feed"
        }
        Write-Log "CRITICAL DETECTED: Process [$($Proc.ProcessName)] connected to malicious IP: $RemoteIP" -Level DETECTED
    }
}

Write-Log "Network Audit Complete. Found $($NetworkDetections.Count) malicious connections." -Level SUCCESS

if ($null -eq $NetworkDetections) { return @() }
return $NetworkDetections
