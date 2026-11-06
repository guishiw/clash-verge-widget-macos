#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Clash Verge Widget.app"
APPEX="$APP/Contents/PlugIns/ClashVergeWidgetExtension.appex"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.local.ClashVergeWidget.host.plist"
LABEL="com.local.ClashVergeWidget.host"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ -d "$APPEX" ]]; then
    pluginkit -r "$APPEX" 2>/dev/null || true
fi

if [[ -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    mkdir -p "$HOME/.Trash"
    TRASHED_APP="$HOME/.Trash/Clash Verge Widget-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$APP" "$TRASHED_APP"
    echo "Installed app moved to $TRASHED_APP"
fi

rm -f "$LAUNCH_AGENT"
echo "Clash Verge Widget uninstalled. Logs and Clash Verge data were left untouched."
