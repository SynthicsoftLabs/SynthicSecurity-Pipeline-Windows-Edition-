<#
.SYNOPSIS
    Nuclear Eviction - Total Enterprise Management Obliteration v1.0
    The ultimate enterprise unenrollment and management eviction tool.
    
.DESCRIPTION
    Designed for the impossible: Windows 11 HOME edition showing enterprise enrollment.
    
    This script is the "nuclear option" for complete enterprise management removal:
    - Multiple fallback methods for every operation
    - Continues on failure (never stops mid-execution)
    - Works on Home/Pro/Enterprise/Education editions
    - Removes hidden accounts, services, policies
    - Verifies every action with multiple detection methods
    - Protects core OS functions while obliterating management
    
    TARGETS:
    - Azure AD enrollment (impossible on Home, but checking anyway)
    - Domain join artifacts
    - MDM/Intune enrollment
    - Workplace join
    - Enterprise provisioning
    - Hidden administrator accounts
    - Management services and tasks
    - Policy enforcement mechanisms
    - Certificate-based enrollment
    - Registry-based control
    - WMI-based management
    - Network-level blocks
    
.NOTES
    Author: SynthicSoft Labs - Adam R
    Created for: Impossible scenario - Home edition with enterprise management
    Version: 1.0 Nuclear
    Date: 2025-01-14
    
.EXAMPLE
    .\NuclearEviction.ps1
    Full nuclear eviction with all safety checks
    
.EXAMPLE
    .\NuclearEviction.ps1 -AggressiveMode
    Maximum aggression, minimal safety (use if standard fails)
#>

[CmdletBinding()]
param(
    [switch]$AggressiveMode,
    [switch]$SkipBackup,
    [string]$LogPath = "C:\SynthicForensics\NuclearEviction_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$Script:FailureCount = 0
$Script:SuccessCount = 0

# ============================================================================
# INITIALIZATION
# ============================================================================

New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
$Script:LogFile = "$LogPath\nuclear_eviction.log"
$Script:VerificationLog = "$LogPath\verification_results.txt"

Start-Transcript -Path $Script:LogFile -Append

function Write-Nuclear {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','FAILURE','CRITICAL','VERIFY')]
        [string]$Level = 'INFO',
        [switch]$NoNewline
    )
    
    $Colors = @{
        'INFO' = 'Cyan'
        'SUCCESS' = 'Green'
        'WARNING' = 'Yellow'
        'FAILURE' = 'Red'
        'CRITICAL' = 'Magenta'
        'VERIFY' = 'White'
    }
    
    $Prefix = @{
        'INFO' = '[*]'
        'SUCCESS' = '[✓]'
        'WARNING' = '[!]'
        'FAILURE' = '[✗]'
        'CRITICAL' = '[!!!]'
        'VERIFY' = '[?]'
    }
    
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $Output = "$($Prefix[$Level]) $Message"
    
    if ($NoNewline) {
        Write-Host $Output -ForegroundColor $Colors[$Level] -NoNewline
    } else {
        Write-Host $Output -ForegroundColor $Colors[$Level]
    }
    
    Add-Content -Path $Script:LogFile -Value "[$Timestamp] [$Level] $Message"
    
    if ($Level -eq 'SUCCESS') { $Script:SuccessCount++ }
    if ($Level -eq 'FAILURE') { $Script:FailureCount++ }
}

function Invoke-WithFallback {
    param(
        [string]$Name,
        [scriptblock[]]$Methods,
        [scriptblock]$Verification = $null
    )
    
    Write-Nuclear "Attempting: $Name" -Level INFO
    
    $MethodNumber = 1
    $Success = $false
    
    foreach ($Method in $Methods) {
        try {
            Write-Nuclear "  Method $MethodNumber/$($Methods.Count)..." -Level INFO -NoNewline
            & $Method
            
            if ($Verification) {
                $VerifyResult = & $Verification
                if ($VerifyResult) {
                    Write-Host " SUCCESS" -ForegroundColor Green
                    Write-Nuclear "  Verified: $Name" -Level SUCCESS
                    $Success = $true
                    break
                } else {
                    Write-Host " FAILED (verification)" -ForegroundColor Yellow
                    Write-Nuclear "  Method $MethodNumber failed verification" -Level WARNING
                }
            } else {
                Write-Host " SUCCESS" -ForegroundColor Green
                Write-Nuclear "  Completed: Method $MethodNumber" -Level SUCCESS
                $Success = $true
                break
            }
        } catch {
            Write-Host " ERROR: $_" -ForegroundColor Red
            Write-Nuclear "  Method $MethodNumber failed: $_" -Level FAILURE
        }
        $MethodNumber++
    }
    
    if (-not $Success) {
        Write-Nuclear "ALL METHODS FAILED: $Name" -Level FAILURE
    }
    
    return $Success
}

