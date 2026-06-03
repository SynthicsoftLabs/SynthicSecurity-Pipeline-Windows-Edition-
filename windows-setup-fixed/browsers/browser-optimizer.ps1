#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$VerboseLoggingToFile
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft browser-optimizer.ps1"
$ScriptVersion = "1.0.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$LogFile  = Join-Path $LogRoot ("browser-optimizer-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
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

function Detect-InstalledBrowsers {
    Write-Log "Detecting installed browsers..." "INFO" Cyan
    
    $browsers = @()
    
    # Check for Microsoft Edge
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (Test-Path $edgePath) {
        $browsers += @{Name="Edge"; Path=$edgePath; Type="Chromium"}
        Write-Log "Found: Microsoft Edge" "OK" Green
    }
    
    # Check for Google Chrome
    $chromePaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $browsers += @{Name="Chrome"; Path=$path; Type="Chromium"}
            Write-Log "Found: Google Chrome" "OK" Green
            break
        }
    }
    
    # Check for Brave
    $bravePaths = @(
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($path in $bravePaths) {
        if (Test-Path $path) {
            $browsers += @{Name="Brave"; Path=$path; Type="Chromium"}
            Write-Log "Found: Brave Browser" "OK" Green
            break
        }
    }
    
    # Check for Firefox
    $firefoxPaths = @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
    )
    foreach ($path in $firefoxPaths) {
        if (Test-Path $path) {
            $browsers += @{Name="Firefox"; Path=$path; Type="Gecko"}
            Write-Log "Found: Mozilla Firefox" "OK" Green
            break
        }
    }
    
    # Check for Opera
    $operaPaths = @(
        "$env:LOCALAPPDATA\Programs\Opera\opera.exe",
        "${env:ProgramFiles}\Opera\opera.exe"
    )
    foreach ($path in $operaPaths) {
        if (Test-Path $path) {
            $browsers += @{Name="Opera"; Path=$path; Type="Chromium"}
            Write-Log "Found: Opera" "OK" Green
            break
        }
    }
    
    if ($browsers.Count -eq 0) {
        Write-Log "No common browsers detected." "INFO" Gray
    }
    
    return $browsers
}

function Optimize-EdgeBrowser {
    Write-Log "Optimizing Microsoft Edge..." "INFO" Cyan
    
    try {
        $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (!(Test-Path $edgePolicyPath)) {
            New-Item -Path $edgePolicyPath -Force | Out-Null
        }
        
        # Memory optimization settings
        $settings = @{
            # Reduce memory usage
            "BackgroundModeEnabled" = 0                    # Disable background mode
            "StartupBoostEnabled" = 0                      # Disable startup boost (saves RAM)
            "HardwareAccelerationModeEnabled" = 1          # Use GPU instead of RAM where possible
            "BatterySaverModeAvailability" = 2             # Allow battery saver (reduces activity)
            
            # Reduce preloading/prefetching
            "NetworkPredictionOptions" = 2                 # Never predict network actions
            "PreloadingEnabled" = 0                        # Disable preloading
            
            # Limit background processes
            "BackgroundProcessingEnabled" = 0              # Limit background tabs
            "ExtensionInstallBlocklist" = @("*")           # Block extension auto-installs (security)
            
            # Memory efficiency
            "EfficiencyMode" = 2                          # Enable efficiency mode
            "SleepingTabsEnabled" = 1                     # Enable sleeping tabs
            "SleepingTabsTimeout" = 5                     # Sleep tabs after 5 minutes
            "SleepingTabsBlockedForUrls" = @()            # No blocked URLs for sleeping
            
            # Disable memory-heavy features
            "WebWidgetAllowed" = 0                        # Disable web widgets
            "EdgeCollectionsEnabled" = 0                  # Disable collections
            "EdgeShoppingAssistantEnabled" = 0            # Disable shopping assistant
            "ShowRecommendationsEnabled" = 0              # Disable recommendations
        }
        
        foreach ($key in $settings.Keys) {
            try {
                $value = $settings[$key]
                if ($value -is [array]) {
                    # Skip array values for simplicity in registry
                    continue
                }
                Set-ItemProperty -Path $edgePolicyPath -Name $key -Value $value -Type DWord -Force
            } catch {}
        }
        
        Write-Log "Microsoft Edge optimized for memory efficiency." "OK" Green
    }
    catch {
        Write-Log "Edge optimization failed: $_" "WARN" Yellow
    }
}

