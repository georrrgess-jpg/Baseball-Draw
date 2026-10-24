#!/usr/bin/env bash
# Loads every GDScript with autoloads present and prints parse/compile errors.
cd "$(dirname "$0")/.."
timeout 300 godot --headless --path . --import >/dev/null 2>&1
timeout 180 godot --headless --path . res://tests/check_all.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|FAILED|CHECKED|at: GDScript::reload|^ERROR" | grep -v "ALSA\|audio driver\|dummy driver\|snd_" 
