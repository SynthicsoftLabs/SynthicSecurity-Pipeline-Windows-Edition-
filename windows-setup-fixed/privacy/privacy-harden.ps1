#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft privacy-harden.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("privacy-harden-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
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

function Disable-Telemetry {
    Write-Log "Disabling Windows telemetry and data collection..." "INFO" Cyan
    
    # Disable telemetry services
    $telemetryServices = @(
        "DiagTrack",
        "dmwappushservice"
    )
    
    foreach ($svc in $telemetryServices) {
        try {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled telemetry service: $svc" "OK" Green
            }
        } catch {}
    }
    
    # Registry settings for telemetry
    $telemetryKeys = @(
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name="AllowTelemetry"; Value=0},
        @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name="AllowTelemetry"; Value=0},
        @{Path="HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name="AllowTelemetry"; Value=0}
    )
    
    foreach ($key in $telemetryKeys) {
        try {
            if (!(Test-Path $key.Path)) {
                New-Item -Path $key.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $key.Path -Name $key.Name -Value $key.Value -Type DWord -Force
        } catch {}
    }
}

function Disable-ActivityHistory {
    Write-Log "Disabling activity history and timeline..." "INFO" Cyan
    
    $activityKeys = @(
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="EnableActivityFeed"; Value=0},
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="PublishUserActivities"; Value=0},
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="UploadUserActivities"; Value=0}
    )
    
    foreach ($key in $activityKeys) {
        try {
            if (!(Test-Path $key.Path)) {
                New-Item -Path $key.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $key.Path -Name $key.Name -Value $key.Value -Type DWord -Force
        } catch {}
    }
}

function Disable-LocationTracking {
    Write-Log "Disabling location tracking..." "INFO" Cyan
    
    try {
        $locPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (!(Test-Path $locPath)) {
            New-Item -Path $locPath -Force | Out-Null
        }
        Set-ItemProperty -Path $locPath -Name "Value" -Value "Deny" -Force
        
        # Disable location service
        Stop-Service -Name "lfsvc" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "lfsvc" -StartupType Disabled -ErrorAction SilentlyContinue
    } catch {}
}

function Disable-Advertising {
    Write-Log "Disabling advertising ID and personalized ads..." "INFO" Cyan
    
    $adKeys = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; Value=0},
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name="DisabledByGroupPolicy"; Value=1}
    )
    
    foreach ($key in $adKeys) {
        try {
            if (!(Test-Path $key.Path)) {
                New-Item -Path $key.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $key.Path -Name $key.Name -Value $key.Value -Type DWord -Force
        } catch {}
    }
}

function Disable-Cortana {
    Write-Log "Disabling Cortana..." "INFO" Cyan
    
    try {
        $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (!(Test-Path $cortanaPath)) {
            New-Item -Path $cortanaPath -Force | Out-Null
        }
        Set-ItemProperty -Path $cortanaPath -Name "AllowCortana" -Value 0 -Type DWord -Force
    } catch {}
}

function Disable-WebSearch {
    Write-Log "Disabling web search in Start Menu..." "INFO" Cyan
    
    try {
        $searchPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (!(Test-Path $searchPath)) {
            New-Item -Path $searchPath -Force | Out-Null
        }
        Set-ItemProperty -Path $searchPath -Name "DisableWebSearch" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $searchPath -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
    } catch {}
}

function Disable-TipsAndSuggestions {
    Write-Log "Disabling tips, suggestions, and ads..." "INFO" Cyan
    
    $suggestionKeys = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338388Enabled"; Value=0},
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338389Enabled"; Value=0},
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353694Enabled"; Value=0},
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353696Enabled"; Value=0},
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SoftLandingEnabled"; Value=0},
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowSyncProviderNotifications"; Value=0}
    )
    
    foreach ($key in $suggestionKeys) {
        try {
            if (!(Test-Path $key.Path)) {
                New-Item -Path $key.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $key.Path -Name $key.Name -Value $key.Value -Type DWord -Force
        } catch {}
    }
}

function Configure-OneDrive {
    Write-Log "Configuring OneDrive (disable for local-only setup)..." "INFO" Cyan
    
    try {
        $onedrivePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
        if (!(Test-Path $onedrivePath)) {
            New-Item -Path $onedrivePath -Force | Out-Null
        }
        Set-ItemProperty -Path $onedrivePath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
        Write-Log "OneDrive file sync disabled (can be re-enabled by user if needed)" "INFO" Gray
    } catch {}
}

function Disable-FeedbackRequests {
    Write-Log "Disabling Windows feedback requests..." "INFO" Cyan
    
    try {
        $feedbackPath = "HKCU:\Software\Microsoft\Siuf\Rules"
        if (!(Test-Path $feedbackPath)) {
            New-Item -Path $feedbackPath -Force | Out-Null
        }
        Set-ItemProperty -Path $feedbackPath -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord -Force
        
        $feedbackPath2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (!(Test-Path $feedbackPath2)) {
            New-Item -Path $feedbackPath2 -Force | Out-Null
        }
        Set-ItemProperty -Path $feedbackPath2 -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force
    } catch {}
}

function Disable-WindowsSpotlight {
    Write-Log "Disabling Windows Spotlight on lock screen..." "INFO" Cyan
    
    try {
        $spotlightPath = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
        if (!(Test-Path $spotlightPath)) {
            New-Item -Path $spotlightPath -Force | Out-Null
        }
        Set-ItemProperty -Path $spotlightPath -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
    } catch {}
}

# Execute all privacy hardening
Disable-Telemetry
Disable-ActivityHistory
Disable-LocationTracking
Disable-Advertising
Disable-Cortana
Disable-WebSearch
Disable-TipsAndSuggestions
Configure-OneDrive
Disable-FeedbackRequests
Disable-WindowsSpotlight

Write-Log "privacy-harden.ps1 completed. Reboot recommended for all changes to take effect." "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
