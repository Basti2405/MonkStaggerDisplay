#!/usr/bin/env bash
# Kopiert das AddOn in den WoW-AddOns-Ordner.
#
#   scripts/install.sh                 # nutzt WOW_ADDONS_DIR oder den erkannten Pfad
#   scripts/install.sh "/pfad/zu/Interface/AddOns"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="MonkStaggerDisplay"

DEFAULT_DIR="/mnt/f/Blizzard/World of Warcraft/_retail_/Interface/AddOns"
TARGET_ROOT="${1:-${WOW_ADDONS_DIR:-$DEFAULT_DIR}}"

[ -d "$TARGET_ROOT" ] || {
    echo "AddOns-Ordner nicht gefunden: $TARGET_ROOT" >&2
    echo "Pfad als Argument übergeben oder WOW_ADDONS_DIR setzen." >&2
    exit 1
}

TARGET="$TARGET_ROOT/$ADDON"
mkdir -p "$TARGET"

# Nur Laufzeitdateien kopieren; Altbestände entfernen, damit keine
# entfernten Lua-Dateien im AddOns-Ordner zurückbleiben.
rm -f "$TARGET"/*.lua "$TARGET"/*.toc "$TARGET"/README.md
cp "$ROOT/$ADDON/$ADDON.toc" "$TARGET/"
cp "$ROOT/$ADDON"/*.lua       "$TARGET/"

echo "Installiert nach: $TARGET"
ls -la "$TARGET"
echo
echo "Im Spiel: /reload  (oder Client neu starten)"