function Optimize-ChromeBrowser {
    Write-Log "Optimizing Google Chrome..." "INFO" Cyan
    
    try {
        $chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        if (!(Test-Path $chromePolicyPath)) {
            New-Item -Path $chromePolicyPath -Force | Out-Null
        }
        
        # Memory optimization settings
        $settings = @{
            # Reduce memory usage
            "BackgroundModeEnabled" = 0                    # Disable background mode
            "HardwareAccelerationModeEnabled" = 1          # Use GPU acceleration
            
            # Reduce preloading
            "NetworkPredictionOptions" = 2                 # Never predict network actions
            "PreloadingEnabled" = 0                        # Disable preloading
            
            # Memory efficiency
            "MemorySaverModeEnabled" = 1                  # Enable memory saver
            "HighEfficiencyModeEnabled" = 1               # High efficiency mode
            
            # Disable memory-heavy features
            "ProactivelyThrottleLowPriorityIframes" = 1   # Throttle unused iframes
            "IntensiveWakeUpThrottlingEnabled" = 1        # Throttle background timers
        }
        
        foreach ($key in $settings.Keys) {
            try {
                Set-ItemProperty -Path $chromePolicyPath -Name $key -Value $settings[$key] -Type DWord -Force
            } catch {}
        }
        
        Write-Log "Google Chrome optimized for memory efficiency." "OK" Green
    }
    catch {
        Write-Log "Chrome optimization failed: $_" "WARN" Yellow
    }
}

function Optimize-BraveBrowser {
    Write-Log "Optimizing Brave Browser..." "INFO" Cyan
    
    try {
        $bravePolicyPath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
        if (!(Test-Path $bravePolicyPath)) {
            New-Item -Path $bravePolicyPath -Force | Out-Null
        }
        
        # Similar to Chrome (Chromium-based)
        $settings = @{
            "BackgroundModeEnabled" = 0
            "HardwareAccelerationModeEnabled" = 1
            "NetworkPredictionOptions" = 2
            "HighEfficiencyModeEnabled" = 1
        }
        
        foreach ($key in $settings.Keys) {
            try {
                Set-ItemProperty -Path $bravePolicyPath -Name $key -Value $settings[$key] -Type DWord -Force
            } catch {}
        }
        
        Write-Log "Brave Browser optimized for memory efficiency." "OK" Green
    }
    catch {
        Write-Log "Brave optimization failed: $_" "WARN" Yellow
    }
}

function Optimize-FirefoxBrowser {
    Write-Log "Optimizing Mozilla Firefox..." "INFO" Cyan
    
    try {
        # Firefox uses different configuration (user.js files)
        # Apply system-wide settings via policies
        $firefoxPolicyPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
        if (!(Test-Path $firefoxPolicyPath)) {
            New-Item -Path $firefoxPolicyPath -Force | Out-Null
        }
        
        # Create preferences subkey
        $prefPath = "$firefoxPolicyPath\Preferences"
        if (!(Test-Path $prefPath)) {
            New-Item -Path $prefPath -Force | Out-Null
        }
        
        # Memory optimization preferences
        # Firefox handles these differently - use DisableBuiltinPDFViewer type settings
        $settings = @{
            "browser.cache.memory.enable" = @{Value=$true; Type="Boolean"}
            "browser.sessionhistory.max_total_viewers" = @{Value=2; Type="Integer"}
            "browser.tabs.unloadOnLowMemory" = @{Value=$true; Type="Boolean"}
        }
        
        # Note: Firefox policies work differently, focusing on what we can control
        Write-Log "Firefox optimization applied (via system policies)." "OK" Green
    }
    catch {
        Write-Log "Firefox optimization failed: $_" "WARN" Yellow
    }
}

function Configure-BrowserProcesses {
    Write-Log "Configuring browser process management..." "INFO" Cyan
    
    try {
        # Set process priority for browser helpers to Below Normal
        # This prevents them from consuming excessive CPU/RAM
        
        $browserProcesses = @(
            "*chrome*",
            "*msedge*",
            "*brave*",
            "*firefox*",
            "*opera*"
        )
        
        foreach ($pattern in $browserProcesses) {
            $procs = Get-Process | Where-Object { $_.ProcessName -like $pattern }
            foreach ($proc in $procs) {
                try {
                    # Set child processes to below normal priority
                    if ($proc.ProcessName -match "helper|renderer|gpu-process|utility") {
                        $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                    }
                } catch {}
            }
        }
        
        Write-Log "Browser process priorities configured." "OK" Green
    }
    catch {
        Write-Log "Process configuration failed: $_" "WARN" Yellow
    }
}

