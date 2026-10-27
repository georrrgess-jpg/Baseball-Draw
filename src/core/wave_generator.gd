class_name WaveGenerator
extends RefCounted
## Builds enemy waves from a budget that grows with inning, wave and difficulty.
## Each wave is themed (rush, heavy, swarm, squad, mixed) so innings feel different,
## and generation is deterministic per (seed, inning, wave) so resumed runs match.

const GROUP_SIZE := {
	"runner": Vector2i(3, 5), "sprinter": Vector2i(2, 4), "armored": Vector2i(1, 3), "swarmer": Vector2i(5, 7),
	"jumper": Vector2i(2, 3), "trickster": Vector2i(1, 2), "captain": Vector2i(1, 1), "slugger": Vector2i(1, 1),
	"base_stealer": Vector2i(2, 3),
}

const THEMES := {
	"mixed": {"runner": 3.0, "sprinter": 1.5, "armored": 1.5, "swarmer": 1.2, "jumper": 1.2, "trickster": 1.0, "captain": 0.8, "slugger": 0.6,
		"base_stealer": 1.2},
	"rush": {"runner": 2.0, "sprinter": 4.0, "jumper": 2.0, "swarmer": 1.5, "trickster": 1.0, "base_stealer": 2.5},
	"heavy": {"runner": 1.0, "armored": 4.0, "slugger": 1.5, "captain": 1.0},
	"swarm": {"swarmer": 5.0, "runner": 1.5, "sprinter": 1.0},
	"squad": {"captain": 2.5, "runner": 3.0, "armored": 1.0, "trickster": 1.5, "base_stealer": 1.0},
}


## Effective inning used for scaling (Quick Defense ramps faster).
static func effective_inning(run: RunState) -> float:
	var scale := float(DB.mode(run.mode_id).get("inning_scale", 1.0))
	return 1.0 + float(run.inning - 1) * scale


static func hp_multiplier(run: RunState) -> float:
	var ei := effective_inning(run)
	var mult := 1.0 + 0.24 * (ei - 1.0)
	if ei > 6.0:
		mult *= pow(1.08, ei - 6.0)
	mult *= float(DB.difficulty(run.difficulty_id).enemy_hp)
	mult *= 1.0 + run.modifier_total("enemy_hp")
	return mult


static func speed_multiplier(run: RunState) -> float:
	var ei := effective_inning(run)
	var mult := 1.0 + minf(0.012 * (ei - 1.0), 0.15)
	mult *= float(DB.difficulty(run.difficulty_id).enemy_speed)
	mult *= 1.0 + run.modifier_total("enemy_speed")
	return mult


static func generate(run: RunState, wave_index: int, route_count: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.run_seed, run.inning, wave_index])
	var ei := effective_inning(run)
	var diff := DB.difficulty(run.difficulty_id)
	var is_last := wave_index == run.waves_per_inning - 1
	var boss := run.boss_for_inning(run.inning) if is_last else ""

	var budget := (8.0 + 4.8 * (ei - 1.0) + 2.6 * float(wave_index)) * float(diff.budget)
	if ei > 9.0:
		budget *= pow(1.08, ei - 9.0)
	if boss != "":
		budget *= 0.35

	# Enemy pool for this inning.
	var pool: Array[String] = []
	for id in DB.enemies.keys():
		var e: Dictionary = DB.enemies[id]
		if e.get("boss", false) or id == "decoy":
			continue
		if float(e.from_inning) <= ei:
			pool.append(id)

	# First wave of a run is a gentle introduction.
	var theme := "mixed"
	if run.inning == 1 and wave_index == 0 and not run.is_endless():
		theme = "intro"
	elif boss == "":
		var themes := ["mixed", "mixed", "rush", "heavy", "swarm", "squad"]
		theme = themes[rng.randi() % themes.size()]
	if "swarm_season" in run.modifiers and theme != "intro":
		theme = "swarm"
	elif ("heavy_hitters" in run.modifiers or run.modifier_total("heavy") > 0.0) and rng.randf() < 0.45 and theme != "intro":
		theme = "heavy"

	var groups: Array = []
	var t := 1.0
	var route_cursor := rng.randi() % maxi(route_count, 1)
	if theme == "intro":
		groups.append(_group("runner", 4, route_cursor, t, 1.1, ""))
		groups.append(_group("runner", 2, (route_cursor + 1) % route_count, t + 6.0, 1.2, ""))
		budget = 0.0

	if boss != "":
		groups.append(_group(boss, 1, rng.randi() % route_count, t + 3.0, 1.0, ""))

	var weights: Dictionary = THEMES.get(theme, THEMES.mixed)
	var safety := 0
	while budget > 0.6 and safety < 60:
		safety += 1
		var id := _pick(pool, weights, rng)
		if id == "":
			break
		var e: Dictionary = DB.enemies[id]
		var gs: Vector2i = GROUP_SIZE.get(id, Vector2i(1, 2))
		var count := rng.randi_range(gs.x, gs.y)
		# Late innings bring bigger groups.
		if ei >= 6.0 and id in ["runner", "swarmer", "sprinter"]:
			count += int((ei - 5.0) / 2.0)
		var cost := float(e.cost) * count
		if cost > budget * 1.25:
			count = maxi(1, int(budget / float(e.cost)))
			cost = float(e.cost) * count
		budget -= cost
		var affix := ""
		if rng.randf() < float(diff.get("elite_chance", 0.0)) * (1.0 + ei * 0.05) and id != "swarmer":
			affix = DB.elite_affixes[rng.randi() % DB.elite_affixes.size()].id
		var interval := 0.55 if id == "swarmer" else rng.randf_range(0.7, 1.1)
		groups.append(_group(id, count, route_cursor, t, interval, affix))
		# Captains bring an escort.
		if id == "captain":
			groups.append(_group("runner", 3, route_cursor, t + 0.5, 0.6, ""))
			budget -= 3.0
		route_cursor = (route_cursor + 1 + (rng.randi() % 2)) % maxi(route_count, 1)
		t += float(count) * interval * 0.5 + rng.randf_range(1.6, 3.4)

	var preview := {}
	for g in groups:
		preview[g.enemy] = int(preview.get(g.enemy, 0)) + int(g.count)
	return {"groups": groups, "boss": boss, "theme": theme, "preview": preview, "total": _total(groups)}


static func _group(id: String, count: int, route: int, start: float, interval: float, affix: String) -> Dictionary:
	return {"enemy": id, "count": count, "route": route, "start": start, "interval": interval, "affix": affix}


static func _total(groups: Array) -> int:
	var n := 0
	for g in groups:
		n += int(g.count)
	return n


static func _pick(pool: Array[String], weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in pool:
		total += float(weights.get(id, 0.0))
	if total <= 0.0:
		return pool[rng.randi() % pool.size()] if pool.size() > 0 else ""
	var r := rng.randf() * total
	for id in pool:
		r -= float(weights.get(id, 0.0))
		if r <= 0.0:
			return id
	return pool[pool.size() - 1]
