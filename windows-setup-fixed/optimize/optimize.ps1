#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$AggressivePower,
    [switch]$AggressiveVisualTweaks,
    [switch]$DisableBackgroundApps,
    [switch]$TuneServices,
    [switch]$DisableIndexing,
    [switch]$TuneScheduledTasks,
    [switch]$EnableMemoryCompression,
    [switch]$TrimStartupItems,
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft optimize.ps1"
$ScriptVersion = "3.1.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("optimize-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
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

function Optimize-PowerPlan {
    Write-Log "Optimizing power and CPU policy..." "INFO" Cyan

    if ($AggressivePower) {
        powercfg -setactive SCHEME_MIN | Out-Null
    }

    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null

    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 30 | Out-Null
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null

    powercfg -setactive SCHEME_CURRENT | Out-Null
}

function Optimize-Visuals {
    if (-not $AggressiveVisualTweaks) { return }

    Write-Log "Applying visual-performance tweaks..." "INFO" Cyan

    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    New-Item -Path $adv -Force | Out-Null
    Set-ItemProperty -Path $adv -Name DisableAnimations -Value 1
    Set-ItemProperty -Path $adv -Name TaskbarAnimations -Value 0

    $desk = "HKCU:\Control Panel\Desktop"
    New-Item -Path $desk -Force | Out-Null
    Set-ItemProperty -Path $desk -Name MenuShowDelay -Value 80
    Set-ItemProperty -Path $desk -Name WindowAnimations -Value 0
}

function Optimize-BackgroundApps {
    if (!$DisableBackgroundApps) { return }

    Write-Log "Disabling background UWP apps via policy..." "INFO" Cyan

    $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name LetAppsRunInBackground -Type DWord -Value 2
}

function Set-ServiceSafeStartup {
    param([string]$Name,[string]$Type)

    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $Name -StartupType $Type -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Optimize-Services {
    if (-not $TuneServices) { return }

    Write-Log "Optimizing safe Windows services..." "INFO" Cyan

    Set-ServiceSafeStartup "DiagTrack" "Manual"
    Set-ServiceSafeStartup "SysMain" "Manual"
    Set-ServiceSafeStartup "MapsBroker" "Disabled"
    Set-ServiceSafeStartup "RetailDemo" "Disabled"
    Set-ServiceSafeStartup "XblAuthManager" "Manual"
    Set-ServiceSafeStartup "XblGameSave" "Manual"
    Set-ServiceSafeStartup "XboxGipSvc" "Manual"
    Set-ServiceSafeStartup "XboxNetApiSvc" "Manual"

    if ($DisableIndexing) {
        Set-ServiceSafeStartup "WSearch" "Manual"
    }
}

function Clean-TempAndCache {
    Write-Log "Cleaning temp files, cache, and prefetch..." "INFO" Cyan

    $paths = @(
        "$env:TEMP\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*"
    )

    foreach ($p in $paths) {
        try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Optimize-Storage {
    Write-Log "Optimizing storage (SSD TRIM / HDD defrag)..." "INFO" Cyan

    try {
        $vols = Get-Volume | Where-Object DriveLetter

        foreach ($v in $vols) {
            if ($v.MediaType -match "SSD") {
                Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -ErrorAction SilentlyContinue
            } elseif ($v.MediaType -match "HDD") {
                Optimize-Volume -DriveLetter $v.DriveLetter -Defrag -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}

function Optimize-ScheduledTasks {
    if (-not $TuneScheduledTasks) { return }

    Write-Log "Disabling safe scheduled tasks..." "INFO" Cyan

    $disable = @(
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
    )

    foreach ($task in $disable) {
        try {
            Disable-ScheduledTask `
                -TaskName (Split-Path $task -Leaf) `
                -TaskPath (Split-Path $task -Parent + "\") `
                -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }
}

function Optimize-Memory {
    if (-not $EnableMemoryCompression) { return }

    Write-Log "Enabling Windows memory compression..." "INFO" Cyan

    try { Enable-MMAgent -MemoryCompression } catch {}
}

function Optimize-StartupItems {
    if (-not $TrimStartupItems) { return }

    Write-Log "Trimming startup programs..." "INFO" Cyan

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $patterns = @(
        "*Update*", "*Updater*", "*GoogleUpdate*", "*OneDriveStandaloneUpdater*", "*AdobeARM*"
    )

    $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue

    if ($items) {
        foreach ($name in $items.PSObject.Properties.Name) {
            foreach ($pat in $patterns) {
                if ($name -like $pat) {
                    try {
                        Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
            }
        }
    }
}

function Pin-TaskbarItems {
    Write-Log "Pinning essential items to taskbar..." "INFO" Cyan
    
    try {
        # Pin Task Manager to taskbar
        $taskMgrPath = "$env:SystemRoot\System32\Taskmgr.exe"
        if (Test-Path $taskMgrPath) {
            try {
                $shell = New-Object -ComObject Shell.Application
                $folder = $shell.Namespace((Split-Path $taskMgrPath))
                $item = $folder.ParseName((Split-Path $taskMgrPath -Leaf))
                $verb = $item.Verbs() | Where-Object {$_.Name -match "taskbar"}
                if ($verb) {
                    $verb.DoIt()
                    Write-Log "Pinned Task Manager to taskbar." "OK" Green
                }
            } catch {}
        }
        
        # Pin Notepad to taskbar
        $notepadPath = "$env:SystemRoot\System32\notepad.exe"
        if (Test-Path $notepadPath) {
            try {
                $shell = New-Object -ComObject Shell.Application
                $folder = $shell.Namespace((Split-Path $notepadPath))
                $item = $folder.ParseName((Split-Path $notepadPath -Leaf))
                $verb = $item.Verbs() | Where-Object {$_.Name -match "taskbar"}
                if ($verb) {
                    $verb.DoIt()
                    Write-Log "Pinned Notepad to taskbar." "OK" Green
                }
            } catch {}
        }
    }
    catch {
        Write-Log "Taskbar pinning encountered issues (may require manual pinning)." "WARN" Yellow
    }
}

function Create-SettingsShortcuts {
    Write-Log "Creating important settings shortcuts in Start Menu..." "INFO" Cyan
    
    try {
        # Create Start Menu shortcuts for important settings
        $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\System Tools"
        if (!(Test-Path $startMenuPath)) {
            New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null
        }
        
        $importantSettings = @{
            "System Information" = "ms-settings:about"
            "Windows Update Center" = "ms-settings:windowsupdate"
            "Network Status" = "ms-settings:network-status"
            "Storage Management" = "ms-settings:storagesense"
            "Power  & Sleep" = "ms-settings:powersleep"
            "Apps & Features" = "ms-settings:appsfeatures"
            "Windows Security" = "windowsdefender:"
            "Device Manager" = "devmgmt.msc"
        }
        
        $shell = New-Object -ComObject WScript.Shell
        
        foreach ($name in $importantSettings.Keys) {
            try {
                $shortcutPath = Join-Path $startMenuPath "$name.lnk"
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $importantSettings[$name]
                $shortcut.Save()
            } catch {}
        }
        
        Write-Log "Created important settings shortcuts in Start Menu." "OK" Green
    }
    catch {
        Write-Log "Settings shortcuts creation encountered issues." "WARN" Yellow
    }
}

Optimize-PowerPlan
Optimize-Visuals
Optimize-BackgroundApps
Optimize-Services
Clean-TempAndCache
Optimize-Storage
Optimize-ScheduledTasks
Optimize-Memory
Optimize-StartupItems
Pin-TaskbarItems
Create-SettingsShortcuts

Write-Log "optimize.ps1 completed. Reboot recommended." "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