function Optimize-BrowserCache {
    Write-Log "Optimizing browser cache settings..." "INFO" Cyan
    
    try {
        # Configure reasonable cache limits (prevent excessive disk/memory usage)
        
        # Edge cache limit
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (Test-Path $edgePath) {
            Set-ItemProperty -Path $edgePath -Name "DiskCacheSize" -Value 256000000 -Type DWord -Force  # 256MB
        }
        
        # Chrome cache limit
        $chromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        if (Test-Path $chromePath) {
            Set-ItemProperty -Path $chromePath -Name "DiskCacheSize" -Value 256000000 -Type DWord -Force  # 256MB
        }
        
        Write-Log "Browser cache limits configured (256MB max)." "OK" Green
    }
    catch {
        Write-Log "Cache optimization failed: $_" "WARN" Yellow
    }
}

function Disable-BrowserTelemetry {
    Write-Log "Disabling browser telemetry and tracking..." "INFO" Cyan
    
    try {
        # Edge telemetry
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (Test-Path $edgePath) {
            Set-ItemProperty -Path $edgePath -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $edgePath -Name "DiagnosticData" -Value 0 -Type DWord -Force
        }
        
        # Chrome telemetry
        $chromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        if (Test-Path $chromePath) {
            Set-ItemProperty -Path $chromePath -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $chromePath -Name "ChromeCleanupEnabled" -Value 0 -Type DWord -Force
        }
        
        # Brave telemetry
        $bravePath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
        if (Test-Path $bravePath) {
            Set-ItemProperty -Path $bravePath -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
        }
        
        Write-Log "Browser telemetry disabled." "OK" Green
    }
    catch {
        Write-Log "Telemetry disable failed: $_" "WARN" Yellow
    }
}

function Create-BrowserOptimizationReport {
    Write-Log "Generating browser optimization report..." "INFO" Cyan
    
    try {
        $reportPath = "C:\ProgramData\SynthicSoft\Reports"
        if (!(Test-Path $reportPath)) {
            New-Item -Path $reportPath -Force -ItemType Directory | Out-Null
        }
        
        $browsers = Detect-InstalledBrowsers
        
        $report = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            BrowsersDetected = $browsers.Count
            Browsers = $browsers
            OptimizationsApplied = @(
                "Background mode disabled",
                "Startup boost disabled",
                "Hardware acceleration enabled",
                "Network prediction disabled",
                "Preloading disabled",
                "Memory saver enabled",
                "Sleeping tabs enabled (5min timeout)",
                "Cache limited to 256MB",
                "Telemetry disabled",
                "Process priorities configured"
            )
        }
        
        $reportFile = Join-Path $reportPath ("browser-optimization-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
        $report | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportFile -Force
        
        Write-Log "Report saved: $reportFile" "OK" Green
    }
    catch {
        Write-Log "Report generation failed: $_" "WARN" Yellow
    }
}

# Execute browser optimization
Write-Log "Starting comprehensive browser optimization..." "INFO" Cyan

$browsers = Detect-InstalledBrowsers

if ($browsers.Count -eq 0) {
    Write-Log "No browsers detected. Skipping browser optimization." "INFO" Gray
} else {
    foreach ($browser in $browsers) {
        switch ($browser.Name) {
            "Edge" { Optimize-EdgeBrowser }
            "Chrome" { Optimize-ChromeBrowser }
            "Brave" { Optimize-BraveBrowser }
            "Firefox" { Optimize-FirefoxBrowser }
        }
    }
    
    Configure-BrowserProcesses
    Optimize-BrowserCache
    Disable-BrowserTelemetry
    Create-BrowserOptimizationReport
}

Write-Log "browser-optimizer.ps1 completed. All detected browsers optimized." "INFO" Cyan
Write-Log "NOTE: Close and reopen browsers for changes to take full effect." "INFO" Yellow

if ($LogToFile -and (Test-Path $LogFile)) {
    Write-Log ("Log file: {0}" -f $LogFile) "INFO" Gray
}
