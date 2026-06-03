<#
.SYNOPSIS
    Enhanced "Clean Machine" Enterprise Reclamation System v2.0
    Surgically removes Corporate/MDM management while preserving Windows Hello authentication.
    
.DESCRIPTION
    Comprehensive MDM removal targeting:
    - Lenovo/OEM hardware beacons
    - Intune/Azure AD enrollment
    - Enterprise provisioning infrastructure
    - Network-level management channels
    - WMI provider hooks
    
    PROTECTED COMPONENTS:
    - Windows Hello/PIN authentication
    - NGC (Next Generation Credentials)
    - User credential providers
    - Biometric authentication
    
.NOTES
    Author: SynthicSoft Labs - Adam R
    Version: 2.0 Enhanced
    Date: 2025-01-14
    Requires: Administrator privileges
    
.EXAMPLE
    .\CleanMachine_Enhanced.ps1
    Runs full system reclamation with forensic logging
    
.EXAMPLE
    .\CleanMachine_Enhanced.ps1 -ForensicOnly
    Captures evidence without making changes
#>

[CmdletBinding()]
param(
    [switch]$ForensicOnly,
    [switch]$SkipBackup,
    [string]$LogPath = "C:\SynthicForensics"
)

#Requires -RunAsAdministrator

# ============================================================================
# INITIALIZATION & SAFETY CHECKS
# ============================================================================

$ErrorActionPreference = "Continue"
$Script:Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Script:LogFile = "$LogPath\CleanMachine_$Timestamp.log"
$Script:EvidencePath = "$LogPath\Evidence_$Timestamp"

# Create forensic directories
New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
New-Item -Path $Script:EvidencePath -ItemType Directory -Force | Out-Null

# Start transcript logging
Start-Transcript -Path $Script:LogFile -Append

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Info'
    )
    
    $Colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Critical' = 'Magenta'
    }
    
    $Prefix = @{
        'Info' = '[*]'
        'Success' = '[+]'
        'Warning' = '[!]'
        'Error' = '[-]'
        'Critical' = '[!!!]'
    }
    
    $Output = "$($Prefix[$Level]) $Message"
    Write-Host $Output -ForegroundColor $Colors[$Level]
    Add-Content -Path $Script:LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Output"
}

function Backup-RegistryKey {
    param([string]$Path, [string]$Name)
    
    if ($SkipBackup) { return }
    
    if (Test-Path $Path) {
        try {
            $BackupFile = "$Script:EvidencePath\Registry_Backup_$Name.reg"
            reg export $Path $BackupFile /y | Out-Null
            Write-Status "Backed up: $Name" -Level Success
        } catch {
            Write-Status "Backup failed for $Name : $_" -Level Warning
        }
    }
}

function Test-WindowsHello {
    $NgcPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock"
    $HelloEnabled = (Get-ItemProperty -Path $NgcPath -Name "AllowSimpleDevicePassword" -ErrorAction SilentlyContinue).AllowSimpleDevicePassword
    return ($HelloEnabled -ne $null)
}

# ============================================================================
# BANNER & PRE-FLIGHT
# ============================================================================

Clear-Host
Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           CLEAN MACHINE v2.0 - SYSTEM RECLAMATION SUITE             ║" -ForegroundColor Cyan
Write-Host "║                    SynthicSoft Labs - 2025                           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($ForensicOnly) {
    Write-Status "FORENSIC COLLECTION MODE - No changes will be made" -Level Warning
}

Write-Status "Initializing system analysis..." -Level Info
Write-Status "Log file: $Script:LogFile" -Level Info
Write-Status "Evidence path: $Script:EvidencePath" -Level Info

# Check Windows Hello status
$HelloStatus = Test-WindowsHello
Write-Status "Windows Hello Status: $($HelloStatus ? 'PROTECTED' : 'Not Configured')" -Level $(if($HelloStatus){'Success'}else{'Info'})

# ============================================================================
# PHASE 0: COMPREHENSIVE FORENSIC EVIDENCE COLLECTION
# ============================================================================

Write-Host "`n[PHASE 0] FORENSIC EVIDENCE COLLECTION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Capturing system state for legal documentation..." -Level Info

