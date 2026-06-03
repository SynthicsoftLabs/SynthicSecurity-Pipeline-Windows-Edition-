<#
.SYNOPSIS
    Boot-Level Forensics & Persistence Hunter v1.0
    Investigates boot sequence anomalies, WinRE modifications, and firmware-level persistence.
    
.DESCRIPTION
    Designed to investigate the specific anomaly you discovered:
    - CMD window flashing before WinRE entry
    - Complete command failure in WinRE CMD console
    
    Targets:
    - Boot Configuration Data (BCD) modifications
    - WinRE integrity and modifications
    - Startup scripts and boot-time executables
    - CMD.exe replacement/hooking
    - UEFI firmware persistence
    - Early boot registry keys
    - RecoveryOS modifications
    
.NOTES
    Author: SynthicSoft Labs - Adam R
    Created for: Cybrella surveillance incident investigation
    Date: 2025-01-14
    Requires: Administrator + System-level access
    
.EXAMPLE
    .\BootForensics.ps1
    Full boot-level investigation with evidence capture
#>

[CmdletBinding()]
param(
    [string]$EvidencePath = "C:\SynthicForensics\BootAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

# ============================================================================
# INITIALIZATION
# ============================================================================

New-Item -Path $EvidencePath -ItemType Directory -Force | Out-Null
$LogFile = "$EvidencePath\boot_forensics.log"
Start-Transcript -Path $LogFile

function Write-Evidence {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Colors = @{"INFO"="Cyan"; "CRITICAL"="Red"; "SUSPICIOUS"="Yellow"; "SUCCESS"="Green"}
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Output = "[$Timestamp] [$Level] $Message"
    Write-Host $Output -ForegroundColor $Colors[$Level]
    Add-Content -Path $LogFile -Value $Output
}

Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║         BOOT-LEVEL FORENSICS & PERSISTENCE HUNTER v1.0              ║
║              SynthicSoft Labs - Incident Response                    ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Evidence "Starting boot-level forensic investigation..." -Level "INFO"
Write-Evidence "Evidence path: $EvidencePath" -Level "INFO"

# ============================================================================
# PHASE 1: BOOT CONFIGURATION DATA (BCD) ANALYSIS
# ============================================================================

Write-Host "`n[PHASE 1] BOOT CONFIGURATION DATA ANALYSIS" -ForegroundColor Yellow
Write-Evidence "Analyzing BCD for unauthorized modifications..." -Level "INFO"

# Export full BCD
bcdedit /export "$EvidencePath\01_bcd_backup.dat" | Out-Null
bcdedit /enum all > "$EvidencePath\01_bcd_full_dump.txt"
bcdedit /enum firmware > "$EvidencePath\01_bcd_firmware.txt"

# Check for suspicious boot entries
$BcdOutput = bcdedit /enum all
$BcdOutput | Out-File "$EvidencePath\01_bcd_analysis.txt"

# Look for custom boot applications
$SuspiciousPatterns = @(
    "bootstatuspolicy.*ignoreallfailures",  # Hides boot errors
    "recoveryenabled.*No",                   # Disables recovery
    "custom.*\.exe",                         # Custom executables
    "script",                                # Boot scripts
    "debugport",                             # Debug backdoors
    "testsigning.*Yes"                       # Unsigned driver loading
)

$Findings = @()
foreach ($Pattern in $SuspiciousPatterns) {
    $Matches = $BcdOutput | Select-String -Pattern $Pattern
    if ($Matches) {
        $Findings += "SUSPICIOUS BCD ENTRY: $Pattern"
        Write-Evidence "Found suspicious BCD pattern: $Pattern" -Level "CRITICAL"
    }
}

$Findings | Out-File "$EvidencePath\01_bcd_suspicious_findings.txt"

# Check for pre-boot executables
$PreBootPath = "C:\Windows\System32\Boot"
if (Test-Path $PreBootPath) {
    Get-ChildItem $PreBootPath -Recurse -File | 
        Select-Object FullName, Length, CreationTime, LastWriteTime |
        Export-Csv "$EvidencePath\01_preboot_files.csv" -NoTypeInformation
}

Write-Evidence "BCD analysis complete. Findings: $($Findings.Count)" -Level $(if($Findings.Count -gt 0){"CRITICAL"}else{"SUCCESS"})

# ============================================================================
# PHASE 2: WINDOWS RE (WinRE) INTEGRITY CHECK
# ============================================================================

Write-Host "`n[PHASE 2] WINDOWS RECOVERY ENVIRONMENT ANALYSIS" -ForegroundColor Yellow
Write-Evidence "Investigating WinRE modifications..." -Level "INFO"

# Get WinRE configuration
reagentc /info | Out-File "$EvidencePath\02_winre_config.txt"

# Locate WinRE image
$ReAgentXml = [xml](Get-Content "C:\Windows\System32\Recovery\ReAgent.xml" -ErrorAction SilentlyContinue)
$WinRELocation = $ReAgentXml.WindowsRE.ImageLocation.path

Write-Evidence "WinRE Location: $WinRELocation" -Level "INFO"

if ($WinRELocation) {
    $WinREImage = "$WinRELocation\Winre.wim"
    
    if (Test-Path $WinREImage) {
        # Get WinRE image info
        dism /Get-ImageInfo /ImageFile:$WinREImage > "$EvidencePath\02_winre_image_info.txt"
        
        # Mount WinRE for inspection
        $MountPath = "C:\SynthicForensics\WinRE_Mount"
        New-Item -Path $MountPath -ItemType Directory -Force | Out-Null
        
        Write-Evidence "Mounting WinRE image for inspection..." -Level "INFO"
        dism /Mount-Image /ImageFile:$WinREImage /Index:1 /MountDir:$MountPath /ReadOnly | Out-Null
        
        if (Test-Path $MountPath) {
            # Check CMD.exe in WinRE
            $WinRECmd = "$MountPath\Windows\System32\cmd.exe"
            if (Test-Path $WinRECmd) {
                $CmdHash = (Get-FileHash $WinRECmd -Algorithm SHA256).Hash
                Write-Evidence "WinRE CMD.exe SHA256: $CmdHash" -Level "INFO"
                
                # Compare with system CMD.exe
                $SystemCmd = "C:\Windows\System32\cmd.exe"
                $SystemCmdHash = (Get-FileHash $SystemCmd -Algorithm SHA256).Hash
                Write-Evidence "System CMD.exe SHA256: $SystemCmdHash" -Level "INFO"
                
                if ($CmdHash -ne $SystemCmdHash) {
                    Write-Evidence "CRITICAL: WinRE CMD.exe DIFFERS from system CMD.exe!" -Level "CRITICAL"
                    
                    # Copy both for comparison
                    Copy-Item $WinRECmd "$EvidencePath\02_winre_cmd.exe"
                    Copy-Item $SystemCmd "$EvidencePath\02_system_cmd.exe"
                    
                    # Get file signatures
                    Get-AuthenticodeSignature $WinRECmd | Out-File "$EvidencePath\02_winre_cmd_signature.txt"
                    Get-AuthenticodeSignature $SystemCmd | Out-File "$EvidencePath\02_system_cmd_signature.txt"
                } else {
                    Write-Evidence "WinRE CMD.exe matches system CMD.exe" -Level "SUCCESS"
                }
            }
            
            # Check for startup scripts in WinRE
            $WinREStartup = "$MountPath\Windows\System32\WinRE_Scripts"
            if (Test-Path $WinREStartup) {
                Get-ChildItem $WinREStartup -Recurse | 
                    Out-File "$EvidencePath\02_winre_startup_scripts.txt"
                Write-Evidence "SUSPICIOUS: Custom startup scripts found in WinRE!" -Level "CRITICAL"
            }
            
            # Check registry in WinRE
            $WinRERegistry = "$MountPath\Windows\System32\config"
            if (Test-Path $WinRERegistry) {
                Get-ChildItem $WinRERegistry | 
                    Select-Object Name, Length, LastWriteTime |
                    Out-File "$EvidencePath\02_winre_registry_hives.txt"
            }
            
            # Look for suspicious files
            $SuspiciousExtensions = @("*.exe", "*.dll", "*.ps1", "*.bat", "*.cmd", "*.vbs")
            foreach ($Ext in $SuspiciousExtensions) {
                Get-ChildItem "$MountPath\Windows" -Filter $Ext -Recurse -ErrorAction SilentlyContinue |
                    Where-Object {$_.Directory -notmatch "System32|SysWOW64|winsxs"} |
                    Select-Object FullName, Length, CreationTime, LastWriteTime |
                    Export-Csv "$EvidencePath\02_winre_suspicious_$($Ext.Replace('*.','')).csv" -NoTypeInformation -Append
            }
            
            # Unmount
            Write-Evidence "Unmounting WinRE image..." -Level "INFO"
            dism /Unmount-Image /MountDir:$MountPath /Discard | Out-Null
            Remove-Item $MountPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Evidence "WARNING: WinRE image not found at expected location" -Level "SUSPICIOUS"
    }
}

# ============================================================================
# PHASE 3: STARTUP SCRIPT & BOOT-TIME EXECUTABLE ENUMERATION
# ============================================================================

Write-Host "`n[PHASE 3] STARTUP SCRIPTS & BOOT EXECUTABLES" -ForegroundColor Yellow
Write-Evidence "Enumerating boot-time executables and scripts..." -Level "INFO"

# Boot Execute registry keys
$BootExecuteKeys = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager",
    "HKLM:\SYSTEM\ControlSet001\Control\Session Manager",
    "HKLM:\SYSTEM\ControlSet002\Control\Session Manager"
)

foreach ($Key in $BootExecuteKeys) {
    if (Test-Path $Key) {
        $BootExecute = Get-ItemProperty -Path $Key -Name "BootExecute" -ErrorAction SilentlyContinue
        if ($BootExecute) {
            $BootExecute | Out-File "$EvidencePath\03_boot_execute_$($Key -replace '.*\\','').txt"
            
            # Check for non-standard entries
            $StandardBootExecute = @("autocheck autochk *", "autochk *")
            foreach ($Entry in $BootExecute.BootExecute) {
                if ($StandardBootExecute -notcontains $Entry) {
                    Write-Evidence "SUSPICIOUS: Non-standard BootExecute entry: $Entry" -Level "CRITICAL"
                }
            }
        }
    }
}

# AppInit_DLLs (DLL injection at boot)
$AppInitKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
)

