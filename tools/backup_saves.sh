#!/usr/bin/env bash
# Copy the complete Queens Domain "Saved" directory to a timestamped backup
# and verify every file by SHA-256. Read-only with respect to the source.
# Refuses to run while the game (or its wineserver) is running.
set -euo pipefail

# Defaults match a Bottles (flatpak) install in a bottle named "gaming"; override with QD_SAVED or QD_BOTTLE.
SRC="${QD_SAVED:-$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/${QD_BOTTLE:-gaming}/drive_c/users/$USER/AppData/Local/QueensDomain/Saved}"
DEST_ROOT="${QD_BACKUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)/backups}"

if pgrep -fi '^[A-Z]:\\.*QueensDomain(-Win64-Shipping)?\.exe' >/dev/null; then
    echo "Game appears to be running. Close it first." >&2
    exit 1
fi
[ -d "$SRC" ] || { echo "Source not found: $SRC" >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
label="${1:-manual}"
dest="$DEST_ROOT/${stamp}_${label}"
[ -e "$dest" ] && { echo "Destination exists: $dest" >&2; exit 1; }
mkdir -p "$dest"

# -a keeps timestamps; --no-clobber is redundant for a fresh dir but cheap insurance.
cp -a --no-clobber "$SRC" "$dest/Saved"

(cd "$SRC" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$dest/source.sha256"
(cd "$dest/Saved" && sha256sum --quiet -c "../source.sha256")
chmod -R a-w "$dest"

echo "Backup OK: $dest"
echo "Files: $(wc -l < "$dest/source.sha256")"
