#!/usr/bin/env python3
"""Read-only dumper for UE4 (4.27) GVAS SaveGame files.

  gvas_dump.py dump <file.sav>            flat "path = value" lines
  gvas_dump.py diff <old.sav> <new.sav>   only paths that differ

Unknown or ambiguous binary data is printed as hex instead of guessed.
"""
import struct
import sys

# Structs that UE serializes natively (not as tagged property lists).
NATIVE = {
    "Vector": "<fff", "Rotator": "<fff", "Quat": "<ffff", "Vector2D": "<ff",
    "Vector4": "<ffff", "LinearColor": "<ffff", "IntPoint": "<ii", "IntVector": "<iii",
    "DateTime": "<q", "Timespan": "<q", "Color": "<BBBB",
}


class R:
    def __init__(self, b, p=0):
        self.b, self.p = b, p

    def take(self, n):
        v = self.b[self.p:self.p + n]
        if len(v) < n:
            raise ValueError("read past end")
        self.p += n
        return v

    def u(self, fmt):
        v = struct.unpack_from(fmt, self.b, self.p)
        self.p += struct.calcsize(fmt)
        return v if len(v) > 1 else v[0]

    def fstr(self):
        n = self.u("<i")
        if n == 0:
            return ""
        if n < 0:
            return self.take(-2 * n).decode("utf-16le")[:-1]
        if n > 1 << 20:
            raise ValueError("implausible string length")
        return self.take(n)[:-1].decode("latin1")


def guid(b):
    return b.hex()


def read_header(r):
    assert r.take(4) == b"GVAS"
    r.u("<ii")
    r.u("<HHHI")
    r.fstr()
    r.u("<i")
    n = r.u("<i")
    r.take(n * 20)
    return r.fstr()


def props(r, path, out, end=None):
    """Tagged property list until 'None'."""
    while end is None or r.p < end:
        name = r.fstr()
        if name == "None" or name == "":
            return
        typ = r.fstr()
        size, idx = r.u("<ii")
        key = f"{path}.{name}" + (f"[{idx}]" if idx else "")
        meta = {}
        if typ == "StructProperty":
            meta["struct"] = r.fstr(); r.take(16)
        elif typ == "BoolProperty":
            out.append((key, bool(r.u("<B"))))
        elif typ in ("ByteProperty", "EnumProperty"):
            meta["enum"] = r.fstr()
        elif typ in ("ArrayProperty", "SetProperty"):
            meta["inner"] = r.fstr()
        elif typ == "MapProperty":
            meta["k"] = r.fstr(); meta["v"] = r.fstr()
        if r.u("<B"):
            r.take(16)
        start = r.p
        try:
            value(r, typ, meta, size, key, out)
        except Exception as e:  # keep going: fall back to raw bytes for this property
            r.p = start
            out.append((key, f"<unparsed {typ} {size}B: {e}>"))
        r.p = start + size


def scalar(r, typ, enum=None):
    if typ == "IntProperty": return r.u("<i")
    if typ == "UInt32Property": return r.u("<I")
    if typ == "Int64Property": return r.u("<q")
    if typ == "FloatProperty": return round(r.u("<f"), 4)
    if typ == "DoubleProperty": return r.u("<d")
    if typ == "BoolProperty": return bool(r.u("<B"))
    if typ in ("NameProperty", "StrProperty", "ObjectProperty", "EnumProperty"): return r.fstr()
    if typ == "SoftObjectProperty": return r.fstr() + ("" if not (s := r.fstr()) else ":" + s)
    if typ == "ByteProperty": return r.fstr() if enum not in (None, "None") else r.u("<B")
    if typ == "TextProperty": raise ValueError("TextProperty in container")
    raise ValueError("unknown scalar " + typ)


def struct_value(r, sname, key, out, size=None):
    if sname in NATIVE:
        v = r.u(NATIVE[sname])
        out.append((key, tuple(round(x, 2) if isinstance(x, float) else x for x in v)
                    if isinstance(v, tuple) else v))
    elif sname == "Guid":
        out.append((key, guid(r.take(16))))
    else:
        props(r, key, out)


def value(r, typ, meta, size, key, out):
    if typ == "BoolProperty":
        return
    if typ == "StructProperty":
        struct_value(r, meta["struct"], key, out)
    elif typ == "TextProperty":
        out.append((key, f"<text {r.take(size).hex()}>"))
    elif typ in ("ArrayProperty", "SetProperty"):
        if typ == "SetProperty":
            r.u("<i")  # removed count
        n = r.u("<i")
        out.append((key + ".#", n))
        inner = meta["inner"]
        if inner == "StructProperty" and typ == "ArrayProperty":
            r.fstr(); r.fstr(); r.u("<q"); sname = r.fstr(); r.take(16); r.take(1)
            for i in range(n):
                struct_value(r, sname, f"{key}[{i}]", out)
        elif inner == "StructProperty":
            for i in range(n):
                out.append((f"{key}{{{i}}}", guid(r.take(16))))
        else:
            vals = [scalar(r, inner) for _ in range(n)]
            if typ == "SetProperty":
                out.extend((f"{key}{{{v}}}", True) for v in vals)
            else:
                out.extend((f"{key}[{i}]", v) for i, v in enumerate(vals))
    elif typ == "MapProperty":
        r.u("<i")  # removed count
        n = r.u("<i")
        out.append((key + ".#", n))
        kt, vt = meta["k"], meta["v"]
        for i in range(n):
            if kt == "StructProperty":
                k = guid(r.take(16))  # struct keys in this game look like GUIDs; printed raw
            else:
                k = scalar(r, kt)
            kk = f"{key}{{{k}}}"
            if vt == "StructProperty":
                props(r, kk, out)
            else:
                out.append((kk, scalar(r, vt)))
    else:
        out.append((key, scalar(r, typ, meta.get("enum"))))


def dump(path):
    r = R(open(path, "rb").read())
    cls = read_header(r)
    out = [("$class", cls)]
    props(r, "", out)
    return out


if __name__ == "__main__":
    if sys.argv[1:2] == ["dump"] and len(sys.argv) == 3:
        for k, v in dump(sys.argv[2]):
            print(f"{k} = {v}")
    elif sys.argv[1:2] == ["diff"] and len(sys.argv) == 4:
        a, b = dict(dump(sys.argv[2])), dict(dump(sys.argv[3]))
        for k in sorted(set(a) | set(b)):
            if a.get(k) != b.get(k):
                print(f"{k}: {a.get(k, '<absent>')}  ->  {b.get(k, '<absent>')}")
    else:
        sys.exit(__doc__)