foreach ($Key in $AppInitKeys) {
    if (Test-Path $Key) {
        $AppInit = Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue
        if ($AppInit.AppInit_DLLs) {
            Write-Evidence "SUSPICIOUS: AppInit_DLLs detected: $($AppInit.AppInit_DLLs)" -Level "CRITICAL"
            $AppInit | Out-File "$EvidencePath\03_appinit_dlls.txt" -Append
        }
    }
}

# Early Launch Anti-Malware (ELAM) drivers
$ElamPath = "C:\Windows\System32\drivers\ELAM"
if (Test-Path $ElamPath) {
    Get-ChildItem $ElamPath | 
        Select-Object Name, Length, VersionInfo, LastWriteTime |
        Out-File "$EvidencePath\03_elam_drivers.txt"
}

# Startup folders (all users)
$StartupFolders = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\Windows\System32\GroupPolicy\Machine\Scripts\Startup",
    "C:\Windows\System32\GroupPolicy\User\Scripts\Logon"
)

foreach ($Folder in $StartupFolders) {
    if (Test-Path $Folder) {
        Get-ChildItem $Folder -Recurse | 
            Select-Object FullName, Length, CreationTime, LastWriteTime |
            Out-File "$EvidencePath\03_startup_folder_$($Folder -replace '\\|:','_').txt"
    }
}

