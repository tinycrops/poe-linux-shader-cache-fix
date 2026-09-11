#!/usr/bin/env bash
# fix.sh — stop the NVIDIA driver from wiping its shader disk cache between game
# launches. Raises the limit (default 20 GiB) and disables the cleanup, GLOBALLY
# for the user's session, because any GL/Vulkan app started without the value
# reverts to the 1 GiB default and can wipe the cache (NVIDIA README, ch. 11K).
#
#   ./fix.sh            apply
#   ./fix.sh --dry-run  show what would change
#   SHADER_CACHE_SIZE=<bytes> ./fix.sh   different limit
#
# Writes: ~/.config/environment.d/50-nvidia-shader-cache.conf   (systemd user session)
#         ~/.profile                                            (login shells / GDM X11 session)
#         ~/.local/share/applications/*.desktop that launch steam (env prefix, so the
#         next Steam start gets it before you log out and back in)
# No sudo. Idempotent.
set -euo pipefail
SIZE="${SHADER_CACHE_SIZE:-21474836480}"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
VARS="__GL_SHADER_DISK_CACHE_SIZE=$SIZE __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
say() { printf '%s\n' "$*"; }
do_() { if [ $DRY = 1 ]; then say "  would: $*"; else "$@"; fi; }

say "1. ~/.config/environment.d/50-nvidia-shader-cache.conf"
ENVD="$HOME/.config/environment.d"; F="$ENVD/50-nvidia-shader-cache.conf"
content="# NVIDIA shader disk cache: 1 GiB default, wiped at app start when exceeded.
# Raised so long Path of Exile sessions do not force a cold recompile next launch.
__GL_SHADER_DISK_CACHE_SIZE=$SIZE
__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
if [ $DRY = 1 ]; then say "  would write $F"; else mkdir -p "$ENVD"; printf '%s\n' "$content" > "$F"; say "  written"; fi

say "2. ~/.profile"
if grep -q '__GL_SHADER_DISK_CACHE_SIZE' "$HOME/.profile" 2>/dev/null; then
  do_ sed -i "s/^export __GL_SHADER_DISK_CACHE_SIZE=.*/export __GL_SHADER_DISK_CACHE_SIZE=$SIZE/" "$HOME/.profile"; say "  updated"
else
  if [ $DRY = 1 ]; then say "  would append exports"; else
    printf '\n# NVIDIA shader cache limit (see ~/.config/environment.d/50-nvidia-shader-cache.conf)\nexport __GL_SHADER_DISK_CACHE_SIZE=%s\nexport __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1\n' "$SIZE" >> "$HOME/.profile"; say "  appended"; fi
fi

say "3. Steam launchers in ~/.local/share/applications"
APPS="$HOME/.local/share/applications"; mkdir -p "$APPS"
if [ ! -e "$APPS/steam.desktop" ]; then
  for s in /usr/share/applications/steam.desktop "$HOME/.steam/debian-installation/deb-installer/steam.desktop"; do
    [ -f "$s" ] && { do_ cp "$s" "$APPS/steam.desktop"; say "  copied $s to user dir"; break; }
  done
fi
for f in "$APPS"/*.desktop; do
  [ -f "$f" ] || continue
  grep -qE '^Exec=(env [^|]* )?(/usr/(games|bin)/)?steam(\s|$)' "$f" || continue
  if [ -L "$f" ]; then t=$(readlink -f "$f"); do_ rm "$f"; do_ cp "$t" "$f"; say "  $f: symlink replaced by a user copy"; fi
  if grep -q '__GL_SHADER_DISK_CACHE_SIZE' "$f"; then
    do_ sed -i -E "s/__GL_SHADER_DISK_CACHE_SIZE=[0-9]+/__GL_SHADER_DISK_CACHE_SIZE=$SIZE/" "$f"; say "  $(basename "$f"): limit updated"
  else
    do_ sed -i -E "s|^Exec=((/usr/(games\|bin)/)?steam(\s\|$))|Exec=env $VARS \1|" "$f"; say "  $(basename "$f"): Exec prefixed"
  fi
done
[ $DRY = 1 ] || update-desktop-database "$APPS" 2>/dev/null || true

say "4. Live user session (new apps started by systemd/dbus)"
do_ systemctl --user set-environment $VARS
do_ dbus-update-activation-environment --systemd $VARS 2>/dev/null || true

say
say "Done. Quit Steam fully and start it again from its launcher; the first game"
say "launch is one last cold compile. Log out and back in once so every app sees"
say "the new limit. Verify later with ./check.sh (cache 'created' times should stop"
say "matching launch times)."