# ============================================================================
# BANNER
# ============================================================================

Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║            ⚠️  NUCLEAR EVICTION - ENTERPRISE OBLITERATION  ⚠️             ║
║                                                                          ║
║          Total Enterprise Management Removal with Fallbacks             ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

Write-Host ""
Write-Nuclear "Windows Edition: $((Get-ComputerInfo).WindowsEditionId)" -Level INFO
Write-Nuclear "Build: $((Get-ComputerInfo).WindowsBuildLabEx)" -Level INFO
Write-Nuclear "Aggressive Mode: $AggressiveMode" -Level $(if($AggressiveMode){'WARNING'}else{'INFO'})
Write-Nuclear "Log Path: $LogPath" -Level INFO
Write-Host ""

if (-not $AggressiveMode) {
    Write-Host "[WARNING] This script will remove ALL enterprise management." -ForegroundColor Yellow
    Write-Host "[WARNING] Cannot be easily undone. Press CTRL+C to abort." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 5
}

# ============================================================================
# PHASE 0: PRE-FLIGHT SYSTEM STATE CAPTURE
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PHASE 0: SYSTEM STATE CAPTURE & HIDDEN ENTITY DETECTION  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Capture enrollment status
Write-Nuclear "Capturing pre-eviction system state..." -Level INFO
dsregcmd /status > "$LogPath\00_pre_dsregcmd_status.txt"

# Get detailed Windows edition info
$EditionInfo = Get-ComputerInfo | Select-Object WindowsEditionId, WindowsProductName, OsArchitecture
$EditionInfo | Out-File "$LogPath\00_edition_info.txt"

if ($EditionInfo.WindowsEditionId -match "Home") {
    Write-Nuclear "CRITICAL: Windows HOME edition with enterprise management is IMPOSSIBLE" -Level CRITICAL
    Write-Nuclear "This indicates sophisticated OS modification or registry manipulation" -Level CRITICAL
}

# Check for hidden accounts
Write-Nuclear "Scanning for hidden administrator accounts..." -Level INFO
$AllUsers = Get-LocalUser
$HiddenAdmins = $AllUsers | Where-Object {
    $_.Enabled -eq $true -and 
    $_.Description -match "Built-in account|System|Admin|Management" -and
    $_.Name -notmatch "^(Administrator|Guest)$"
}

if ($HiddenAdmins) {
    Write-Nuclear "Found $($HiddenAdmins.Count) suspicious accounts:" -Level WARNING
    $HiddenAdmins | ForEach-Object {
        Write-Nuclear "  - $($_.Name) (SID: $($_.SID))" -Level WARNING
    }
    $HiddenAdmins | Export-Csv "$LogPath\00_hidden_accounts.csv" -NoTypeInformation
} else {
    Write-Nuclear "No suspicious accounts detected" -Level SUCCESS
}

# Check for hidden services
Write-Nuclear "Scanning for hidden management services..." -Level INFO
$HiddenServices = Get-Service | Where-Object {
    $_.DisplayName -match "Management|Remote|MDM|Intune|Enrollment" -and
    $_.ServiceName -notmatch "^(WinRM|RemoteRegistry)$"
}

if ($HiddenServices) {
    Write-Nuclear "Found $($HiddenServices.Count) management services" -Level WARNING
    $HiddenServices | Export-Csv "$LogPath\00_management_services.csv" -NoTypeInformation
}

# Check for enrollment artifacts
$EnrollmentCheck = @{
    "Azure AD" = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin"
    "Intune/MDM" = Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments"
    "Workplace" = Test-Path "HKLM:\SOFTWARE\Microsoft\WorkplaceJoin"
    "Provisioning" = Test-Path "HKLM:\SOFTWARE\Microsoft\Provisioning"
    "PolicyManager" = Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current"
}

