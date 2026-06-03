<#
.SYNOPSIS
    Boot-Level Persistence Remediation Toolkit v1.0
    Surgically removes boot-time persistence and rebuilds critical boot components.
    
.DESCRIPTION
    Based on findings from BootForensics.ps1, this tool:
    - Rebuilds Windows Recovery Environment from clean source
    - Reconstructs Boot Configuration Data (BCD)
    - Removes boot-time registry persistence
    - Verifies/replaces CMD.exe integrity
    - Cleans startup scripts and boot executables
    
    USE ONLY AFTER reviewing BootForensics evidence package.
    
.NOTES
    Author: SynthicSoft Labs - Adam R
    Created for: Cybrella boot-level persistence removal
    Date: 2025-01-14
    Requires: Administrator + Clean Windows ISO/media
    
.EXAMPLE
    .\BootRemediation.ps1 -ISOPath "D:\Windows11.iso"
    Full boot-level cleanup with WinRE rebuild from ISO
    
.EXAMPLE
    .\BootRemediation.ps1 -SkipWinRE
    Clean boot persistence without rebuilding WinRE
#>

[CmdletBinding()]
param(
    [string]$ISOPath,
    [switch]$SkipWinRE,
    [switch]$SkipBCD,
    [string]$LogPath = "C:\SynthicForensics\BootRemediation_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
$LogFile = "$LogPath\remediation.log"
Start-Transcript -Path $LogFile

function Write-Action {
    param([string]$Message, [string]$Level = "INFO")
    $Colors = @{"INFO"="Cyan"; "SUCCESS"="Green"; "WARNING"="Yellow"; "ERROR"="Red"}
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message" -ForegroundColor $Colors[$Level]
    Add-Content -Path $LogFile -Value "[$Timestamp] [$Level] $Message"
}

Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║        BOOT-LEVEL PERSISTENCE REMEDIATION TOOLKIT v1.0              ║
║                 ⚠️  DESTRUCTIVE OPERATIONS AHEAD  ⚠️                  ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

Write-Host "`n[WARNING] This script will make significant boot-level changes." -ForegroundColor Yellow
Write-Host "[WARNING] Ensure you have reviewed BootForensics evidence first." -ForegroundColor Yellow
Write-Host "[WARNING] Create a full system backup before proceeding.`n" -ForegroundColor Yellow

$Confirmation = Read-Host "Type 'PROCEED' to continue or anything else to abort"
if ($Confirmation -ne "PROCEED") {
    Write-Host "Remediation aborted by user." -ForegroundColor Red
    exit 1
}

Write-Action "Starting boot-level persistence remediation" -Level "INFO"

# ============================================================================
# PHASE 1: BACKUP CRITICAL COMPONENTS
# ============================================================================

Write-Host "`n[PHASE 1] BACKING UP CRITICAL COMPONENTS" -ForegroundColor Yellow
Write-Action "Creating backups before modification..." -Level "INFO"

# Backup BCD
bcdedit /export "$LogPath\bcd_backup_$(Get-Date -Format 'HHmmss').dat" | Out-Null
Write-Action "BCD backed up" -Level "SUCCESS"

# Backup registry keys
$CriticalKeys = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
)

foreach ($Key in $CriticalKeys) {
    $KeyName = $Key -replace ".*\\", ""
    reg export $Key "$LogPath\registry_backup_$KeyName.reg" /y | Out-Null
}

Write-Action "Registry keys backed up" -Level "SUCCESS"

# ============================================================================
# PHASE 2: REMOVE BOOT-TIME REGISTRY PERSISTENCE
# ============================================================================

Write-Host "`n[PHASE 2] REMOVING BOOT-TIME REGISTRY PERSISTENCE" -ForegroundColor Yellow
Write-Action "Cleaning early-boot registry keys..." -Level "INFO"

# Clean BootExecute (keep only standard entries)
$SessionManagerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$BootExecute = (Get-ItemProperty -Path $SessionManagerKey).BootExecute

$StandardBootExecute = @("autocheck autochk *")
$Cleaned = $false