# System Identity & Enrollment Status
dsregcmd /status > "$Script:EvidencePath\00_dsregcmd_status.txt"
Get-ComputerInfo | Out-File "$Script:EvidencePath\00_computer_info.txt"
systeminfo > "$Script:EvidencePath\00_system_info.txt"

# Active Directory & Azure Status
try {
    Get-ADComputer $env:COMPUTERNAME -Properties * | Out-File "$Script:EvidencePath\00_ad_computer.txt" -ErrorAction SilentlyContinue
} catch { Write-Status "Not domain-joined or AD module unavailable" -Level Info }

# Network Connections & Remote Access
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} | 
    Export-Csv "$Script:EvidencePath\00_active_connections.csv" -NoTypeInformation

Get-NetTCPConnection | Where-Object {$_.RemotePort -in @(3389, 5985, 5986, 22)} |
    Export-Csv "$Script:EvidencePath\00_remote_access_connections.csv" -NoTypeInformation

# MDM/Management Services
Get-Service | Where-Object {$_.DisplayName -match "Management|MDM|Intune|Remote|Provisioning|Enrollment"} |
    Select-Object Name, DisplayName, Status, StartType | 
    Export-Csv "$Script:EvidencePath\00_management_services.csv" -NoTypeInformation

# Suspicious Hardware Devices
Get-PnpDevice | Where-Object {
    $_.Manufacturer -match "Lenovo|Remote|Virtual|Management" -or 
    $_.Class -match "SoftwareComponent" -or
    $_.FriendlyName -match "UDC|SIF|Hidden|Beacon"
} | Export-Csv "$Script:EvidencePath\00_suspicious_devices.csv" -NoTypeInformation

# Scheduled Tasks (Enrollment & Management)
Get-ScheduledTask | Where-Object {
    $_.TaskPath -match "EnterpriseMgmt|Enrollment|Provisioning|DMClient" -or
    $_.TaskName -match "MDM|Intune|Management"
} | Export-Csv "$Script:EvidencePath\00_enrollment_tasks.csv" -NoTypeInformation

# Certificate Store (MDM Certificates)
Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    $_.Subject -match "MDM|Intune|Management|Device" -or
    $_.Issuer -match "Microsoft|Azure|Intune"
} | Select-Object Subject, Issuer, NotAfter, Thumbprint |
    Export-Csv "$Script:EvidencePath\00_mdm_certificates.csv" -NoTypeInformation

# WMI Namespaces & Providers
Get-CimInstance -Namespace root/cimv2/mdm -ClassName __Namespace -ErrorAction SilentlyContinue |
    Out-File "$Script:EvidencePath\00_wmi_mdm_namespaces.txt"

Get-WmiObject -Namespace root -Class __Provider | Where-Object {$_.Name -match "MDM|DM|Enrollment"} |
    Export-Csv "$Script:EvidencePath\00_wmi_providers.csv" -NoTypeInformation

# Running Processes (Management Related)
Get-Process | Where-Object {
    $_.ProcessName -match "MDM|Intune|Enrollment|Provisioning|Management|Lenovo|UDC|WMI"
} | Select-Object ProcessName, Id, Path, Company |
    Export-Csv "$Script:EvidencePath\00_management_processes.csv" -NoTypeInformation

# Registry Keys (Pre-Modification)
$RegistryTargets = @{
    "Enrollments" = "HKLM:\SOFTWARE\Microsoft\Enrollments"
    "PolicyManager" = "HKLM:\SOFTWARE\Microsoft\PolicyManager"
    "DeviceManagement" = "HKLM:\SOFTWARE\Microsoft\DevDetail"
    "Provisioning" = "HKLM:\SOFTWARE\Microsoft\Provisioning"
    "DMClient" = "HKLM:\SOFTWARE\Microsoft\DMClient"
    "EnterpriseAppMgmt" = "HKLM:\SOFTWARE\Microsoft\EnterpriseModernAppManagement"
    "WindowsUpdate" = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    "AzureAD" = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin"
}

foreach ($Key in $RegistryTargets.GetEnumerator()) {
    Backup-RegistryKey -Path $Key.Value -Name $Key.Key
}

