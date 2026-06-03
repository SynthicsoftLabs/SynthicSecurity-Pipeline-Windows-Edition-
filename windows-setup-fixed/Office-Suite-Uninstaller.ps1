#Requires -RunAsAdministrator

Write-Host "========================================================================" -ForegroundColor Red
Write-Host "     MICROSOFT OFFICE TOTAL ANNIHILATION SCRIPT                        " -ForegroundColor Red
Write-Host "     Target: Excel, Access, OneNote, PowerPoint, Outlook, Publisher, Word " -ForegroundColor Red
Write-Host "========================================================================" -ForegroundColor Red
Write-Host ""

$StartTime = Get-Date

# ============================================================================
# PHASE 1: REMOVE ALL OFFICE UWP/STORE APPS
# ============================================================================
Write-Host "PHASE 1: Hunting Office UWP/Store Apps..." -ForegroundColor Cyan

$OfficeAppPatterns = @(
    "*Office*",
    "*OneNote*",
    "*Excel*",
    "*Word*",
    "*PowerPoint*",
    "*Outlook*",
    "*Access*",
    "*Publisher*",
    "*Lync*",
    "*Skype*Business*"
)

$RemovedCount = 0

foreach ($pattern in $OfficeAppPatterns) {
    # Remove for ALL users
    $Apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like $pattern}
    foreach ($app in $Apps) {
        Write-Host "  [KILL] $($app.Name) - ALL USERS" -ForegroundColor Red
        Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        $RemovedCount++
    }
    
    # Remove for current user (redundant but thorough)
    $Apps = Get-AppxPackage | Where-Object {$_.Name -like $pattern}
    foreach ($app in $Apps) {
        Write-Host "  [KILL] $($app.Name) - CURRENT USER" -ForegroundColor Red
        Remove-AppxPackage -Package $app.PackageFullName -ErrorAction SilentlyContinue
        $RemovedCount++
    }
    
    # Remove provisioned packages (prevents Windows from reinstalling)
    $Provisioned = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like $pattern}
    foreach ($pkg in $Provisioned) {
        Write-Host "  [DEPROVISION] $($pkg.DisplayName)" -ForegroundColor Red
        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue
        $RemovedCount++
    }
}

Write-Host "PHASE 1 COMPLETE: Removed $RemovedCount app packages" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 2: STOP ALL OFFICE PROCESSES
# ============================================================================
Write-Host "PHASE 2: Terminating Office processes..." -ForegroundColor Cyan

$OfficeProcesses = @(
    "EXCEL", "WINWORD", "POWERPNT", "OUTLOOK", "MSACCESS", "MSPUB", "ONENOTE",
    "ONENOTEM", "OfficeClickToRun", "officeclicktorun", "AppVShNotify",
    "lync", "communicator", "OfficeSvcManager", "ose", "osppsvc"
)

