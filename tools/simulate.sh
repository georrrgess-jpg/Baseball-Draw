#!/usr/bin/env bash
# Runs autopilot games headlessly and prints one summary line per game.
# Usage: tools/simulate.sh <mode> <difficulty> <games> [extra args, e.g. --no-cards]
# Modes: standard, quick, endless, boss_rush, ranked. Dugout Draft picks are listed per game
# (boons=...); for tables and boon statistics use tools/balance/simulate.py.
cd "$(dirname "$0")/.."
mode="$1"; diff="$2"; n="$3"; shift 3
for i in $(seq 1 "$n"); do
	out=$(timeout 900 godot --headless --path . --fixed-fps 30 -- --test-battle="$mode" --difficulty="$diff" --auto \
		--profile="sim_${mode}_${diff}_$$_$i" --fresh-profile "$@" 2>&1)
	line=$(echo "$out" | grep "FINISHED" | head -1)
	runs=$(echo "$out" | grep -E "state=dugout|state=results" | sed -E 's/.*inning=([0-9]+).*runs=([0-9]+).*/i\1:r\2/' | tr '\n' ' ')
	boons=$(echo "$out" | grep -E "^\[AUTO\] boon " | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')
	echo "$mode/$diff #$i: ${line:-NO RESULT} | $runs${boons:+| boons=$boons}"
	echo "$out" | grep -E "SCRIPT ERROR" | head -3
done
