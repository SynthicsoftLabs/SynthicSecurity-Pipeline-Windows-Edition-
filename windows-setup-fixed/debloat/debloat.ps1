[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft debloat.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $LogRoot ("debloat-" + $Timestamp + ".log")
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

$BloatAppPatterns = @(
    "Microsoft.3DBuilder",
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MSPaint",
    "Microsoft.MixedReality.Portal",
    "Microsoft.OneConnect",
    "Microsoft.People",
    "Microsoft.SkypeApp",
    "Microsoft.XboxApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.549981C3F5F10", # Cortana
    "Microsoft.WindowsFeedbackHub",
    "BytedancePte.Ltd.TikTok"
)

$OfficePatterns = @(
    "Microsoft.Office.Desktop",
    "Microsoft.Office.Desktop.Access",
    "Microsoft.Office.Desktop.Excel",
    "Microsoft.Office.Desktop.Word",
    "Microsoft.Office.Desktop.Outlook",
    "Microsoft.Office.Desktop.PowerPoint",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.Office.OneNote"
)

$LinkedInPatterns = @(
    "LinkedIn.LinkedIn"
)

function Remove-AppxByPattern {
    param(
        [string[]]$Patterns,
        [string]$Reason
    )
    foreach ($pattern in $Patterns) {
        try {
            $apps = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like "*$pattern*" }
            foreach ($app in $apps) {
                if ($app.Name -match "McAfee" -or $app.Name -match "Norton") {
                    Write-Log ("Skipping OEM AV appx: {0}" -f $app.Name) "INFO" ([ConsoleColor]::Gray)
                    continue
                }
                Write-Log ("Removing {0} ({1}) - {2}" -f $app.Name, $app.PackageFullName, $Reason) "INFO" ([ConsoleColor]::Cyan)
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log ("Failed removing appx pattern {0}: {1}" -f $pattern, $_) "WARN" ([ConsoleColor]::Yellow)
        }
    }
}

function Remove-StoreApps {
    Write-Log "Removing common bloatware Store apps." "INFO" ([ConsoleColor]::Cyan)
    Remove-AppxByPattern -Patterns $BloatAppPatterns -Reason "general bloat"
    Remove-AppxByPattern -Patterns $OfficePatterns -Reason "Office 365 suite"
    Remove-AppxByPattern -Patterns $LinkedInPatterns -Reason "LinkedIn app"
}

function Remove-Nahimic {
    Write-Log "Removing Nahimic components." "INFO" ([ConsoleColor]::Cyan)
    try {
        $nahApps = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*Nahimic*" -or $_.PackageFullName -like "*Nahimic*" }
        foreach ($app in $nahApps) {
            Write-Log ("Removing Nahimic appx: {0}" -f $app.PackageFullName) "INFO" ([ConsoleColor]::Cyan)
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Error removing Nahimic appx: $_" "WARN" ([ConsoleColor]::Yellow)
    }

    $svcNames = @(
        "NahimicService",
        "NahimicSvc32",
        "NahimicSvc64"
    )
    foreach ($svc in $svcNames) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                if ($s.Status -eq "Running") { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log ("Disabled Nahimic service: {0}" -f $svc) "INFO" ([ConsoleColor]::Gray)
            }
        } catch {}
    }

    try {
        $paths = @(
            "C:\Program Files\Nahimic",
            "C:\Program Files (x86)\Nahimic",
            "C:\ProgramData\A-Volute",
            "$env:ProgramFiles\A-Volute",
            "$env:ProgramFiles(x86)\A-Volute"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Write-Log ("Removing Nahimic folder: {0}" -f $p) "INFO" ([ConsoleColor]::Cyan)
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log "Error removing Nahimic folders: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Remove-ClickToRun {
    Write-Log "Attempting to remove Office Click-to-Run components." "INFO" ([ConsoleColor]::Cyan)
    try {
        $uninstKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        $subKeys = Get-ChildItem $uninstKey -ErrorAction SilentlyContinue
        foreach ($sub in $subKeys) {
            try {
                $dispName = (Get-ItemProperty -Path $sub.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                $uninstString = (Get-ItemProperty -Path $sub.PSPath -Name "UninstallString" -ErrorAction SilentlyContinue).UninstallString
                if ($dispName -and ($dispName -like "*Microsoft 365*" -or $dispName -like "*Office*Click-to-Run*")) {
                    Write-Log ("Found Office component: {0}" -f $dispName) "INFO" ([ConsoleColor]::Gray)
                    if ($uninstString) {
                        Write-Log ("Uninstalling via: {0}" -f $uninstString) "INFO" ([ConsoleColor]::Cyan)
                        Start-Process "cmd.exe" "/c `"$uninstString /quiet /norestart`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    }
                }
            } catch {}
        }
    } catch {
        Write-Log "Error during Office Click-to-Run removal: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

Remove-StoreApps
Remove-Nahimic
Remove-ClickToRun

Write-Log "debloat.ps1 completed." "INFO" ([ConsoleColor]::Cyan)
if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" ([ConsoleColor]::Gray)
}