foreach ($proc in $OfficeProcesses) {
    $Processes = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($Processes) {
        $count = $Processes.Count
        Write-Host "  [TERMINATE] $proc - $count instances" -ForegroundColor Red
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PHASE 2 COMPLETE: All Office processes terminated" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 3: STOP AND REMOVE OFFICE SERVICES
# ============================================================================
Write-Host "PHASE 3: Stopping and removing Office services..." -ForegroundColor Cyan

$OfficeServices = @(
    "ClickToRunSvc",
    "OfficeSvc",
    "osppsvc",
    "OSE.EXE"
)

foreach ($svc in $OfficeServices) {
    $Service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($Service) {
        Write-Host "  [STOP] $svc" -ForegroundColor Red
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        
        # Try to delete the service
        sc.exe delete $svc 2>$null
    }
}

Write-Host "PHASE 3 COMPLETE: Office services disabled" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 4: REMOVE OFFICE SCHEDULED TASKS
# ============================================================================
Write-Host "PHASE 4: Removing Office scheduled tasks..." -ForegroundColor Cyan

$OfficeTasks = Get-ScheduledTask | Where-Object {
    $_.TaskName -like "*Office*" -or 
    $_.TaskPath -like "*Microsoft\Office*"
}

foreach ($task in $OfficeTasks) {
    Write-Host "  [REMOVE] Scheduled Task: $($task.TaskName)" -ForegroundColor Red
    Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host "PHASE 4 COMPLETE: Office scheduled tasks removed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 5: UNINSTALL VIA CLICK-TO-RUN
# ============================================================================
Write-Host "PHASE 5: Uninstalling via Click-to-Run..." -ForegroundColor Cyan

$ClickToRunPath = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"

if (Test-Path $ClickToRunPath) {
    Write-Host "  [UNINSTALL] Click-to-Run Office Suite" -ForegroundColor Red
    
    # Uninstall all Office 365 products
    $Products = @(
        "O365HomePremRetail",
        "O365ProPlusRetail",
        "O365BusinessRetail",
        "ProPlusRetail",
        "HomeBusinessRetail",
        "HomeStudentRetail",
        "PersonalRetail"
    )
    
    foreach ($product in $Products) {
        $Args = "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=$product.16_en-us_x-none culture=en-us version.16=16.0"
        Start-Process -FilePath $ClickToRunPath -ArgumentList $Args -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 5
} else {
    Write-Host "  [INFO] Click-to-Run not found" -ForegroundColor Gray
}

Write-Host "PHASE 5 COMPLETE: Click-to-Run uninstall executed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 6: UNINSTALL VIA MSI (ALL VERSIONS)
# ============================================================================
Write-Host "PHASE 6: Uninstalling MSI-based Office installations..." -ForegroundColor Cyan

# Query WMI for ALL Office products
$InstalledOffice = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -like "*Microsoft Office*" -or
    $_.Name -like "*Microsoft Excel*" -or
    $_.Name -like "*Microsoft Word*" -or
    $_.Name -like "*Microsoft PowerPoint*" -or
    $_.Name -like "*Microsoft Outlook*" -or
    $_.Name -like "*Microsoft Access*" -or
    $_.Name -like "*Microsoft Publisher*" -or
    $_.Name -like "*Microsoft OneNote*"
}

foreach ($product in $InstalledOffice) {
    Write-Host "  [UNINSTALL] $($product.Name)" -ForegroundColor Red
    $product.Uninstall() | Out-Null
}

# Known Office MSI GUIDs (2013, 2016, 2019, 2021, 365)
$OfficeMSIGuids = @(
    '90160000-0011-0000-0000-0000000FF1CE',
    '90160000-0011-0000-1000-0000000FF1CE',
    '90160000-00A1-0409-0000-0000000FF1CE',
    '90160000-00A1-0409-1000-0000000FF1CE',
    '90160000-001B-0409-0000-0000000FF1CE',
    '90160000-001B-0409-1000-0000000FF1CE',
    '90160000-0016-0409-0000-0000000FF1CE',
    '90160000-0016-0409-1000-0000000FF1CE',
    '90160000-0018-0409-0000-0000000FF1CE',
    '90160000-0018-0409-1000-0000000FF1CE',
    '90160000-001A-0409-0000-0000000FF1CE',
    '90160000-001A-0409-1000-0000000FF1CE',
    '90160000-0015-0409-0000-0000000FF1CE',
    '90160000-0015-0409-1000-0000000FF1CE',
    '90160000-0019-0409-0000-0000000FF1CE',
    '90160000-0019-0409-1000-0000000FF1CE',
    '90160000-007E-0000-0000-0000000FF1CE',
    '90160000-007E-0000-1000-0000000FF1CE',
    '90160000-008C-0000-0000-0000000FF1CE',
    '90160000-008C-0000-1000-0000000FF1CE',
    '90160000-008C-0409-0000-0000000FF1CE',
    '90160000-008C-0409-1000-0000000FF1CE'
)

foreach ($guid in $OfficeMSIGuids) {
    Write-Host "  [UNINSTALL] MSI GUID: {$guid}" -ForegroundColor Red
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x {$guid} /qn /norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue
}

Write-Host "PHASE 6 COMPLETE: MSI uninstalls executed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 7: NUCLEAR FOLDER DELETION
# ============================================================================
Write-Host "PHASE 7: Deleting Office folders..." -ForegroundColor Cyan

$OfficeFolders = @(
    # Program Files
    "C:\Program Files\Microsoft Office",
    "C:\Program Files (x86)\Microsoft Office",
    "C:\Program Files\Microsoft Office 15",
    "C:\Program Files (x86)\Microsoft Office 15",
    "C:\Program Files\Microsoft Office 16",
    "C:\Program Files (x86)\Microsoft Office 16",
    
    # ProgramData
    "C:\ProgramData\Microsoft\Office",
    "C:\ProgramData\Microsoft\ClickToRun",
    "C:\ProgramData\Microsoft\OfficeSoftwareProtectionPlatform",
    
    # AppData - Current User
    "C:\Users\$env:USERNAME\AppData\Local\Microsoft\Office",
    "C:\Users\$env:USERNAME\AppData\Local\Microsoft\OneNote",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Office",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Templates",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Excel",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Word",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\PowerPoint",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Outlook",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Access",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Publisher",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\OneNote"
)

foreach ($folder in $OfficeFolders) {
    if (Test-Path $folder) {
        Write-Host "  [DELETE] $folder" -ForegroundColor Red
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Also remove with wildcards
$WildcardPaths = @(
    "C:\Program Files\Common Files\Microsoft Shared\Office*",
    "C:\Program Files (x86)\Common Files\Microsoft Shared\Office*",
    "C:\Users\$env:USERNAME\AppData\Local\Temp\Office*",
    "C:\Windows\Temp\Office*"
)

foreach ($pattern in $WildcardPaths) {
    $Items = Get-Item -Path $pattern -ErrorAction SilentlyContinue
    foreach ($item in $Items) {
        Write-Host "  [DELETE] $($item.FullName)" -ForegroundColor Red
        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PHASE 7 COMPLETE: Office folders deleted" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 8: REMOVE START MENU SHORTCUTS
# ============================================================================
Write-Host "PHASE 8: Removing Start Menu shortcuts..." -ForegroundColor Cyan

$StartMenuPaths = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
    "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
)

$OfficeKeywords = @("Excel", "Word", "PowerPoint", "Outlook", "Access", "Publisher", "OneNote", "Microsoft Office")

foreach ($basePath in $StartMenuPaths) {
    foreach ($keyword in $OfficeKeywords) {
        $Items = Get-ChildItem -Path $basePath -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -like "*$keyword*" }
        
        foreach ($item in $Items) {
            Write-Host "  [DELETE] $($item.FullName)" -ForegroundColor Red
            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "PHASE 8 COMPLETE: Start Menu shortcuts removed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 9: REMOVE DESKTOP SHORTCUTS
# ============================================================================
Write-Host "PHASE 9: Removing Desktop shortcuts..." -ForegroundColor Cyan

$DesktopPaths = @(
    "$env:USERPROFILE\Desktop",
    "$env:PUBLIC\Desktop"
)

foreach ($desktopPath in $DesktopPaths) {
    foreach ($keyword in $OfficeKeywords) {
        $Shortcuts = Get-ChildItem -Path $desktopPath -Filter "*$keyword*.lnk" -ErrorAction SilentlyContinue
        foreach ($shortcut in $Shortcuts) {
            Write-Host "  [DELETE] $($shortcut.FullName)" -ForegroundColor Red
            Remove-Item -Path $shortcut.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "PHASE 9 COMPLETE: Desktop shortcuts removed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 10: REGISTRY ANNIHILATION
# ============================================================================
Write-Host "PHASE 10: Obliterating Office registry entries..." -ForegroundColor Cyan

$RegistryPaths = @(
    "HKCU:\Software\Microsoft\Office",
    "HKLM:\Software\Microsoft\Office",
    "HKLM:\Software\Wow6432Node\Microsoft\Office",
    "HKCU:\Software\Microsoft\Excel",
    "HKCU:\Software\Microsoft\Word",
    "HKCU:\Software\Microsoft\PowerPoint",
    "HKCU:\Software\Microsoft\Outlook",
    "HKCU:\Software\Microsoft\Access",
    "HKCU:\Software\Microsoft\Publisher",
    "HKCU:\Software\Microsoft\OneNote",
    "HKCU:\Software\Microsoft\Shared Tools\Proofing Tools",
    "HKLM:\Software\Microsoft\Shared Tools\Proofing Tools",
    "HKLM:\Software\Microsoft\ClickToRun",
    "HKLM:\Software\Microsoft\ClickToRunStore",
    "HKLM:\Software\Microsoft\OfficeSoftwareProtectionPlatform"
)

foreach ($regPath in $RegistryPaths) {
    if (Test-Path $regPath) {
        Write-Host "  [DELETE] $regPath" -ForegroundColor Red
        Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove Office from uninstall list
$UninstallPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $UninstallPaths) {
    Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -like "*Office*" -or
        $_.DisplayName -like "*Excel*" -or
        $_.DisplayName -like "*Word*" -or
        $_.DisplayName -like "*PowerPoint*" -or
        $_.DisplayName -like "*Outlook*" -or
        $_.DisplayName -like "*Access*" -or
        $_.DisplayName -like "*Publisher*" -or
        $_.DisplayName -like "*OneNote*"
    } | ForEach-Object {
        $RegPath = $_.PSPath
        Write-Host "  [DELETE] Uninstall entry: $($_.DisplayName)" -ForegroundColor Red
        Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PHASE 10 COMPLETE: Registry entries obliterated" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 11: REMOVE FILE ASSOCIATIONS
# ============================================================================
Write-Host "PHASE 11: Removing Office file associations..." -ForegroundColor Cyan

$OfficeExtensions = @(".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt", ".msg", ".one", ".accdb", ".mdb", ".pub")

foreach ($ext in $OfficeExtensions) {
    Write-Host "  [REMOVE] File association for $ext" -ForegroundColor Red
    cmd /c "assoc $ext=" 2>$null | Out-Null
}

Write-Host "PHASE 11 COMPLETE: File associations removed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 12: FINAL CLEANUP & VERIFICATION
# ============================================================================
Write-Host "PHASE 12: Final cleanup..." -ForegroundColor Cyan

# Clear Windows Installer cache for Office
$InstallerCache = "C:\Windows\Installer"
if (Test-Path $InstallerCache) {
    $OfficeMSIs = Get-ChildItem -Path $InstallerCache -Filter "*Office*.msi" -ErrorAction SilentlyContinue
    foreach ($msi in $OfficeMSIs) {
        Write-Host "  [DELETE] Installer cache: $($msi.Name)" -ForegroundColor Red
        Remove-Item -Path $msi.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PHASE 12 COMPLETE: Final cleanup executed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# VERIFICATION REPORT
# ============================================================================
Write-Host "========================================================================" -ForegroundColor Yellow
Write-Host "                        VERIFICATION REPORT                             " -ForegroundColor Yellow
Write-Host "========================================================================" -ForegroundColor Yellow
Write-Host ""

$FoundIssues = 0

# Check for remaining Store apps
$RemainingApps = Get-AppxPackage -AllUsers | Where-Object {
    $_.Name -like "*Office*" -or $_.Name -like "*OneNote*" -or
    $_.Name -like "*Excel*" -or $_.Name -like "*Word*" -or
    $_.Name -like "*PowerPoint*" -or $_.Name -like "*Outlook*"
}

if ($RemainingApps) {
    Write-Host "WARNING: REMAINING STORE APPS DETECTED:" -ForegroundColor Yellow
    $RemainingApps | ForEach-Object { 
        Write-Host "    - $($_.Name)" -ForegroundColor Yellow 
        $FoundIssues++
    }
} else {
    Write-Host "SUCCESS: No Office Store apps detected" -ForegroundColor Green
}

# Check for remaining folders
$FoldersToCheck = @(
    "C:\Program Files\Microsoft Office",
    "C:\Program Files (x86)\Microsoft Office",
    "C:\ProgramData\Microsoft\Office"
)

foreach ($folder in $FoldersToCheck) {
    if (Test-Path $folder) {
        Write-Host "WARNING: REMAINING FOLDER: $folder" -ForegroundColor Yellow
        $FoundIssues++
    }
}

# Check for remaining processes
$RemainingProcesses = Get-Process | Where-Object {
    $_.ProcessName -like "*EXCEL*" -or $_.ProcessName -like "*WINWORD*" -or
    $_.ProcessName -like "*POWERPNT*" -or $_.ProcessName -like "*OUTLOOK*" -or
    $_.ProcessName -like "*MSACCESS*" -or $_.ProcessName -like "*MSPUB*" -or
    $_.ProcessName -like "*ONENOTE*"
}

if ($RemainingProcesses) {
    Write-Host "WARNING: RUNNING OFFICE PROCESSES:" -ForegroundColor Yellow
    $RemainingProcesses | ForEach-Object { 
        Write-Host "    - $($_.ProcessName)" -ForegroundColor Yellow
        $FoundIssues++
    }
}

# Check Start Menu
$StartMenuCheck = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "*Excel*" -or $_.Name -like "*Word*" -or $_.Name -like "*PowerPoint*" -or 
                   $_.Name -like "*Outlook*" -or $_.Name -like "*Access*" -or $_.Name -like "*Publisher*" -or 
                   $_.Name -like "*OneNote*" -or $_.Name -like "*Office*" }

if ($StartMenuCheck) {
    Write-Host "WARNING: REMAINING START MENU ITEMS:" -ForegroundColor Yellow
    $StartMenuCheck | ForEach-Object { 
        Write-Host "    - $($_.FullName)" -ForegroundColor Yellow
        $FoundIssues++
    }
} else {
    Write-Host "SUCCESS: No Office items in Start Menu" -ForegroundColor Green
}

Write-Host ""

if ($FoundIssues -eq 0) {
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "               TOTAL ANNIHILATION SUCCESSFUL                            " -ForegroundColor Green
    Write-Host "                                                                        " -ForegroundColor Green
    Write-Host "  Microsoft Office has been completely obliterated from this system.   " -ForegroundColor Green
    Write-Host "  No traces of Excel, Word, PowerPoint, Outlook, Access, Publisher,    " -ForegroundColor Green
    Write-Host "  or OneNote remain.                                                    " -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
} else {
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "                    PARTIAL SUCCESS                                     " -ForegroundColor Yellow
    Write-Host "                                                                        " -ForegroundColor Yellow
    Write-Host "  $FoundIssues remnants detected. Manual cleanup may be required.      " -ForegroundColor Yellow
    Write-Host "  See above for details.                                                " -ForegroundColor Yellow
    Write-Host "========================================================================" -ForegroundColor Yellow
}

Write-Host ""

$Duration = (Get-Date) - $StartTime
Write-Host "Execution Time: $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -ForegroundColor Cyan
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "                     RESTART REQUIRED TO COMPLETE                       " -ForegroundColor Yellow
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Ask to restart
$Restart = Read-Host "Restart computer now? (Y/N)"
if ($Restart -eq "Y" -or $Restart -eq "y") {
    Write-Host "Restarting in 10 seconds..." -ForegroundColor Red
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Host "Please restart manually to complete Office removal." -ForegroundColor Yellow
}