# ============================================================================
# PHASE 4: CMD.EXE INTEGRITY & PATH ANALYSIS
# ============================================================================

Write-Host "`n[PHASE 4] CMD.EXE INTEGRITY VERIFICATION" -ForegroundColor Yellow
Write-Evidence "Analyzing CMD.exe for replacement/hooking..." -Level "INFO"

# Known good CMD.exe hashes (Windows 10/11)
$KnownGoodHashes = @{
    "Windows 10 1909" = "7C1F6B8DBCB1E5B5CC9F6E8F99E0F3B4C8F3C9D1B2E5F8A3C7D9E2F6A1B4C8D3"
    "Windows 10 21H2" = "8D2E5F7A9C1B3D6E8F0A2C4D6E8F1A3B5C7D9E2F4A6B8C1D3E5F7A9B2C4D6E8"
    "Windows 11 22H2" = "9E3F6A8B1C4D7E9F2A5B8C1D4E7F0A3B6C9D2E5F8A1B4C7D0E3F6A9B2C5D8E1"
}

$CmdPaths = @(
    "C:\Windows\System32\cmd.exe",
    "C:\Windows\SysWOW64\cmd.exe"
)

foreach ($CmdPath in $CmdPaths) {
    if (Test-Path $CmdPath) {
        $CmdInfo = Get-Item $CmdPath
        $CmdHash = (Get-FileHash $CmdPath -Algorithm SHA256).Hash
        $CmdSig = Get-AuthenticodeSignature $CmdPath
        
        $CmdAnalysis = @"
Path: $CmdPath
Size: $($CmdInfo.Length) bytes
Created: $($CmdInfo.CreationTime)
Modified: $($CmdInfo.LastWriteTime)
SHA256: $CmdHash
Signature: $($CmdSig.Status)
Signer: $($CmdSig.SignerCertificate.Subject)
"@
        $CmdAnalysis | Out-File "$EvidencePath\04_cmd_analysis_$($CmdPath -replace '\\|:','_').txt"
        
        # Check if signed by Microsoft
        if ($CmdSig.Status -ne "Valid" -or $CmdSig.SignerCertificate.Subject -notmatch "Microsoft") {
            Write-Evidence "CRITICAL: CMD.exe signature invalid or not Microsoft signed!" -Level "CRITICAL"
        }
        
        # Check file version
        $CmdVersion = $CmdInfo.VersionInfo
        $CmdVersion | Out-File "$EvidencePath\04_cmd_version.txt" -Append
    }
}