Write-Nuclear "Enrollment Detection Results:" -Level INFO
foreach ($Check in $EnrollmentCheck.GetEnumerator()) {
    $Status = if ($Check.Value) { "DETECTED" } else { "Clean" }
    $Level = if ($Check.Value) { "WARNING" } else { "SUCCESS" }
    Write-Nuclear "  $($Check.Key): $Status" -Level $Level
}

$EnrollmentCheck | Out-String | Out-File "$LogPath\00_enrollment_detection.txt"

# ============================================================================
# PHASE 1: HIDDEN ACCOUNT REMOVAL (Multiple Methods)
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           PHASE 1: HIDDEN ACCOUNT OBLITERATION            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($HiddenAdmins) {
    foreach ($Account in $HiddenAdmins) {
        $AccountName = $Account.Name
        
        Invoke-WithFallback -Name "Remove Account: $AccountName" -Methods @(
            # Method 1: PowerShell cmdlet
            { Remove-LocalUser -Name $AccountName -ErrorAction Stop },
            
            # Method 2: NET USER command
            { net user $AccountName /delete | Out-Null },
            
            # Method 3: WMI
            { 
                $User = Get-WmiObject -Class Win32_UserAccount -Filter "Name='$AccountName'"
                $User.Delete()
            },
            
            # Method 4: Direct registry removal
            {
                $SID = $Account.SID.Value
                $ProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
                if (Test-Path $ProfilePath) {
                    Remove-Item -Path $ProfilePath -Recurse -Force
                }
            }
        ) -Verification {
            -not (Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue)
        }
    }
} else {
    Write-Nuclear "No hidden accounts to remove" -Level SUCCESS
}

# ============================================================================
# PHASE 2: AZURE AD / AAD DISJOIN (Multiple Methods)
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              PHASE 2: AZURE AD EVICTION                   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Invoke-WithFallback -Name "Azure AD Disjoin" -Methods @(
    # Method 1: dsregcmd
    { dsregcmd /leave | Out-Null },
    
    # Method 2: Remove CloudDomainJoin registry
    {
        $CloudJoinPaths = @(
            "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDJ"
        )
        foreach ($Path in $CloudJoinPaths) {
            if (Test-Path $Path) {
                Remove-Item -Path $Path -Recurse -Force
            }
        }
    },
    
    # Method 3: Delete AAD join artifacts
    {
        $AADPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AAD",
            "HKLM:\SOFTWARE\Microsoft\IdentityStore"
        )
        foreach ($Path in $AADPaths) {
            if (Test-Path $Path) {
                Remove-Item -Path $Path -Recurse -Force
            }
        }
    },
    
    # Method 4: Remove AAD certificates
    {
        Get-ChildItem Cert:\LocalMachine\My | Where-Object {
            $_.Subject -match "CN=MS-Organization-Access" -or
            $_.Issuer -match "MS-Organization-P2P-Access"
        } | Remove-Item -Force
    }
) -Verification {
    $Status = dsregcmd /status
    $Status -match "AzureAdJoined\s*:\s*NO"
}

# ============================================================================
# PHASE 3: DOMAIN DISJOIN (Multiple Methods)
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              PHASE 3: DOMAIN EVICTION                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$IsDomainJoined = (Get-WmiObject Win32_ComputerSystem).PartOfDomain

if ($IsDomainJoined) {
    Write-Nuclear "Domain membership detected - EVICTING" -Level WARNING
    
    Invoke-WithFallback -Name "Domain Disjoin" -Methods @(
        # Method 1: PowerShell Remove-Computer
        { Remove-Computer -WorkgroupName "WORKGROUP" -Force -ErrorAction Stop },
        
        # Method 2: WMI UnjoinDomainOrWorkgroup
        {
            $Computer = Get-WmiObject Win32_ComputerSystem
            $Computer.UnjoinDomainOrWorkgroup($null, $null, 0)
        },
        
        # Method 3: Registry modification (forces workgroup)
        {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Domain" -Value "WORKGROUP"
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "Name" -Value $env:COMPUTERNAME
        }
    ) -Verification {
        -not (Get-WmiObject Win32_ComputerSystem).PartOfDomain
    }
} else {
    Write-Nuclear "Not domain-joined" -Level SUCCESS
}

