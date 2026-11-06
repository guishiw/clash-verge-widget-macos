#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CLASH_VERGE_CONFIG:-$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Clash Verge control shortcuts: configuration not found"
    exit 2
fi

if ! /usr/bin/grep -Eq '^enable_global_hotkey:[[:space:]]*true[[:space:]]*$' "$CONFIG_FILE"; then
    echo "Clash Verge control shortcuts: global shortcuts are disabled"
    exit 1
fi

HOTKEYS="$({
    /usr/bin/awk '
        /^hotkeys:[[:space:]]*$/ { in_hotkeys = 1; next }
        in_hotkeys && /^-[[:space:]]*/ {
            line = $0
            sub(/^-[[:space:]]*/, "", line)
            print line
            next
        }
        in_hotkeys && /^[^[:space:]-][^:]*:/ { exit }
    ' "$CONFIG_FILE"
} || true)"

required=(
    clash_mode_rule
    clash_mode_global
    clash_mode_direct
    toggle_system_proxy
    toggle_tun_mode
)

missing=0
for function_name in "${required[@]}"; do
    match="$(/usr/bin/awk -F',' -v name="$function_name" '
        $1 == name && length($2) > 0 {
            sub(/^[^,]*,[[:space:]]*/, "", $0)
            print $0
            exit
        }
    ' <<< "$HOTKEYS")"
    if [[ -n "$match" ]]; then
        echo "Clash Verge control shortcut: $function_name=$match"
    else
        echo "Clash Verge control shortcut missing: $function_name"
        missing=1
    fi
done

conflicts="$(/usr/bin/awk -F',' '
    NF >= 2 {
        function_name = $1
        chord = $0
        sub(/^[^,]*,[[:space:]]*/, "", chord)
        normalized = toupper(chord)
        gsub(/[[:space:]]/, "", normalized)
        if (owner[normalized] != "" && owner[normalized] != function_name) {
            print owner[normalized] " and " function_name " both use " chord
        } else {
            owner[normalized] = function_name
        }
    }
' <<< "$HOTKEYS")"

if [[ -n "$conflicts" ]]; then
    while IFS= read -r conflict; do
        echo "Clash Verge control shortcut conflict: $conflict"
    done <<< "$conflicts"
    missing=1
fi

if [[ "$missing" -ne 0 ]]; then
    echo "Configure the five shortcuts in Clash Verge > Settings > Shortcut Settings."
    exit 1
fi

echo "Clash Verge control shortcuts: ready"
