# Changelog

## v2.3.0 - Bug Fix Release

- **FIXED:** `devsetup.ps1` missing `$SkipIDrive` parameter declaration — master.ps1 passed the flag but devsetup silently ignored it; IDrive was always installed regardless of the skip flag.
- **FIXED:** `devsetup.ps1` now actually installs IDrive via winget when `$SkipIDrive` is not set (it was absent from the package list).
- **FIXED:** `patch-intel.ps1` used `$patchesApplied` in the KEV summary block before the variable was defined, causing it to always report 0 patches. Variable is now computed before the summary.
- **FIXED:** `master.ps1` did not forward `$VerboseLoggingToFile` to `network-harden.ps1` or `debloat.ps1`, so those phases never logged to file even when `-VerboseLoggingToFile` was passed to master.

## v2.2.1 - Critical Hotfix (December 3, 2024)

- **FIXED:** Syntax error in devsetup.ps1 (lines 185-186)
- **ADDED:** unblock-scripts.ps1 for truly autonomous execution
- **ADDED:** Comprehensive README with setup instructions

## v2.2.0 - Enterprise Self-Healing (December 3, 2024)

- Smart package detection (3 methods)
- Multi-source download redundancy
- Retry logic with exponential backoff
- Graceful error handling
- Execution summary

## v1.0.0 - Initial Release

- Added `master.ps1` orchestrator.
- Added `devsetup.ps1` for development tooling installation.
- Added `network/network-harden.ps1` for safe network hardening.
- Added `debloat/debloat.ps1` to remove OEM bloat (preserves McAfee/Norton).
- Added `optimize/optimize.ps1` for performance tuning.
- Added `patching/patch-intel.ps1` for autonomous patching and KEV-aware intel.
