# SynthicSecurity — Autonomous Cyber Defense Suite
### Aegis Edition v5.1 · Developed by Synthicsoft Labs

> Autonomous Windows endpoint protection suite featuring real-time threat detection, behavioral heuristics, ransomware canaries, ASEP persistence hunting, and self-remediating IR playbooks — all in a single PowerShell command.

**Author:** Adam Rivers, CEO — Synthicsoft Labs  
**Platform:** Windows · PowerShell 5.1+  
**Requires:** Administrator privileges

---

## Overview

SynthicSecurity is a professional-grade, fully autonomous endpoint detection and response (EDR) suite for Windows. It requires no third-party agents, no cloud subscription, and no configuration — run one command and it captures a forensic baseline, hardens the system, hunts for threats across 50+ persistence points, and remediates findings automatically using playbook-driven incident response.

All evidence is preserved in timestamped session packages for post-incident review.

---

## Quick Start

```powershell
# Full autonomous run — detect, harden, remediate, and patch
.\Invoke-SecuritySuite.ps1 -FullScan -ApplyRemediation -ApplyHardening -ApplyPatches

# Read-only assessment — no changes made
.\Invoke-SecuritySuite.ps1 -FullScan -DryRun
```

---

## Pipeline Phases

| Phase | Module | What it does |
|-------|--------|-------------|
| 1 | **Forensics** | Captures BCD config, WinRE status, binary hashes, DNS cache, and network snapshot before any changes |
| 2 | **Hardening** | Disables LLMNR/NetBIOS, enables Defender real-time protection, activates PowerShell script block logging and command-line auditing |
| 3 | **Titan Detection Engine** | Runs all detection modules in sequence (see below) |
| 4 | **Smart Remediation** | Executes targeted IR playbooks for each detection type |
| 5 | **Patching** | Fetches CISA KEV feed, applies Windows and third-party updates, verifies critical service health post-patch |

### Detection Modules

- **Threat Detection Engine** — Sigma-mapped registry persistence, WMI event consumers, suspicious startup files, unsigned processes in user-writable paths, and PowerShell script block analysis
- **Behavioral Heuristics** — MITRE ATT&CK pattern matching for process injection, DLL sideloading, and Living-off-the-Land (LotL) binary abuse
- **ASEP Hunter** — Deep scan of 50+ Windows Auto-Start Extension Points including Run keys, Winlogon values, LSA providers, and Session Manager entries
- **Network Guardian** — Live connection audit against Feodo, ThreatFox, and URLhaus threat intelligence feeds
- **Disk IOC Hunter** — Recursive MD5/SHA256 hash scan of Temp, AppData, and Public directories against MalwareBazaar
- **Ransomware Sentinel** — Deploys canary files across user directories and detects unauthorized modification or deletion indicating active encryption
- **Deception Module** — Honey-file tripwires that trigger immediate host isolation on unauthorized access
- **Memory Guardian** — Detects process hollowing, suspicious parentage of critical processes (lsass, svchost), and unsigned modules loaded into high-value processes

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-FullScan` | Runs the complete Titan Detection Engine |
| `-ApplyRemediation` | Executes IR playbooks for all detections |
| `-ApplyHardening` | Applies security baselines to the OS |
| `-ApplyPatches` | Runs vulnerability management and update verification |
| `-DryRun` | Detects and logs threats without making any changes |
| `-LogRoot` | Override the default log directory (default: `C:\ProgramData\SynthicSecurity\Logs`) |

---

## Remediation Playbooks

| Threat Type | Automated Response |
|-------------|-------------------|
| ASEP Anomaly | Resets registry value to known-good state |
| Ransomware / Deception Trigger | Disables all network adapters to isolate host |
| Known Malicious Binary (IOC Match) | Terminates process and quarantines file |
| Malicious Network Connection | Terminates responsible process |
| Unsigned Process in Suspicious Path | Terminates process and quarantines binary |
| Suspicious DLL Sideload | Quarantines DLL to evidence directory |
| WMI Event Consumer | Removes subscription from `root\subscription` |

---

## Intelligence Feeds

Threat intelligence is cached locally and refreshed automatically each run:

| Feed | Source | Used For |
|------|--------|---------|
| Feodo Tracker | abuse.ch | Malicious IPs (C2 botnet infrastructure) |
| MalwareBazaar | abuse.ch | MD5 hash matching against live processes |
| ThreatFox | abuse.ch | SHA256 hash matching |
| URLhaus | abuse.ch | Malicious URL/domain detection |
| CISA KEV | cisa.gov | Prioritised Windows vulnerability patching |

---

## Evidence & Logs

Every session writes a self-contained evidence package to:

```
C:\ProgramData\SynthicSecurity\Logs\Session_[YYYYMMDD-HHmmss]\
├── master_orchestrator.log
├── Forensics\          # BCD export, binary hashes, network snapshot, DNS cache
├── Detection\          # Threat report (JSON) and detection log
├── ASEP\               # Persistence point scan results
├── Ransomware\         # Canary deployment and audit log
├── Remediation\        # Quarantined files and registry change log
└── Patching\           # CISA KEV data, update results, service verification
```

---

## Requirements

- Windows 10 / Windows 11 (PowerShell 5.1 or above)
- Administrator privileges
- Internet access recommended (for live threat intelligence feeds and patching); all modules degrade gracefully when offline

---

## Modules

| File | Description |
|------|-------------|
| `Invoke-SecuritySuite.ps1` | Main orchestrator — runs the full pipeline |
| `modules/forensics.ps1` | Boot integrity and system snapshot |
| `modules/hardening.ps1` | OS security baseline enforcement |
| `modules/threat-detection.ps1` | Core detection engine |
| `modules/heuristics.ps1` | Behavioral pattern analysis |
| `modules/asep-hunter.ps1` | Persistence point scanning |
| `modules/network-guardian.ps1` | Live connection auditing |
| `modules/disk-hunter.ps1` | Hash-based disk IOC scanning |
| `modules/ransomware-sentinel.ps1` | Canary file deployment and monitoring |
| `modules/deception.ps1` | Honey-file tripwire management |
| `modules/memory-guardian.ps1` | In-memory threat detection |
| `modules/remediation.ps1` | IR playbook execution |
| `modules/patching.ps1` | Vulnerability management and update verification |
| `modules/intelligence.ps1` | Threat feed ingestion and caching |

---

*© 2026 Synthicsoft Labs. Developed by Adam Rivers, CEO.*
