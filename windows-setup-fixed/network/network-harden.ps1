[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft network-harden.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $LogRoot ("network-harden-" + $Timestamp + ".log")
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

function Enable-FirewallProfiles {
    Write-Log "Enabling Windows Firewall for all profiles." "INFO" ([ConsoleColor]::Cyan)
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Failed to enable firewall profiles: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Add-HardeningFirewallRules {
    Write-Log "Adding hardened firewall rules." "INFO" ([ConsoleColor]::Cyan)
    try {
        New-NetFirewallRule -DisplayName "Block SMB from Public" -Direction Inbound -Action Block -Protocol TCP -LocalPort 445 -Profile Public -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Block Inbound NetBIOS from Public" -Direction Inbound -Action Block -Protocol UDP -LocalPort 137,138 -Profile Public -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Block Inbound LLMNR" -Direction Inbound -Action Block -Protocol UDP -LocalPort 5355 -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-Log "Failed to add firewall rules: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Harden-LLMNR-Netbios {
    Write-Log "Disabling LLMNR and NetBIOS where safe." "INFO" ([ConsoleColor]::Cyan)
    try {
        $polKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $polKey)) { New-Item -Path $polKey -Force | Out-Null }
        New-ItemProperty -Path $polKey -Name "EnableMulticast" -PropertyType DWord -Value 0 -Force | Out-Null

        $nics = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled = TRUE" -ErrorAction SilentlyContinue
        foreach ($nic in $nics) {
            try {
                $nic.SetTcpipNetbios(2) | Out-Null
            } catch {}
        }
    } catch {
        Write-Log "Error hardening LLMNR/NetBIOS: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Harden-TcpParameters {
    Write-Log "Applying conservative TCP/IP hardening." "INFO" ([ConsoleColor]::Cyan)
    try {
        $tcpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        if (-not (Test-Path $tcpKey)) { New-Item -Path $tcpKey -Force | Out-Null }

        New-ItemProperty -Path $tcpKey -Name "EnableICMPRedirect" -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $tcpKey -Name "DisableIPSourceRouting" -PropertyType DWord -Value 2 -Force | Out-Null
        New-ItemProperty -Path $tcpKey -Name "SynAttackProtect" -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $tcpKey -Name "EnableDeadGWDetect" -PropertyType DWord -Value 0 -Force | Out-Null
    } catch {
        Write-Log "Error configuring TCP parameters: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Harden-WindowsFirewallSettings {
    Write-Log "Applying additional firewall settings." "INFO" ([ConsoleColor]::Cyan)
    try {
        netsh advfirewall set allprofiles state on | Out-Null
        netsh advfirewall set currentprofile settings inboundblockenabled yes | Out-Null
        netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
    } catch {
        Write-Log "Error applying firewall advanced settings: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

function Harden-DNSPrivacy {
    Write-Log "Hardening DNS privacy (no search list injection)." "INFO" ([ConsoleColor]::Cyan)
    try {
        $dnsKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        if (-not (Test-Path $dnsKey)) { New-Item -Path $dnsKey -Force | Out-Null }
        New-ItemProperty -Path $dnsKey -Name "DisableParallelAandAAAA" -PropertyType DWord -Value 1 -Force | Out-Null
    } catch {
        Write-Log "Error hardening DNS settings: $_" "WARN" ([ConsoleColor]::Yellow)
    }
}

Enable-FirewallProfiles
Add-HardeningFirewallRules
Harden-LLMNR-Netbios
Harden-TcpParameters
Harden-WindowsFirewallSettings
Harden-DNSPrivacy

Write-Log "network-harden.ps1 completed." "INFO" ([ConsoleColor]::Cyan)
if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" ([ConsoleColor]::Gray)
}
