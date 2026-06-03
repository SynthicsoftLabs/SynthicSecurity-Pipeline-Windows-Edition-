#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Global Intelligence Module v3.0
    Automated ingestion of massive open-source IOC feeds (IPs, Hashes, Domains).
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$IntelligencePath = "C:\ProgramData\SynthicSecurity\Intelligence",
    [int]$MaxAgeHours = 24
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $IntelligencePath)) {
    New-Item -Path $IntelligencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $IntelligencePath "intelligence.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','FAILURE')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'FAILURE'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

# ============================================================================
# FEED DEFINITIONS
# ============================================================================

$Feeds = @(
    @{ Name = "Feodo_IPs"; Url = "https://feodotracker.abuse.ch/downloads/ipblocklist.txt"; Type = "IP" },
    @{ Name = "MalwareBazaar_MD5"; Url = "https://bazaar.abuse.ch/export/txt/md5/recent/"; Type = "Hash" },
    @{ Name = "ThreatFox_SHA256"; Url = "https://threatfox.abuse.ch/export/csv/sha256/recent/"; Type = "Hash" },
    @{ Name = "URLhaus_URLs"; Url = "https://urlhaus.abuse.ch/downloads/csv_recent/"; Type = "URL" }
)

# ============================================================================
# INGESTION LOGIC
# ============================================================================

Write-Log "Starting Global Intelligence Ingestion..." -Level INFO

foreach ($Feed in $Feeds) {
    $LocalPath = Join-Path $IntelligencePath "$($Feed.Name).txt"
    
    # Check if cache is still valid
    if (Test-Path $LocalPath) {
        $Age = (New-TimeSpan -Start (Get-Item $LocalPath).LastWriteTime -End (Get-Date)).TotalHours
        if ($Age -lt $MaxAgeHours) {
            Write-Log "Cache valid for $($Feed.Name) ($([Math]::Round($Age, 1)) hours old)." -Level SUCCESS
            continue
        }
    }

    Write-Log "Downloading $($Feed.Name) from $($Feed.Url)..." -Level INFO
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Feed.Url -OutFile $LocalPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        Write-Log "Successfully ingested $($Feed.Name)." -Level SUCCESS
    } catch {
        Write-Log "Failed to download $($Feed.Name): $_" -Level WARNING
    }
}

# ============================================================================
# PARSING & COMPILATION (Helper for Detection Engine)
# ============================================================================

function Get-IntelligenceData {
    param([string]$Type)
    
    $Data = @()
    $TargetFeeds = $Feeds | Where-Object { $_.Type -eq $Type }
    
    foreach ($Feed in $TargetFeeds) {
        $LocalPath = Join-Path $IntelligencePath "$($Feed.Name).txt"
        if (Test-Path $LocalPath) {
            # Basic parsing: Filter out comments and empty lines
            $Content = Get-Content $LocalPath | Where-Object { $_ -notmatch "^#" -and $_ -notmatch "^\s*$" }
            $Data += $Content
        }
    }
    return $Data | Select-Object -Unique
}

Write-Log "Global Intelligence Module Ready." -Level INFO
