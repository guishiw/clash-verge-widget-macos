Clash Verge Widget for macOS
============================

Requirements
------------
- macOS 14 or later
- Apple Silicon (arm64)
- Clash Verge Rev installed and running

Install
-------
1. Open Terminal, drag Install.command into the Terminal window, and press Return.
2. Open System Settings > Privacy & Security > Accessibility.
3. Enable Clash Verge Widget.
4. Open the Clash Verge main window once. It can then be closed again.

The app is ad-hoc signed and is not Apple-notarized. Verify SHA256SUMS.txt and
download only from the official GitHub repository. If macOS blocks the first
launch, try opening the installed app once, then open System Settings > Privacy
& Security and choose Open Anyway. Run Install.command again afterward if the
automatic startup service did not start. Do not disable Gatekeeper globally.

Uninstall
---------
Run Uninstall.command. The installed app is moved to the Trash. Clash Verge
configuration and widget logs are not deleted.

Project
-------
https://github.com/guishiw/clash-verge-widget-macos
