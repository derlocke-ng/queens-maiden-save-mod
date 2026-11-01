#!/usr/bin/env python3
"""Snapshot or diff the Queens Domain save directory. Never writes to it.

  snapshot_saves.py snap  <name>          record names, sizes, mtimes, sha256; copy SaveGames files
  snapshot_saves.py diff  <old> <new>     compare two recorded snapshots
  snapshot_saves.py peek  <file.sav>      print key GVAS fields of a save

Snapshots are stored as JSON in ../snapshots/.
"""
import getpass
import hashlib
import json
import os
import shutil
import struct
import sys
import time

# Default: a Bottles (flatpak) install in a bottle named "gaming"; override with QD_SAVED or QD_BOTTLE.
SAVED = os.environ.get(
    "QD_SAVED",
    os.path.expanduser(
        "~/.var/app/com.usebottles.bottles/data/bottles/bottles/" + os.environ.get("QD_BOTTLE", "gaming")
        + "/drive_c/users/" + getpass.getuser() + "/AppData/Local/QueensDomain/Saved"
    ),
)
SNAPDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "snapshots")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def snap(name):
    files = {}
    for root, _, names in os.walk(SAVED):
        for n in names:
            p = os.path.join(root, n)
            st = os.stat(p)
            files[os.path.relpath(p, SAVED)] = {
                "size": st.st_size,
                "mtime": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime)),
                "sha256": sha256(p),
            }
    os.makedirs(SNAPDIR, exist_ok=True)
    out = os.path.join(SNAPDIR, name + ".json")
    if os.path.exists(out):
        sys.exit(f"snapshot exists: {out}")
    # Keep copies of the save files themselves so later field-level diffs are possible.
    copydir = os.path.join(SNAPDIR, name)
    os.makedirs(copydir)
    for rel in files:
        if rel.startswith("SaveGames" + os.sep):
            shutil.copy2(os.path.join(SAVED, rel), os.path.join(copydir, os.path.basename(rel)))
    with open(out, "w") as f:
        json.dump({"taken": time.strftime("%Y-%m-%d %H:%M:%S"), "files": files}, f, indent=1)
    print(f"{len(files)} files -> {out} (save copies in {copydir})")


def diff(a, b):
    load = lambda n: json.load(open(os.path.join(SNAPDIR, n + ".json")))["files"]
    old, new = load(a), load(b)
    for k in sorted(set(old) | set(new)):
        o, n = old.get(k), new.get(k)
        if o is None:
            print(f"+ {k}  {n['size']}B  {n['mtime']}")
        elif n is None:
            print(f"- {k}")
        elif o["sha256"] != n["sha256"]:
            print(f"M {k}  {o['size']}B -> {n['size']}B  {o['mtime']} -> {n['mtime']}")
        elif o["mtime"] != n["mtime"]:
            print(f"t {k}  (same content, mtime {o['mtime']} -> {n['mtime']})")


def peek(path):
    b = open(path, "rb").read()

    def rstr(p):
        n = struct.unpack_from("<i", b, p)[0]
        return b[p + 4 : p + 4 + n - 1].decode("latin1"), p + 4 + n

    def find(name):
        k = b.find(struct.pack("<i", len(name) + 1) + name.encode() + b"\0")
        return -1 if k < 0 else k + 4 + len(name) + 1

    p = 4 + 18
    _, p = rstr(p)
    _, cnt = struct.unpack_from("<ii", b, p)
    p += 8 + cnt * 20
    cls, _ = rstr(p)
    print("class:", cls)
    for name in ("SaveVersion", "ActiveSuspendSlot", "PlayTime_Seconds", "GamePlayTime_Seconds"):
        q = find(name)
        if q >= 0:
            _, q = rstr(q)
            print(f"{name}: {struct.unpack_from('<i', b, q + 9)[0]}")
    for name in ("SaveLevel", "SavePointID", "LastTouchedCheckpoint", "SavedArea"):
        q = find(name)
        if q >= 0:
            _, q = rstr(q)
            print(f"{name}: {rstr(q + 9)[0]}")
    q = find("Translation")
    if q >= 0:
        _, q = rstr(q)
        _, q = rstr(q + 8)
        print("Translation: (%.1f, %.1f, %.1f)" % struct.unpack_from("<fff", b, q + 17))


if __name__ == "__main__":
    cmd = sys.argv[1:2]
    if cmd == ["snap"] and len(sys.argv) == 3:
        snap(sys.argv[2])
    elif cmd == ["diff"] and len(sys.argv) == 4:
        diff(sys.argv[2], sys.argv[3])
    elif cmd == ["peek"] and len(sys.argv) == 3:
        peek(sys.argv[2])
    else:
        sys.exit(__doc__)
