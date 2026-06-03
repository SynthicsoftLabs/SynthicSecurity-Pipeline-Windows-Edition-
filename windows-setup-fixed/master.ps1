[CmdletBinding()]
param(
    [switch]$SkipDev,
    [switch]$SkipDevEnv,
    [switch]$SkipNetwork,
    [switch]$SkipPrivacy,
    [switch]$SkipDebloat,
    [switch]$SkipOptimize,
    [switch]$SkipRAMOptimizer,
    [switch]$SkipPatchIntel,
    [switch]$SkipBrowserOptimizer,
    [switch]$SkipSystemPrep,
    [switch]$VerboseLoggingToFile,
    [switch]$OptimizeAggressiveProfile,
    [switch]$SkipIDrive,
    [switch]$SkipWSL,
    [switch]$SkipVSCode
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptName    = "SynthicSoft master.ps1"
$ScriptVersion = "2.3.0"
$LogRoot       = "C:\ProgramData\SynthicSoft\Logs"

# Initialize phase tracking
$global:PhaseResults = @()
$global:TotalPhases = 0
$global:SuccessfulPhases = 0
$global:FailedPhases = 0
$global:SkippedPhases = 0

if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MasterLog = Join-Path $LogRoot ("master-" + $Timestamp + ".log")
$LogToFile = $VerboseLoggingToFile.IsPresent

if ($LogToFile) {
    New-Item -ItemType File -Path $MasterLog -Force | Out-Null
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
    if ($LogToFile -and (Test-Path $MasterLog)) {
        Add-Content -Path $MasterLog -Value $line
    }
}

Write-Log "=== $ScriptName v$ScriptVersion starting ===" "INFO" ([ConsoleColor]::Cyan)

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script must be run as Administrator. Exiting." "FATAL" ([ConsoleColor]::Red)
    exit 1
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$DevScriptDefault        = Join-Path $ScriptRoot "devsetup.ps1"
$DevEnvScriptDefault     = Join-Path $ScriptRoot "devenv\devenv-setup.ps1"
$NetworkScriptDefault    = Join-Path $ScriptRoot "network\network-harden.ps1"
$PrivacyScriptDefault    = Join-Path $ScriptRoot "privacy\privacy-harden.ps1"
$DebloatScriptDefault    = Join-Path $ScriptRoot "debloat\debloat.ps1"
$OptimizeScriptDefault   = Join-Path $ScriptRoot "optimize\optimize.ps1"
$RAMOptimizerDefault     = Join-Path $ScriptRoot "memory\ram-optimizer.ps1"
$PatchIntelScriptDefault = Join-Path $ScriptRoot "patching\patch-intel.ps1"
$BrowserOptimizerDefault = Join-Path $ScriptRoot "browsers\browser-optimizer.ps1"
$SystemPrepScriptDefault = Join-Path $ScriptRoot "system\system-prep.ps1"

function Resolve-ScriptPath {
    param(
        [string]$DefaultPath,
        [string]$FallbackName
    )

    if (Test-Path $DefaultPath) {
        return $DefaultPath
    }

    try {
        $found = Get-ChildItem -Path $ScriptRoot -Filter $FallbackName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Log ("Resolved {0} via search: {1}" -f $FallbackName, $found.FullName) "INFO" ([ConsoleColor]::Gray)
            return $found.FullName
        }
    } catch {}

    Write-Log ("Unable to resolve script {0}. Expected: {1}" -f $FallbackName, $DefaultPath) "WARN" ([ConsoleColor]::Yellow)
    return $null
}