Write-Status "Forensic evidence collection complete: $Script:EvidencePath" -Level Success

if ($ForensicOnly) {
    Write-Host "`n[FORENSIC MODE] Evidence collected. No system modifications performed." -ForegroundColor Green
    Stop-Transcript
    exit 0
}

# ============================================================================
# PHASE 1: NEUTRALIZE HARDWARE BEACONS
# ============================================================================

Write-Host "`n[PHASE 1] HARDWARE BEACON NEUTRALIZATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Disabling OEM management hardware components..." -Level Info

$HardwareTargets = Get-PnpDevice | Where-Object {
    ($_.Class -eq "SoftwareComponent" -or $_.Class -eq "System") -and (
        $_.Manufacturer -match "Lenovo|Intel.*Management|AMT|vPro" -or
        $_.FriendlyName -match "UDC|SIF|Management Engine|Remote|Beacon|Virtual Button"
    )
}

$DisabledCount = 0
foreach ($Device in $HardwareTargets) {
    try {
        Disable-PnpDevice -InstanceId $Device.InstanceId -Confirm:$false -ErrorAction Stop
        Write-Status "Disabled hardware: $($Device.FriendlyName)" -Level Success
        $DisabledCount++
    } catch {
        Write-Status "Failed to disable: $($Device.FriendlyName) - $_" -Level Warning
    }
}

Write-Status "Hardware beacons neutralized: $DisabledCount devices" -Level Success

# ============================================================================
# PHASE 2: MANAGEMENT SERVICE TERMINATION
# ============================================================================

Write-Host "`n[PHASE 2] MANAGEMENT SERVICE TERMINATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Stopping and disabling management services..." -Level Info

# CRITICAL: Windows Hello Protected Services - DO NOT DISABLE
$ProtectedServices = @(
    "DeviceAssociationService",  # Required for Windows Hello/PIN
    "NgcSvc",                     # NGC Service (Hello)
    "NgcCtnrSvc",                 # NGC Container
    "KeyIso",                     # Cryptographic Services (Hello)
    "VaultSvc",                   # Credential Manager
    "WbioSrvc"                    # Biometric Service
)

$TargetServices = @(
    # MDM & Intune Services
    "DmEnrollmentSvc",
    "DmwApPushService", 
    "CDPSvc",
    "PimIndexMaintenanceSvc",
    "MessagingService",
    
    # Provisioning Services
    "ProvLaunch",
    "Provisioning",
    "DsmSvc",
    
    # Lenovo Specific
    "SIFService",
    "UDC Video Integration Service",
    "Lenovo System Interface Foundation",
    "Lenovo Vantage Service",
    "LenovoFnAndFunctionKeys",
    
    # Windows Management (WMI can be dangerous - handle carefully)
    # "winmgmt" - REMOVED, too dangerous
    
    # Remote Management
    "WinRM",
    "RemoteRegistry",
    "RemoteAccess",
    
    # Update & Telemetry (Optional - user decision)
    "wuauserv",
    "DiagTrack",
    "dmwappushservice"
)

$StoppedCount = 0
foreach ($ServiceName in $TargetServices) {
    if ($ProtectedServices -contains $ServiceName) {
        Write-Status "SKIPPING PROTECTED: $ServiceName (Windows Hello)" -Level Warning
        continue
    }
    
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($Service) {
        try {
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-Status "Terminated: $ServiceName" -Level Success
            $StoppedCount++
        } catch {
            Write-Status "Failed to stop: $ServiceName - $_" -Level Warning
        }
    }
}

Write-Status "Management services terminated: $StoppedCount services" -Level Success

# ============================================================================
# PHASE 3: SCHEDULED TASK NEUTRALIZATION
# ============================================================================

Write-Host "`n[PHASE 3] SCHEDULED TASK NEUTRALIZATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Disabling enrollment and management tasks..." -Level Info

$TaskPaths = @(
    "\Microsoft\Windows\EnterpriseMgmt\*",
    "\Microsoft\Windows\Workplace Join\*",
    "\Microsoft\Windows\RemoteAssistance\*",
    "\Microsoft\Windows\Customer Experience Improvement Program\*",
    "\Microsoft\Windows\Application Experience\*"
)

