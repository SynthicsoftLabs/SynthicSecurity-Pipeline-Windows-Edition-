#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Memory Guardian Module v5.0
    Scans for process hollowing, reflective DLL injection, and memory-resident malware patterns.
    Optimized for PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Memory_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $EvidencePath "memory_guardian.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','DETECTED')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch($Level){'SUCCESS'{'Green'}'WARNING'{'Yellow'}'DETECTED'{'Red'}default{'Cyan'}}
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$ts][$Level] $Message"
}

Write-Log "Starting Memory Guardian Module v5.0..." -Level INFO
$MemoryDetections = @()

# ============================================================================
# MEMORY AUDIT (Detection)
# ============================================================================

Write-Log "Scanning for memory-resident threats..." -Level INFO

# 1. Detect Suspicious Process Parentage (Indicators of Hollowing/Injection)
$SuspiciousProcesses = Get-WmiObject Win32_Process | Where-Object {
    ($_.Name -eq "svchost.exe" -and $_.ParentProcessId -ne (Get-Process -Name services).Id) -or
    ($_.Name -eq "lsass.exe" -and $_.ParentProcessId -ne (Get-Process -Name wininit).Id)
}

foreach ($Proc in $SuspiciousProcesses) {
    $MemoryDetections += [PSCustomObject]@{
        Type = "Suspicious Process Parentage"
        Process = $Proc.Name
        PID = $Proc.ProcessId
        Severity = "High"
        Evidence = "Critical system process spawned by unauthorized parent (Possible Hollowing)."
    }
    Write-Log "DETECTED: Suspicious Parentage for [$($Proc.Name)] (PID: $($Proc.ProcessId))" -Level DETECTED
}

# 2. Detect Reflective DLL Injection (Unsigned Modules in System Processes)
# Note: Deep memory scanning requires external tools like PE-Sieve, but we can do heuristic checks.
Write-Log "Auditing loaded modules in high-value processes..." -Level INFO
$Targets = Get-Process -Name "explorer", "lsass", "svchost" -ErrorAction SilentlyContinue
foreach ($T in $Targets) {
    try {
        $UnsignedModules = $T.Modules | Where-Object { 
            $_.FileName -notmatch "C:\\Windows\\System32|C:\\Windows\\SysWOW64" -and 
            (Get-AuthenticodeSignature $_.FileName).Status -ne "Valid"
        }
        foreach ($Mod in $UnsignedModules) {
            $MemoryDetections += [PSCustomObject]@{
                Type = "Suspicious Loaded Module"
                Process = $T.ProcessName
                Module = $Mod.ModuleName
                Path = $Mod.FileName
                Severity = "High"
                Evidence = "Unsigned non-system DLL loaded in critical process."
            }
            Write-Log "DETECTED: Unsigned module [$($Mod.ModuleName)] in $($T.ProcessName)" -Level DETECTED
        }
    } catch {}
}

Write-Log "Memory Guardian Audit Complete. Found $($MemoryDetections.Count) anomalies." -Level SUCCESS

if ($null -eq $MemoryDetections) { return @() }
return $MemoryDetections
