#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Unblock all SynthicSoft Windows Setup Suite scripts for autonomous execution.

.DESCRIPTION
    This script removes the "Downloaded from Internet" flag from all PowerShell scripts
    in the suite, eliminating security warnings that would require user interaction.
    
    Run this ONCE before running master.ps1 for fully autonomous execution.

.EXAMPLE
    .\unblock-scripts.ps1
    
.NOTES
    SynthicSoft Labs - Windows Setup Suite v2.2.1
    Must be run as Administrator
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " SynthicSoft Script Unblock Utility" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify running as admin
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Get script root directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "[INFO] Scanning for PowerShell scripts..." -ForegroundColor Cyan
Write-Host "Location: $scriptRoot" -ForegroundColor Gray
Write-Host ""

# Find all .ps1 files recursively
$scripts = Get-ChildItem -Path $scriptRoot -Filter "*.ps1" -Recurse -File -ErrorAction SilentlyContinue

if ($scripts.Count -eq 0) {
    Write-Host "[WARN] No PowerShell scripts found in $scriptRoot" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Host "[INFO] Found $($scripts.Count) PowerShell script(s)" -ForegroundColor Cyan
Write-Host ""

$unblockedCount = 0
$alreadyUnblockedCount = 0
$failedCount = 0

foreach ($script in $scripts) {
    $relativePath = $script.FullName.Replace($scriptRoot, ".")
    
    try {
        # Check if file is blocked
        $zone = Get-Item -Path $script.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
        
        if ($zone) {
            # File is blocked, unblock it
            Unblock-File -Path $script.FullName -ErrorAction Stop
            Write-Host "[OK] Unblocked: $relativePath" -ForegroundColor Green
            $unblockedCount++
        }
        else {
            # File is already unblocked
            Write-Host "[OK] Already unblocked: $relativePath" -ForegroundColor Gray
            $alreadyUnblockedCount++
        }
    }
    catch {
        Write-Host "[ERROR] Failed to unblock: $relativePath" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " UNBLOCK SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total scripts found: $($scripts.Count)" -ForegroundColor White
Write-Host "Unblocked now:       $unblockedCount" -ForegroundColor Green
Write-Host "Already unblocked:   $alreadyUnblockedCount" -ForegroundColor Gray

if ($failedCount -gt 0) {
    Write-Host "Failed:              $failedCount" -ForegroundColor Red
}

Write-Host ""

if ($failedCount -eq 0 -and ($unblockedCount + $alreadyUnblockedCount) -eq $scripts.Count) {
    Write-Host "[SUCCESS] All scripts are now unblocked!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run master.ps1 with ZERO security prompts:" -ForegroundColor Cyan
    Write-Host "  .\master.ps1 -VerboseLoggingToFile" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The suite will run 100% autonomously with no user interaction." -ForegroundColor Green
}
elseif ($failedCount -gt 0) {
    Write-Host "[WARNING] Some scripts could not be unblocked." -ForegroundColor Yellow
    Write-Host "You may still see security warnings for these files." -ForegroundColor Yellow
}
else {
    Write-Host "[INFO] Scripts are ready for autonomous execution." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