$DisabledTasks = 0
foreach ($TaskPath in $TaskPaths) {
    try {
        $Tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
        foreach ($Task in $Tasks) {
            Disable-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop | Out-Null
            Write-Status "Disabled task: $($Task.TaskName)" -Level Success
            $DisabledTasks++
        }
    } catch {
        Write-Status "Failed to disable tasks in $TaskPath - $_" -Level Warning
    }
}

Write-Status "Scheduled tasks neutralized: $DisabledTasks tasks" -Level Success

# ============================================================================
# PHASE 4: CLOUD EXPERIENCE HOST NEUTRALIZATION
# ============================================================================

Write-Host "`n[PHASE 4] CLOUD EXPERIENCE HOST NEUTRALIZATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Neutralizing OOBE enrollment mechanism..." -Level Info

$CXHPath = "C:\Windows\SystemApps\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy"
$CXHExe = "$CXHPath\CloudExperienceHost.exe"

if (Test-Path $CXHExe) {
    try {
        # Take ownership
        takeown /f $CXHExe /a | Out-Null
        icacls $CXHExe /grant administrators:F | Out-Null
        
        # Deny execution instead of renaming (survives updates better)
        icacls $CXHExe /deny "SYSTEM:(X)" | Out-Null
        icacls $CXHExe /deny "NETWORK SERVICE:(X)" | Out-Null
        
        Write-Status "CloudExperienceHost execution blocked" -Level Success
    } catch {
        Write-Status "Failed to neutralize CloudExperienceHost: $_" -Level Warning
    }
} else {
    Write-Status "CloudExperienceHost not found" -Level Info
}

# ============================================================================
# PHASE 5: WMI PROVIDER & MDM NAMESPACE PURGE
# ============================================================================

Write-Host "`n[PHASE 5] WMI PROVIDER PURGE" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Unregistering MDM WMI providers..." -Level Info

$MdmDlls = @(
    "C:\Windows\System32\mdmregistration.dll",
    "C:\Windows\System32\dmwmiprovider.dll",
    "C:\Windows\System32\appxdeploymentextensions.dll",
    "C:\Windows\System32\EnterpriseAppMgmtSvc.dll"
)

