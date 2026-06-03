<#
.SYNOPSIS
    OEM Decoupler & Sentinel: Restores user ownership and purges OEM persistence.
    Target: Lenovo UDC, McAfee Stubs, and Windows Provisioning Bloatware.
#>

$ErrorActionPreference = "SilentlyContinue"
Write-Host "`n[!] STARTING SYSTEM RECLAMATION..." -ForegroundColor Cyan -BackgroundColor Black

# --- 1. SEVER THE RECOVERY DROPPER ---
$RecoveryDir = "C:\Recovery\Customizations"
if (Test-Path "$RecoveryDir\USMT.PPKG") {
    Write-Host "[*] Neutralizing Factory Dropper (.ppkg)..." -ForegroundColor Yellow
    takeown /f $RecoveryDir /r /a /d y
    icacls $RecoveryDir /grant administrators:F /t
    Move-Item "$RecoveryDir\USMT.PPKG" "$RecoveryDir\USMT.PPKG.infosec_quarantine" -Force
}

# --- 2. RECLAIM REGISTRY OWNERSHIP & PURGE POLICIES ---
$PolicyKeys = @(
    "SOFTWARE\Policies\Microsoft",
    "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"
)

foreach ($SubKey in $PolicyKeys) {
    Write-Host "[*] Purging Managed Policy Locks: $SubKey" -ForegroundColor Yellow
    $ACL = Get-Acl "HKLM:\$SubKey"
    $User = New-Object System.Security.AccessControl.RegistryAccessRule ("Administrators", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $ACL.SetAccessRule($User)
    Set-Acl "HKLM:\$SubKey" $ACL
    Remove-Item -Path "HKLM:\$SubKey" -Recurse -Force
}

# --- 3. KILL DRIVER STUBS & ACTIVE BINARIES ---
$OrphanPaths = @(
    "C:\Windows\System32\drivers\Lenovo\udc",
    "C:\Windows\System32\drivers\UMDF\UdcDriver.Dll",
    "C:\Windows\System32\UDCInfInstaller.exe",
    "C:\Program Files\Lenovo\UniversalDeviceClient",
    "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy"
)

foreach ($Path in $OrphanPaths) {
    if (Test-Path $Path) {
        Write-Host "[-] Nuking Orphan: $Path" -ForegroundColor Red
        takeown /f $Path /r /a /d y
        icacls $Path /grant administrators:F /t
        Remove-Item $Path -Recurse -Force
    }
}

# --- 4. DISABLE MAINTENANCE TRIGGER SERVICES ---
$Services = @("mfevtp", "mfevtps", "UDClientService", "UsageAndQualityInsights-MaintenanceTask")
foreach ($Svc in $Services) {
    Stop-Service $Svc -Force
    Set-Service $Svc -StartupType Disabled
    Write-Host "[-] Service/Task $Svc set to Disabled." -ForegroundColor Gray
}

# --- 5. REPAIR WINLOGON HIJACKS ---
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "Userinit" -Value "C:\Windows\system32\userinit.exe"

# --- 6. FORCE REFRESH ---
gpupdate /force
Write-Host "`n[+] RECLAMATION COMPLETE. SYSTEM IS NOW IN CLEAN STATE." -ForegroundColor Green
Write-Host "[!] Restart recommended to clear UMDF driver hooks from memory." -ForegroundColor White
