#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft system-prep.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("system-prep-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$LogToFile = $VerboseLoggingToFile.IsPresent

if ($LogToFile) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $ts   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts][$Level] $Message"
    Write-Host $line -ForegroundColor $Color
    if ($LogToFile) {
        Add-Content -Path $LogFile -Value $line
    }
}

Write-Log "=== $ScriptName v$ScriptVersion ===" "INFO" Cyan

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Must run as Administrator." "FATAL" Red
    exit 1
}

function Create-SystemRestorePoint {
    Write-Log "Creating system restore point..." "INFO" Cyan
    
    try {
        # Enable System Restore if not enabled
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        
        # Create restore point
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        Checkpoint-Computer -Description "SynthicSoft Setup Suite - $timestamp" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "System restore point created successfully." "OK" Green
    } catch {
        Write-Log "System restore point creation failed: $_" "WARN" Yellow
    }
}

function Generate-SystemDocumentation {
    Write-Log "Generating system documentation..." "INFO" Cyan
    
    try {
        $docPath = "C:\ProgramData\SynthicSoft\SystemInfo"
        if (!(Test-Path $docPath)) {
            New-Item -ItemType Directory -Path $docPath -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        
        # Computer info
        $computerInfo = Get-ComputerInfo | Select-Object `
            CsName, CsManufacturer, CsModel, `
            OsName, OsVersion, OsBuildNumber, OsArchitecture, `
            CsProcessors, CsTotalPhysicalMemory, `
            OsInstallDate, OsLastBootUpTime
        
        $computerInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath "$docPath\ComputerInfo-$timestamp.json" -Force
        
        # Installed software
        $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
            Where-Object {$_.DisplayName} |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        
        $software | ConvertTo-Json -Depth 2 | Out-File -FilePath "$docPath\InstalledSoftware-$timestamp.json" -Force
        
        # Network configuration
        $networkConfig = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | 
            Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed
        
        $networkConfig | ConvertTo-Json -Depth 2 | Out-File -FilePath "$docPath\NetworkConfig-$timestamp.json" -Force
        
        # Disk information
        $diskInfo = Get-Disk | Select-Object Number, FriendlyName, PartitionStyle, Size, HealthStatus
        $diskInfo | ConvertTo-Json -Depth 2 | Out-File -FilePath "$docPath\DiskInfo-$timestamp.json" -Force
        
        Write-Log "System documentation saved to: $docPath" "OK" Green
        
        # Create human-readable summary
        $summary = @"
=== SYSTEM INFORMATION SUMMARY ===
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Computer: $($computerInfo.CsName)
Manufacturer: $($computerInfo.CsManufacturer)
Model: $($computerInfo.CsModel)
OS: $($computerInfo.OsName) $($computerInfo.OsVersion)
Build: $($computerInfo.OsBuildNumber)
Installed: $($computerInfo.OsInstallDate)
Last Boot: $($computerInfo.OsLastBootUpTime)

Memory: $([math]::Round($computerInfo.CsTotalPhysicalMemory / 1GB, 2)) GB
Processors: $($computerInfo.CsProcessors.Count)

Installed Applications: $($software.Count)
Active Network Adapters: $($networkConfig.Count)
Physical Disks: $($diskInfo.Count)

Full documentation available at: $docPath
"@
        
        $summary | Out-File -FilePath "$docPath\SystemSummary-$timestamp.txt" -Force
        
    } catch {
        Write-Log "System documentation generation failed: $_" "WARN" Yellow
    }
}

function Configure-ScheduledMaintenance {
    Write-Log "Configuring scheduled maintenance tasks..." "INFO" Cyan
    
    try {
        # Weekly disk cleanup task
        $action = New-ScheduledTaskAction -Execute "cleanmgr.exe" -Argument "/sagerun:1"
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName "SynthicSoft-WeeklyDiskCleanup" `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
            -Description "Weekly disk cleanup" -Force | Out-Null
        
        Write-Log "Scheduled weekly disk cleanup task." "OK" Green
        
        # Weekly Defender full scan
        $action2 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"Start-MpScan -ScanType FullScan`""
        $trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At 3am
        
        Register-ScheduledTask -TaskName "SynthicSoft-WeeklyDefenderScan" `
            -Action $action2 -Trigger $trigger2 -Principal $principal -Settings $settings `
            -Description "Weekly Defender full scan" -Force | Out-Null
        
        Write-Log "Scheduled weekly Defender full scan." "OK" Green
        
    } catch {
        Write-Log "Scheduled maintenance configuration failed: $_" "WARN" Yellow
    }
}

function Verify-BitLocker {
    Write-Log "Checking BitLocker encryption status..." "INFO" Cyan
    
    try {
        $bitlockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        $systemDrive = $bitlockerVolumes | Where-Object {$_.MountPoint -eq "$env:SystemDrive\"}
        
        if ($systemDrive) {
            if ($systemDrive.ProtectionStatus -eq "On") {
                Write-Log "BitLocker is ENABLED and protecting system drive." "OK" Green
            } else {
                Write-Log "BitLocker is available but NOT protecting system drive." "WARN" Yellow
                Write-Log "Consider enabling BitLocker for full disk encryption." "INFO" Gray
            }
        } else {
            Write-Log "BitLocker status could not be determined." "INFO" Gray
        }
    } catch {
        Write-Log "BitLocker check failed: $_" "WARN" Yellow
    }
}

function Create-RecoveryDocumentation {
    Write-Log "Creating disaster recovery documentation..." "INFO" Cyan
    
    try {
        $recoveryPath = "C:\ProgramData\SynthicSoft\Recovery"
        if (!(Test-Path $recoveryPath)) {
            New-Item -ItemType Directory -Path $recoveryPath -Force | Out-Null
        }
        
        $recoveryDoc = @"
=== DISASTER RECOVERY GUIDE ===
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
System: $env:COMPUTERNAME

CRITICAL INFORMATION:
- This system was configured by SynthicSoft Windows Setup Suite
- All setup logs are in: C:\ProgramData\SynthicSoft\Logs
- System documentation: C:\ProgramData\SynthicSoft\SystemInfo

BACKUP SOLUTION:
- IDrive backup software is installed
- Configure IDrive with your account credentials
- Set backup schedule for critical data
- Test restore capability regularly

RECOVERY STEPS (In Case of Failure):
1. Boot from Windows installation media
2. Select "Repair your computer"
3. Choose "System Restore" and select SynthicSoft restore point
4. If restore fails, reinstall Windows 11
5. Re-run SynthicSoft setup suite: master.ps1 -VerboseLoggingToFile
6. Restore data from IDrive backup

IMPORTANT CONTACTS:
- IT Support: [Configure in your organization]
- IDrive Support: support@idrive.com
- Microsoft Support: support.microsoft.com

LICENSES & CREDENTIALS:
[Store securely - DO NOT save passwords in this file]
- Windows License: [Document product key location]
- Software Licenses: [List commercial software]
- Service Accounts: [List service credentials location]

NETWORK CONFIGURATION:
- Computer Name: $env:COMPUTERNAME
- Domain/Workgroup: $env:USERDOMAIN
- IP Configuration: See NetworkConfig-*.json in SystemInfo folder

SECURITY NOTES:
- BitLocker Status: $(if ((Get-BitLockerVolume -MountPoint "$env:SystemDrive\" -ErrorAction SilentlyContinue).ProtectionStatus -eq "On") {"ENABLED"} else {"DISABLED - Consider enabling"})
- Defender: Enabled with weekly full scans
- Firewall: Enabled on all profiles
- Updates: Automatic via Windows Update

MAINTENANCE SCHEDULE:
- Weekly Disk Cleanup: Sundays at 2:00 AM
- Weekly Defender Scan: Saturdays at 3:00 AM
- Monthly Security Patches: Automatic via patch-intel.ps1

For questions about this system configuration:
Review logs in C:\ProgramData\SynthicSoft\Logs

Last Setup Run: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
        
        $recoveryDoc | Out-File -FilePath "$recoveryPath\DISASTER_RECOVERY_GUIDE.txt" -Force
        Write-Log "Recovery documentation created at: $recoveryPath" "OK" Green
        
    } catch {
        Write-Log "Recovery documentation creation failed: $_" "WARN" Yellow
    }
}

function Configure-AutomaticDriverUpdates {
    Write-Log "Configuring automatic driver updates..." "INFO" Cyan
    
    try {
        # Enable driver updates via Windows Update
        $driverPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
        if (!(Test-Path $driverPath)) {
            New-Item -Path $driverPath -Force | Out-Null
        }
        Set-ItemProperty -Path $driverPath -Name "SearchOrderConfig" -Value 1 -Type DWord -Force
        
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (!(Test-Path $wuPath)) {
            New-Item -Path $wuPath -Force | Out-Null
        }
        Set-ItemProperty -Path $wuPath -Name "ExcludeWUDriversInQualityUpdate" -Value 0 -Type DWord -Force
        
        Write-Log "Automatic driver updates enabled via Windows Update." "OK" Green
    } catch {
        Write-Log "Driver update configuration failed: $_" "WARN" Yellow
    }
}

function Optimize-PageFile {
    Write-Log "Optimizing page file settings..." "INFO" Cyan
    
    try {
        $totalRAM = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
        $totalRAMGB = [math]::Round($totalRAM / 1GB, 2)
        
        # For systems with 16GB+ RAM, let Windows manage page file
        if ($totalRAMGB -ge 16) {
            $pageFile = Get-CimInstance -ClassName Win32_PageFileSetting
            if ($pageFile) {
                $pageFile | Remove-CimInstance
            }
            
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            $cs | Set-CimInstance -Property @{AutomaticManagedPagefile = $true}
            
            Write-Log "Page file set to system-managed (recommended for $totalRAMGB GB RAM)." "OK" Green
        } else {
            Write-Log "Page file left at current settings ($totalRAMGB GB RAM)." "INFO" Gray
        }
    } catch {
        Write-Log "Page file optimization failed: $_" "WARN" Yellow
    }
}

function Configure-VisualEffects {
    Write-Log "Optimizing visual effects for performance..." "INFO" Cyan
    
    try {
        # Set to "Adjust for best performance" but keep some useful effects
        $visualPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (!(Test-Path $visualPath)) {
            New-Item -Path $visualPath -Force | Out-Null
        }
        Set-ItemProperty -Path $visualPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force
        
        Write-Log "Visual effects optimized for performance." "OK" Green
    } catch {
        Write-Log "Visual effects configuration failed: $_" "WARN" Yellow
    }
}

# Execute all system preparation tasks
Create-SystemRestorePoint
Generate-SystemDocumentation
Configure-ScheduledMaintenance
Verify-BitLocker
Create-RecoveryDocumentation
Configure-AutomaticDriverUpdates
Optimize-PageFile
Configure-VisualEffects

Write-Log "system-prep.ps1 completed. System is documented and prepared for production use." "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