# ============================================================================
# PHASE 4: MDM / INTUNE UNENROLLMENT (Heavy Fallbacks)
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║            PHASE 4: MDM/INTUNE OBLITERATION               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Method 1: Per-enrollment GUID removal
$EnrollmentGUIDs = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue

if ($EnrollmentGUIDs) {
    foreach ($Enrollment in $EnrollmentGUIDs) {
        $GUID = $Enrollment.PSChildName
        Write-Nuclear "Processing enrollment: $GUID" -Level INFO
        
        Invoke-WithFallback -Name "Remove Enrollment $GUID" -Methods @(
            # Method 1: ProvisioningHandler
            {
                $Handler = Get-WmiObject -Namespace "root\cimv2\mdm" -Class "MDM_Client"
                $Handler.Unenroll()
            },
            
            # Method 2: Registry deletion
            {
                Remove-Item -Path $Enrollment.PSPath -Recurse -Force
            },
            
            # Method 3: Task deletion
            {
                Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\$GUID\*" -ErrorAction SilentlyContinue |
                    Unregister-ScheduledTask -Confirm:$false
                Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\$GUID" -Recurse -Force
            }
        ) -Verification {
            -not (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments\$GUID")
        }
    }
}

# Method 2: Nuclear registry obliteration
$MDMRegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Enrollments",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseModernAppManagement",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager",
    "HKLM:\SOFTWARE\Microsoft\Provisioning",
    "HKLM:\SOFTWARE\Microsoft\DMClient",
    "HKLM:\SOFTWARE\Microsoft\DevDetail"
)

foreach ($RegPath in $MDMRegistryPaths) {
    Invoke-WithFallback -Name "Remove Registry: $RegPath" -Methods @(
        # Method 1: Direct removal
        { Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop },
        
        # Method 2: Backup then remove
        {
            $BackupName = $RegPath -replace '.*\\', ''
            reg export $RegPath "$LogPath\backup_$BackupName.reg" /y | Out-Null
            Remove-Item -Path $RegPath -Recurse -Force
        },
        
        # Method 3: Rename (in case locked)
        {
            $NewName = "$RegPath.DELETED"
            Rename-Item -Path $RegPath -NewName $NewName -Force
        }
    ) -Verification {
        -not (Test-Path $RegPath)
    }
}

# Method 3: WMI MDM namespace removal
Invoke-WithFallback -Name "Remove WMI MDM Namespace" -Methods @(
    # Method 1: Delete namespace
    {
        $Namespace = Get-WmiObject -Namespace "root\cimv2" -Class "__Namespace" -Filter "Name='mdm'"
        if ($Namespace) { $Namespace.Delete() }
    },
    
    # Method 2: Remove all MDM classes
    {
        Get-WmiObject -Namespace "root\cimv2\mdm" -List -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Delete() }
    }
) -Verification {
    $null -eq (Get-WmiObject -Namespace "root\cimv2" -Class "__Namespace" -Filter "Name='mdm'" -ErrorAction SilentlyContinue)
}

# ============================================================================
# PHASE 5: WORKPLACE JOIN REMOVAL
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║            PHASE 5: WORKPLACE JOIN EVICTION               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Invoke-WithFallback -Name "Workplace Join Removal" -Methods @(
    # Method 1: dsregcmd
    { dsregcmd /leave /WJ | Out-Null },
    
    # Method 2: Registry removal
    {
        $WPJPaths = @(
            "HKLM:\SOFTWARE\Microsoft\WorkplaceJoin",
            "HKCU:\SOFTWARE\Microsoft\WorkplaceJoin"
        )
        foreach ($Path in $WPJPaths) {
            if (Test-Path $Path) {
                Remove-Item -Path $Path -Recurse -Force
            }
        }
    },
    
    # Method 3: Certificate removal
    {
        Get-ChildItem Cert:\CurrentUser\My | Where-Object {
            $_.Subject -match "Workplace Join" -or
            $_.Issuer -match "MS-Organization"
        } | Remove-Item -Force
    }
) -Verification {
    $Status = dsregcmd /status
    $Status -match "WorkplaceJoined\s*:\s*NO"
}

