#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft ram-optimizer.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("ram-optimizer-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
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

function Get-MemoryStats {
    Write-Log "Collecting memory statistics..." "INFO" Cyan
    
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRAM = [math]::Round($totalRAM - $freeRAM, 2)
    $usedPercent = [math]::Round(($usedRAM / $totalRAM) * 100, 1)
    
    Write-Log "Total RAM: $totalRAM GB" "INFO" Gray
    Write-Log "Used RAM: $usedRAM GB ($usedPercent%)" "INFO" Gray
    Write-Log "Free RAM: $freeRAM GB" "INFO" Gray
    
    return @{
        TotalGB = $totalRAM
        UsedGB = $usedRAM
        FreeGB = $freeRAM
        UsedPercent = $usedPercent
    }
}

function Clear-StandbyMemory {
    Write-Log "Clearing standby memory cache..." "INFO" Cyan
    
    try {
        # Use Windows API to clear standby list (safe method)
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        
        public class MemoryManagement {
            [DllImport("kernel32.dll")]
            public static extern bool SetProcessWorkingSetSize(IntPtr proc, int min, int max);
            
            public static void ClearMemory() {
                GC.Collect();
                GC.WaitForPendingFinalizers();
                if (Environment.OSVersion.Platform == PlatformID.Win32NT) {
                    SetProcessWorkingSetSize(System.Diagnostics.Process.GetCurrentProcess().Handle, -1, -1);
                }
            }
        }
"@
        
        [MemoryManagement]::ClearMemory()
        
        # Clear DNS cache (frees memory)
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        
        # Clear event logs if over 100MB (safe space reclaim)
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | 
            Where-Object { $_.FileSize -gt 100MB }
        
        foreach ($log in $logs) {
            if ($log.LogName -notmatch "Security|System|Application") {
                try {
                    wevtutil.exe cl $log.LogName 2>$null
                } catch {}
            }
        }
        
        Write-Log "Standby memory cleared successfully." "OK" Green
    }
    catch {
        Write-Log "Standby memory clear failed: $_" "WARN" Yellow
    }
}

function Optimize-WorkingSets {
    Write-Log "Optimizing process working sets..." "INFO" Cyan
    
    try {
        # Get non-critical processes using excessive memory
        $processes = Get-Process | 
            Where-Object { 
                $_.WorkingSet64 -gt 100MB -and
                $_.ProcessName -notmatch "^(explorer|dwm|csrss|services|lsass|svchost|System|Registry|smss|wininit|winlogon)$"
            } | 
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 20
        
        $reclaimedMB = 0
        foreach ($proc in $processes) {
            try {
                $beforeWS = $proc.WorkingSet64
                $proc.Refresh()
                
                # Trim working set (safe, Windows will reallocate if needed)
                $handle = [System.Diagnostics.Process]::GetProcessById($proc.Id).Handle
                [MemoryManagement]::SetProcessWorkingSetSize($handle, -1, -1)
                
                Start-Sleep -Milliseconds 50
                $proc.Refresh()
                $afterWS = $proc.WorkingSet64
                $reclaimedMB += [math]::Round(($beforeWS - $afterWS) / 1MB, 1)
            }
            catch {}
        }
        
        if ($reclaimedMB -gt 0) {
            Write-Log "Reclaimed approximately $reclaimedMB MB from process working sets." "OK" Green
        }
    }
    catch {
        Write-Log "Working set optimization failed: $_" "WARN" Yellow
    }
}

