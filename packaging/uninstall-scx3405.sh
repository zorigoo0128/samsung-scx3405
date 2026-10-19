#!/bin/bash
# Uninstall everything the SCX-3405 driver package installed.
# Run with sudo:  sudo /Library/Printers/SCX3405/uninstall-scx3405.sh
set -u

echo "[scx3405] removing print queue"
lpadmin -x SCX3405 2>/dev/null

echo "[scx3405] removing files"
rm -rf /Library/Printers/SCX3405
rm -rf /Library/Printers/Splix
rm -rf "/Applications/Scan SCX3405.app"
rm -f /usr/local/bin/scan-photo

killall -HUP cupsd 2>/dev/null

echo "[scx3405] done. Scans saved in ~/Pictures/Scans were left untouched."