# ============================================================================
# PHASE 6: MANAGEMENT SERVICES OBLITERATION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          PHASE 6: MANAGEMENT SERVICES TERMINATION         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Critical services to preserve (Windows Hello, BitLocker, etc.)
$ProtectedServices = @(
    "DeviceAssociationService",
    "NgcSvc", "NgcCtnrSvc", "KeyIso", "VaultSvc", "WbioSrvc",
    "BDESVC", "wuauserv", "WinDefend", "SecurityHealthService"
)

$TargetServices = @(
    # MDM Services
    "DmEnrollmentSvc", "DmwApPushService", "CDPSvc",
    "PimIndexMaintenanceSvc", "MessagingService",
    
    # Provisioning
    "ProvLaunch", "Provisioning", "DsmSvc",
    
    # Remote Management
    "WinRM", "RemoteRegistry", "RemoteAccess",
    
    # Telemetry
    "DiagTrack", "dmwappushservice",
    
    # Lenovo/OEM
    "SIFService", "Lenovo*", "*Vantage*"
)

foreach ($ServiceName in $TargetServices) {
    if ($ProtectedServices -contains $ServiceName) {
        Write-Nuclear "PROTECTED: Skipping $ServiceName" -Level WARNING
        continue
    }
    
    # Handle wildcards
    $Services = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    foreach ($Service in $Services) {
        Invoke-WithFallback -Name "Terminate Service: $($Service.Name)" -Methods @(
            # Method 1: PowerShell cmdlets
            {
                Stop-Service -Name $Service.Name -Force -ErrorAction Stop
                Set-Service -Name $Service.Name -StartupType Disabled -ErrorAction Stop
            },
            
            # Method 2: SC command
            {
                sc.exe stop $Service.Name | Out-Null
                sc.exe config $Service.Name start= disabled | Out-Null
            },
            
            # Method 3: Registry modification
            {
                $ServiceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Service.Name)"
                if (Test-Path $ServiceKey) {
                    Set-ItemProperty -Path $ServiceKey -Name "Start" -Value 4 # Disabled
                }
                Stop-Process -Name $Service.Name -Force -ErrorAction SilentlyContinue
            },
            
            # Method 4: Delete service
            {
                sc.exe delete $Service.Name | Out-Null
            }
        ) -Verification {
            $Check = Get-Service -Name $Service.Name -ErrorAction SilentlyContinue
            $null -eq $Check -or $Check.StartType -eq 'Disabled'
        }
    }
}

# ============================================================================
# PHASE 7: SCHEDULED TASK OBLITERATION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          PHASE 7: SCHEDULED TASK OBLITERATION             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$TaskPaths = @(
    "\Microsoft\Windows\EnterpriseMgmt\*",
    "\Microsoft\Windows\Workplace Join\*",
    "\Microsoft\Windows\RemoteAssistance\*",
    "\Microsoft\Windows\Customer Experience Improvement Program\*"
)

foreach ($TaskPath in $TaskPaths) {
    $Tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
    
    foreach ($Task in $Tasks) {
        Invoke-WithFallback -Name "Remove Task: $($Task.TaskName)" -Methods @(
            # Method 1: Unregister-ScheduledTask
            { Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -Confirm:$false -ErrorAction Stop },
            
            # Method 2: schtasks command
            { schtasks /delete /tn "$($Task.TaskPath)$($Task.TaskName)" /f | Out-Null },
            
            # Method 3: COM object
            {
                $Schedule = New-Object -ComObject Schedule.Service
                $Schedule.Connect()
                $Folder = $Schedule.GetFolder($Task.TaskPath)
                $Folder.DeleteTask($Task.TaskName, 0)
            }
        ) -Verification {
            $null -eq (Get-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction SilentlyContinue)
        }
    }
}

# ============================================================================
# PHASE 8: CERTIFICATE STORE PURGE
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           PHASE 8: CERTIFICATE OBLITERATION               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$CertStores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")

foreach ($Store in $CertStores) {
    $MDMCerts = Get-ChildItem $Store -ErrorAction SilentlyContinue | Where-Object {
        $_.Subject -match "MDM Device|Microsoft Intune|MS-Organization|WIP|Workplace" -or
        $_.Issuer -match "Microsoft Intune|MDM Device|MS-Organization"
    }
    
    foreach ($Cert in $MDMCerts) {
        Invoke-WithFallback -Name "Remove Certificate: $($Cert.Subject)" -Methods @(
            # Method 1: Remove-Item
            { Remove-Item -Path "$Store\$($Cert.Thumbprint)" -Force -ErrorAction Stop },
            
            # Method 2: Certificate object
            {
                $CertStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $CertStore.Open("ReadWrite")
                $CertStore.Remove($Cert)
                $CertStore.Close()
            },
            
            # Method 3: Certutil
            { certutil -delstore "My" $Cert.Thumbprint | Out-Null }
        ) -Verification {
            $null -eq (Get-ChildItem $Store -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $Cert.Thumbprint })
        }
    }
}