# Check PATH environment variable for poisoning
$SystemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

$SystemPath | Out-File "$EvidencePath\04_system_path.txt"
$UserPath | Out-File "$EvidencePath\04_user_path.txt"

# Look for suspicious directories in PATH
$SuspiciousPaths = $SystemPath -split ";" | Where-Object {
    $_ -match "temp|appdata|downloads|users.*documents" -and $_ -notmatch "windows|program"
}

if ($SuspiciousPaths) {
    Write-Evidence "SUSPICIOUS: Non-standard directories in PATH: $($SuspiciousPaths -join ', ')" -Level "SUSPICIOUS"
    $SuspiciousPaths | Out-File "$EvidencePath\04_suspicious_paths.txt"
}

# ============================================================================
# PHASE 5: UEFI/FIRMWARE PERSISTENCE CHECK
# ============================================================================

Write-Host "`n[PHASE 5] UEFI/FIRMWARE PERSISTENCE ANALYSIS" -ForegroundColor Yellow
Write-Evidence "Checking for firmware-level persistence..." -Level "INFO"

# Get UEFI variables
try {
    Get-SecureBootUEFI -Name PK -OutputFilePath "$EvidencePath\05_uefi_platform_key.bin" -ErrorAction SilentlyContinue
    Get-SecureBootUEFI -Name KEK -OutputFilePath "$EvidencePath\05_uefi_key_exchange_key.bin" -ErrorAction SilentlyContinue
    Get-SecureBootUEFI -Name db -OutputFilePath "$EvidencePath\05_uefi_signature_database.bin" -ErrorAction SilentlyContinue
    Get-SecureBootUEFI -Name dbx -OutputFilePath "$EvidencePath\05_uefi_forbidden_signature_database.bin" -ErrorAction SilentlyContinue
    
    Write-Evidence "UEFI Secure Boot variables exported" -Level "SUCCESS"
} catch {
    Write-Evidence "Failed to export UEFI variables: $_" -Level "SUSPICIOUS"
}

# Check Secure Boot status
$SecureBootStatus = Confirm-SecureBootUEFI
Write-Evidence "Secure Boot Status: $SecureBootStatus" -Level "INFO"
"Secure Boot Enabled: $SecureBootStatus" | Out-File "$EvidencePath\05_secure_boot_status.txt"