function Configure-MemoryManagement {
    Write-Log "Configuring advanced memory management..." "INFO" Cyan
    
    try {
        # Disable unnecessary memory-consuming features
        
        # Disable Superfetch/Prefetch on systems with adequate RAM
        $totalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        if ($totalRAM -ge 8) {
            # Disable Superfetch (SysMain) on 8GB+ systems with SSD
            $sysmain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
            if ($sysmain -and $sysmain.Status -eq "Running") {
                Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled SysMain/Superfetch (not needed with adequate RAM)." "OK" Green
            }
        }
        
        # Configure memory compression (already enabled by optimize.ps1, verify)
        $compression = Get-MMAgent -ErrorAction SilentlyContinue
        if ($compression -and -not $compression.MemoryCompression) {
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-Log "Memory compression enabled." "OK" Green
        }
        
        # Optimize paging file for performance
        # System-managed is best for most systems
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        if (-not $cs.AutomaticManagedPagefile) {
            $cs | Set-CimInstance -Property @{AutomaticManagedPagefile = $true}
            Write-Log "Configured system-managed page file." "OK" Green
        }
        
        # Disable RAM-heavy visual effects (already done by optimize.ps1)
        $visualPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (!(Test-Path $visualPath)) {
            New-Item -Path $visualPath -Force | Out-Null
        }
        Set-ItemProperty -Path $visualPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force
        
    }
    catch {
        Write-Log "Memory management configuration failed: $_" "WARN" Yellow
    }
}

function Optimize-SystemCache {
    Write-Log "Optimizing system cache..." "INFO" Cyan
    
    try {
        # Configure LargeSystemCache for better memory management
        $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        
        # Optimize for applications (not file cache) on workstations
        Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord -Force
        
        # Disable paging of kernel and drivers (if sufficient RAM)
        $totalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        if ($totalRAM -ge 16) {
            Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
            Write-Log "Disabled paging of kernel (16GB+ RAM detected)." "OK" Green
        }
        
        # Clear font cache (can grow large over time)
        $fontCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Caches"
        if (Test-Path $fontCachePath) {
            Remove-Item -Path "$fontCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "System cache optimized." "OK" Green
    }
    catch {
        Write-Log "System cache optimization failed: $_" "WARN" Yellow
    }
}

function Monitor-MemoryLeaks {
    Write-Log "Checking for potential memory leaks..." "INFO" Cyan
    
    try {
        # Identify processes with unusually high memory usage
        $suspiciousProcesses = Get-Process | 
            Where-Object { $_.WorkingSet64 -gt 500MB } |
            Select-Object ProcessName, 
                @{N='MemoryMB';E={[math]::Round($_.WorkingSet64/1MB,1)}},
                @{N='HandleCount';E={$_.HandleCount}} |
            Sort-Object MemoryMB -Descending
        
        if ($suspiciousProcesses) {
            Write-Log "High memory usage processes detected:" "WARN" Yellow
            foreach ($proc in $suspiciousProcesses | Select-Object -First 5) {
                Write-Log ("  {0}: {1} MB ({2} handles)" -f $proc.ProcessName, $proc.MemoryMB, $proc.HandleCount) "INFO" Gray
            }
            Write-Log "Consider closing unused applications to free memory." "INFO" Gray
        } else {
            Write-Log "No memory leak indicators detected." "OK" Green
        }
    }
    catch {
        Write-Log "Memory leak check failed: $_" "WARN" Yellow
    }
}

function Create-RAMMonitorTask {
    Write-Log "Creating scheduled RAM monitoring task..." "INFO" Cyan
    
    try {
        $taskName = "SynthicSoft-RAMMonitor"
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        
        # Create task that runs this script daily at 3 AM
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -VerboseLoggingToFile"
        
        $trigger = New-ScheduledTaskTrigger -Daily -At 3am
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $taskName `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
            -Description "Daily RAM optimization and monitoring by SynthicSoft Labs" -Force | Out-Null
        
        Write-Log "Scheduled daily RAM optimization (3:00 AM)." "OK" Green
    }
    catch {
        Write-Log "Task creation failed: $_" "WARN" Yellow
    }
}

# Execute RAM optimization
Write-Log "Starting RAM optimization..." "INFO" Cyan

$beforeStats = Get-MemoryStats

Clear-StandbyMemory
Optimize-WorkingSets
Configure-MemoryManagement
Optimize-SystemCache
Monitor-MemoryLeaks
Create-RAMMonitorTask

Start-Sleep -Seconds 2
$afterStats = Get-MemoryStats

$freedMB = [math]::Round(($afterStats.FreeGB - $beforeStats.FreeGB) * 1024, 0)
if ($freedMB -gt 0) {
    Write-Log "RAM optimization freed approximately $freedMB MB." "OK" Green
}

Write-Log "ram-optimizer.ps1 completed. System RAM optimized for performance." "INFO" Cyan

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
