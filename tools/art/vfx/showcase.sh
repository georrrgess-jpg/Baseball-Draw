#!/usr/bin/env bash
# Captures an ability card's visual effect on the Practice Field.
# Usage: tools/art/vfx/showcase.sh <card_id>[@t1/t2][,<card_id>...] <out_dir> [times] [extra game args...]
#   times: seconds after the cast, comma separated (default 0.15,0.5,1.0)
#   extra args, e.g. --vfx-cam=yaw,pitch,dist  --vfx-delay=0.6  --vfx-level=3  --cam-view=x,z,yaw,pitch,dist
# Runs with a fixed timestep (--fixed-fps) so captures land on the same game time no matter
# how slow software rendering is. Saves <out_dir>/<card_id>_<centiseconds>.png.
set -u
card="$1"; out="$2"; times="${3:-0.15,0.5,1.0}"
shift $(( $# >= 3 ? 3 : $# ))
cd "$(dirname "$0")/../../.."
mkdir -p "$out"
out="$(cd "$out" && pwd)"
timeout 3000 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1280x720 --fixed-fps 30 \
	-- --test-battle=practice --profile=vfx --no-hud --vfx-showcase="$card" --vfx-shots="$times" --vfx-out="$out" "$@" 2>&1 \
	| grep -E "SCRIPT ERROR|SHADER ERROR|^ERROR|^\[VFX\]|at: |error\("  | grep -v "ALSA\|audio"
