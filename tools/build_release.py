#!/usr/bin/env python3
"""Build the QDQuickSave release zips into dist/.

  build_release.py --version 1.0.0                 mod-only zip and the -with-UE4SS bundle
  build_release.py --version 1.0.0 --mod-only      mod-only zip
  build_release.py --version 1.0.0 --ue4ss-zip PATH   use a local copy of the pinned UE4SS zip

Both zips are laid out relative to the game folder (the one containing QueensDomain.exe), so users extract
them there. The bundle uses the UE4SS build pinned in packaging/ue4ss.lock.json (verified by SHA-256), without
debug symbols, documentation or the built-in mods, and with end-user settings (no console windows).
Standard library only.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_DIR = os.path.join(ROOT, "mods", "QDQuickSave")
LICENSE = os.path.join(ROOT, "LICENSE")
LOCK = os.path.join(ROOT, "packaging", "ue4ss.lock.json")
DIST = os.path.join(ROOT, "dist")
CACHE = os.path.join(ROOT, ".cache")
WIN64 = "QueensDomain/Binaries/Win64"
MODS = WIN64 + "/ue4ss/Mods"

# Files taken from the UE4SS archive (paths inside it). Everything else (UE4SS.pdb, Docs, templates, the
# built-in example and debugging mods) is left out.
UE4SS_KEEP = [
    re.compile(r"^dwmapi\.dll$"),
    re.compile(r"^ue4ss/UE4SS\.dll$"),
    re.compile(r"^ue4ss/UE4SS-settings\.ini$"),
    re.compile(r"^ue4ss/LICENSE$"),
    re.compile(r"^ue4ss/Mods/shared/"),
]

# End-user settings: no console windows, D3D11 if the GUI is ever enabled.
SETTINGS_OVERRIDES = {
    "ConsoleEnabled": "0",
    "GuiConsoleEnabled": "0",
    "GuiConsoleVisible": "0",
    "GraphicsAPI": "dx11",
}

MODS_TXT = "QDQuickSave : 1\n"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def add_bytes(zf, name, data):
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def mod_files(version):
    out = []
    for base, _, names in os.walk(MOD_DIR):
        for n in sorted(names):
            path = os.path.join(base, n)
            rel = os.path.relpath(path, MOD_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                out.append((f"{MODS}/QDQuickSave/{rel}", f.read()))
    out.append((f"{MODS}/QDQuickSave/VERSION.txt", f"QDQuickSave {version}\n".encode()))
    with open(LICENSE, "rb") as f:
        lic = f.read()
    out.append((f"{MODS}/QDQuickSave/LICENSE.txt", lic))
    out.append(("QDQuickSave-LICENSE.txt", lic))
    return sorted(out)


def readme_txt(version, bundled):
    lines = [
        f"QDQuickSave {version} - quicksave / quickload for Queens Domain",
        "",
        "Extract this zip into the game folder: the folder that contains QueensDomain.exe.",
        "Then follow README.md on the project page for the remaining step on Linux/Steam Deck (one DLL override).",
        "",
        "F5 = quicksave (in game, after your first save at a monolith)",
        "F9 twice = load the quicksave (in game or on the death screen)",
        "",
        "Project page: https://github.com/derlocke-ng/queens-maiden-save-mod",
        "QDQuickSave is MIT licensed (QDQuickSave-LICENSE.txt).",
    ]
    if bundled:
        lines += ["", "Includes UE4SS (MIT licence, see QueensDomain/Binaries/Win64/ue4ss/LICENSE)."]
    return ("\r\n".join(lines) + "\r\n").encode()


def load_ue4ss(local_zip):
    with open(LOCK) as f:
        lock = json.load(f)
    if local_zip:
        with open(local_zip, "rb") as f:
            data = f.read()
    else:
        cached = os.path.join(CACHE, lock["file"])
        if os.path.exists(cached):
            with open(cached, "rb") as f:
                data = f.read()
        else:
            print(f"downloading {lock['url']}")
            with urllib.request.urlopen(lock["url"], timeout=120) as r:
                data = r.read()
            os.makedirs(CACHE, exist_ok=True)
            with open(cached, "wb") as f:
                f.write(data)
    got = sha256(data)
    if got != lock["sha256"]:
        sys.exit(f"UE4SS archive SHA-256 mismatch: {got} != {lock['sha256']} (see packaging/ue4ss.lock.json)")
    return data, lock


def patch_settings(text):
    for key, value in SETTINGS_OVERRIDES.items():
        text, n = re.subn(rf"(?m)^({re.escape(key)}\s*=\s*)[^\r\n]*", rf"\g<1>{value}", text)
        if n != 1:
            sys.exit(f"UE4SS-settings.ini: expected exactly one '{key}' line, found {n}")
    return text


def ue4ss_files(data):
    out = []
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if name.endswith("/") or not any(p.search(name) for p in UE4SS_KEEP):
                continue
            content = z.read(name)
            if name == "ue4ss/UE4SS-settings.ini":
                content = patch_settings(content.decode("utf-8")).encode("utf-8")
            out.append((f"{WIN64}/{name}", content))
    names = {n for n, _ in out}
    for required in (f"{WIN64}/dwmapi.dll", f"{WIN64}/ue4ss/UE4SS.dll", f"{WIN64}/ue4ss/UE4SS-settings.ini"):
        if required not in names:
            sys.exit(f"UE4SS archive is missing {required}")
    out.append((f"{MODS}/mods.txt", MODS_TXT.encode()))
    return sorted(out)


def write_zip(path, files):
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in files:
            add_bytes(zf, name, data)
    with open(path, "rb") as f:
        digest = sha256(f.read())
    print(f"{os.path.relpath(path, ROOT)}  {os.path.getsize(path):,} bytes  sha256 {digest}")
    return digest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="release version, e.g. 1.0.0 (a leading 'v' is stripped)")
    ap.add_argument("--mod-only", action="store_true", help="skip the UE4SS bundle")
    ap.add_argument("--ue4ss-zip", help="local copy of the UE4SS archive pinned in packaging/ue4ss.lock.json")
    args = ap.parse_args()
    version = args.version.lstrip("v")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?", version):
        sys.exit(f"invalid version: {args.version}")

    os.makedirs(DIST, exist_ok=True)
    sums = []
    mod = mod_files(version)
    name = f"QDQuickSave-{version}.zip"
    sums.append((write_zip(os.path.join(DIST, name), mod + [("QDQuickSave-README.txt", readme_txt(version, False))]), name))
    if not args.mod_only:
        data, lock = load_ue4ss(args.ue4ss_zip)
        name = f"QDQuickSave-{version}-with-UE4SS.zip"
        files = ue4ss_files(data) + mod + [("QDQuickSave-README.txt", readme_txt(version, True))]
        sums.append((write_zip(os.path.join(DIST, name), files), name))
        print(f"bundled UE4SS {lock['file']} ({lock['commit']})")
    with open(os.path.join(DIST, "SHA256SUMS.txt"), "w") as f:
        for digest, n in sums:
            f.write(f"{digest}  {n}\n")


if __name__ == "__main__":
    main()