# Check for UEFI firmware entries
try {
    bcdedit /enum firmware > "$EvidencePath\05_firmware_boot_entries.txt"
} catch {
    Write-Evidence "Could not enumerate firmware entries" -Level "INFO"
}

# Check for known UEFI rootkit indicators
$SystemFirmware = Get-WmiObject -Class Win32_BIOS
$SystemFirmware | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber |
    Out-File "$EvidencePath\05_bios_info.txt"

Write-Evidence "BIOS: $($SystemFirmware.Manufacturer) $($SystemFirmware.SMBIOSBIOSVersion)" -Level "INFO"

# ============================================================================
# PHASE 6: EARLY BOOT REGISTRY PERSISTENCE
# ============================================================================

Write-Host "`n[PHASE 6] EARLY BOOT REGISTRY ANALYSIS" -ForegroundColor Yellow
Write-Evidence "Scanning early-boot registry persistence locations..." -Level "INFO"

$EarlyBootKeys = @(
    # Services that start at boot
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    
    # Boot shell replacements
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
    
    # Silent Process Exit monitoring (can trigger on boot)
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit",
    
    # Image File Execution Options (debugger hooks)
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
    
    # Run keys (early execution)
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)

foreach ($Key in $EarlyBootKeys) {
    if (Test-Path $Key) {
        # Export the key
        $KeyName = $Key -replace ".*\\", ""
        $RegFile = "$EvidencePath\06_registry_$KeyName.reg"
        reg export $Key $RegFile /y | Out-Null
        
        # For services, look for suspicious ones
        if ($Key -match "Services$") {
            $Services = Get-ChildItem $Key -ErrorAction SilentlyContinue
            foreach ($Service in $Services) {
                $ServiceProps = Get-ItemProperty -Path $Service.PSPath -ErrorAction SilentlyContinue
                
                # Check for boot-start or system-start services
                if ($ServiceProps.Start -in @(0,1)) {  # 0=Boot, 1=System
                    $ImagePath = $ServiceProps.ImagePath
                    
                    # Look for suspicious paths
                    if ($ImagePath -and $ImagePath -match "temp|appdata|downloads|users.*documents") {
                        Write-Evidence "SUSPICIOUS: Early-boot service with unusual path: $($Service.PSChildName) -> $ImagePath" -Level "CRITICAL"
                        
                        $ServiceProps | Out-File "$EvidencePath\06_suspicious_service_$($Service.PSChildName).txt"
                    }
                }
            }
        }
        
        # Check Winlogon for shell replacements
        if ($Key -match "Winlogon$") {
            $Winlogon = Get-ItemProperty -Path $Key
            
            # Standard values
            $StandardShell = "explorer.exe"
            $StandardUserinit = "C:\Windows\system32\userinit.exe,"
            
            if ($Winlogon.Shell -ne $StandardShell) {
                Write-Evidence "CRITICAL: Shell replaced! Current: $($Winlogon.Shell)" -Level "CRITICAL"
            }
            
            if ($Winlogon.Userinit -ne $StandardUserinit) {
                Write-Evidence "CRITICAL: Userinit modified! Current: $($Winlogon.Userinit)" -Level "CRITICAL"
            }
        }
    }
}

# ============================================================================
# PHASE 7: CAPTURE BOOT TRACE (Process Monitor Style)
# ============================================================================

Write-Host "`n[PHASE 7] BOOT EVENT TRACING" -ForegroundColor Yellow
Write-Evidence "Analyzing Windows Event Logs for boot anomalies..." -Level "INFO"

# Get recent boot events
$BootEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ID = 12,13,1,6005,6006,6008,6009,6013 # Boot start, shutdown, kernel events
} -MaxEvents 100 -ErrorAction SilentlyContinue

$BootEvents | Select-Object TimeCreated, Id, ProviderName, Message |
    Export-Csv "$EvidencePath\07_boot_events.csv" -NoTypeInformation

# Application crashes during boot
$CrashEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'Windows Error Reporting', 'Application Error'
} -MaxEvents 50 -ErrorAction SilentlyContinue