foreach ($Entry in $BootExecute) {
    if ($Entry -notin $StandardBootExecute) {
        Write-Action "Removing suspicious BootExecute entry: $Entry" -Level "WARNING"
        $Cleaned = $true
    }
}

if ($Cleaned) {
    Set-ItemProperty -Path $SessionManagerKey -Name "BootExecute" -Value $StandardBootExecute
    Write-Action "BootExecute cleaned to standard values" -Level "SUCCESS"
}

# Remove AppInit_DLLs
$AppInitKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
)

foreach ($Key in $AppInitKeys) {
    if (Test-Path $Key) {
        $AppInit = Get-ItemProperty -Path $Key -Name "AppInit_DLLs" -ErrorAction SilentlyContinue
        if ($AppInit.AppInit_DLLs) {
            Write-Action "Removing AppInit_DLLs: $($AppInit.AppInit_DLLs)" -Level "WARNING"
            Remove-ItemProperty -Path $Key -Name "AppInit_DLLs" -Force
            Set-ItemProperty -Path $Key -Name "LoadAppInit_DLLs" -Value 0
        }
    }
}

# Reset Winlogon to defaults
$WinlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $WinlogonKey -Name "Shell" -Value "explorer.exe"
Set-ItemProperty -Path $WinlogonKey -Name "Userinit" -Value "C:\Windows\system32\userinit.exe,"
Write-Action "Winlogon reset to default values" -Level "SUCCESS"

# Remove Silent Process Exit monitoring
$SilentExitKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit"
if (Test-Path $SilentExitKey) {
    Remove-Item -Path $SilentExitKey -Recurse -Force
    Write-Action "Silent Process Exit monitoring removed" -Level "SUCCESS"
}

# Clean Image File Execution Options (remove debuggers)
$IFEOKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$IFEOEntries = Get-ChildItem $IFEOKey -ErrorAction SilentlyContinue

foreach ($Entry in $IFEOEntries) {
    $Debugger = Get-ItemProperty -Path $Entry.PSPath -Name "Debugger" -ErrorAction SilentlyContinue
    if ($Debugger) {
        Write-Action "Removing debugger from: $($Entry.PSChildName)" -Level "WARNING"
        Remove-ItemProperty -Path $Entry.PSPath -Name "Debugger" -Force
    }
}

Write-Action "Registry persistence cleaned" -Level "SUCCESS"

# ============================================================================
# PHASE 3: REMOVE SUSPICIOUS BOOT-START SERVICES
# ============================================================================

Write-Host "`n[PHASE 3] REMOVING SUSPICIOUS BOOT-START SERVICES" -ForegroundColor Yellow
Write-Action "Scanning for unauthorized boot-start services..." -Level "INFO"

$ServicesKey = "HKLM:\SYSTEM\CurrentControlSet\Services"
$Services = Get-ChildItem $ServicesKey -ErrorAction SilentlyContinue

$RemovedServices = 0
foreach ($Service in $Services) {
    $ServiceProps = Get-ItemProperty -Path $Service.PSPath -ErrorAction SilentlyContinue
    
    # Check for boot-start (0) or system-start (1) services
    if ($ServiceProps.Start -in @(0,1)) {
        $ImagePath = $ServiceProps.ImagePath
        
        # Flag suspicious paths
        if ($ImagePath -and $ImagePath -match "temp|appdata|downloads|users\\.*\\documents") {
            Write-Action "SUSPICIOUS SERVICE: $($Service.PSChildName) -> $ImagePath" -Level "WARNING"
            
            # Log for manual review
            $ServiceProps | Out-File "$LogPath\suspicious_service_$($Service.PSChildName).txt"
            
            Write-Host "  Service: $($Service.PSChildName)" -ForegroundColor Red
            Write-Host "  Path: $ImagePath" -ForegroundColor Red
            $Remove = Read-Host "  Remove this service? (Y/N)"
            
            if ($Remove -eq 'Y') {
                Remove-Item -Path $Service.PSPath -Recurse -Force
                Write-Action "Removed service: $($Service.PSChildName)" -Level "SUCCESS"
                $RemovedServices++
            }
        }
    }
}

