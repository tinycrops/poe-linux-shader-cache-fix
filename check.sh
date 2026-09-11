#!/usr/bin/env bash
# check.sh — is the NVIDIA shader disk cache being wiped between launches of
# Path of Exile / Path of Exile 2 on Linux (Steam + Proton, NVIDIA driver)?
# Read-only. Prints evidence; changes nothing.
set -u
DEFAULT_LIMIT=$((1024*1024*1024))   # driver default since 460: 1 GiB

steam_root() {
  for d in "${STEAM_ROOT:-}" "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.steam/debian-installation"; do
    [ -n "$d" ] && [ -d "$d/steamapps" ] && { readlink -f "$d"; return; }
  done
}
ROOT=$(steam_root); [ -n "$ROOT" ] || { echo "Steam install not found (set STEAM_ROOT)"; exit 1; }
echo "Steam root: $ROOT"

echo; echo "== 1. Is the cache limit raised? =="
for v in __GL_SHADER_DISK_CACHE_SIZE __GL_SHADER_DISK_CACHE_SKIP_CLEANUP; do
  printf '  %-36s shell: %-14s systemd user env: %s\n' "$v" "${!v:-unset}" \
    "$(systemctl --user show-environment 2>/dev/null | sed -n "s/^$v=//p" | grep . || echo unset)"
done

echo; echo "== 2. Driver's default cache (used when Steam does not hand the game its own path) =="
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nvidia/GLCache"
if [ -d "$CACHE" ]; then
  total=0
  while IFS= read -r d; do
    echo "  $d  (dir created $(stat -c %w "$d" | cut -c1-19))"
    find "$d" -maxdepth 1 -name '*.bin' -printf '     created %TY-%Tm-%Td %TH:%TM  %10s bytes  %f\n' | sort
    s=$(du -sb "$d" | cut -f1); total=$((total+s))
  done < <(find "$CACHE" -mindepth 2 -maxdepth 2 -type d)
  echo "  total: $total bytes"
  if [ "$total" -gt "$DEFAULT_LIMIT" ] && [ -z "${__GL_SHADER_DISK_CACHE_SIZE:-}" ]; then
    echo "  !! over the 1 GiB default and no limit override in this shell: the next app start can wipe it"
  fi
  echo "  (a 'created' time equal to a game launch time = the cache was wiped at that launch)"
else
  echo "  none at $CACHE"
fi

echo; echo "== 3. Per game =="
for app in 238960:"Path of Exile" 2694490:"Path of Exile 2"; do
  id=${app%%:*}; name=${app#*:}
  gdir="$ROOT/steamapps/common/$name"; [ -d "$gdir" ] || continue
  echo "  $name ($id)"
  last=$(grep -E "Setting MESA_GLSL_CACHE_DIR=$ROOT/steamapps/shadercache/$id" "$ROOT/logs/shader_log.txt" 2>/dev/null | tail -1 | cut -c2-20)
  echo "    Steam last applied its managed shader cache at launch: ${last:-never (log not found or no entry)}"
  launches=$(grep -c 'LOG FILE OPENING' "$gdir/logs/Client.txt" 2>/dev/null || echo 0)
  lastlaunch=$(grep 'LOG FILE OPENING' "$gdir/logs/Client.txt" 2>/dev/null | tail -1 | cut -c1-19)
  echo "    game launches in Client.txt: $launches (last: ${lastlaunch:-?})"
  lmdb=$(grep -c 'Failed to open LMDB environment' "$gdir/logs/Client.txt" 2>/dev/null || echo 0)
  echo "    'Failed to open LMDB environment … Access denied' lines: $lmdb (Wine-level; the game's own pipeline cache never persists)"
  mgd="$ROOT/steamapps/shadercache/$id/nvidiav1"
  [ -d "$mgd" ] && echo "    Steam-managed NVIDIA cache on disk: $(du -sh "$mgd" | cut -f1), last written $(find "$mgd" -type f -printf '%TY-%Tm-%Td %TH:%TM\n' | sort | tail -1)"
done
