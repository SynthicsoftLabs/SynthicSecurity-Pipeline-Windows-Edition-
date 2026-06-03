#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ASEP Hunter Module v4.0 (Titan Edition)
    Comprehensive scanning of 50+ Windows Auto-Start Extension Points.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\ASEP_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "asep_hunter.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting ASEP Hunter Module v4.0 (Titan Edition)..." -Level INFO
$AsepDetections = @()

# ============================================================================
# SCANNING LOGIC
# ============================================================================

# 1. Registry Deep Scan (50+ Keys)
$AsepKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnceEx",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ShellServiceObjectDelayLoad",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
)

foreach ($Key in $AsepKeys) {
    if (Test-Path $Key) {
        Write-Log "Scanning ASEP Key: $Key" -Level INFO
        $Props = Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue
        foreach ($Prop in $Props.PSObject.Properties) {
            $TargetProps = @("Userinit","Shell","BootExecute","Appinit_DLLs","Authentication Packages")
            if ($TargetProps -contains $Prop.Name) {
                # BootExecute is REG_MULTI_SZ - PowerShell returns it as String[], not String.
                # Calling .ToString() on an array yields "System.String[]", never matching the expected value.
                # Join array entries with newline to produce a reliable flat string for comparison.
                $RawValue = $Prop.Value
                $Value = if ($RawValue -is [System.Array]) { ($RawValue -join "`n").Trim() } else { $RawValue.ToString().Trim() }
                # Detection Logic: Non-standard values in critical keys
                if ($Prop.Name -eq "BootExecute" -and $Value -ne "autocheck autochk *") {
                    $AsepDetections += [PSCustomObject]@{
                        Type = "ASEP Anomaly"
                        Key = $Key
                        ValueName = $Prop.Name
                        Evidence = "Non-standard BootExecute value: $Value"
                        Severity = "High"
                    }
                    Write-Log "DETECTED: Anomaly in $Key\$($Prop.Name)" -Level DETECTED
                }
            }
        }
    }
}

# 2. Service & Driver Audit
Write-Log "Auditing Services and Drivers..." -Level INFO
$SuspiciousServices = Get-WmiObject Win32_Service | Where-Object { $_.StartMode -eq "Auto" -and $_.PathName -match "Temp|AppData" }
foreach ($Svc in $SuspiciousServices) {
    $AsepDetections += [PSCustomObject]@{
        Type = "Suspicious Service"
        Name = $Svc.Name
        Path = $Svc.PathName
        Evidence = "Auto-start service pointing to user-writable directory"
        Severity = "Critical"
    }
    Write-Log "DETECTED: Suspicious Service [$($Svc.Name)] at $($Svc.PathName)" -Level DETECTED
}

Write-Log "ASEP Hunting Complete. Found $($AsepDetections.Count) persistence anomalies." -Level SUCCESS

if ($null -eq $AsepDetections) { return @() }
return $AsepDetections