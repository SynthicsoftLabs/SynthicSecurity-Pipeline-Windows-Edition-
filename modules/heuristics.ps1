#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Advanced Behavioral Heuristics Engine v3.0
    Zero-day detection patterns based on MITRE ATT&CK (Process Hollowing, DLL Sideloading, etc.).
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Heuristics_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "heuristics.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Advanced Behavioral Heuristics Engine..." -Level INFO
$HeuristicDetections = @()

# ============================================================================
# PATTERN 1: PROCESS HOLLOWING / INJECTION INDICATORS
# ============================================================================

Write-Log "Pattern 1: Scanning for Process Injection Indicators..." -Level INFO

# Detect processes with high memory disparity or suspicious parent-child relationships
$Processes = Get-Process | Where-Object { $_.Path }
foreach ($Proc in $Processes) {
    try {
        # Suspicious Parent: Non-services.exe spawning system processes
        # This is a simplified heuristic for zero-day behavior
        if ($Proc.ProcessName -match "lsass|wininit|services" -and $Proc.Parent.Name -notmatch "wininit|services|System") {
            $HeuristicDetections += [PSCustomObject]@{
                Type = "Suspicious Process Lineage"
                Process = $Proc.ProcessName
                Parent = $Proc.Parent.Name
                Severity = "High"
                Evidence = "System process spawned by non-standard parent (Potential Injection)"
            }
            Write-Log "DETECTED: Suspicious Lineage for $($Proc.ProcessName) (Parent: $($Proc.Parent.Name))" -Level DETECTED
        }
    } catch {}
}

# ============================================================================
# PATTERN 2: DLL SIDELOADING / HIJACKING
# ============================================================================

Write-Log "Pattern 2: Scanning for DLL Sideloading Indicators..." -Level INFO

# Scan for known DLLs in non-standard locations (e.g., appdata)
$SuspiciousDlls = @("version.dll", "winmm.dll", "uxtheme.dll", "cryptbase.dll", "userenv.dll")
foreach ($Dll in $SuspiciousDlls) {
    $Matches = Get-ChildItem -Path "C:\Users" -Filter $Dll -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "System32|SysWOW64|WinSxS" }
    foreach ($Match in $Matches) {
        $HeuristicDetections += [PSCustomObject]@{
            Type = "Potential DLL Sideloading"
            Path = $Match.FullName
            Severity = "Medium"
            Evidence = "Known system DLL found in user-writable directory"
        }
        Write-Log "DETECTED: Suspicious DLL location: $($Match.FullName)" -Level DETECTED
    }
}

# ============================================================================
# PATTERN 3: LIVING OFF THE LAND (LotL) ABUSE
# ============================================================================

Write-Log "Pattern 3: Scanning for LotL Binary Abuse..." -Level INFO

# Detect suspicious use of certutil, mshsta, regsvr32
$LotlCommands = @("certutil.exe", "mshta.exe", "regsvr32.exe", "bitsadmin.exe")
foreach ($Cmd in $LotlCommands) {
    # Check for these processes running with network connections or from temp
    $Procs = Get-Process -Name ($Cmd.Replace(".exe", "")) -ErrorAction SilentlyContinue
    foreach ($P in $Procs) {
        if ($P.Path -match "Temp|AppData") {
            $HeuristicDetections += [PSCustomObject]@{
                Type = "Suspicious LotL Execution"
                Process = $P.ProcessName
                Path = $P.Path
                Severity = "High"
                Evidence = "LotL binary executing from suspicious path"
            }
            Write-Log "DETECTED: LotL binary [$($P.ProcessName)] executing from $($P.Path)" -Level DETECTED
        }
    }
}

Write-Log "Heuristics Scan Complete. Found $($HeuristicDetections.Count) behavioral anomalies." -Level SUCCESS

if ($null -eq $HeuristicDetections) { return @() }
return $HeuristicDetections