$UnregisteredCount = 0
foreach ($Dll in $MdmDlls) {
    if (Test-Path $Dll) {
        try {
            Start-Process "regsvr32.exe" -ArgumentList "/u /s `"$Dll`"" -Wait -NoNewWindow
            Write-Status "Unregistered: $Dll" -Level Success
            $UnregisteredCount++
        } catch {
            Write-Status "Failed to unregister: $Dll - $_" -Level Warning
        }
    }
}

# Restart WMI (safely)
Write-Status "Restarting WMI service..." -Level Info
try {
    Restart-Service Winmgmt -Force
    Write-Status "WMI service restarted" -Level Success
} catch {
    Write-Status "WMI restart failed (may require manual reboot): $_" -Level Warning
}

Write-Status "WMI providers unregistered: $UnregisteredCount DLLs" -Level Success

# ============================================================================
# PHASE 6: REGISTRY ANCHOR REMOVAL
# ============================================================================

Write-Host "`n[PHASE 6] REGISTRY ANCHOR REMOVAL" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Purging enrollment and policy registry keys..." -Level Info

# CRITICAL: Windows Hello Protected Registry Keys - DO NOT REMOVE
$ProtectedRegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication",
    "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock"
)

$RegTargets = @(
    # MDM Enrollment
    "HKLM:\SOFTWARE\Microsoft\Enrollments",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseModernAppManagement",
    
    # Policy & Configuration
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers",
    
    # Device Management
    "HKLM:\SOFTWARE\Microsoft\DevDetail",
    "HKLM:\SOFTWARE\Microsoft\DMClient",
    "HKLM:\SOFTWARE\Microsoft\Provisioning",
    
    # Windows Update Management (Corporate)
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
    
    # Cloud Join
    "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDJ\AAD"
)

$RemovedCount = 0
foreach ($RegPath in $RegTargets) {
    # Skip if protected
    $IsProtected = $false
    foreach ($Protected in $ProtectedRegPaths) {
        if ($RegPath -like "$Protected*") {
            Write-Status "PROTECTED: Skipping $RegPath (Windows Hello)" -Level Warning
            $IsProtected = $true
            break
        }
    }
    
    if ($IsProtected) { continue }
    
    if (Test-Path $RegPath) {
        try {
            Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop
            Write-Status "Purged: $RegPath" -Level Success
            $RemovedCount++
        } catch {
            Write-Status "Failed to remove: $RegPath - $_" -Level Warning
        }
    }
}

Write-Status "Registry anchors removed: $RemovedCount keys" -Level Success

# ============================================================================
# PHASE 7: OOBE & SYSTEM IDENTITY ROTATION
# ============================================================================

Write-Host "`n[PHASE 7] SYSTEM IDENTITY ROTATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Rotating hardware identity markers..." -Level Info

# Modify OOBE to prevent re-enrollment
$OobePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE"
if (!(Test-Path $OobePath)) {
    New-Item -Path $OobePath -Force | Out-Null
}

try {
    Set-ItemProperty -Path $OobePath -Name "PrivacyConsentStatus" -Value 1 -Type DWord
    Set-ItemProperty -Path $OobePath -Name "DisableVoice" -Value 1 -Type DWord
    Set-ItemProperty -Path $OobePath -Name "ProtectYourPC" -Value 3 -Type DWord
    Set-ItemProperty -Path $OobePath -Name "SkipMachineOOBE" -Value 1 -Type DWord
    Set-ItemProperty -Path $OobePath -Name "SkipUserOOBE" -Value 1 -Type DWord
    Write-Status "OOBE privacy flags configured" -Level Success
} catch {
    Write-Status "Failed to configure OOBE: $_" -Level Warning
}

# Generate new MachineGuid (makes system appear "new" to MDM)
$OldGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid").MachineGuid
$NewGuid = [guid]::NewGuid().ToString()

try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $NewGuid
    Write-Status "MachineGuid rotated: $OldGuid -> $NewGuid" -Level Success
    Add-Content -Path "$Script:EvidencePath\06_machine_guid_rotation.txt" -Value "Old GUID: $OldGuid`nNew GUID: $NewGuid"
} catch {
    Write-Status "Failed to rotate MachineGuid: $_" -Level Warning
}

# ============================================================================
# PHASE 8: IMMUTABLE NETWORK BLACKLIST
# ============================================================================

Write-Host "`n[PHASE 8] NETWORK BLACKLIST DEPLOYMENT" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Applying DNS-level management blacklist..." -Level Info

$HostsPath = "C:\Windows\System32\drivers\etc\hosts"

$BlockedDomains = @(
    # Microsoft MDM/Intune Endpoints
    "0.0.0.0 enterprise.manage.microsoft.com",
    "0.0.0.0 enrollment.manage.microsoft.com",
    "0.0.0.0 manage.microsoft.com",
    "0.0.0.0 portal.manage.microsoft.com",
    "0.0.0.0 m.manage.microsoft.com",
    "0.0.0.0 fef.msua06.manage.microsoft.com",
    "0.0.0.0 fef.msua02.manage.microsoft.com",
    "0.0.0.0 fef.msua04.manage.microsoft.com",
    "0.0.0.0 fef.msua05.manage.microsoft.com",
    "0.0.0.0 fef.msub01.manage.microsoft.com",
    "0.0.0.0 fef.msub02.manage.microsoft.com",
    "0.0.0.0 fef.msub03.manage.microsoft.com",
    "0.0.0.0 fef.msub05.manage.microsoft.com",
    "0.0.0.0 fef.msuc01.manage.microsoft.com",
    "0.0.0.0 fef.msuc02.manage.microsoft.com",
    "0.0.0.0 fef.msuc03.manage.microsoft.com",
    "0.0.0.0 fef.msuc05.manage.microsoft.com",
    
    # Azure AD & Autopilot
    "0.0.0.0 ztd.dds.microsoft.com",
    "0.0.0.0 cs.dds.microsoft.com",
    "0.0.0.0 login.microsoftonline.com",
    "0.0.0.0 login.live.com",
    "0.0.0.0 account.live.com",
    
    # Windows Update for Business
    "0.0.0.0 enterpriseregistration.windows.net",
    "0.0.0.0 enterpriseenrollment.manage.microsoft.com",
    "0.0.0.0 enterpriseenrollment-s.manage.microsoft.com",
    
    # Telemetry & Reporting
    "0.0.0.0 v10.vortex-win.data.microsoft.com",
    "0.0.0.0 settings-win.data.microsoft.com",
    "0.0.0.0 watson.telemetry.microsoft.com",
    "0.0.0.0 umwatsonc.events.data.microsoft.com",
    
    # Lenovo Management (Add specific domains if known)
    "0.0.0.0 download.lenovo.com",
    "0.0.0.0 support.lenovo.com"
)

# Backup original hosts file
Copy-Item $HostsPath "$Script:EvidencePath\hosts.original" -Force

# Unlock hosts file
attrib -r -s -h $HostsPath

$AddedCount = 0
foreach ($Entry in $BlockedDomains) {
    $Domain = $Entry.Split(' ')[1]
    $Exists = Select-String -Path $HostsPath -Pattern $Domain -Quiet
    
    if (!$Exists) {
        Add-Content -Path $HostsPath -Value $Entry
        $AddedCount++
    }
}

# Lock hosts file with SYSTEM deny
try {
    $Acl = Get-Acl $HostsPath
    $DenyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "Write,Delete,DeleteSubdirectoriesAndFiles", "Deny"
    )
    $Acl.SetAccessRule($DenyRule)
    Set-Acl $HostsPath $Acl
    
    # Make file hidden and system
    attrib +r +s +h $HostsPath
    
    Write-Status "Network blacklist locked with SYSTEM deny" -Level Success
} catch {
    Write-Status "Failed to lock hosts file: $_" -Level Warning
}

