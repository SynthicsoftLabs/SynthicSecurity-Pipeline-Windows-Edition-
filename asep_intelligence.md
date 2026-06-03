# Windows Auto-Start Extension Points (ASEPs) - Titan Edition

## 1. Registry Run Keys (Standard & Obscure)
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnceEx`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnceEx`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\Install\Software\Microsoft\Windows\CurrentVersion\Run`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\Install\Software\Microsoft\Windows\CurrentVersion\RunOnce`

## 2. Boot & Session Initialization
- `HKLM\System\CurrentControlSet\Control\Session Manager\BootExecute` (Default: `autocheck autochk *`)
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Userinit`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Notify`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Taskman`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Appinit_DLLs`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\Load`

## 3. Services & Drivers
- `HKLM\System\CurrentControlSet\Services` (Scanning for `Start` = 0, 1, 2)
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServicesOnce`

## 4. Shell & Explorer Extensions
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ShellServiceObjectDelayLoad`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders`
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders`

## 5. Advanced APT Mechanisms (LSA, COM, etc.)
- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Authentication Packages`
- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Notification Packages`
- `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Security Packages`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options` (Debugger hijacking)
- `HKLM\SOFTWARE\Classes\CLSID\{...}\InprocServer32` (COM Object Hijacking)
- `HKCU\Software\Classes\CLSID\{...}\InprocServer32` (User-level COM Hijacking)

## 6. WMI & Scheduled Tasks
- `root\subscription:__EventConsumer` (WMI Eventing)
- `C:\Windows\System32\Tasks` (Direct file scan)
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree`
