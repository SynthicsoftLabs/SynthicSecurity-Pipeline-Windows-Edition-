#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Forensic & Boot Integrity Module v1.1
    Analyzes boot configuration, verifies system binary integrity, and captures forensic evidence.
    Optimized for PowerShell 5.1 compatibility.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\Forensics_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [switch]$DeepScan
)

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $EvidencePath)) {
    New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
}

$LogFile = "$EvidencePath\forensics.log"

function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','CRITICAL')] 
        [string]$Level = 'INFO'
    )
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $Output = "[$Level] $Message"
    
    # PS 5.1 Compatible Color Logic
    $Color = "Cyan"
    if ($Level -eq 'CRITICAL') { $Color = "Magenta" }
    elseif ($Level -eq 'WARNING') { $Color = "Yellow" }
    elseif ($Level -eq 'SUCCESS') { $Color = "Green" }
    elseif ($Level -eq 'FAILURE') { $Color = "Red" }

    Write-Host $Output -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "[$Timestamp] $Output"
}

Write-Log "Starting Forensic & Boot Integrity Analysis..." -Level INFO

# ============================================================================
# PHASE 1: BOOT INTEGRITY (BCD & WINRE)
# ============================================================================

Write-Log "Phase 1: Boot Configuration Analysis..." -Level INFO

# 1.1 BCD Analysis
try {
    $BcdBackup = Join-Path $EvidencePath "bcd_backup.dat"
    bcdedit /export $BcdBackup | Out-Null
    Write-Log "BCD exported for forensic analysis." -Level SUCCESS
    
    $BcdEnum = bcdedit /enum all
    $SuspiciousBcd = $BcdEnum | Where-Object { $_ -match "testsigning Yes|nointegritychecks Yes|debug Yes" }
    if ($SuspiciousBcd) {
        Write-Log "CRITICAL: Suspicious BCD settings detected (TestSigning/Debug/NoIntegrityChecks)!" -Level CRITICAL
        $SuspiciousBcd | Out-File (Join-Path $EvidencePath "suspicious_bcd.txt")
    }
} catch {
    Write-Log "Failed to analyze BCD: $_" -Level FAILURE
}

# 1.2 WinRE Status
try {
    $WinREInfo = reagentc /info
    $WinREInfo | Out-File (Join-Path $EvidencePath "winre_info.txt")
    if ($WinREInfo -match "Disabled") {
        Write-Log "WARNING: Windows Recovery Environment is DISABLED." -Level WARNING
    } else {
        Write-Log "WinRE is enabled and active." -Level SUCCESS
    }
} catch {}

# ============================================================================
# PHASE 2: SYSTEM BINARY INTEGRITY
# ============================================================================

Write-Log "Phase 2: System Binary Integrity Verification..." -Level INFO

$CriticalBinaries = @(
    "C:\Windows\System32\cmd.exe",
    "C:\Windows\System32\userinit.exe",
    "C:\Windows\System32\winlogon.exe",
    "C:\Windows\System32\lsass.exe",
    "C:\Windows\System32\drivers\etc\hosts"
)

foreach ($Path in $CriticalBinaries) {
    if (Test-Path $Path) {
        $Sig = Get-AuthenticodeSignature $Path
        if ($Sig.Status -ne "Valid" -and $Path -notmatch "hosts") {
            Write-Log "CRITICAL: Invalid signature for $Path!" -Level CRITICAL
            # Capture hash for threat intel
            Get-FileHash $Path | Export-Csv (Join-Path $EvidencePath "compromised_hashes.csv") -Append -NoTypeInformation
        } else {
            Write-Log "Verified: $Path" -Level SUCCESS
        }
    }
}

# ============================================================================
# PHASE 3: NETWORK & PERSISTENCE SNAPSHOT
# ============================================================================

Write-Log "Phase 3: Capturing Forensic Snapshots..." -Level INFO

# 3.1 Active Connections
Get-NetTCPConnection -State Established | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess, State | 
    Export-Csv (Join-Path $EvidencePath "network_snapshot.csv") -NoTypeInformation

# 3.2 DNS Cache (Check for C2 domains)
Get-DnsClientCache | Export-Csv (Join-Path $EvidencePath "dns_cache.csv") -NoTypeInformation

# 3.3 Scheduled Tasks
Get-ScheduledTask | Where-Object { $_.State -ne "Disabled" -and $_.Author -notmatch "Microsoft" } | 
    Select-Object TaskName, TaskPath, Author, State | Export-Csv (Join-Path $EvidencePath "suspicious_tasks.csv") -NoTypeInformation

Write-Log "Forensic & Boot Integrity Analysis Complete. Evidence saved to $EvidencePath" -Level SUCCESS