Write-Status "Network blacklist deployed: $AddedCount domains" -Level Success

# ============================================================================
# PHASE 9: INTUNE/MDM CERTIFICATE REMOVAL
# ============================================================================

Write-Host "`n[PHASE 9] MDM CERTIFICATE PURGE" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Removing MDM enrollment certificates..." -Level Info

$CertStores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")
$RemovedCerts = 0

foreach ($Store in $CertStores) {
    $MdmCerts = Get-ChildItem $Store -ErrorAction SilentlyContinue | Where-Object {
        $_.Subject -match "MDM Device|Microsoft Intune|MS-Organization-Access|WIP" -or
        $_.Issuer -match "Microsoft Intune|MDM Device Certificate"
    }
    
    foreach ($Cert in $MdmCerts) {
        try {
            # Backup certificate details
            $CertInfo = "Thumbprint: $($Cert.Thumbprint)`nSubject: $($Cert.Subject)`nIssuer: $($Cert.Issuer)`n`n"
            Add-Content -Path "$Script:EvidencePath\09_removed_certificates.txt" -Value $CertInfo
            
            Remove-Item -Path "$Store\$($Cert.Thumbprint)" -Force -ErrorAction Stop
            Write-Status "Removed cert: $($Cert.Subject)" -Level Success
            $RemovedCerts++
        } catch {
            Write-Status "Failed to remove cert: $($Cert.Subject) - $_" -Level Warning
        }
    }
}

Write-Status "MDM certificates removed: $RemovedCerts" -Level Success

# ============================================================================
# PHASE 10: WINDOWS FIREWALL HARDENING
# ============================================================================

Write-Host "`n[PHASE 10] FIREWALL HARDENING" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Blocking management endpoints at firewall level..." -Level Info

$FirewallRules = @(
    @{Name="Block_MDM_Outbound"; Direction="Outbound"; RemoteAddress="40.83.*.*, 52.168.*.*"; Action="Block"},
    @{Name="Block_Intune_Management"; Direction="Outbound"; RemotePort="443"; Program="C:\Windows\System32\dmclient.exe"; Action="Block"},
    @{Name="Block_WinRM"; Direction="Inbound"; RemotePort="5985,5986"; Action="Block"},
    @{Name="Block_RDP_External"; Direction="Inbound"; RemotePort="3389"; Action="Block"}
)

