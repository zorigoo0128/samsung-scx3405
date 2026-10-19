Samsung SCX-3405 — Driver Installer
===================================

Installs printing (SpliX) and scanning (SANE) support for the Samsung
SCX-3400 series on Apple Silicon Macs running macOS 26 or later.

This installer is not signed with an Apple Developer ID, so macOS shows a
warning the first time you open it. That is expected.

To install
----------
1. Right-click (or Control-click) "Install SCX3405.pkg" and choose "Open".
2. Click "Open" again in the confirmation dialog.
3. Follow the Installer and enter your password when asked.

If macOS still refuses
----------------------
Open Terminal and run (replace the path with this DMG's if it differs):

    xattr -dr com.apple.quarantine "/Volumes/SCX-3405 Installer/Install SCX3405.pkg"

then repeat step 1.

After installing
----------------
 * Printing — a printer named "SCX3405" appears in System Settings >
   Printers & Scanners. Print as usual.
 * Scanning — open the "Scan SCX3405" app in Applications and click Scan,
   or run "scan-photo" in Terminal. Scans are saved as lossless PNG to
   ~/Pictures/Scans. Maximum resolution is 600 dpi.

Uninstall
---------
    sudo /Library/Printers/SCX3405/uninstall-scx3405.sh

Requirements
------------
Apple Silicon (M-series) Mac, macOS 26 or later, and the printer connected
by USB.
