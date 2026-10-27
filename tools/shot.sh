#!/usr/bin/env bash
# Renders one screenshot of the running game under a virtual display.
# Usage: tools/shot.sh <output.png> <seconds> [game args...]
# Example: tools/shot.sh /tmp/battle.png 15 --test-battle=quick --auto --profile=test
set -u
out="$1"; secs="$2"; shift 2
dir="$(mktemp -d)"
cd "$(dirname "$0")/.."
timeout 1200 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1600x900 \
	-- "$@" --shots="$dir" --shot-times="$secs" 2>&1 | grep -E "SCRIPT ERROR|^ERROR" | grep -v "ALSA\|audio" | head -5
if [ -f "$dir/shot_00.png" ]; then
	mv "$dir/shot_00.png" "$out"
	echo "saved $out"
else
	echo "no screenshot produced"
fi
rmdir "$dir" 2>/dev/null || true
