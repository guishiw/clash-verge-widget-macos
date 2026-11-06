#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$PROJECT_DIR/dist/Clash Verge Widget.app"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/Clash Verge Widget.app"
APPEX="$DESTINATION_APP/Contents/PlugIns/ClashVergeWidgetExtension.appex"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.local.ClashVergeWidget.host.plist"
LOG_DIR="$HOME/Library/Logs/ClashVergeWidget"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "${CLASH_WIDGET_SKIP_BUILD:-0}" != "1" ]]; then
    "$PROJECT_DIR/Scripts/build.sh"
elif [[ ! -d "$SOURCE_APP" ]]; then
    echo "Missing built app: $SOURCE_APP" >&2
    exit 1
fi

mkdir -p "$DESTINATION_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR"

if [[ -e "$DESTINATION_APP" ]]; then
    BACKUP="$HOME/.Trash/Clash Verge Widget-$(date +%Y%m%d-%H%M%S).app"
    mv "$DESTINATION_APP" "$BACKUP"
    echo "Previous build moved to $BACKUP"
fi

ditto "$SOURCE_APP" "$DESTINATION_APP"
chmod -R go-rwx "$DESTINATION_APP"

sed \
    -e "s#__EXECUTABLE__#$DESTINATION_APP/Contents/MacOS/ClashVergeWidgetHost#g" \
    -e "s#__STDOUT__#$LOG_DIR/host.log#g" \
    -e "s#__STDERR__#$LOG_DIR/host-error.log#g" \
    "$PROJECT_DIR/Resources/LaunchAgent.plist.template" > "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT"

launchctl bootout "gui/$(id -u)/com.local.ClashVergeWidget.host" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"; then
    # launchd can briefly retain the previous job after bootout.
    sleep 1
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
fi
launchctl enable "gui/$(id -u)/com.local.ClashVergeWidget.host"
launchctl kickstart -k "gui/$(id -u)/com.local.ClashVergeWidget.host"

"$LSREGISTER" -f "$DESTINATION_APP"
pluginkit -a "$APPEX"

echo "$DESTINATION_APP"
