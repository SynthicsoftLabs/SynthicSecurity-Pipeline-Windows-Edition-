#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SynthicSecurity Autonomous Cyber Defense Suite v2.2
    Professional-grade, fully automated security suite for Windows.
    Optimized for PowerShell 5.1 compatibility. No special characters.
#>
[CmdletBinding()]
param(
    [switch]$FullScan,
    [switch]$ApplyRemediation,
    [switch]$ApplyPatches,
    [switch]$ApplyHardening,
    [switch]$DryRun,
    [string]$LogRoot = "C:\ProgramData\SynthicSecurity\Logs"
)

$ErrorActionPreference = "Stop"

# ============================================================================
# INITIALIZATION
# ============================================================================

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SessionLog = Join-Path $LogRoot "Session_$Timestamp"
if (-not (Test-Path $SessionLog)) { New-Item -ItemType Directory -Path $SessionLog -Force | Out-Null }

$MasterLog = Join-Path $SessionLog "master_orchestrator.log"

function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','CRITICAL','TASK')] 
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts][$Level] $Message"
    
    $color = "Gray"
    if ($Level -eq 'SUCCESS') { $color = "Green" }
    elseif ($Level -eq 'WARNING') { $color = "Yellow" }
    elseif ($Level -eq 'FAILURE') { $color = "Red" }
    elseif ($Level -eq 'CRITICAL') { $color = "Magenta" }
    elseif ($Level -eq 'TASK') { $color = "Cyan" }

    Write-Host $line -ForegroundColor $color
    Add-Content -Path $MasterLog -Value $line
}

# ============================================================================
# PRE-FLIGHT: UNBLOCK SCRIPTS & ENV PREP
# ============================================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulesPath = Join-Path $ScriptRoot "modules"

Write-Log "Pre-flight: Unblocking security modules for autonomous execution..." -Level INFO
Get-ChildItem -Path $ScriptRoot -Recurse -Include *.ps1, *.psm1 | Unblock-File -ErrorAction SilentlyContinue

Clear-Host
Write-Host "------------------------------------------------------------------------"
Write-Host "      SYNTHICSECURITY - AUTONOMOUS CYBER DEFENSE v5.0" -ForegroundColor Cyan
Write-Host "             Professional Endpoint Protection & Response"
Write-Host "               *** AEGIS EDITION - ALL ENCOMPASSING ***" -ForegroundColor Green
Write-Host "------------------------------------------------------------------------"

# Privilege Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "CRITICAL ERROR: Administrator privileges required." -Level CRITICAL
    exit 1
}

# ============================================================================
# EXECUTION PIPELINE
# ============================================================================