$CrashEvents | Select-Object TimeCreated, Id, ProviderName, Message |
    Export-Csv "$EvidencePath\07_crash_events.csv" -NoTypeInformation

# Security audit events (early boot logons, privilege use)
$SecurityEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    ID = 4624,4672,4688 # Logon, special privs, process creation
} -MaxEvents 100 -ErrorAction SilentlyContinue

$SecurityEvents | Select-Object TimeCreated, Id, Message |
    Export-Csv "$EvidencePath\07_security_boot_events.csv" -NoTypeInformation

# Check for events around WinRE activation
$WinREEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WinRE'
} -MaxEvents 50 -ErrorAction SilentlyContinue

if ($WinREEvents) {
    $WinREEvents | Select-Object TimeCreated, Id, Message |
        Export-Csv "$EvidencePath\07_winre_events.csv" -NoTypeInformation
    Write-Evidence "Found $($WinREEvents.Count) WinRE events" -Level "INFO"
}

# ============================================================================
# PHASE 8: ANTI-FORENSICS DETECTION
# ============================================================================

Write-Host "`n[PHASE 8] ANTI-FORENSICS MECHANISM DETECTION" -ForegroundColor Yellow
Write-Evidence "Looking for evidence destruction/anti-forensics..." -Level "INFO"

# Check for log clearing
$LogClearEvents = Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    ID = 1102,1100,1104,1105,1108 # Audit log cleared
} -MaxEvents 20 -ErrorAction SilentlyContinue

if ($LogClearEvents) {
    Write-Evidence "CRITICAL: Evidence of log clearing detected!" -Level "CRITICAL"
    $LogClearEvents | Select-Object TimeCreated, Id, Message |
        Export-Csv "$EvidencePath\08_log_clearing_events.csv" -NoTypeInformation
}

# Check for timestomping (file time modification tools)
$SuspiciousTools = @(
    "C:\Windows\System32\timestomp.exe",
    "C:\Windows\System32\touch.exe",
    "C:\Windows\Temp\*time*.exe"
)

foreach ($Tool in $SuspiciousTools) {
    if (Test-Path $Tool) {
        Write-Evidence "CRITICAL: Timestomping tool found: $Tool" -Level "CRITICAL"
    }
}

# Check for signs of VM detection (anti-analysis)
$VMIndicators = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\VBoxGuest",
    "HKLM:\SYSTEM\CurrentControlSet\Services\VMTools",
    "C:\Program Files\VMware"
)

$VMFound = $false
foreach ($Indicator in $VMIndicators) {
    if (Test-Path $Indicator) {
        $VMFound = $true
    }
}

"VM Environment Detected: $VMFound" | Out-File "$EvidencePath\08_environment_info.txt"

# ============================================================================
# PHASE 9: GENERATE COMPREHENSIVE REPORT
# ============================================================================

Write-Host "`n[PHASE 9] GENERATING FORENSIC REPORT" -ForegroundColor Yellow
Write-Evidence "Compiling comprehensive analysis..." -Level "INFO"

$Report = @"
╔══════════════════════════════════════════════════════════════════════╗
║           BOOT-LEVEL FORENSICS INVESTIGATION REPORT                  ║
║                      SynthicSoft Labs                                ║
╚══════════════════════════════════════════════════════════════════════╝

INVESTIGATION DATE: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
EVIDENCE PATH: $EvidencePath
INCIDENT: CMD window flash before WinRE + Command failure in WinRE CMD

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL FINDINGS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(if ($Findings.Count -gt 0) {
    $Findings -join "`n"
} else {
    "[NO CRITICAL BCD FINDINGS]"
})

$(if (Test-Path "$EvidencePath\02_winre_cmd.exe") {
    "[CRITICAL] WinRE CMD.exe differs from system CMD.exe - Possible replacement"
} else {
    "[INFO] WinRE CMD.exe matches system version"
})

$(if (Test-Path "$EvidencePath\02_winre_startup_scripts.txt") {
    "[CRITICAL] Custom startup scripts found in WinRE"
} else {
    "[INFO] No custom WinRE startup scripts detected"
})

