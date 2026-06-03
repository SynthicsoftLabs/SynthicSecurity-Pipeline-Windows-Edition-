# Research Findings: Advanced Detection & Professional Guardrails

## Sigma Rules for Windows Persistence & TTPs

### 1. WMI Event Registration (Persistence)
- **Technique:** Adversaries create permanent WMI event subscriptions to execute code on system events (e.g., boot, logon).
- **Detection (Sysmon/Event Logs):**
  - **Event ID 19:** WmiEventFilter activity (Filter creation).
  - **Event ID 20:** WmiEventConsumer activity (Consumer creation).
  - **Event ID 21:** WmiEventConsumerToFilter activity (Binding creation).
- **Suspicious Patterns:**
  - Consumers pointing to `powershell.exe`, `cmd.exe`, `scrcons.exe` (VBScript/JScript), or `mshta.exe`.
  - Filters using rare or highly specific WQL queries (e.g., monitoring for a specific process or time).

### 2. Registry Persistence (Run Keys & IFEO)
- **Technique:** Adding malicious binaries to `Run`/`RunOnce` keys or using Image File Execution Options (IFEO) to hijack legitimate processes.
- **Detection:**
  - Monitor `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` and `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
  - Monitor `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options` for `Debugger` values.
- **Guardrails:** Whitelist known legitimate installers and applications (e.g., `Brave`, `Greenshot`, `OneDrive`).

### 3. PowerShell Obfuscation & Malicious Behavior
- **Technique:** Using encoded commands, IEX, and web downloads to bypass static analysis.
- **Detection (Event ID 4104):**
  - Keywords: `Net.WebClient`, `DownloadString`, `Invoke-Expression`, `EncodedCommand`, `FromBase64String`, `GzipStream`.
  - Obfuscation indicators: High entropy, excessive use of special characters (`+`, `"`, `'`), and backticks.

## Professional Security Guardrails (SynthicSoft Standards)

### 1. Windows Hello & Authentication Protection
- **Protected Services:** `NgcSvc`, `NgcCtnrSvc`, `KeyIso`, `VaultSvc`, `WbioSrvc`, `DeviceAssociationService`.
- **Constraint:** NEVER disable these services as they break PIN and biometric login.

### 2. Whitelisting (Anti-False Positive)
- **Paths:** `%AppData%\Local\BraveSoftware`, `%AppData%\Local\Programs\Greenshot`, `%ProgramFiles%`, `%ProgramFiles(x86)%`.
- **Signatures:** Verify Authenticode signatures for binaries before flagging them as suspicious.

### 3. Forensic-First Approach
- **Backup:** Always export registry keys and BCD settings before modification.
- **Evidence:** Capture screenshots, process lists, and network connections before remediation.

## Advanced Remediation Playbooks
- **Persistence Removal:**
  - Revert `BootExecute` to `autocheck autochk *`.
  - Reset `Winlogon\Shell` to `explorer.exe`.
  - Reset `Winlogon\Userinit` to `C:\Windows\system32\userinit.exe,`.
- **Boot Integrity:**
  - Verify `cmd.exe` integrity via `Get-AuthenticodeSignature`.
  - Restore `cmd.exe` from `WinSxS` if compromised.
  - Harden BCD: `recoveryenabled Yes`, `testsigning Off`, `debug No`.
