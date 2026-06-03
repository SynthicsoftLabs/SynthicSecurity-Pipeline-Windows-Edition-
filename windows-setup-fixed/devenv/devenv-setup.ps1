#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile,
    [switch]$SkipWSL,
    [switch]$SkipVSCode
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft devenv-setup.ps1"
$ScriptVersion = "1.1.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("devenv-setup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
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

function Test-InternetConnection {
    try {
        $res = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -WarningAction SilentlyContinue
        return $res.TcpTestSucceeded
    } catch { return $false }
}

function Install-WindowsTerminal {
    Write-Log "Installing Windows Terminal..." "INFO" Cyan
    
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-InternetConnection)) {
        try {
            $installed = winget list --id Microsoft.WindowsTerminal 2>$null
            if ($installed -notmatch "Microsoft.WindowsTerminal") {
                $args = "install --id Microsoft.WindowsTerminal --silent --accept-package-agreements --accept-source-agreements"
                Start-Process -FilePath $cmd.Source -ArgumentList $args -Wait -NoNewWindow
                Write-Log "Windows Terminal installed." "OK" Green
            } else {
                Write-Log "Windows Terminal already installed." "INFO" Gray
            }
        } catch {
            Write-Log "Windows Terminal installation failed: $_" "WARN" Yellow
        }
    }
}

function Install-VSCode {
    if ($SkipVSCode) {
        Write-Log "VS Code installation skipped by parameter." "INFO" Gray
        return
    }
    
    Write-Log "Installing Visual Studio Code with extensions..." "INFO" Cyan
    
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-InternetConnection)) {
        try {
            $installed = winget list --id Microsoft.VisualStudioCode 2>$null
            if ($installed -notmatch "Microsoft.VisualStudioCode") {
                $args = "install --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements"
                Start-Process -FilePath $cmd.Source -ArgumentList $args -Wait -NoNewWindow
                Write-Log "VS Code installed." "OK" Green
                
                # Wait for VS Code to be available
                Start-Sleep -Seconds 10
            }
            
            # Install essential extensions
            $codeCmd = Get-Command code -ErrorAction SilentlyContinue
            if ($codeCmd) {
                $extensions = @(
                    "ms-python.python",
                    "ms-vscode.powershell",
                    "golang.go",
                    "rust-lang.rust-analyzer",
                    "ms-vscode.cpptools",
                    "ms-azuretools.vscode-docker",
                    "eamodio.gitlens",
                    "esbenp.prettier-vscode",
                    "dbaeumer.vscode-eslint"
                )
                
                foreach ($ext in $extensions) {
                    try {
                        Start-Process -FilePath $codeCmd.Source -ArgumentList "--install-extension $ext --force" -Wait -NoNewWindow
                        Write-Log "Installed VS Code extension: $ext" "OK" Green
                    } catch {}
                }
            }
        } catch {
            Write-Log "VS Code setup failed: $_" "WARN" Yellow
        }
    }
}


function Enable-WSL {
    if ($SkipWSL) {
        Write-Log "WSL installation skipped by parameter." "INFO" Gray
        return
    }
    
    Write-Log "Enabling WSL2 and installing Ubuntu..." "INFO" Cyan
    
    try {
        # Check if WSL is already enabled
        $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        
        if ($wslFeature.State -ne "Enabled") {
            Write-Log "Enabling WSL feature..." "INFO" Cyan
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Enable Virtual Machine Platform
        $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($vmFeature.State -ne "Enabled") {
            Write-Log "Enabling Virtual Machine Platform..." "INFO" Cyan
            Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Set WSL 2 as default
        wsl --set-default-version 2 2>$null | Out-Null
        
        # Install Ubuntu if online - with smart detection
        if (Test-InternetConnection) {
            # Check if Ubuntu is already installed
            $ubuntuInstalled = $false
            try {
                $wslList = wsl -l -v 2>&1 | Out-String
                if ($wslList -match "Ubuntu" -or $wslList -match "ubuntu") {
                    $ubuntuInstalled = $true
                    Write-Log "Ubuntu for WSL is already installed." "OK" Green
                }
            }
            catch {
                # If wsl -l fails, Ubuntu is definitely not installed
                $ubuntuInstalled = $false
            }
            
            # Also check via WinGet as backup detection
            if (-not $ubuntuInstalled) {
                try {
                    $ubuntuCheck = winget list --id Canonical.Ubuntu 2>$null | Out-String
                    if ($ubuntuCheck -match "Ubuntu") {
                        $ubuntuInstalled = $true
                        Write-Log "Ubuntu for WSL detected via WinGet." "OK" Green
                    }
                }
                catch {}
            }
            
            # Only install if definitely not present
            if (-not $ubuntuInstalled) {
                Write-Log "Installing Ubuntu for WSL2 (this may take several minutes)..." "INFO" Cyan
                try {
                    wsl --install -d Ubuntu --no-launch 2>&1 | Out-Null
                    Write-Log "Ubuntu installed. User must run 'wsl' to complete first-time setup." "INFO" Yellow
                }
                catch {
                    Write-Log "Ubuntu installation may have failed. Check with 'wsl -l -v'" "WARN" Yellow
                }
            }
        }
    } catch {
        Write-Log "WSL setup failed: $_" "WARN" Yellow
    }
}

function Configure-Git {
    Write-Log "Configuring Git settings..." "INFO" Cyan
    
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        try {
            # Set safe defaults
            git config --global core.autocrlf true 2>$null
            git config --global init.defaultBranch main 2>$null
            git config --global pull.rebase false 2>$null
            git config --global credential.helper wincred 2>$null
            
            Write-Log "Git configured with safe defaults." "OK" Green
            Write-Log "User should set: git config --global user.name and user.email" "INFO" Gray
        } catch {}
    }
}

function Create-UserFolders {
    Write-Log "Creating standard development folder structure..." "INFO" Cyan
    
    try {
        $userProfile = $env:USERPROFILE
        $folders = @(
            "$userProfile\Development",
            "$userProfile\Development\Projects",
            "$userProfile\Development\Tools",
            "$userProfile\Development\Repos",
            "$userProfile\Documents\Scripts",
            "$userProfile\Documents\Notes"
        )
        
        foreach ($folder in $folders) {
            if (!(Test-Path $folder)) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Write-Log "Created: $folder" "OK" Green
            }
        }
    } catch {
        Write-Log "Folder creation failed: $_" "WARN" Yellow
    }
}