function Invoke-SubScript {
    param(
        [string]$StepName,
        [string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )
    
    $global:TotalPhases++

    if (-not $ScriptPath) {
        Write-Log ("[{0}] skipped; path unresolved." -f $StepName) "WARN" ([ConsoleColor]::Yellow)
        $global:SkippedPhases++
        $global:PhaseResults += [PSCustomObject]@{
            Phase = $StepName
            Status = "Skipped"
            Duration = "0s"
            Reason = "Path unresolved"
        }
        return $false
    }

    if (-not (Test-Path $ScriptPath)) {
        Write-Log ("[{0}] CRITICAL: script missing: {1}" -f $StepName, $ScriptPath) "WARN" ([ConsoleColor]::Yellow)
        Write-Log ("[{0}] Self-healing: Continuing with remaining phases..." -f $StepName) "INFO" ([ConsoleColor]::Gray)
        $global:SkippedPhases++
        $global:PhaseResults += [PSCustomObject]@{
            Phase = $StepName
            Status = "Skipped"
            Duration = "0s"
            Reason = "Script not found"
        }
        return $false
    }

    Write-Log ("[{0}] running: {1}" -f $StepName, $ScriptPath) "TASK" ([ConsoleColor]::Cyan)
    
    # Retry logic for transient failures
    $maxRetries = 2
    $retryCount = 0
    $success = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($retryCount -le $maxRetries -and -not $success) {
        try {
            if ($retryCount -gt 0) {
                Write-Log ("[{0}] Self-healing retry {1} of {2}..." -f $StepName, $retryCount, $maxRetries) "INFO" ([ConsoleColor]::Yellow)
                Start-Sleep -Seconds 3
            }

            # Execute the script
            & $ScriptPath @Arguments
            $exitCode = $LASTEXITCODE
            
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
            
            $sw.Stop()
            
            if ($exitCode -eq 0) {
                Write-Log ("[{0}] completed successfully ({1:N1}s)" -f $StepName, $sw.Elapsed.TotalSeconds) "OK" ([ConsoleColor]::Green)
                $success = $true
                $global:SuccessfulPhases++
                $global:PhaseResults += [PSCustomObject]@{
                    Phase = $StepName
                    Status = "Success"
                    Duration = ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
                    Reason = "Completed"
                }
                return $true
            }
            else {
                Write-Log ("[{0}] exited with code {1} ({2:N1}s)" -f $StepName, $exitCode, $sw.Elapsed.TotalSeconds) "WARN" ([ConsoleColor]::Yellow)
                
                # Some non-zero exit codes are acceptable (warnings, not errors)
                if ($exitCode -eq 1 -and $StepName -match "PATCH|OPTIMIZE") {
                    Write-Log ("[{0}] Non-critical warning code, treating as success" -f $StepName) "INFO" ([ConsoleColor]::Gray)
                    $success = $true
                    $global:SuccessfulPhases++
                    $global:PhaseResults += [PSCustomObject]@{
                        Phase = $StepName
                        Status = "Success (Warning)"
                        Duration = ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
                        Reason = "Exit code $exitCode"
                    }
                    return $true
                }
                
                $retryCount++
            }
        }
        catch {
            $sw.Stop()
            Write-Log ("[{0}] ERROR: {1} ({2:N1}s)" -f $StepName, $_.Exception.Message, $sw.Elapsed.TotalSeconds) "WARN" ([ConsoleColor]::Yellow)
            $retryCount++
        }
    }

    # If we exhausted retries, log and continue (don't fail entire suite)
    if (-not $success) {
        Write-Log ("[{0}] FAILED after {1} attempts" -f $StepName, ($maxRetries + 1)) "WARN" ([ConsoleColor]::Red)
        Write-Log ("[{0}] Self-healing: Continuing with remaining phases for maximum coverage..." -f $StepName) "INFO" ([ConsoleColor]::Yellow)
        $global:FailedPhases++
        $global:PhaseResults += [PSCustomObject]@{
            Phase = $StepName
            Status = "Failed"
            Duration = ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
            Reason = "Max retries exceeded"
        }
        return $false
    }

    return $true
}

if (-not $SkipSystemPrep) {
    $SystemPrepScript = Resolve-ScriptPath -DefaultPath $SystemPrepScriptDefault -FallbackName "system-prep.ps1"
    $sysPrepArgs = @{}
    if ($VerboseLoggingToFile) {
        $sysPrepArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "SYSTEM-PREP" -ScriptPath $SystemPrepScript -Arguments $sysPrepArgs
} else {
    Write-Log "[SYSTEM-PREP] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipDev) {
    $DevScript = Resolve-ScriptPath -DefaultPath $DevScriptDefault -FallbackName "devsetup.ps1"
    $devArgs = @{}
    if ($VerboseLoggingToFile) {
        $devArgs['VerboseLoggingToFile'] = $true
    }
    if ($SkipIDrive) {
        $devArgs['SkipIDrive'] = $true
    }
    Invoke-SubScript -StepName "DEVSETUP" -ScriptPath $DevScript -Arguments $devArgs
} else {
    Write-Log "[DEVSETUP] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipDevEnv) {
    $DevEnvScript = Resolve-ScriptPath -DefaultPath $DevEnvScriptDefault -FallbackName "devenv-setup.ps1"
    $devEnvArgs = @{}
    if ($VerboseLoggingToFile) {
        $devEnvArgs['VerboseLoggingToFile'] = $true
    }
    if ($SkipWSL) {
        $devEnvArgs['SkipWSL'] = $true
    }
    if ($SkipVSCode) {
        $devEnvArgs['SkipVSCode'] = $true
    }
    Invoke-SubScript -StepName "DEVENV-SETUP" -ScriptPath $DevEnvScript -Arguments $devEnvArgs
} else {
    Write-Log "[DEVENV-SETUP] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipNetwork) {
    $NetworkScript = Resolve-ScriptPath -DefaultPath $NetworkScriptDefault -FallbackName "network-harden.ps1"
    $networkArgs = @{}
    if ($VerboseLoggingToFile) {
        $networkArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "NETWORK-HARDEN" -ScriptPath $NetworkScript -Arguments $networkArgs
} else {
    Write-Log "[NETWORK-HARDEN] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipPrivacy) {
    $PrivacyScript = Resolve-ScriptPath -DefaultPath $PrivacyScriptDefault -FallbackName "privacy-harden.ps1"
    $privacyArgs = @{}
    if ($VerboseLoggingToFile) {
        $privacyArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "PRIVACY-HARDEN" -ScriptPath $PrivacyScript -Arguments $privacyArgs
} else {
    Write-Log "[PRIVACY-HARDEN] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipDebloat) {
    $DebloatScript = Resolve-ScriptPath -DefaultPath $DebloatScriptDefault -FallbackName "debloat.ps1"
    $debloatArgs = @{}
    if ($VerboseLoggingToFile) {
        $debloatArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "DEBLOAT" -ScriptPath $DebloatScript -Arguments $debloatArgs
} else {
    Write-Log "[DEBLOAT] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipOptimize) {
    $OptimizeScript = Resolve-ScriptPath -DefaultPath $OptimizeScriptDefault -FallbackName "optimize.ps1"

    $optArgs = @{}
    if ($VerboseLoggingToFile) {
        $optArgs['VerboseLoggingToFile'] = $true
    }

    if ($OptimizeAggressiveProfile) {
        $optArgs['AggressivePower'] = $true
        $optArgs['AggressiveVisualTweaks'] = $true
        $optArgs['DisableBackgroundApps'] = $true
        $optArgs['TuneServices'] = $true
        $optArgs['TuneScheduledTasks'] = $true
        $optArgs['EnableMemoryCompression'] = $true
        $optArgs['TrimStartupItems'] = $true
        $optArgs['DisableIndexing'] = $true
    } else {
        $optArgs['TuneServices'] = $true
        $optArgs['TuneScheduledTasks'] = $true
        $optArgs['EnableMemoryCompression'] = $true
        $optArgs['TrimStartupItems'] = $true
    }

    Invoke-SubScript -StepName "OPTIMIZE" -ScriptPath $OptimizeScript -Arguments $optArgs
} else {
    Write-Log "[OPTIMIZE] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipRAMOptimizer) {
    $RAMOptimizerScript = Resolve-ScriptPath -DefaultPath $RAMOptimizerDefault -FallbackName "ram-optimizer.ps1"
    $ramArgs = @{}
    if ($VerboseLoggingToFile) {
        $ramArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "RAM-OPTIMIZER" -ScriptPath $RAMOptimizerScript -Arguments $ramArgs
} else {
    Write-Log "[RAM-OPTIMIZER] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipPatchIntel) {
    $PatchIntelScript = Resolve-ScriptPath -DefaultPath $PatchIntelScriptDefault -FallbackName "patch-intel.ps1"
    $patchArgs = @{}
    if ($VerboseLoggingToFile) {
        $patchArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "PATCH-INTEL" -ScriptPath $PatchIntelScript -Arguments $patchArgs
} else {
    Write-Log "[PATCH-INTEL] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

if (-not $SkipBrowserOptimizer) {
    $BrowserOptimizerScript = Resolve-ScriptPath -DefaultPath $BrowserOptimizerDefault -FallbackName "browser-optimizer.ps1"
    $browserArgs = @{}
    if ($VerboseLoggingToFile) {
        $browserArgs['VerboseLoggingToFile'] = $true
    }
    Invoke-SubScript -StepName "BROWSER-OPTIMIZER" -ScriptPath $BrowserOptimizerScript -Arguments $browserArgs
} else {
    Write-Log "[BROWSER-OPTIMIZER] skipped by flag." "INFO" ([ConsoleColor]::Gray)
}

Write-Log "=== Autonomous deployment completed ===" "INFO" ([ConsoleColor]::Cyan)
Write-Log "" "INFO" ([ConsoleColor]::White)

# Display comprehensive summary
Write-Log "=== EXECUTION SUMMARY ===" "INFO" ([ConsoleColor]::Cyan)
Write-Log ("Total Phases: {0}" -f $global:TotalPhases) "INFO" ([ConsoleColor]::White)
Write-Log ("Successful: {0}" -f $global:SuccessfulPhases) "OK" ([ConsoleColor]::Green)
if ($global:FailedPhases -gt 0) {
    Write-Log ("Failed: {0}" -f $global:FailedPhases) "WARN" ([ConsoleColor]::Red)
}
if ($global:SkippedPhases -gt 0) {
    Write-Log ("Skipped: {0}" -f $global:SkippedPhases) "INFO" ([ConsoleColor]::Yellow)
}
Write-Log "" "INFO" ([ConsoleColor]::White)

# Display detailed phase results
Write-Log "=== PHASE DETAILS ===" "INFO" ([ConsoleColor]::Cyan)
foreach ($result in $global:PhaseResults) {
    $color = switch ($result.Status) {
        "Success" { [ConsoleColor]::Green }
        "Success (Warning)" { [ConsoleColor]::Yellow }
        "Failed" { [ConsoleColor]::Red }
        "Skipped" { [ConsoleColor]::Gray }
        default { [ConsoleColor]::White }
    }
    Write-Log ("{0,-20} {1,-20} {2,8} - {3}" -f $result.Phase, $result.Status, $result.Duration, $result.Reason) "INFO" $color
}
Write-Log "" "INFO" ([ConsoleColor]::White)

# Calculate success rate
if ($global:TotalPhases -gt 0) {
    $successRate = [math]::Round((($global:SuccessfulPhases / $global:TotalPhases) * 100), 1)
    if ($successRate -eq 100) {
        Write-Log ("Success Rate: {0}% (PERFECT)" -f $successRate) "OK" ([ConsoleColor]::Green)
    }
    elseif ($successRate -ge 80) {
        Write-Log ("Success Rate: {0}% (GOOD)" -f $successRate) "OK" ([ConsoleColor]::Green)
    }
    elseif ($successRate -ge 60) {
        Write-Log ("Success Rate: {0}% (ACCEPTABLE)" -f $successRate) "WARN" ([ConsoleColor]::Yellow)
    }
    else {
        Write-Log ("Success Rate: {0}% (REVIEW NEEDED)" -f $successRate) "WARN" ([ConsoleColor]::Red)
    }
}
Write-Log "" "INFO" ([ConsoleColor]::White)

# Self-healing summary
if ($global:FailedPhases -gt 0) {
    Write-Log "=== SELF-HEALING REPORT ===" "INFO" ([ConsoleColor]::Yellow)
    Write-Log "Some phases encountered issues but suite continued execution." "INFO" ([ConsoleColor]::Yellow)
    Write-Log "Review failed phases above and re-run specific scripts if needed." "INFO" ([ConsoleColor]::Yellow)
    Write-Log "System is still usable with completed phases." "INFO" ([ConsoleColor]::Yellow)
    Write-Log "" "INFO" ([ConsoleColor]::White)
}

Write-Log "All automated steps have been executed." "INFO" ([ConsoleColor]::Cyan)
Write-Log "Logs available at: C:\ProgramData\SynthicSoft\Logs" "INFO" ([ConsoleColor]::Gray)
if ($LogToFile -and (Test-Path $MasterLog)) {
    Write-Log ("Master log: {0}" -f $MasterLog) "INFO" ([ConsoleColor]::Gray)
}
Write-Log "System is ready for use. Reboot if recommended by patch-intel." "INFO" ([ConsoleColor]::Yellow)
Write-Log "=== Post-deployment: Configure IDrive backup account and initial backup ===" "INFO" ([ConsoleColor]::Gray)
Write-Log "=== master.ps1 finished ===" "INFO" ([ConsoleColor]::Cyan)
