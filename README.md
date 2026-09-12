# Path of Exile on Linux: the hideout that took forever after every restart

Path of Exile and Path of Exile 2 under Steam/Proton on an NVIDIA GPU: every
time the game was restarted, loading the hideout took minutes. It was not
disk, not RAM, not network, and not file permissions. It was the NVIDIA
driver deleting its own shader cache at launch.

Write-up with the evidence: **https://tinycrops.github.io/poe-linux-shader-cache-fix/**

## The short version

- The NVIDIA driver keeps compiled shaders in `~/.cache/nvidia/GLCache`, limited
  to **1 GiB** by default. When an app starts and the cache is over the limit,
  the driver **wipes the whole cache** and starts over.
- One long Path of Exile session writes more than 1 GiB (PoE 2 wrote 200 MB in
  its first 13 minutes; PoE 1's cache under Steam's management had reached
  5.2 GB). So almost every restart began cold, and the first area, the hideout,
  paid for recompiling every pipeline.
- Steam normally hands the game its own cache location with no such limit. On
  this machine Steam stopped doing that after a client update on 2026-09-04,
  which is when the problem started.

## Fix

```
./check.sh        # read-only: shows whether the cache is being wiped
./fix.sh          # raises the limit to 20 GiB and disables the cleanup, for the whole session
```

`fix.sh` sets `__GL_SHADER_DISK_CACHE_SIZE` and `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1`
in `~/.config/environment.d/`, `~/.profile`, the live systemd user session, and
as an `env` prefix on the Steam launchers in `~/.local/share/applications/`.
No sudo. Quit and restart Steam; log out and in once for full effect. The first
launch afterwards is the last cold compile.

Why global rather than a per-game launch option: the NVIDIA README says any
application started without the raised value reverts the cache to the default
size and wipes it if it is over. A launch option protects one game and leaves
every other GL/Vulkan app able to delete its cache.

## Day two: a second limit at 2 GiB per file

With the wipe gone the cache reached 2.1 GB and restarts were fast, until one
restart was cold with nothing wiped. The game had a different, nearly empty
cache file open; the 2.1 GB one had stopped growing a few MB past 2^31 bytes.
`overlap.py` parses both tables of contents: 98.6% of the shaders being compiled
into the new file were already in the abandoned one, so the driver was not
reading it. Undocumented per-file limit at 2 GiB: past it the driver starts a
fresh file and ignores the old data.

```
./overlap.py                      # compares the two largest cache files for the current driver
./overlap.py OLD.toc NEW.toc      # or any two
```

So the variables stop deletion but not this rollover; a game with this many
shader variants goes cold about once per 2 GiB of new pipelines. The durable
answer is Steam's own shader-cache management (it merges and deduplicates the
driver caches; PoE 1's managed cache reached 5.2 GB in one file and kept
working), which stopped being applied here after the Sep 4 client update.
Check Steam → Settings → Downloads → Shader Pre-Caching is on.

## Not fixed

Both games log `Failed to open LMDB environment at ...\Pipelines. Error: Access
denied.` on every launch under Proton (30 of 30 PoE 2 launches, 324 lines in
PoE 1's log). Linux permissions are correct; it is a failure inside Wine's
Windows API layer opening the game's own LMDB pipeline cache. No fix found. The
driver cache above is what compensates for it.

## Tested on

Ubuntu 24.04, GNOME on X11, NVIDIA driver 580.173.02, GTX 1060 6 GB, Steam
client 1788652215, Path of Exile (Proton 10) and Path of Exile 2 (Proton
Experimental), both on the native Vulkan renderer.

## References

- NVIDIA README, chapter 11K "Shader disk cache" (`/usr/share/doc/nvidia-driver-580/README.txt.gz`)
- [steam-for-linux #11392](https://github.com/ValveSoftware/steam-for-linux/issues/11392): precompiled shaders pruned by the NVIDIA driver
- [NVIDIA forums: shader disk cache max size](https://forums.developer.nvidia.com/t/opengl-shader-disk-cache-max-size-garbage-collection/60056)