try {
    Write-Log "Initializing Autonomous Security Pipeline..." -Level INFO
    $GlobalDetections = @()

    # 1. Forensic & Boot Integrity Snapshot
    Write-Log "Phase 1: Capturing Forensic Baseline..." -Level TASK
    $ForensicsScript = Join-Path $ModulesPath "forensics.ps1"
    & $ForensicsScript -EvidencePath (Join-Path $SessionLog "Forensics")

    # 2. System Hardening
    if ($ApplyHardening) {
        Write-Log "Phase 2: Applying Security Hardening..." -Level TASK
        $HardeningScript = Join-Path $ModulesPath "hardening.ps1"
        & $HardeningScript -EvidencePath (Join-Path $SessionLog "Hardening")
    }

    # 3. Titan Detection Engine
    if ($FullScan) {
        Write-Log "Phase 3: Executing Titan Detection Engine (v4.0)..." -Level TASK
        
        # 3.1 Standard & Behavioral Detection
        $DetectionScript = Join-Path $ModulesPath "threat-detection.ps1"
        $Res1 = & $DetectionScript -EvidencePath (Join-Path $SessionLog "Detection") -IncludeIntelFeeds -IncludeHeuristics
        if ($null -ne $Res1) { $GlobalDetections += $Res1 }

        # 3.2 ASEP Hunter (50+ Persistence Points)
        $AsepScript = Join-Path $ModulesPath "asep-hunter.ps1"
        $Res2 = & $AsepScript -EvidencePath (Join-Path $SessionLog "ASEP")
        if ($null -ne $Res2) { $GlobalDetections += $Res2 }

        # 3.3 Network Guardian (Live Connection Audit)
        $NetworkScript = Join-Path $ModulesPath "network-guardian.ps1"
        $Res3 = & $NetworkScript -EvidencePath (Join-Path $SessionLog "Network")
        if ($null -ne $Res3) { $GlobalDetections += $Res3 }

        # 3.4 Deep Disk IOC Hunter
        $DiskScript = Join-Path $ModulesPath "disk-hunter.ps1"
        $Res4 = & $DiskScript -EvidencePath (Join-Path $SessionLog "Disk")
        if ($null -ne $Res4) { $GlobalDetections += $Res4 }

        # 3.5 Aegis Deception Audit
        $DeceptionScript = Join-Path $ModulesPath "deception.ps1"
        $Res5 = & $DeceptionScript -EvidencePath (Join-Path $SessionLog "Deception")
        if ($null -ne $Res5) { $GlobalDetections += $Res5 }

        # 3.6 Ransomware Sentinel: Deploy canaries first (idempotent), then audit
        $RansomScript = Join-Path $ModulesPath "ransomware-sentinel.ps1"
        try {
            & $RansomScript -EvidencePath (Join-Path $SessionLog "Ransomware") -DeployOnly
        } catch {
            Write-Log "WARNING: Canary deployment encountered an error: $_. Audit will still run." -Level WARNING
        }
        $Res6 = & $RansomScript -EvidencePath (Join-Path $SessionLog "Ransomware")
        if ($null -ne $Res6) { $GlobalDetections += $Res6 }

        # 3.7 Memory Guardian Audit
        $MemoryScript = Join-Path $ModulesPath "memory-guardian.ps1"
        $Res7 = & $MemoryScript -EvidencePath (Join-Path $SessionLog "Memory")
        if ($null -ne $Res7) { $GlobalDetections += $Res7 }
        
        # Ensure GlobalDetections is always an array
        $GlobalDetections = @($GlobalDetections | Where-Object { $null -ne $_ })
    }

    # 4. Smart Remediation
    if ($ApplyRemediation -and $null -ne $GlobalDetections -and $GlobalDetections.Count -gt 0) {
        Write-Log "Phase 4: Executing Smart Remediation Playbooks..." -Level TASK
        $RemediationScript = Join-Path $ModulesPath "remediation.ps1"
        & $RemediationScript -Detections $GlobalDetections -EvidencePath (Join-Path $SessionLog "Remediation") -DryRun:$DryRun
    }

    # 5. Patching & Vulnerability Management
    if ($ApplyPatches) {
        Write-Log "Phase 5: Executing Vulnerability Remediation (Patching)..." -Level TASK
        $PatchingScript = Join-Path $ModulesPath "patching.ps1"
        & $PatchingScript -EvidencePath (Join-Path $SessionLog "Patching")
    }

    Write-Log "Pipeline Execution Completed Successfully." -Level SUCCESS
    
} catch {
    Write-Log "ORCHESTRATOR FAILURE: $_" -Level CRITICAL
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level FAILURE
} finally {
    Write-Host "`n=== SESSION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Log Directory: $SessionLog"
    
    $Count = 0
    if ($null -ne $GlobalDetections) { $Count = $GlobalDetections.Count }
    
    if ($Count -gt 0) {
        Write-Host "Threats Detected: $Count" -ForegroundColor Red
    } else {
        Write-Host "Threats Detected: 0" -ForegroundColor Green
    }
    
    Write-Host "Status: COMPLETED" -ForegroundColor Green
    Write-Host "========================`n"
}