#!/usr/bin/env bash
# Stage, install and remove UE4SS for Queens Domain, recording every file added.
#
#   ue4ss.sh stage <zip> <sha256>   verify the archive hash and extract it into staging/ (game untouched)
#   ue4ss.sh apply                  copy staging/ into the game's Win64 dir (no overwrite),
#                                   write install-manifest.sha256, add the per-exe dwmapi override
#   ue4ss.sh status                 show what is installed and whether files changed since install
#   ue4ss.sh remove                 delete exactly the manifest's files and dirs, then the override
#   ue4ss.sh deploy-mod <Name>      copy mods/<Name>/ from the work folder into ue4ss/Mods/<Name>/ and
#                                   update its manifest lines (only inside our own mod folder)
#
# Nothing here touches save files.
set -euo pipefail

WORK="$(cd "$(dirname "$0")/.." && pwd)"
WIN64="${QD_WIN64:-${QD_GAME:-$HOME/games/QueensDomain}/QueensDomain/Binaries/Win64}"
STAGE="$WORK/ue4ss/staging"
MANIFEST="$WORK/ue4ss/install-manifest.sha256"
BOTTLE="${QD_BOTTLE:-gaming}"
REGKEY='HKEY_CURRENT_USER\Software\Wine\AppDefaults\QueensDomain-Win64-Shipping.exe\DllOverrides'
bcli() { flatpak run --command=bottles-cli com.usebottles.bottles "$@"; }

game_running() { pgrep -fi '^[A-Z]:\\.*QueensDomain(-Win64-Shipping)?\.exe' >/dev/null; }

case "${1:-}" in
stage)
    zip="$2"; want="$3"
    got="$(sha256sum "$zip" | cut -d' ' -f1)"
    [ "$got" = "$want" ] || { echo "SHA-256 mismatch: $got" >&2; exit 1; }
    [ -e "$STAGE" ] && { echo "staging exists, remove it first: $STAGE" >&2; exit 1; }
    mkdir -p "$STAGE"
    7z x -o"$STAGE" "$zip" >/dev/null
    echo "Staged into $STAGE:"
    (cd "$STAGE" && find . -type f | sort)
    ;;
apply)
    game_running && { echo "Close the game first." >&2; exit 1; }
    [ -f "$MANIFEST" ] && { echo "Already installed (manifest exists)." >&2; exit 1; }
    # Refuse if anything we would add already exists in the game dir.
    clash=0
    while IFS= read -r -d '' f; do
        rel="${f#"$STAGE"/}"
        [ -e "$WIN64/$rel" ] && { echo "exists, not overwriting: $WIN64/$rel" >&2; clash=1; }
    done < <(find "$STAGE" -type f -print0)
    [ "$clash" = 0 ] || exit 1
    (cd "$STAGE" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$MANIFEST.tmp"
    cp -a --no-clobber "$STAGE"/. "$WIN64"/
    (cd "$WIN64" && sha256sum --quiet -c "$MANIFEST.tmp")
    mv "$MANIFEST.tmp" "$MANIFEST"
    bcli reg -b "$BOTTLE" -k "$REGKEY" -v dwmapi -d native,builtin -t REG_SZ add
    echo "Installed $(wc -l < "$MANIFEST") files into $WIN64; manifest: $MANIFEST"
    ;;
status)
    [ -f "$MANIFEST" ] || { echo "Not installed (no manifest)."; exit 0; }
    echo "Files from manifest (FAILED = changed since install, e.g. logs/settings):"
    (cd "$WIN64" && sha256sum -c "$MANIFEST" 2>&1 | grep -v ': OK$' || true)
    echo "Files under ue4ss/ not in the manifest (created at runtime):"
    (cd "$WIN64" && find ue4ss -type f 2>/dev/null | sed 's#^#./#' | sort) \
        | comm -23 - <(cut -c67- "$MANIFEST" | sort)
    grep -i -A2 'AppDefaults\\\\QueensDomain-Win64-Shipping.exe' \
        "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/$BOTTLE/user.reg" || echo "(no registry override)"
    ;;
remove)
    game_running && { echo "Close the game first." >&2; exit 1; }
    [ -f "$MANIFEST" ] || { echo "No manifest; refusing to guess what to delete." >&2; exit 1; }
    # Only the top-level entries UE4SS adds (dwmapi.dll and the ue4ss/ folder) are removed,
    # and only if they are listed in the manifest.
    tops="$(cut -c67- "$MANIFEST" | sed 's#^\./##' | cut -d/ -f1 | sort -u)"
    echo "Will remove from $WIN64:"; echo "$tops" | sed 's/^/  /'
    read -r -p "Proceed? [y/N] " ok; [ "$ok" = y ] || exit 1
    while IFS= read -r t; do
        case "$t" in ''|.|..|*/*) echo "skip suspicious entry: $t" >&2; continue;; esac
        rm -rf -- "${WIN64:?}/$t"
    done <<< "$tops"
    bcli reg -b "$BOTTLE" -k "$REGKEY" -v dwmapi del || echo "(registry value already absent)"
    mv "$MANIFEST" "$MANIFEST.removed-$(date +%Y%m%d-%H%M%S)"
    echo "Removed."
    ;;
deploy-mod)
    name="${2:?mod name}"
    case "$name" in *[!A-Za-z0-9_]*) echo "bad mod name" >&2; exit 1;; esac
    game_running && { echo "Close the game first." >&2; exit 1; }
    [ -f "$MANIFEST" ] || { echo "UE4SS not installed (no manifest)." >&2; exit 1; }
    [ -d "$WORK/mods/$name" ] || { echo "no such mod: $WORK/mods/$name" >&2; exit 1; }
    dest="$WIN64/ue4ss/Mods/$name"
    rm -rf -- "$dest"
    cp -r "$WORK/mods/$name" "$dest"
    grep -v "  ./ue4ss/Mods/$name/" "$MANIFEST" > "$MANIFEST.tmp" || true
    (cd "$WIN64" && find "./ue4ss/Mods/$name" -type f -print0 | sort -z | xargs -0 sha256sum) >> "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
    echo "Deployed $name:"; (cd "$WIN64" && find "./ue4ss/Mods/$name" -type f)
    ;;
*)
    sed -n '2,13p' "$0"; exit 1;;
esac