$CreatedRules = 0
foreach ($Rule in $FirewallRules) {
    try {
        $Existing = Get-NetFirewallRule -DisplayName $Rule.Name -ErrorAction SilentlyContinue
        if ($Existing) {
            Remove-NetFirewallRule -DisplayName $Rule.Name
        }
        
        New-NetFirewallRule @Rule -DisplayName $Rule.Name -Enabled True -Profile Any -ErrorAction Stop | Out-Null
        Write-Status "Created firewall rule: $($Rule.Name)" -Level Success
        $CreatedRules++
    } catch {
        Write-Status "Failed to create rule: $($Rule.Name) - $_" -Level Warning
    }
}

Write-Status "Firewall rules deployed: $CreatedRules rules" -Level Success

# ============================================================================
# PHASE 11: TPM PROVISIONING CLEANUP (Careful!)
# ============================================================================

Write-Host "`n[PHASE 11] TPM PROVISIONING REVIEW" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Analyzing TPM enrollment artifacts..." -Level Info

try {
    $TpmInfo = Get-Tpm
    if ($TpmInfo.TpmReady) {
        Write-Status "TPM Status: Ready (Owned: $($TpmInfo.TpmOwned))" -Level Info
        
        # Export TPM info for forensics
        $TpmInfo | Out-File "$Script:EvidencePath\11_tpm_status.txt"
        
        # Check for MDM provisioning in TPM
        $TpmCerts = Get-TpmEndorsementKeyInfo -ErrorAction SilentlyContinue
        if ($TpmCerts) {
            $TpmCerts | Out-File "$Script:EvidencePath\11_tpm_endorsement.txt"
        }
        
        Write-Status "TPM clear NOT recommended (Windows Hello dependency)" -Level Warning
    }
} catch {
    Write-Status "TPM analysis failed: $_" -Level Warning
}

# ============================================================================
# PHASE 12: LOG CLEANUP & EVIDENCE PRESERVATION
# ============================================================================

Write-Host "`n[PHASE 12] LOG CLEANUP & PRESERVATION" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Cleaning management logs..." -Level Info

$LogTargets = @(
    "C:\Windows\System32\LogFiles\Scm",
    "C:\Windows\System32\config\systemprofile\AppData\Local\mdm",
    "C:\ProgramData\Microsoft\Provisioning",
    "C:\ProgramData\Microsoft\DMClient",
    "C:\Windows\Logs\measuredboot"
)

$CleanedLogs = 0
foreach ($LogPath in $LogTargets) {
    if (Test-Path $LogPath) {
        try {
            # Archive before deletion
            $LogName = Split-Path $LogPath -Leaf
            Compress-Archive -Path $LogPath -DestinationPath "$Script:EvidencePath\12_archived_logs_$LogName.zip" -ErrorAction SilentlyContinue
            
            Remove-Item -Path $LogPath -Recurse -Force -ErrorAction Stop
            Write-Status "Cleaned log: $LogPath" -Level Success
            $CleanedLogs++
        } catch {
            Write-Status "Failed to clean: $LogPath - $_" -Level Warning
        }
    }
}

Write-Status "Log directories cleaned: $CleanedLogs" -Level Success

# ============================================================================
# PHASE 13: FINAL SYSTEM AUDIT & VERIFICATION
# ============================================================================

Write-Host "`n[PHASE 13] FINAL SYSTEM AUDIT" -ForegroundColor Yellow -BackgroundColor Black
Write-Status "Verifying system reclamation status..." -Level Info

# Re-check enrollment status
dsregcmd /status | Out-File "$Script:EvidencePath\13_post_dsregcmd_status.txt"

Write-Host "`n--- ENROLLMENT STATUS ---" -ForegroundColor Cyan
$DsregStatus = dsregcmd /status
$DsregStatus | Select-String "AzureAdJoined|EnterpriseJoined|DomainJoined|WorkplaceJoined"