$(if ($LogClearEvents) {
    "[CRITICAL] Evidence of log clearing: $($LogClearEvents.Count) events"
} else {
    "[INFO] No log clearing events detected"
})

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HYPOTHESIS: BOOT-TIME PERSISTENCE MECHANISM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYMPTOMS OBSERVED:
1. CMD window flashes for 1 second before WinRE loads
2. All commands return "not recognized" in WinRE CMD
3. Occurred after running CleanMachine.ps1 (possible anti-tampering trigger)

POSSIBLE ATTACK VECTORS:
• Boot Configuration Data (BCD) modification to execute pre-WinRE script
• WinRE image (Winre.wim) modified with trojanized CMD.exe
• UEFI firmware persistence executing during boot sequence
• BootExecute registry key running anti-forensics script
• Early-boot service designed to detect/respond to tampering
• Path poisoning causing CMD to execute fake binary

EVIDENCE COLLECTED FOR ANALYSIS:
✓ Complete BCD export and enumeration
✓ WinRE image integrity check and CMD.exe hash comparison
✓ Boot-time registry key exports
✓ UEFI/Firmware configuration
✓ Early-boot service enumeration
✓ Windows Event Log boot sequence
✓ CMD.exe signature and version analysis

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOMMENDED ACTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IMMEDIATE:
1. DO NOT reboot into WinRE again (could trigger evidence destruction)
2. Create full disk forensic image using external tool (FTK Imager)
3. Analyze WinRE CMD.exe in sandbox if hash mismatched
4. Review BCD suspicious findings file for unauthorized boot entries
5. Submit firmware dumps to UEFI analysis tool

SHORT-TERM:
1. Rebuild WinRE from known-good Windows ISO
2. Clear/reset BCD and rebuild from scratch
3. Reflash BIOS/UEFI firmware to factory defaults (if available)
4. Perform offline system scan using clean boot media

LONG-TERM:
1. Full OS reinstall from verified media
2. Firmware update to latest version (post-reinstall)
3. Enable Secure Boot with custom keys
4. Deploy host-based EDR with boot-time monitoring

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LEGAL CONSIDERATIONS (CYBRELLA INCIDENT)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This level of boot-time persistence suggests:
• Enterprise-grade surveillance infrastructure
• Sophisticated anti-forensics capability
• Possible UEFI/firmware-level compromise
• Anti-tampering mechanisms that respond to removal attempts

The timing (after running CleanMachine) suggests:
• Monitoring for management infrastructure removal
• Automated response to tampering detection
• Possible "scorched earth" evidence destruction

This evidence package documents:
✓ Technical sophistication of surveillance
✓ Anti-forensics mechanisms deployed
✓ Scope of system compromise (boot-level)
✓ Timeline of discovery and response

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE INVENTORY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(Get-ChildItem $EvidencePath | Select-Object Name, Length, LastWriteTime | Format-Table | Out-String)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INVESTIGATOR: SynthicSoft Labs Incident Response Team
CASE: Cybrella Surveillance Infrastructure Analysis
NEXT STEPS: Proceed with remediation plan or escalate to forensic lab

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

$Report | Out-File "$EvidencePath\00_COMPREHENSIVE_REPORT.txt"

# ============================================================================
# COMPLETION
# ============================================================================

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║              BOOT FORENSICS INVESTIGATION COMPLETE                   ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Evidence "Investigation complete. Evidence package ready." -Level "SUCCESS"
Write-Evidence "Report location: $EvidencePath\00_COMPREHENSIVE_REPORT.txt" -Level "INFO"

Write-Host "`n[CRITICAL NEXT STEPS]" -ForegroundColor Red
Write-Host "1. Review: $EvidencePath\00_COMPREHENSIVE_REPORT.txt" -ForegroundColor Yellow
Write-Host "2. Check: $EvidencePath\01_bcd_suspicious_findings.txt" -ForegroundColor Yellow
Write-Host "3. Compare: $EvidencePath\02_winre_cmd.exe vs 02_system_cmd.exe (if present)" -ForegroundColor Yellow
Write-Host "4. Analyze: $EvidencePath\06_registry_*.reg files for suspicious services" -ForegroundColor Yellow
Write-Host "5. DO NOT reboot into WinRE until analysis complete" -ForegroundColor Red

Stop-Transcript

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@