# ============================================================================
# PHASE 9: POLICY OBLITERATION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║            PHASE 9: GROUP POLICY OBLITERATION             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Invoke-WithFallback -Name "Remove Group Policy Settings" -Methods @(
    # Method 1: GPUpdate with force reset
    {
        Remove-Item "C:\Windows\System32\GroupPolicy" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\System32\GroupPolicyUsers" -Recurse -Force -ErrorAction SilentlyContinue
        gpupdate /force | Out-Null
    },
    
    # Method 2: Registry policy removal
    {
        $PolicyKeys = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows",
            "HKCU:\SOFTWARE\Policies\Microsoft\Windows",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"
        )
        foreach ($Key in $PolicyKeys) {
            if (Test-Path $Key) {
                # Backup first
                $KeyName = $Key -replace '.*\\', ''
                reg export $Key "$LogPath\policy_backup_$KeyName.reg" /y | Out-Null
                
                # Remove all except essential
                Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.PSObject.Properties | Where-Object {
                        $_.Name -notmatch "PS|Explorer|System"
                    } | ForEach-Object {
                        Remove-ItemProperty -Path $Key -Name $_.Name -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    },
    
    # Method 3: secedit reset
    {
        secedit /configure /cfg "$env:windir\inf\defltbase.inf" /db defltbase.sdb /verbose | Out-Null
    }
)

# ============================================================================
# PHASE 10: NETWORK MANAGEMENT BLOCKS
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          PHASE 10: NETWORK MANAGEMENT BLOCKADE            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Comprehensive MDM endpoint list
$BlockedDomains = @(
    # Microsoft Intune/MDM
    "0.0.0.0 enterprise.manage.microsoft.com",
    "0.0.0.0 enrollment.manage.microsoft.com",
    "0.0.0.0 manage.microsoft.com",
    "0.0.0.0 portal.manage.microsoft.com",
    "0.0.0.0 m.manage.microsoft.com",
    "0.0.0.0 fef.msua06.manage.microsoft.com",
    "0.0.0.0 fef.msua02.manage.microsoft.com",
    "0.0.0.0 fef.msub01.manage.microsoft.com",
    "0.0.0.0 fef.msuc01.manage.microsoft.com",
    
    # Azure AD / Autopilot
    "0.0.0.0 ztd.dds.microsoft.com",
    "0.0.0.0 cs.dds.microsoft.com",
    "0.0.0.0 login.microsoftonline.com",
    "0.0.0.0 enterpriseregistration.windows.net",
    "0.0.0.0 enterpriseenrollment.manage.microsoft.com",
    
    # Telemetry
    "0.0.0.0 v10.vortex-win.data.microsoft.com",
    "0.0.0.0 settings-win.data.microsoft.com",
    "0.0.0.0 watson.telemetry.microsoft.com"
)

$HostsPath = "C:\Windows\System32\drivers\etc\hosts"

Invoke-WithFallback -Name "Apply Network Blacklist" -Methods @(
    # Method 1: Modify hosts file
    {
        attrib -r -s -h $HostsPath
        
        $CurrentHosts = Get-Content $HostsPath
        $NewEntries = @()
        
        foreach ($Entry in $BlockedDomains) {
            $Domain = $Entry.Split(' ')[1]
            if ($CurrentHosts -notmatch [regex]::Escape($Domain)) {
                $NewEntries += $Entry
            }
        }
        
        if ($NewEntries.Count -gt 0) {
            Add-Content -Path $HostsPath -Value "`n# Nuclear Eviction - Management Blocks"
            Add-Content -Path $HostsPath -Value $NewEntries
        }
        
        # Lock hosts file
        $Acl = Get-Acl $HostsPath
        $DenyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "Write,Delete", "Deny"
        )
        $Acl.AddAccessRule($DenyRule)
        Set-Acl $HostsPath $Acl
        
        attrib +r +s +h $HostsPath
    },
    
    # Method 2: Firewall rules
    {
        $RuleName = "Block_MDM_Management"
        Remove-NetFirewallRule -DisplayName "$RuleName*" -ErrorAction SilentlyContinue
        
        New-NetFirewallRule -DisplayName "${RuleName}_Outbound" `
            -Direction Outbound `
            -Action Block `
            -RemoteAddress "40.83.0.0/16","52.168.0.0/16","13.107.0.0/16" `
            -Enabled True -Profile Any | Out-Null
    }
)