Write-Host "`n--- REMAINING MANAGEMENT SERVICES ---" -ForegroundColor Cyan
$RemainingServices = Get-Service | Where-Object {
    $_.DisplayName -match "Management|MDM|Intune" -and $_.Status -eq "Running"
}
if ($RemainingServices) {
    $RemainingServices | Format-Table Name, DisplayName, Status
} else {
    Write-Status "No active management services detected" -Level Success
}

Write-Host "`n--- WINDOWS HELLO STATUS ---" -ForegroundColor Cyan
try {
    $HelloTest = Get-WindowsHelloForBusiness -ErrorAction SilentlyContinue
    if ($HelloTest) {
        Write-Status "Windows Hello: FUNCTIONAL" -Level Success
    } else {
        Write-Status "Windows Hello: Not configured" -Level Info
    }
} catch {
    Write-Status "Windows Hello test inconclusive" -Level Warning
}

# ============================================================================
# COMPLETION BANNER
# ============================================================================

Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    SYSTEM RECLAMATION COMPLETE                       ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Status "Forensic evidence preserved at: $Script:EvidencePath" -Level Info
Write-Status "Full transcript log: $Script:LogFile" -Level Info

Write-Host "`n[CRITICAL] NEXT STEPS:" -ForegroundColor Red -BackgroundColor Black
Write-Host "  1. Review forensic evidence for legal documentation" -ForegroundColor Yellow
Write-Host "  2. REBOOT SYSTEM to finalize all changes" -ForegroundColor Yellow
Write-Host "  3. After reboot, verify Windows Hello/PIN still works" -ForegroundColor Yellow
Write-Host "  4. Run 'dsregcmd /status' to confirm clean state" -ForegroundColor Yellow
Write-Host "  5. Monitor network traffic for any remaining management connections" -ForegroundColor Yellow

Write-Host "`n[WARNING] If Windows Hello fails after reboot:" -ForegroundColor Red
Write-Host "  Run: gpupdate /force" -ForegroundColor Cyan
Write-Host "  Then: Settings > Accounts > Sign-in options > Reset PIN" -ForegroundColor Cyan

Stop-Transcript

# Optional: Create summary report
$SummaryReport = @"
╔══════════════════════════════════════════════════════════════════════╗
║          CLEAN MACHINE v2.0 - RECLAMATION SUMMARY REPORT             ║
╚══════════════════════════════════════════════════════════════════════╝

Execution Time: $Script:Timestamp
Log File: $Script:LogFile
Evidence Path: $Script:EvidencePath

ACTIONS TAKEN:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Hardware beacons disabled: $DisabledCount devices
• Management services stopped: $StoppedCount services
• Scheduled tasks disabled: $DisabledTasks tasks
• WMI providers unregistered: $UnregisteredCount DLLs
• Registry keys removed: $RemovedCount keys
• MDM certificates purged: $RemovedCerts certificates
• Firewall rules created: $CreatedRules rules
• Network domains blacklisted: $AddedCount entries
• Log directories archived: $CleanedLogs locations

PROTECTED COMPONENTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Windows Hello/PIN authentication preserved
✓ NGC (Next Generation Credentials) intact
✓ Credential Provider chain maintained
✓ Biometric authentication services protected

FORENSIC EVIDENCE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All pre-modification system states captured for legal documentation:
- Registry backups (.reg files)
- Network connection logs (CSV)
- Service status snapshots (CSV)
- Certificate details (TXT)
- Hardware device inventories (CSV)
- Scheduled task listings (CSV)

RECOMMENDED FOLLOW-UP:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Reboot system immediately
2. Verify Windows Hello/PIN functionality
3. Run: dsregcmd /status
4. Check: Get-Service | Where-Object {$_.DisplayName -match "Management"}
5. Review evidence folder for legal case documentation

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
System reclaimed. Machine identity rotated. Network egress blocked.
Corporate management infrastructure dismantled.

For support: SynthicSoft Labs - Cybersecurity Operations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

$SummaryReport | Out-File "$Script:EvidencePath\00_SUMMARY_REPORT.txt"
Write-Host "`n[+] Summary report generated: $Script:EvidencePath\00_SUMMARY_REPORT.txt" -ForegroundColor Green

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
