#!/bin/bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$PACKAGE_DIR/Clash Verge Widget.app"
LAUNCH_AGENT_TEMPLATE="$PACKAGE_DIR/LaunchAgent.plist.template"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/Clash Verge Widget.app"
APPEX="$DESTINATION_APP/Contents/PlugIns/ClashVergeWidgetExtension.appex"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.local.ClashVergeWidget.host.plist"
LOG_DIR="$HOME/Library/Logs/ClashVergeWidget"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" || ! -f "$LAUNCH_AGENT_TEMPLATE" ]]; then
    echo "The release package is incomplete. Download and extract it again." >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

mkdir -p "$DESTINATION_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR" "$HOME/.Trash"

if [[ -e "$DESTINATION_APP" ]]; then
    BACKUP="$HOME/.Trash/Clash Verge Widget-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$DESTINATION_APP" "$BACKUP"
    echo "Previous build moved to $BACKUP"
fi

ditto "$SOURCE_APP" "$DESTINATION_APP"
chmod -R go-rwx "$DESTINATION_APP"

sed \
    -e "s#__EXECUTABLE__#$DESTINATION_APP/Contents/MacOS/ClashVergeWidgetHost#g" \
    -e "s#__STDOUT__#$LOG_DIR/host.log#g" \
    -e "s#__STDERR__#$LOG_DIR/host-error.log#g" \
    "$LAUNCH_AGENT_TEMPLATE" > "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT"

launchctl bootout "gui/$(id -u)/com.local.ClashVergeWidget.host" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null; then
    sleep 1
    if ! launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"; then
        echo "The LaunchAgent could not start yet. Approve the app in Privacy & Security, then run Install.command again." >&2
    fi
fi
launchctl enable "gui/$(id -u)/com.local.ClashVergeWidget.host"
launchctl kickstart -k "gui/$(id -u)/com.local.ClashVergeWidget.host" 2>/dev/null || true

"$LSREGISTER" -f "$DESTINATION_APP"
pluginkit -a "$APPEX"
/usr/bin/open "$DESTINATION_APP" 2>/dev/null || true

echo
echo "Installed to: $DESTINATION_APP"
echo "Next: enable Clash Verge Widget in System Settings > Privacy & Security > Accessibility."
echo "Then open the Clash Verge main window once to initialize hidden-window controls."