function Configure-PowerShellProfile {
    Write-Log "Setting up PowerShell profile..." "INFO" Cyan
    
    try {
        $profileContent = @'
# SynthicSoft PowerShell Profile
# Auto-generated by devenv-setup.ps1

# Aliases for common operations
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name touch -Value New-Item

# Function: Create and enter directory
function mkcd { param($dir) New-Item -ItemType Directory -Path $dir -Force | Set-Location }

# Function: Quick navigation to Development folder
function dev { Set-Location "$env:USERPROFILE\Development" }

# Enhanced prompt with Git branch (if in Git repo)
function prompt {
    $loc = Get-Location
    $gitBranch = ""
    
    if (Test-Path .git) {
        try {
            $gitBranch = " [$(git branch --show-current 2>$null)]"
        } catch {}
    }
    
    Write-Host "PS " -NoNewline -ForegroundColor Green
    Write-Host "$loc" -NoNewline -ForegroundColor Cyan
    Write-Host "$gitBranch" -NoNewline -ForegroundColor Yellow
    return "> "
}

# Welcome message
Write-Host "SynthicSoft Development Environment" -ForegroundColor Cyan
Write-Host "Type 'dev' to navigate to Development folder" -ForegroundColor Gray
'@

        $profilePath = $PROFILE.CurrentUserAllHosts
        $profileDir = Split-Path -Parent $profilePath
        
        if (!(Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        
        Set-Content -Path $profilePath -Value $profileContent -Force
        Write-Log "PowerShell profile created at: $profilePath" "OK" Green
    } catch {
        Write-Log "PowerShell profile creation failed: $_" "WARN" Yellow
    }
}

function Enable-DeveloperMode {
    Write-Log "Enabling Windows Developer Mode..." "INFO" Cyan
    
    try {
        $devModePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
        if (!(Test-Path $devModePath)) {
            New-Item -Path $devModePath -Force | Out-Null
        }
        Set-ItemProperty -Path $devModePath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $devModePath -Name "AllowAllTrustedApps" -Value 1 -Type DWord -Force
        Write-Log "Developer Mode enabled." "OK" Green
    } catch {
        Write-Log "Developer Mode enablement failed: $_" "WARN" Yellow
    }
}

function Install-OptionalFeatures {
    Write-Log "Enabling optional Windows features for development..." "INFO" Cyan
    
    $features = @(
        "Microsoft-Hyper-V-All",
        "Containers",
        "Microsoft-Windows-Subsystem-Linux"
    )
    
    foreach ($feature in $features) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($featureState -and $featureState.State -ne "Enabled") {
                Write-Log "Enabling feature: $feature" "INFO" Cyan
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -All -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }
}

# Execute setup
Install-WindowsTerminal
Install-VSCode
Enable-WSL
Configure-Git
Create-UserFolders
Configure-PowerShellProfile
Enable-DeveloperMode
Install-OptionalFeatures

Write-Log "devenv-setup.ps1 completed. Reboot recommended for Windows features to activate." "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
