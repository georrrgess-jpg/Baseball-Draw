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
shot main_menu 9 --scene=main_menu --profile=shots --no-help --skip-welcome
shot battle 18 --test-battle=quick --auto --profile=shots
shot action 20 --test-battle=standard --auto --profile=shots --start-inning=4 --cam-view=0,-6,18,-36,26
shot boss 22 --test-battle=standard --auto --profile=shots --start-inning=9 --start-wave=2 --cam-view=0,-10,15,-38,32
shot setup 7 --test-battle=standard --profile=shots --no-help
shot tutorial 8 --test-battle=quick --profile=shots_tutorial --fresh-profile
shot dugout 9 --test-battle=standard --profile=shots --start-inning=3 --open-dugout --no-help
shot results 12 --test-battle=quick --profile=shots --start-inning=3 --show-results --no-help
shot play_menu 5 --scene=play_menu --profile=shots
shot play_daily 6 --scene=play_menu --profile=shots --play-mode=daily
shot deck_builder 6 --scene=deck_builder --profile=shots_upg --fresh-profile --grant-demo-cards --demo-remove=2 --auto-build --no-hints
shot card_compare 7 --scene=deck_builder --profile=shots_upg --grant-demo-cards --no-hints --compare=heat_wave,splitter
shot card_upgrades 6 --scene=card_upgrades --profile=shots_upg --grant-demo-cards
shot roster 7 --scene=roster --profile=shots
shot progression 5 --scene=progression --profile=shots
shot missions 5 --scene=progression --profile=shots --tab=1
shot arena_neon_diamond 16 --test-battle=quick --auto --profile=shots --arena=neon_diamond --cam-view=0,-4,20,-30,62
shot arena_frostpark 16 --test-battle=quick --auto --profile=shots --arena=frostpark --cam-view=0,-4,20,-30,62
shot arena_champions_citadel 16 --test-battle=quick --auto --profile=shots --arena=champions_citadel --cam-view=0,-4,20,-30,62
shot packs 2.5 --scene=packs --profile=shots_packs --fresh-profile --pack-demo=champion
shot packs_reveal 9.5 --scene=packs --profile=shots_packs2 --fresh-profile --pack-demo=pro
shot packs_signature 1.9 --scene=packs --profile=shots_packs3 --fresh-profile --pack-demo=signature
# Card ability effects, captured on the Practice Field at a fixed time after the cast.
vfx() { # card seconds_after_cast
	local card="$1" t="$2"
	tools/art/vfx/showcase.sh "$card" "$tmp/vfx" "$t" >/dev/null 2>&1
	local f
	f="$(ls "$tmp/vfx/${card}"_*.png 2>/dev/null | head -1)"
	if [ -n "$f" ]; then
		python3 -c "from PIL import Image; Image.open('$f').convert('RGB').save('$out/vfx_$card.jpg', quality=86)"
		echo "captured vfx_$card"
	else
		echo "FAILED vfx_$card"
	fi
}
vfx heat_wave 1.0
vfx grand_slam_barrage 1.1
vfx thunderbolt 0.8
vfx frost_field 1.0
vfx lockdown 0.8
vfx base_shield 1.0
rm -rf "$tmp"
