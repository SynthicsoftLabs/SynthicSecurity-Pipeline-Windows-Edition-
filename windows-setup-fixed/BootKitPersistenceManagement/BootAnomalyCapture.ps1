<#
.SYNOPSIS
    Boot Anomaly Capture System v1.0
    Captures flashing CMD windows and boot-time executable launches.
    
.DESCRIPTION
    Sets up persistent monitoring to catch the 1-second CMD flash before WinRE:
    - Process creation auditing
    - Command-line argument logging
    - Screen capture on boot
    - File execution logging
    - Parent process tracking
    
    Designed to capture ephemeral boot-time execution that's too fast for manual observation.
    
.NOTES
    Author: SynthicSoft Labs - Adam R
    Date: 2025-01-14
    Purpose: Capture the flashing CMD window observed before WinRE entry
    
.EXAMPLE
    .\BootAnomalyCapture.ps1 -Install
    Installs boot-time monitoring (survives reboots)
    
.EXAMPLE
    .\BootAnomalyCapture.ps1 -Uninstall
    Removes monitoring
    
.EXAMPLE
    .\BootAnomalyCapture.ps1 -ViewLogs
    Display captured boot anomalies
#>

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$ViewLogs,
    [string]$LogPath = "C:\SynthicForensics\BootCapture"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$MonitorScript = @'
# Boot Anomaly Monitor - Runs on every boot
$LogPath = "C:\SynthicForensics\BootCapture"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = "$LogPath\boot_capture_$Timestamp.log"

New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

function Log-Event {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - $Message"
    Add-Content -Path $LogFile -Value $Entry -ErrorAction SilentlyContinue
}

Log-Event "=== BOOT MONITORING STARTED ==="
Log-Event "Session: $Timestamp"

# Monitor process creation
$Query = "SELECT * FROM __InstanceCreationEvent WITHIN 0.1 WHERE TargetInstance ISA 'Win32_Process'"

Register-WmiEvent -Query $Query -SourceIdentifier "ProcessMonitor" -Action {
    $Process = $Event.SourceEventArgs.NewEvent.TargetInstance
    $ProcessInfo = @"
PROCESS CREATED:
  Name: $($Process.Name)
  PID: $($Process.ProcessId)
  CommandLine: $($Process.CommandLine)
  ParentPID: $($Process.ParentProcessId)
  Path: $($Process.ExecutablePath)
  User: $($Process.GetOwner().Domain)\$($Process.GetOwner().User)
"@
    
    Log-Event $ProcessInfo
    
    # Special attention to CMD.exe
    if ($Process.Name -match "cmd\.exe") {
        Log-Event "!!! CMD.EXE DETECTED !!!"
        
        # Try to capture window title
        $WindowTitle = (Get-Process -Id $Process.ProcessId -ErrorAction SilentlyContinue).MainWindowTitle
        if ($WindowTitle) {
            Log-Event "  Window Title: $WindowTitle"
        }
        
        # Screenshot attempt
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $Bitmap = New-Object System.Drawing.Bitmap($Screen.Width, $Screen.Height)
            $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
            $Graphics.CopyFromScreen($Screen.Location, [System.Drawing.Point]::Empty, $Screen.Size)
            $ScreenshotPath = "$LogPath\screenshot_cmd_$($Process.ProcessId)_$(Get-Date -Format 'HHmmss').png"
            $Bitmap.Save($ScreenshotPath)
            $Graphics.Dispose()
            $Bitmap.Dispose()
            Log-Event "  Screenshot saved: $ScreenshotPath"
        } catch {
            Log-Event "  Screenshot failed: $_"
        }
    }
}

# Keep monitoring for 5 minutes (covers boot sequence)
Start-Sleep -Seconds 300

Unregister-Event -SourceIdentifier "ProcessMonitor" -ErrorAction SilentlyContinue
Log-Event "=== BOOT MONITORING ENDED ==="
'@

# ============================================================================
# FUNCTIONS
# ============================================================================

