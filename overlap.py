#!/usr/bin/env python3
"""overlap.py — did the NVIDIA driver stop reading an older shader cache file?

Each cache is a .toc/.bin pair under ~/.cache/nvidia/GLCache/<driver>/<gpu>/.
The .toc is a 32-byte header followed by 32-byte entries: key(16) offset(8) size(8).
If most keys in the file the game is writing NOW already exist in a bigger, idle
file, the driver has abandoned the big one (observed after it crossed 2 GiB) and
the game is recompiling shaders it already had.

  ./overlap.py                  # two largest .toc files for the newest driver dir
  ./overlap.py OLD.toc NEW.toc
"""
import glob, os, struct, sys

def keys(path):
    b = open(path, "rb").read()
    n = (len(b) - 32) // 32
    ks = set(); end = 0
    for i in range(n):
        e = b[32 + i*32: 64 + i*32]
        off, size = struct.unpack("<QQ", e[16:32])
        ks.add(e[:16]); end = max(end, off + size)
    return ks, n, end

def pick():
    root = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "nvidia/GLCache")
    tocs = glob.glob(os.path.join(root, "*", "*", "*.toc"))
    tocs = [t for t in tocs if os.path.getsize(t[:-4] + ".bin") > 1_000_000]
    tocs.sort(key=lambda t: os.path.getsize(t[:-4] + ".bin"), reverse=True)
    if len(tocs) < 2:
        sys.exit("need two cache files over 1 MB; pass OLD.toc NEW.toc explicitly")
    return tocs[0], tocs[1]

old, new = (sys.argv[1], sys.argv[2]) if len(sys.argv) == 3 else pick()
ko, no, eo = keys(old); kn, nn, en = keys(new)
inter = len(ko & kn)
for label, p, n, e in (("old", old, no, eo), ("new", new, nn, en)):
    print(f"{label}: {os.path.basename(p)}  entries={n}  data={e:,} bytes  bin={os.path.getsize(p[:-4]+'.bin'):,} bytes")
pct = 100 * inter / max(nn, 1)
print(f"keys of new already in old: {inter}/{nn} = {pct:.1f}%")
print("-> driver is NOT reading the old file (recompiling known shaders)" if pct > 50 else "-> mostly new shaders; old file is probably still in use")
