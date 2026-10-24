#!/bin/sh
# Verify the props in a throw-away Godot project (never touches the main project).
#   tools/blender/props/godot_check/run_check.sh [workdir] [--shots]
# Imports assets/models/props, runs verify.gd + inspect.gd, optionally renders
# per-prop screenshots and the assembled test stadium (needs xvfb-run).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
WORK=${1:-$(mktemp -d /tmp/props_check.XXXXXX)}
mkdir -p "$WORK/assets/models"
cp "$HERE/project.godot.template" "$WORK/project.godot"
cp "$HERE/verify.gd" "$HERE/inspect.gd" "$HERE/shot.gd" "$WORK/"
cp -r "$REPO/assets/models/props" "$WORK/assets/models/"
godot --headless --path "$WORK" --import >/dev/null 2>&1 || true
godot --headless --path "$WORK" --script verify.gd
godot --headless --path "$WORK" --script inspect.gd > "$WORK/inspect.txt"
echo "node dump: $WORK/inspect.txt"
if [ "$2" = "--shots" ]; then
  mkdir -p "$WORK/shots"
  xvfb-run -a -s "-screen 0 1280x720x24" godot --path "$WORK" --rendering-driver vulkan --script shot.gd -- mode=props out="$WORK/shots"
  xvfb-run -a -s "-screen 0 1280x720x24" godot --path "$WORK" --rendering-driver vulkan --script shot.gd -- mode=scene out="$WORK/shots" name=stadium cx=4 cy=7 cz=28 tx=0 ty=22 tz=-150 fov=50
  echo "screenshots: $WORK/shots"
fi
