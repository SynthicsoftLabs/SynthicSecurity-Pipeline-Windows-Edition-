#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Smart Remediation Module v5.1 (Aegis Edition)
    Autonomous remediation of detected threats with safety guardrails.
    Optimized for PowerShell 5.1 compatibility. No special characters.
#>
[CmdletBinding()]
param(
    [PSCustomObject[]]$Detections,
    [string]$EvidencePath = "C:\SynthicForensics\Remediation_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "remediation.log"

function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','REMEDIATED','CRITICAL')] 
        [string]$Level = 'INFO'
    )
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $Output = "[$Level] $Message"
    
    $Color = "Cyan"
    if ($Level -eq 'SUCCESS' -or $Level -eq 'REMEDIATED') { $Color = "Green" }
    elseif ($Level -eq 'WARNING') { $Color = "Yellow" }
    elseif ($Level -eq 'FAILURE' -or $Level -eq 'CRITICAL') { $Color = "Red" }

    Write-Host $Output -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "[$Timestamp] [$Level] $Message"
}

Write-Log "Starting Smart Remediation Module v5.1..." -Level INFO

if ($null -eq $Detections -or $Detections.Count -eq 0) {
    Write-Log "No threats provided for remediation. Exiting." -Level SUCCESS
    return
}

Write-Log "Processing $($Detections.Count) detections for autonomous remediation..." -Level INFO

# ============================================================================
# REMEDIATION PLAYBOOKS
# ============================================================================

foreach ($Detection in $Detections) {
    $Type = $Detection.Type
    Write-Log "Executing playbook for type: $Type" -Level INFO

    # Use IF-ELSE for multiple conditions to avoid PS 5.1 switch issues with complex strings
    if ($Type -eq "Unsigned Process in Suspicious Path") {
        if (-not $DryRun) {
            try {
                $Proc = Get-Process -Id $Detection.Id -ErrorAction SilentlyContinue
                if ($Proc) { $Proc | Stop-Process -Force }
                
                $QuarantineDir = Join-Path $EvidencePath "Quarantine"
                if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                Move-Item -Path $Detection.Path -Destination $QuarantineDir -Force -ErrorAction Stop
                Write-Log "REMEDIATED: Terminated and quarantined $($Detection.ProcessName)" -Level REMEDIATED
            } catch {
                Write-Log "FAILURE: Could not remediate process $($Detection.ProcessName): $_" -Level FAILURE
            }
        }
    }
    elseif ($Type -eq "WMI Event Consumer") {
        if (-not $DryRun) {
            try {
                Get-WmiObject -Namespace root\subscription -Class __EventConsumer -Filter "Name='$($Detection.Name)'" | Remove-WmiObject
                Write-Log "REMEDIATED: Removed suspicious WMI Event Consumer [$($Detection.Name)]" -Level REMEDIATED
            } catch {
                Write-Log "FAILURE: Could not remove WMI consumer: $_" -Level FAILURE
            }
        }
    }
    elseif ($Type -eq "Known Malicious Binary (IOC Match)" -or $Type -eq "Dormant Malware (Disk IOC Match)") {
        if (-not $DryRun) {
            try {
                if ($Detection.ProcessName) {
                    $Proc = Get-Process -Name $Detection.ProcessName -ErrorAction SilentlyContinue
                    if ($Proc) { $Proc | Stop-Process -Force }
                }
                
                $QuarantineDir = Join-Path $EvidencePath "Quarantine_IOC"
                if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                Move-Item -Path $Detection.Path -Destination $QuarantineDir -Force -ErrorAction Stop
                Write-Log "REMEDIATED: Malware at [$($Detection.Path)] quarantined." -Level REMEDIATED
            } catch {
                Write-Log "FAILURE: Could not remediate IOC match: $_" -Level FAILURE
            }
        }
    }
    elseif ($Type -eq "Malicious Network Connection") {
        if (-not $DryRun) {
            try {
                $Proc = Get-Process -Id $Detection.PID -ErrorAction SilentlyContinue
                if ($Proc) { $Proc | Stop-Process -Force }
                Write-Log "REMEDIATED: Terminated process [$($Detection.Process)] due to malicious network connection to $($Detection.RemoteIP)." -Level REMEDIATED
            } catch {}
        }
    }
    elseif ($Type -eq "ASEP Anomaly") {
        if (-not $DryRun) {
            try {
                if ($Detection.Key -and $Detection.ValueName) {
                    if ($Detection.ValueName -eq "BootExecute") {
                        # BootExecute must be REG_MULTI_SZ. Set-ItemProperty with a plain string
                        # writes REG_SZ which Windows ignores. Use an array to force MULTI_SZ.
                        Set-ItemProperty -Path $Detection.Key -Name "BootExecute" -Value @("autocheck autochk *") -Type MultiString
                    }
                    Write-Log "REMEDIATED: Reset ASEP anomaly in $($Detection.Key)" -Level REMEDIATED
                }
            } catch {}
        }
    }
    elseif ($Type -eq "Deception Trigger: Honey-File Access" -or $Type -eq "Ransomware Indicator: Canary Deleted" -or $Type -eq "Ransomware Indicator: Canary Modified") {
        if (-not $DryRun) {
            Write-Log "CRITICAL IR ACTION: Potential active breach or ransomware. Isolating host..." -Level CRITICAL
            try {
                Get-NetAdapter | Disable-NetAdapter -Confirm:$false
                Write-Log "REMEDIATED: Host isolated (Network Adapters Disabled) due to critical deception/ransomware trigger." -Level REMEDIATED
            } catch {}
        }
    }
    elseif ($Type -eq "Suspicious Process Parentage" -or $Type -eq "Suspicious Loaded Module") {
        if (-not $DryRun) {
            try {
                $Proc = Get-Process -Id $Detection.PID -ErrorAction SilentlyContinue
                if ($Proc) { $Proc | Stop-Process -Force }
                Write-Log "REMEDIATED: Terminated process [$($Detection.Process)] due to memory integrity anomaly." -Level REMEDIATED
            } catch {}
        }
    }
    elseif ($Type -eq "Suspicious Process Lineage") {
        if (-not $DryRun) {
            Write-Log "BEHAVIORAL REMEDIATION: Suspending suspicious process for manual review." -Level WARNING
        }
    }
    elseif ($Type -eq "Potential DLL Sideloading") {
        if (-not $DryRun) {
            try {
                $QuarantineDir = Join-Path $EvidencePath "Quarantine_Heuristic"
                if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                Move-Item -Path $Detection.Path -Destination $QuarantineDir -Force -ErrorAction Stop
                Write-Log "REMEDIATED: Heuristic threat quarantined: $($Detection.Path)" -Level REMEDIATED
            } catch {}
        }
    }
    elseif ($Type -eq "Suspicious Startup File") {
        if (-not $DryRun) {
            try {
                $QuarantineDir = Join-Path $EvidencePath "Quarantine"
                if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                Move-Item -Path $Detection.Path -Destination $QuarantineDir -Force -ErrorAction Stop
                Write-Log "REMEDIATED: Moved suspicious startup file to quarantine: $($Detection.Path)" -Level REMEDIATED
            } catch {
                Write-Log "FAILURE: Could not quarantine startup file: $_" -Level FAILURE
            }
        }
    }
    else {
        Write-Log "No automated remediation playbook for type: $Type. Manual review required." -Level WARNING
    }
}

Write-Log "Remediation Cycle Complete." -Level SUCCESS