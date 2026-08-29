#!/usr/bin/env bash
# Baut das Release-Archiv MonkStaggerDisplay-<version>.zip in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="MonkStaggerDisplay"
TOC="$ROOT/$ADDON/$ADDON.toc"

[ -f "$TOC" ] || { echo "TOC nicht gefunden: $TOC" >&2; exit 1; }

VERSION="$(grep -m1 '^## Version:' "$TOC" | sed 's/^## Version:[[:space:]]*//' | tr -d '\r')"
[ -n "$VERSION" ] || { echo "Version konnte nicht aus der TOC gelesen werden" >&2; exit 1; }

DIST="$ROOT/dist"
OUT="$DIST/${ADDON}-${VERSION}.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

# Nur die Dateien ins Archiv, die WoW tatsächlich lädt, plus Lizenz.
STAGE="$DIST/stage"
mkdir -p "$STAGE/$ADDON"
cp "$ROOT/$ADDON/$ADDON.toc" "$STAGE/$ADDON/"
cp "$ROOT/$ADDON"/*.lua       "$STAGE/$ADDON/"
cp "$ROOT/README.md"          "$STAGE/$ADDON/"
cp "$ROOT/LICENSE"            "$STAGE/$ADDON/"
cp "$ROOT/CHANGELOG.md"       "$STAGE/$ADDON/"

( cd "$STAGE" && zip -qr "$OUT" "$ADDON" )
rm -rf "$STAGE"

echo "Archiv erstellt: $OUT"
unzip -l "$OUT"