function Install-BootMonitoring {
    Write-Host "`n[INSTALLING BOOT ANOMALY CAPTURE]" -ForegroundColor Cyan
    
    # Create log directory
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    Write-Host "[+] Log directory created: $LogPath" -ForegroundColor Green
    
    # Save monitoring script
    $ScriptPath = "$LogPath\BootMonitor.ps1"
    $MonitorScript | Out-File $ScriptPath -Force
    Write-Host "[+] Monitoring script saved: $ScriptPath" -ForegroundColor Green
    
    # Enable process creation auditing
    Write-Host "[*] Enabling process creation auditing..." -ForegroundColor Yellow
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable | Out-Null
    
    # Enable command-line process auditing
    $AuditKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (!(Test-Path $AuditKey)) {
        New-Item -Path $AuditKey -Force | Out-Null
    }
    Set-ItemProperty -Path $AuditKey -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    Write-Host "[+] Command-line auditing enabled" -ForegroundColor Green
    
    # Create scheduled task to run on boot
    $TaskName = "SynthicSoft Boot Anomaly Monitor"
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
    Write-Host "[+] Scheduled task registered: $TaskName" -ForegroundColor Green
    
    # Create startup script (additional layer)
    $StartupPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\BootMonitor.bat"
    $StartupScript = @"
@echo off
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$ScriptPath"
"@
    $StartupScript | Out-File $StartupPath -Force
    Write-Host "[+] Startup script created: $StartupPath" -ForegroundColor Green
    
    # Setup event log monitoring for Security log (process creation events)
    $EventQuery = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[(EventID=4688)]]</Select>
  </Query>
</QueryList>
"@
    $EventQuery | Out-File "$LogPath\event_query.xml"
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║        BOOT ANOMALY CAPTURE INSTALLED SUCCESSFULLY          ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n[NEXT STEPS]" -ForegroundColor Yellow
    Write-Host "1. Reboot the system" -ForegroundColor Cyan
    Write-Host "2. Immediately after boot, check: $LogPath" -ForegroundColor Cyan
    Write-Host "3. Try to trigger WinRE (Shift+Restart)" -ForegroundColor Cyan
    Write-Host "4. Review logs with: .\BootAnomalyCapture.ps1 -ViewLogs" -ForegroundColor Cyan
    Write-Host "`nMonitoring will capture:" -ForegroundColor Yellow
    Write-Host "  • All process creation (especially CMD.exe)" -ForegroundColor White
    Write-Host "  • Command-line arguments" -ForegroundColor White
    Write-Host "  • Parent process tracking" -ForegroundColor White
    Write-Host "  • Screenshot attempts when CMD detected" -ForegroundColor White
    Write-Host "  • First 5 minutes of boot sequence" -ForegroundColor White
}

function Uninstall-BootMonitoring {
    Write-Host "`n[UNINSTALLING BOOT ANOMALY CAPTURE]" -ForegroundColor Cyan
    
    # Remove scheduled task
    $TaskName = "SynthicSoft Boot Anomaly Monitor"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[+] Scheduled task removed" -ForegroundColor Green
    
    # Remove startup script
    $StartupPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\BootMonitor.bat"
    Remove-Item $StartupPath -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Startup script removed" -ForegroundColor Green
    
    # Note: Keeping audit settings and logs for investigation
    Write-Host "[*] Audit settings preserved for investigation" -ForegroundColor Yellow
    Write-Host "[*] Logs preserved in: $LogPath" -ForegroundColor Yellow
    
    Write-Host "`n[UNINSTALL COMPLETE]" -ForegroundColor Green
}

