[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile,
    [switch]$SkipIDrive
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft devsetup.ps1"
$ScriptVersion = "1.4.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $LogRoot ("devsetup-" + $Timestamp + ".log")
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
    if ($LogToFile -and (Test-Path $LogFile)) {
        Add-Content -Path $LogFile -Value $line
    }
}

Write-Log "=== $ScriptName v$ScriptVersion ===" "INFO" ([ConsoleColor]::Cyan)

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Must run as Administrator." "FATAL" ([ConsoleColor]::Red)
    exit 1
}

function Test-InternetConnection {
    try {
        $res = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -WarningAction SilentlyContinue
        return $res.TcpTestSucceeded
    } catch { return $false }
}

function Ensure-Tls {
    try {
        $p = [System.Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}
        [System.Net.ServicePointManager]::SecurityProtocol = $p
    } catch {}
}
Ensure-Tls

function Ensure-Winget {
    Write-Log "Ensuring winget is available..." "INFO" ([ConsoleColor]::Cyan)
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log "winget already present." "OK" ([ConsoleColor]::Green)
        return $true
    }

    if (-not (Test-InternetConnection)) {
        Write-Log "Offline; cannot install winget." "WARN" ([ConsoleColor]::Yellow)
        return $false
    }

    $appx = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if ($appx) {
        Write-Log "App Installer present; winget should be available after next login." "WARN" ([ConsoleColor]::Yellow)
        return $false
    }

    $tempPath = Join-Path $env:TEMP "AppInstaller.msixbundle"
    try {
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        Add-AppPackage -Path $tempPath -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    } catch {
        Write-Log "Failed installing App Installer/winget: $_" "WARN" ([ConsoleColor]::Yellow)
    }

    $cmd2 = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd2) {
        Write-Log "winget installed successfully." "OK" ([ConsoleColor]::Green)
        return $true
    } else {
        Write-Log "winget still unavailable; some installs may be skipped." "WARN" ([ConsoleColor]::Yellow)
        return $false
    }
}

$WingetAvailable = Ensure-Winget

function Install-WithWinget {
    param(
        [string]$IdOrName
    )
    if (-not $WingetAvailable) {
        Write-Log ("winget not available, skipping {0}" -f $IdOrName) "WARN" ([ConsoleColor]::Yellow)
        return
    }
    if (-not (Test-InternetConnection)) {
        Write-Log ("Offline; cannot install {0}" -f $IdOrName) "WARN" ([ConsoleColor]::Yellow)
        return
    }
    
    # Smart detection - check if already installed
    try {
        Write-Log ("Checking if {0} is already installed..." -f $IdOrName) "INFO" ([ConsoleColor]::Gray)
        $listArgs = "list --id `"{0}`" --exact --accept-source-agreements" -f $IdOrName
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $listOutput = & $cmd.Source $listArgs.Split(' ') 2>&1 | Out-String
            if ($listOutput -match $IdOrName -and $LASTEXITCODE -eq 0) {
                Write-Log ("Package already installed: {0} (detected, skipping)" -f $IdOrName) "OK" ([ConsoleColor]::Green)
                return
            }
        }
    }
    catch {
        # If detection fails, continue to installation
    }
    
    # Retry logic for installation
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
            if ($retryCount -gt 0) {
                $waitTime = [math]::Pow(2, $retryCount) * 2
                Write-Log ("Retry attempt {0} of {1} after {2}s..." -f ($retryCount + 1), $maxRetries, $waitTime) "INFO" ([ConsoleColor]::Yellow)
                Start-Sleep -Seconds $waitTime
            }
            
            $args = "install --id `"{0}`" --silent --accept-package-agreements --accept-source-agreements --source winget" -f $IdOrName
            Write-Log ("Installing via winget: {0}" -f $IdOrName) "INFO" ([ConsoleColor]::Cyan)
            $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($cmd) {
                $p = Start-Process -FilePath $cmd.Source -ArgumentList $args -Wait -NoNewWindow -PassThru -ErrorAction Stop
                $exitCode = $p.ExitCode
                
                Write-Log ("winget install {0} exited with {1}" -f $IdOrName, $exitCode) "INFO" ([ConsoleColor]::Gray)
                
                # Success codes
                if ($exitCode -eq 0) {
                    Write-Log ("Successfully installed: {0}" -f $IdOrName) "OK" ([ConsoleColor]::Green)
                    $success = $true
                }
                # Already installed / no upgrade available
                elseif ($exitCode -eq -1978335189) {
                    Write-Log ("Package already installed or no upgrade: {0}" -f $IdOrName) "OK" ([ConsoleColor]::Green)
                    $success = $true
                }
                # Package not found
                elseif ($exitCode -eq -1978335212) {
                    Write-Log ("Package not found: {0}" -f $IdOrName) "WARN" ([ConsoleColor]::Yellow)
                    break  # Don't retry not found
                }
                else {
                    $retryCount++
                }
            }
        } catch {
            Write-Log ("WinGet error for {0}: {1}" -f $IdOrName, $_) "WARN" ([ConsoleColor]::Yellow)
            $retryCount++
        }
    }
    
    if (-not $success) {
        Write-Log ("Failed to install {0} after {1} attempts. Continuing with suite..." -f $IdOrName, $maxRetries) "WARN" ([ConsoleColor]::Yellow)
    }
}

