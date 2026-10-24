#!/usr/bin/env bash
# Renders the documentation screenshots into docs/screenshots/ (JPEG).
# Requires xvfb-run and a Vulkan driver (works with Mesa lavapipe; slow but fine).
set -u
cd "$(dirname "$0")/.."
out=docs/screenshots
mkdir -p "$out"
tmp="$(mktemp -d)"
shot() { # name seconds args...
	local name="$1" secs="$2"; shift 2
	tools/shot.sh "$tmp/$name.png" "$secs" "$@" >/dev/null 2>&1
	if [ -f "$tmp/$name.png" ]; then
		python3 -c "from PIL import Image; Image.open('$tmp/$name.png').convert('RGB').save('$out/$name.jpg', quality=86)"
		echo "captured $name"
	else
		echo "FAILED $name"
	fi
}
shot main_menu 9 --scene=main_menu --profile=shots_menu --fresh-profile --no-help
shot battle 18 --test-battle=quick --auto --profile=shots
shot action 20 --test-battle=standard --auto --profile=shots --start-inning=4 --cam-view=0,-6,18,-36,26
shot boss 22 --test-battle=standard --auto --profile=shots --start-inning=9 --start-wave=2 --cam-view=0,-10,15,-38,32
shot setup 7 --test-battle=standard --profile=shots --no-help
shot help 7 --test-battle=quick --profile=shots
shot dugout 9 --test-battle=standard --profile=shots --start-inning=3 --open-dugout --no-help
shot results 12 --test-battle=quick --profile=shots --start-inning=3 --show-results --no-help
shot play_menu 5 --scene=play_menu --profile=shots
shot deck_builder 6 --scene=deck_builder --profile=shots
shot roster 7 --scene=roster --profile=shots
shot progression 5 --scene=progression --profile=shots
shot arena_neon_diamond 16 --test-battle=quick --auto --profile=shots --arena=neon_diamond --cam-view=0,-4,20,-30,62
shot arena_frostpark 16 --test-battle=quick --auto --profile=shots --arena=frostpark --cam-view=0,-4,20,-30,62
shot arena_champions_citadel 16 --test-battle=quick --auto --profile=shots --arena=champions_citadel --cam-view=0,-4,20,-30,62
rm -rf "$tmp"