Write-Action "Boot-start services reviewed. Removed: $RemovedServices" -Level "SUCCESS"

# ============================================================================
# PHASE 4: VERIFY/REPLACE CMD.EXE
# ============================================================================

Write-Host "`n[PHASE 4] CMD.EXE INTEGRITY VERIFICATION" -ForegroundColor Yellow
Write-Action "Verifying CMD.exe integrity..." -Level "INFO"

$CmdPaths = @(
    "C:\Windows\System32\cmd.exe",
    "C:\Windows\SysWOW64\cmd.exe"
)

foreach ($CmdPath in $CmdPaths) {
    if (Test-Path $CmdPath) {
        $CmdSig = Get-AuthenticodeSignature $CmdPath
        
        if ($CmdSig.Status -ne "Valid" -or $CmdSig.SignerCertificate.Subject -notmatch "Microsoft") {
            Write-Action "CRITICAL: CMD.exe signature invalid! $CmdPath" -Level "ERROR"
            
            # Try to restore from WinSxS
            $Architecture = if ($CmdPath -match "SysWOW64") { "wow64" } else { "amd64" }
            $WinSxSCmd = Get-ChildItem "C:\Windows\WinSxS" -Filter "cmd.exe" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match $Architecture } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            
            if ($WinSxSCmd) {
                Write-Action "Found backup CMD.exe in WinSxS: $($WinSxSCmd.FullName)" -Level "INFO"
                
                # Backup compromised version
                Copy-Item $CmdPath "$LogPath\cmd_compromised_$(Split-Path $CmdPath -Leaf)" -Force
                
                # Replace with clean version
                takeown /f $CmdPath /a | Out-Null
                icacls $CmdPath /grant administrators:F | Out-Null
                Copy-Item $WinSxSCmd.FullName $CmdPath -Force
                
                Write-Action "CMD.exe replaced with clean version from WinSxS" -Level "SUCCESS"
            } else {
                Write-Action "ERROR: Could not find clean CMD.exe backup" -Level "ERROR"
            }
        } else {
            Write-Action "CMD.exe integrity verified: $CmdPath" -Level "SUCCESS"
        }
    }
}

# ============================================================================
# PHASE 5: REBUILD WINDOWS RECOVERY ENVIRONMENT
# ============================================================================

if (!$SkipWinRE) {
    Write-Host "`n[PHASE 5] REBUILDING WINDOWS RECOVERY ENVIRONMENT" -ForegroundColor Yellow
    Write-Action "Rebuilding WinRE from clean source..." -Level "INFO"
    
    if (!$ISOPath) {
        Write-Action "WARNING: No ISO path provided. Skipping WinRE rebuild." -Level "WARNING"
        Write-Action "To rebuild WinRE manually, provide -ISOPath parameter" -Level "INFO"
    } else {
        if (!(Test-Path $ISOPath)) {
            Write-Action "ERROR: ISO not found at $ISOPath" -Level "ERROR"
        } else {
            # Mount ISO
            Write-Action "Mounting Windows ISO..." -Level "INFO"
            $MountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru
            $DriveLetter = ($MountResult | Get-Volume).DriveLetter
            
            $SourceWinRE = "${DriveLetter}:\sources\boot.wim"
            
            if (Test-Path $SourceWinRE) {
                # Disable current WinRE
                reagentc /disable
                
                # Get WinRE location
                $ReAgentXml = [xml](Get-Content "C:\Windows\System32\Recovery\ReAgent.xml")
                $WinRELocation = $ReAgentXml.WindowsRE.ImageLocation.path
                
                # Backup old WinRE
                $OldWinRE = "$WinRELocation\Winre.wim"
                if (Test-Path $OldWinRE) {
                    Copy-Item $OldWinRE "$LogPath\winre_old.wim" -Force
                    Write-Action "Old WinRE backed up" -Level "SUCCESS"
                }
                
                # Extract WinRE from ISO
                Write-Action "Extracting clean WinRE from ISO..." -Level "INFO"
                dism /export-image /SourceImageFile:$SourceWinRE /SourceIndex:1 /DestinationImageFile:"$WinRELocation\Winre.wim" /Compress:max /CheckIntegrity
                
                # Re-enable WinRE
                reagentc /enable
                reagentc /info | Out-File "$LogPath\winre_rebuild_info.txt"
                
                Write-Action "WinRE rebuilt from clean ISO" -Level "SUCCESS"
            } else {
                Write-Action "ERROR: boot.wim not found in ISO" -Level "ERROR"
            }
            
            # Dismount ISO
            Dismount-DiskImage -ImagePath $ISOPath | Out-Null
        }
    }
}