function Install-Choco {
    param(
        [string]$Pkg
    )
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        if (-not (Test-InternetConnection)) {
            Write-Log "Offline; cannot install Chocolatey." "WARN" ([ConsoleColor]::Yellow)
            return
        }
        try {
            Write-Log "Installing Chocolatey..." "INFO" ([ConsoleColor]::Cyan)
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        } catch {
            Write-Log "Chocolatey installation failed: $_" "WARN" ([ConsoleColor]::Yellow)
            return
        }
    }
    try {
        Write-Log ("Installing via choco: {0}" -f $Pkg) "INFO" ([ConsoleColor]::Cyan)
        choco install $Pkg -y --no-progress | Out-Null
    } catch {
        Write-Log ("Chocolatey failed installing {0}: {1}" -f $Pkg, $_) "WARN" ([ConsoleColor]::Yellow)
    }
}

Write-Log "Installing core development and tooling stack..." "INFO" ([ConsoleColor]::Cyan)

$packagesWinget = @(
    "Python.Python.3.13",
    "Rustlang.Rustup",
    "GoLang.Go",
    "Microsoft.VisualStudio.2022.BuildTools",
    "OpenJS.NodeJS.LTS",
    "Git.Git",
    "GitHub.GitHubDesktop",
    "Docker.DockerDesktop",
    "Google.Chrome",
    "Malwarebytes.Malwarebytes",
    "VideoLAN.VLC",
    "XBMCFoundation.Kodi",
    "TheDocumentFoundation.LibreOffice",
    "Valve.Steam",
    "gerardog.gsudo"
)
# Note: Spotify excluded - requires non-admin installation (user can install manually)

foreach ($pkg in $packagesWinget) {
    Install-WithWinget -IdOrName $pkg
}

if ($SkipIDrive) {
    Write-Log "IDrive installation skipped by flag." "INFO" ([ConsoleColor]::Gray)
} else {
    Install-WithWinget -IdOrName "IDriveInc.IDrive"
}

function Create-GodMode {
    Write-Log "Creating GodMode folder with all Windows settings..." "INFO" ([ConsoleColor]::Cyan)
    
    try {
        # GodMode CLSID
        $godModeGUID = "{ED7BA470-8E54-465E-825C-99712043E01C}"
        $godModeName = "GodMode.$godModeGUID"
        
        # Create on Desktop
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $godModePath = Join-Path $desktopPath $godModeName
        
        if (!(Test-Path $godModePath)) {
            New-Item -ItemType Directory -Path $godModePath -Force | Out-Null
            Write-Log "GodMode folder created on Desktop." "OK" ([ConsoleColor]::Green)
        } else {
            Write-Log "GodMode folder already exists on Desktop." "INFO" ([ConsoleColor]::Gray)
        }
        
        # Create shortcut in Start Menu for easy access
        $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\System Tools"
        if (!(Test-Path $startMenuPath)) {
            New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null
        }
        
        $shortcutPath = Join-Path $startMenuPath "GodMode - All Settings.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $godModePath
        $shortcut.Description = "Complete Windows settings and control panel"
        $shortcut.Save()
        
        Write-Log "GodMode shortcut added to Start Menu." "OK" ([ConsoleColor]::Green)
    }
    catch {
        Write-Log "GodMode creation failed: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

Create-GodMode

Install-Choco -Pkg "pstools"

Write-Log "devsetup.ps1 completed." "INFO" ([ConsoleColor]::Cyan)
if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" ([ConsoleColor]::Gray)
}