function View-CapturedLogs {
    Write-Host "`n[CAPTURED BOOT ANOMALIES]" -ForegroundColor Cyan
    
    if (!(Test-Path $LogPath)) {
        Write-Host "[!] No logs found. Monitor may not have run yet." -ForegroundColor Yellow
        return
    }
    
    $Logs = Get-ChildItem "$LogPath\boot_capture_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($Logs.Count -eq 0) {
        Write-Host "[!] No boot capture logs found." -ForegroundColor Yellow
        Write-Host "[*] Either monitoring hasn't run, or no processes were captured." -ForegroundColor Cyan
        return
    }
    
    Write-Host "`nFound $($Logs.Count) capture session(s):`n" -ForegroundColor Green
    
    foreach ($Log in $Logs) {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "LOG: $($Log.Name)" -ForegroundColor Yellow
        Write-Host "DATE: $($Log.LastWriteTime)" -ForegroundColor Yellow
        Write-Host "SIZE: $($Log.Length) bytes" -ForegroundColor Yellow
        Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor Gray
        
        $Content = Get-Content $Log.FullName
        
        # Highlight CMD.exe entries
        foreach ($Line in $Content) {
            if ($Line -match "cmd\.exe" -or $Line -match "CMD.EXE DETECTED") {
                Write-Host $Line -ForegroundColor Red -BackgroundColor Yellow
            } elseif ($Line -match "PROCESS CREATED") {
                Write-Host $Line -ForegroundColor Cyan
            } elseif ($Line -match "CommandLine:") {
                Write-Host $Line -ForegroundColor Magenta
            } else {
                Write-Host $Line
            }
        }
        Write-Host ""
    }
    
    # Check for screenshots
    $Screenshots = Get-ChildItem "$LogPath\screenshot_*.png" -ErrorAction SilentlyContinue
    if ($Screenshots) {
        Write-Host "`n[SCREENSHOTS CAPTURED]" -ForegroundColor Green
        foreach ($Screenshot in $Screenshots) {
            Write-Host "  • $($Screenshot.Name) - $($Screenshot.LastWriteTime)" -ForegroundColor Cyan
        }
        Write-Host "`nScreenshots location: $LogPath" -ForegroundColor Yellow
    }
    
    # Parse Security Event Log for process creation
    Write-Host "`n[SECURITY EVENT LOG - PROCESS CREATION]" -ForegroundColor Cyan
    Write-Host "Querying last 50 process creation events..." -ForegroundColor Yellow
    
    $ProcessEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        ID = 4688  # Process Creation
    } -MaxEvents 50 -ErrorAction SilentlyContinue
    
    if ($ProcessEvents) {
        $CmdEvents = $ProcessEvents | Where-Object { $_.Message -match "cmd\.exe" }
        
        if ($CmdEvents) {
            Write-Host "`n[!] Found $($CmdEvents.Count) CMD.EXE process creation events:" -ForegroundColor Red
            
            foreach ($Event in $CmdEvents) {
                Write-Host "`n────────────────────────────────────────" -ForegroundColor Gray
                Write-Host "Time: $($Event.TimeCreated)" -ForegroundColor Yellow
                
                # Parse event XML for details
                $EventXml = [xml]$Event.ToXml()
                $EventData = $EventXml.Event.EventData.Data
                
                foreach ($Data in $EventData) {
                    if ($Data.Name -eq "NewProcessName" -or $Data.Name -eq "CommandLine" -or $Data.Name -eq "ParentProcessName") {
                        Write-Host "$($Data.Name): $($Data.'#text')" -ForegroundColor Cyan
                    }
                }
            }
        } else {
            Write-Host "[*] No CMD.exe events found in Security log" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║            BOOT ANOMALY CAPTURE SYSTEM v1.0                         ║
║          Captures Ephemeral Boot-Time Execution                      ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

if ($Install) {
    Install-BootMonitoring
} elseif ($Uninstall) {
    Uninstall-BootMonitoring
} elseif ($ViewLogs) {
    View-CapturedLogs
} else {
    Write-Host "`n[USAGE]" -ForegroundColor Yellow
    Write-Host "  Install monitoring:  .\BootAnomalyCapture.ps1 -Install" -ForegroundColor Cyan
    Write-Host "  View captured logs:  .\BootAnomalyCapture.ps1 -ViewLogs" -ForegroundColor Cyan
    Write-Host "  Uninstall:           .\BootAnomalyCapture.ps1 -Uninstall" -ForegroundColor Cyan
    Write-Host "`n[PURPOSE]" -ForegroundColor Yellow
    Write-Host "  Captures the flashing CMD window before WinRE" -ForegroundColor White
    Write-Host "  Logs all process creation during boot" -ForegroundColor White
    Write-Host "  Takes screenshots when CMD.exe detected" -ForegroundColor White
    Write-Host "  Survives reboots to capture boot sequence" -ForegroundColor White
}
"@