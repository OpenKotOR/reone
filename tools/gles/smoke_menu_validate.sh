#!/usr/bin/env bash
# Smoke: launcher -> engine main menu only (no warp). Captures screenshot + log checks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINDIR="$ROOT/build-gles/debug/bin"
OUTDIR="$ROOT/tools/gles/evidence"
GAME="${GAME:-/run/media/brunner56/MyBook/SteamLibrary/steamapps/common/swkotor}"
mkdir -p "$OUTDIR"

if [[ ! -f "$GAME/chitin.key" ]]; then
  echo "KOTOR install not found at $GAME" >&2
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is unset; cannot run GUI smoke" >&2
  exit 1
fi

cat >"$BINDIR/reone.cfg" <<EOF
game=$GAME
dev=1
width=1024
height=768
winscale=100
fullscreen=0
vsync=0
grass=0
pbr=1
ssao=0
ssr=0
fxaa=0
sharpen=0
texquality=0
shadowres=1
anisofilter=4
drawdist=64
musicvol=0
voicevol=0
soundvol=0
movievol=0
logsev=1
logch=9
EOF

cd "$BINDIR"
rm -f engine.log
: >engine.log

if [[ ! -f "$BINDIR/shaderpack.erf" && -f "$ROOT/build/bin/shaderpack.erf" ]]; then
  cp "$ROOT/build/bin/shaderpack.erf" "$BINDIR/shaderpack.erf"
fi
if [[ ! -f "$BINDIR/shaderpack.erf" ]]; then
  echo "Missing shaderpack.erf in $BINDIR" >&2
  exit 1
fi
"$BINDIR/shaderpack" "$ROOT/glsl" "$BINDIR" >/dev/null

pkill -f "$BINDIR/engine" 2>/dev/null || true
pkill -f "$BINDIR/launcher" 2>/dev/null || true
pkill -x engine 2>/dev/null || true
sleep 1

find_engine_pid() {
  local pid cwd
  for pid in $(pgrep -x engine 2>/dev/null || true); do
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    if [[ "$cwd" == "$(readlink -f "$BINDIR")" ]]; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

GDK_BACKEND=x11 SDL_VIDEODRIVER=x11 ./launcher >/dev/null 2>&1 &
LAUNCHER_PID=$!
cleanup() {
  kill "$LAUNCHER_PID" 2>/dev/null || true
  pkill -f "$BINDIR/engine" 2>/dev/null || true
}
trap cleanup EXIT

echo "Waiting for launcher window..."
LAUNCH_WIN=""
for _ in $(seq 1 30); do
  LAUNCH_WIN=$(xdotool search --name "^reone$" 2>/dev/null | head -1 || true)
  [[ -n "$LAUNCH_WIN" ]] && break
  sleep 1
done
if [[ -z "$LAUNCH_WIN" ]]; then
  echo "Launcher window not found" >&2
  exit 1
fi

xdotool windowactivate --sync "$LAUNCH_WIN"
sleep 1
eval "$(xdotool getwindowgeometry --shell "$LAUNCH_WIN")"
LAUNCH_CLICK_X=$((WIDTH / 2))
LAUNCH_CLICK_Y=$((HEIGHT - 75))
xdotool mousemove --window "$LAUNCH_WIN" "$LAUNCH_CLICK_X" "$LAUNCH_CLICK_Y" click 1
echo "Clicked Launch at ${LAUNCH_CLICK_X},${LAUNCH_CLICK_Y}"

ENGINE_PID=""
for _ in $(seq 1 120); do
  ENGINE_PID=$(find_engine_pid || true)
  [[ -n "$ENGINE_PID" ]] && break
  sleep 1
done
if [[ -z "$ENGINE_PID" ]]; then
  echo "Engine did not start" >&2
  exit 1
fi
echo "Engine pid $ENGINE_PID"

sleep 10
ENGINE_WIN=""
for _ in $(seq 1 60); do
  ENGINE_WIN=$(xdotool search --class engine 2>/dev/null | head -1 || true)
  [[ -n "$ENGINE_WIN" ]] && break
  for wid in $(xdotool search --class SDL_app 2>/dev/null); do
    if [[ "$wid" != "$LAUNCH_WIN" ]]; then
      ENGINE_WIN=$wid
      break 2
    fi
  done
  sleep 1
done
if [[ -z "$ENGINE_WIN" ]]; then
  ENGINE_WIN=$(xdotool search --pid "$ENGINE_PID" 2>/dev/null | head -1 || true)
fi
if [[ -z "$ENGINE_WIN" ]]; then
  echo "Engine window not found" >&2
  exit 1
fi
echo "Engine window $ENGINE_WIN"

xdotool windowactivate --sync "$ENGINE_WIN"
sleep 2

# Keep pointer over the 3D view (away from WARP / menu buttons).
xdotool mousemove --window "$ENGINE_WIN" 420 260
sleep 1

TAG="fallback"
if grep -q "Cube map array supported: yes" engine.log 2>/dev/null; then
  TAG="oes-fastpath"
fi

if grep -q "Loading module" engine.log 2>/dev/null; then
  echo "ERROR: engine left main menu (warp/module load detected)" >&2
  grep "Loading module" engine.log || true
  exit 1
fi

SHOT="$OUTDIR/gles-menu-${TAG}-$(date +%Y%m%d-%H%M%S).png"
import -window "$ENGINE_WIN" "$SHOT"
echo "Screenshot: $SHOT"
grep "Cube map array supported" engine.log || true
grep -c "Texture not found" engine.log || true