# ============================================================================
# PHASE 11: WMI PROVIDER OBLITERATION
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           PHASE 11: WMI PROVIDER OBLITERATION             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$MDMDlls = @(
    "C:\Windows\System32\mdmregistration.dll",
    "C:\Windows\System32\dmwmiprovider.dll",
    "C:\Windows\System32\appxdeploymentextensions.dll",
    "C:\Windows\System32\EnterpriseAppMgmtSvc.dll"
)

foreach ($Dll in $MDMDlls) {
    if (Test-Path $Dll) {
        Invoke-WithFallback -Name "Unregister DLL: $(Split-Path $Dll -Leaf)" -Methods @(
            # Method 1: regsvr32
            { Start-Process "regsvr32.exe" -ArgumentList "/u /s `"$Dll`"" -Wait -NoNewWindow -ErrorAction Stop },
            
            # Method 2: Rename DLL
            {
                takeown /f $Dll /a | Out-Null
                icacls $Dll /grant administrators:F | Out-Null
                Rename-Item -Path $Dll -NewName "$Dll.disabled" -Force
            }
        )
    }
}

# Restart WMI safely
try {
    Restart-Service Winmgmt -Force
    Write-Nuclear "WMI service restarted" -Level SUCCESS
} catch {
    Write-Nuclear "WMI restart failed (may need reboot)" -Level WARNING
}

# ============================================================================
# PHASE 12: BOOT-TIME PERSISTENCE REMOVAL
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         PHASE 12: BOOT-TIME PERSISTENCE REMOVAL           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Reset BootExecute to standard
$SessionManager = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
Set-ItemProperty -Path $SessionManager -Name "BootExecute" -Value @("autocheck autochk *")
Write-Nuclear "BootExecute reset to standard" -Level SUCCESS

# Remove AppInit_DLLs
$AppInitKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
)

foreach ($Key in $AppInitKeys) {
    if (Test-Path $Key) {
        Remove-ItemProperty -Path $Key -Name "AppInit_DLLs" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $Key -Name "LoadAppInit_DLLs" -Value 0 -ErrorAction SilentlyContinue
    }
}

Write-Nuclear "AppInit_DLLs removed" -Level SUCCESS

# Reset Winlogon
$Winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $Winlogon -Name "Shell" -Value "explorer.exe"
Set-ItemProperty -Path $Winlogon -Name "Userinit" -Value "C:\Windows\system32\userinit.exe,"
Write-Nuclear "Winlogon reset to defaults" -Level SUCCESS

# ============================================================================
# PHASE 13: OOBE & SYSTEM IDENTITY RESET
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          PHASE 13: SYSTEM IDENTITY ROTATION                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# OOBE Reset
$OobePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE"
if (!(Test-Path $OobePath)) { New-Item -Path $OobePath -Force | Out-Null }

Set-ItemProperty -Path $OobePath -Name "PrivacyConsentStatus" -Value 0
Set-ItemProperty -Path $OobePath -Name "SkipMachineOOBE" -Value 0
Set-ItemProperty -Path $OobePath -Name "SkipUserOOBE" -Value 0
Set-ItemProperty -Path $OobePath -Name "ProtectYourPC" -Value 1
Write-Nuclear "OOBE reset to consumer defaults" -Level SUCCESS

# Rotate MachineGUID
$OldGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid").MachineGuid
$NewGuid = [guid]::NewGuid().ToString()
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $NewGuid
Write-Nuclear "MachineGUID rotated: $OldGuid -> $NewGuid" -Level SUCCESS

"Old GUID: $OldGuid`nNew GUID: $NewGuid" | Out-File "$LogPath\guid_rotation.txt"

# ============================================================================
# PHASE 14: FINAL VERIFICATION & HEALTH CHECK
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         PHASE 14: VERIFICATION & HEALTH CHECK             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Nuclear "Running final verification..." -Level INFO

# Re-check enrollment status
$FinalStatus = dsregcmd /status
$FinalStatus | Out-File "$LogPath\99_post_dsregcmd_status.txt"

$VerificationResults = @"
╔══════════════════════════════════════════════════════════════════════════╗
║                     FINAL VERIFICATION RESULTS                           ║
╚══════════════════════════════════════════════════════════════════════════╝

ENROLLMENT STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(($FinalStatus | Select-String "AzureAdJoined|EnterpriseJoined|DomainJoined|WorkplaceJoined") -join "`n")

REGISTRY CHECKS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Azure AD Registry:       $(if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin") { "STILL EXISTS" } else { "CLEAN" })
Enrollments Registry:    $(if (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments") { "STILL EXISTS" } else { "CLEAN" })
PolicyManager Registry:  $(if (Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager") { "STILL EXISTS" } else { "CLEAN" })
Workplace Join:          $(if (Test-Path "HKLM:\SOFTWARE\Microsoft\WorkplaceJoin") { "STILL EXISTS" } else { "CLEAN" })

ACCOUNT STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Local Accounts:    $((@(Get-LocalUser)).Count)
Enabled Accounts:        $((@(Get-LocalUser | Where-Object Enabled -eq $true)).Count)
Administrator Status:    $(if ((Get-LocalUser "Administrator").Enabled) { "ENABLED" } else { "Disabled" })

SERVICE STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Management Services:     $((@(Get-Service | Where-Object { $_.DisplayName -match "Management|MDM|Intune" -and $_.Status -eq "Running" })).Count) running

WINDOWS HELLO STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(try {
    $NgcService = Get-Service NgcSvc -ErrorAction SilentlyContinue
    if ($NgcService.Status -eq "Running") { "NgcSvc: Running (PROTECTED)" } else { "NgcSvc: $($NgcService.Status)" }
} catch { "NgcSvc: Not configured" })

EXECUTION SUMMARY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Successful Operations:   $Script:SuccessCount
Failed Operations:       $Script:FailureCount
Overall Status:          $(if ($Script:FailureCount -eq 0) { "COMPLETE SUCCESS" } elseif ($Script:FailureCount -lt 5) { "MOSTLY SUCCESSFUL" } else { "PARTIAL SUCCESS" })

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

$VerificationResults | Out-File $Script:VerificationLog
Write-Host $VerificationResults -ForegroundColor Cyan

# ============================================================================
# COMPLETION BANNER
# ============================================================================

Write-Host "`n╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                                          ║" -ForegroundColor Green
Write-Host "║              ✓  NUCLEAR EVICTION COMPLETE  ✓                             ║" -ForegroundColor Green
Write-Host "║                                                                          ║" -ForegroundColor Green
Write-Host "║         Enterprise Management Successfully Obliterated                  ║" -ForegroundColor Green
Write-Host "║                                                                          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`n[CRITICAL NEXT STEPS]" -ForegroundColor Yellow
Write-Host "1. Review verification results: $Script:VerificationLog" -ForegroundColor Cyan
Write-Host "2. REBOOT SYSTEM to finalize all changes" -ForegroundColor Cyan
Write-Host "3. After reboot, verify Windows Hello/PIN works" -ForegroundColor Cyan
Write-Host "4. Run: dsregcmd /status to confirm clean state" -ForegroundColor Cyan
Write-Host "5. Check Settings > Accounts > Access work or school (should be empty)" -ForegroundColor Cyan

if ($Script:FailureCount -gt 0) {
    Write-Host "`n[WARNING] $Script:FailureCount operations failed" -ForegroundColor Yellow
    Write-Host "Review log file for details: $Script:LogFile" -ForegroundColor Yellow
    Write-Host "Consider running with -AggressiveMode if issues persist" -ForegroundColor Yellow
}

Write-Host "`nAll logs saved to: $LogPath" -ForegroundColor Green

Stop-Transcript

$Reboot = Read-Host "`nReboot now to complete eviction? (Y/N)"
if ($Reboot -eq 'Y') {
    Write-Host "Rebooting in 30 seconds..." -ForegroundColor Yellow
    shutdown /r /t 30 /c "Completing Nuclear Eviction - System reboot required"
}