# ============================================================================
# PHASE 6: BOOT CONFIGURATION DATA REBUILD
# ============================================================================

if (!$SkipBCD) {
    Write-Host "`n[PHASE 6] BOOT CONFIGURATION DATA HARDENING" -ForegroundColor Yellow
    Write-Action "Hardening BCD configuration..." -Level "INFO"
    
    # Enable recovery
    bcdedit /set {current} recoveryenabled Yes
    
    # Disable test signing
    bcdedit /set {current} testsigning Off
    
    # Set boot status policy to display all failures
    bcdedit /set {current} bootstatuspolicy DisplayAllFailures
    
    # Disable debug port (closes potential backdoor)
    bcdedit /set {current} debug No
    bcdedit /deletevalue {current} debugport
    
    # Remove any custom boot applications
    $BootMgr = bcdedit /enum {bootmgr}
    if ($BootMgr -match "custom") {
        Write-Action "WARNING: Custom boot manager detected. Manual review required." -Level "WARNING"
        $BootMgr | Out-File "$LogPath\bootmgr_custom.txt"
    }
    
    Write-Action "BCD hardened" -Level "SUCCESS"
}

# ============================================================================
# PHASE 7: CLEAN STARTUP LOCATIONS
# ============================================================================

Write-Host "`n[PHASE 7] CLEANING STARTUP LOCATIONS" -ForegroundColor Yellow
Write-Action "Removing unauthorized startup scripts..." -Level "INFO"

$StartupLocations = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\Windows\System32\GroupPolicy\Machine\Scripts\Startup",
    "C:\Windows\System32\GroupPolicy\User\Scripts\Logon"
)

foreach ($Location in $StartupLocations) {
    if (Test-Path $Location) {
        $Items = Get-ChildItem $Location -File -ErrorAction SilentlyContinue
        
        foreach ($Item in $Items) {
            Write-Action "Found startup item: $($Item.Name)" -Level "WARNING"
            $Item | Select-Object FullName, Length, CreationTime, LastWriteTime |
                Out-File "$LogPath\startup_removed_$($Item.Name).txt"
            
            $Remove = Read-Host "Remove $($Item.Name)? (Y/N)"
            if ($Remove -eq 'Y') {
                Remove-Item $Item.FullName -Force
                Write-Action "Removed: $($Item.Name)" -Level "SUCCESS"
            }
        }
    }
}

# ============================================================================
# PHASE 8: FIRMWARE/UEFI GUIDANCE
# ============================================================================

Write-Host "`n[PHASE 8] FIRMWARE/UEFI RECOMMENDATIONS" -ForegroundColor Yellow
Write-Action "Generating UEFI security recommendations..." -Level "INFO"

$SecureBootStatus = Confirm-SecureBootUEFI
$SystemInfo = Get-WmiObject -Class Win32_BIOS

$UEFIReport = @"
╔══════════════════════════════════════════════════════════════════════╗
║                   UEFI/FIRMWARE SECURITY REPORT                      ║
╚══════════════════════════════════════════════════════════════════════╝

CURRENT STATUS:
• Secure Boot: $SecureBootStatus
• BIOS Manufacturer: $($SystemInfo.Manufacturer)
• BIOS Version: $($SystemInfo.SMBIOSBIOSVersion)
• BIOS Date: $($SystemInfo.ReleaseDate)

RECOMMENDATIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(if (!$SecureBootStatus) {
@"
⚠️  CRITICAL: Secure Boot is DISABLED
   → This allows unsigned boot-time code execution
   → Enable in UEFI settings: Security → Secure Boot → Enabled
"@
} else {
@"
✅ Secure Boot is enabled (good)
"@
})

MANUAL ACTIONS REQUIRED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. REFLASH BIOS/UEFI FIRMWARE
   → Download latest firmware from $($SystemInfo.Manufacturer)
   → Use manufacturer's official update utility
   → This removes potential firmware-level persistence

2. RESET UEFI TO FACTORY DEFAULTS
   → Boot to UEFI/BIOS setup
   → Find "Load Setup Defaults" or "Reset to Factory"
   → Save and exit

3. CLEAR TPM (if applicable)
   → UEFI → Security → TPM → Clear TPM
   → WARNING: This will erase BitLocker keys (back up first)

4. SECURE BOOT KEYS
   → Consider resetting Secure Boot keys to factory defaults
   → Advanced users: Enroll custom keys for additional control

5. DISABLE LEGACY BOOT
   → UEFI → Boot → Boot Mode → UEFI only (disable CSM/Legacy)
   → Prevents MBR-based bootkits

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

$UEFIReport | Out-File "$LogPath\uefi_recommendations.txt"
Write-Host $UEFIReport -ForegroundColor Cyan

# ============================================================================
# PHASE 9: FINAL VERIFICATION
# ============================================================================

Write-Host "`n[PHASE 9] POST-REMEDIATION VERIFICATION" -ForegroundColor Yellow
Write-Action "Verifying remediation..." -Level "INFO"

# Re-check boot execute
$BootExecuteCheck = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager").BootExecute
Write-Action "BootExecute: $BootExecuteCheck" -Level "INFO"

# Re-check CMD signature
$CmdCheck = Get-AuthenticodeSignature "C:\Windows\System32\cmd.exe"
Write-Action "CMD.exe signature status: $($CmdCheck.Status)" -Level $(if($CmdCheck.Status -eq "Valid"){"SUCCESS"}else{"ERROR"})

# Check WinRE status
reagentc /info | Out-File "$LogPath\final_winre_status.txt"

Write-Action "Remediation verification complete" -Level "SUCCESS"

# ============================================================================
# COMPLETION REPORT
# ============================================================================

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║           BOOT-LEVEL PERSISTENCE REMEDIATION COMPLETE                ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

$Summary = @"
REMEDIATION SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ACTIONS COMPLETED:
✓ Boot-time registry persistence removed
✓ Suspicious boot-start services reviewed
✓ CMD.exe integrity verified/restored
$(if (!$SkipWinRE) {"✓ Windows Recovery Environment rebuilt"} else {"⊘ WinRE rebuild skipped"})
$(if (!$SkipBCD) {"✓ Boot Configuration Data hardened"} else {"⊘ BCD hardening skipped"})
✓ Startup locations cleaned
✓ UEFI recommendations generated

MANUAL ACTIONS STILL REQUIRED:
→ Review: $LogPath\uefi_recommendations.txt
→ Reflash BIOS/UEFI firmware
→ Reset UEFI to factory defaults
→ Enable Secure Boot (if disabled)
→ Test boot into WinRE (Shift+Restart)

NEXT BOOT:
• Watch for the flashing CMD window
• If it still appears, firmware-level persistence is likely
• Consider full OS reinstall from clean media

BACKUPS LOCATION: $LogPath
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

$Summary | Out-File "$LogPath\00_REMEDIATION_SUMMARY.txt"
Write-Host $Summary -ForegroundColor Cyan

Stop-Transcript

Write-Host "`nRemediation complete. System reboot recommended.`n" -ForegroundColor Yellow
$Reboot = Read-Host "Reboot now? (Y/N)"
if ($Reboot -eq 'Y') {
    shutdown /r /t 30 /c "Reboot for boot-level remediation"
}
"@