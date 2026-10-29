class_name DeckAI
extends RefCounted
## Auto Build: picks the best 8-card deck from the cards the player owns, for their current team.
##
## Everything comes from generic card data (params, target, radius, cost, cooldown, category, rarity,
## linked defender, data/combos.json and the optional "role" field), so new cards need no special cases.
##
##   deck score = Σ card score + combos + role coverage + energy curve
##   card score = power × mode weight of its role × 0.75 if linked and the defender is absent
##                + signature bonus (linked defender on the team, more for the captain)
##                + small level / mastery tie-breakers
##   power      = what the card does at its current level, per resource spent. For each kind of value
##                (damage, control, defense, buff, economy) the card's value is divided by
##                (cost + cooldown / 8): 8 s of cooldown counts like one energy. Each kind is scaled so the
##                best level-1 card of that kind scores 10 (65 % per resource, 35 % raw impact); the best kind
##                counts fully, the others 40 %. Blended 75 / 25 with a rarity baseline (the designers' own
##                power estimate, and the fallback for params this file doesn't know).
##   coverage   = −6 per missing slot of the mode's minimums (damage 2+ incl. 1 AoE, control 1+, run-stop 1+,
##                boss answer 1 when one is owned), −3 per economy card past one, −2.5 per buff past two.
##   curve      = −5 per energy the average cost leaves the mode's band, −6 per card past two that cost 6+,
##                −2 with no card costing 2 or less.
##   combos     = +1.5 per data/combos.json pair in the deck (+0.5 when one of them is a team signature).
##
## Search: greedy (add the card that raises the deck score most), then best-improvement single swaps until
## no swap helps. Candidates are visited in DB.card_order and compared strictly, so results are stable.

const MODES := ["balanced", "aggressive", "control", "boss"]
const MODE_NAMES := {"balanced": "Balanced", "aggressive": "Aggressive", "control": "Control", "boss": "Boss Killer"}
const MODE_TEXT := {
	"balanced": "A bit of everything: damage, control, a run-stopper and a boss answer.",
	"aggressive": "More damage and buffs, fewer slows. Wins by clearing waves fast.",
	"control": "Slows, stuns and run-stoppers first. Wins by keeping runners off the bases.",
	"boss": "Boss answers and big single hits. Built to take down bosses.",
}
const ROLES := ["damage", "aoe", "control", "defense", "run_stop", "economy", "buff", "boss"]
const ROLE_NAMES := {"damage": "Damage", "aoe": "AoE", "control": "Control", "defense": "Defense",
	"run_stop": "Run-stop", "economy": "Economy", "buff": "Buff", "boss": "Boss"}
const KINDS := ["damage", "control", "defense", "buff", "economy"]
## The best level-1 card of each kind scores this much (a pure buff or economy card does less on its own
## than the best damage card, so their scale tops out lower).
const KIND_SCALE := {"damage": 10.0, "control": 9.5, "defense": 8.5, "buff": 7.5, "economy": 6.5}
const CD_PER_ENERGY := 8.0
const SIG_BONUS := 2.0
const CAPTAIN_BONUS := 0.6
const ABSENT_LINK_PENALTY := 1.0
const ABSENT_LINK_POWER := 0.75     # card_effects.gd: a linked card without its defender casts at 75 %
const COMBO_BONUS := 1.5
const MISSING_PENALTY := 6.0

## Per mode: role weights (missing = 1.0), minimum role counts, average-cost band.
const MODE_CFG := {
	"balanced": {"w": {}, "need": {"damage": 2, "aoe": 1, "control": 1, "stop": 1, "boss": 1}, "band": [2.6, 4.0], "heavy": 1},
	"aggressive": {"w": {"damage": 1.35, "aoe": 1.35, "buff": 1.2, "control": 0.8, "defense": 0.8, "run_stop": 0.85},
		"need": {"damage": 4, "aoe": 2, "control": 0, "stop": 1, "boss": 1}, "band": [2.8, 4.2], "heavy": 2},
	"control": {"w": {"control": 1.4, "run_stop": 1.25, "defense": 1.25, "damage": 0.85, "aoe": 0.9, "buff": 0.85},
		"need": {"damage": 2, "aoe": 1, "control": 3, "stop": 2, "boss": 1}, "band": [2.6, 4.0], "heavy": 1},
	"boss": {"w": {"boss": 1.8, "damage": 1.2, "aoe": 0.95, "buff": 1.05},
		"need": {"damage": 3, "aoe": 1, "control": 1, "stop": 1, "boss": 2}, "band": [2.8, 4.4], "heavy": 2},
}

static var _norm: Dictionary = {}     # "eff_<kind>" / "raw_<kind>" -> best level-1 value over every card


# ================================================================ context

## The player's collection and team, as DeckAI needs them.
static func profile_context() -> Dictionary:
	var owned: Array = []
	var levels := {}
	var mastery := {}
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned.append(cid)
			levels[cid] = Profile.card_level(cid)
			mastery[cid] = CardMastery.stars(cid)
	var team: Array = Profile.data.get("team", []).duplicate()
	var dlv := {}
	for d in team:
		dlv[d] = Profile.defender_level(d)
	return {"owned": owned, "levels": levels, "mastery": mastery, "team": team,
		"captain": str(Profile.data.get("captain", "")), "defender_levels": dlv}


static func _ctx_level(ctx: Dictionary, cid: String) -> int:
	return int(ctx.get("levels", {}).get(cid, 1))


# ================================================================ card analysis

## Everything DeckAI knows about one card at a level: values per kind, power, role and tags.
static func analyze(cid: String, level := 1) -> Dictionary:
	var c := DB.card(cid)
	if c.is_empty():
		return {}
	var v := _values(cid, level)
	var cost := maxf(1.0, float(c.get("cost", 1)))
	var cd := float(c.get("cooldown", 0))
	var spend := cost + cd / CD_PER_ENERGY
	var parts: Array = []
	for k in KINDS:
		var raw: float = v[k]
		if raw <= 0.0:
			continue
		var n := 0.65 * (raw / spend) / _norm_of("eff_" + k) + 0.35 * raw / _norm_of("raw_" + k)
		parts.append(n * float(KIND_SCALE[k]))
	parts.sort()
	parts.reverse()
	var pp := 0.0
	for i in parts.size():
		pp += float(parts[i]) * (1.0 if i == 0 else 0.4)
	pp = minf(pp, 15.0)
	var growth := 1.0 + DB.card_growth_rate * float(maxi(level, 1) - 1)
	var rarity_power := (4.0 + 1.5 * DB.rarity_index(str(c.get("rarity", "common")))) * growth
	var power := rarity_power if pp <= 0.01 else 0.75 * pp + 0.25 * rarity_power
	var tags := _tags(c, v)
	var role := str(c.get("role", ""))
	if not role in ROLES:
		role = _primary(v, tags)
	if not role in tags:
		tags.push_front(role)
	return {"id": cid, "level": level, "values": v, "power": power, "param_power": pp, "rarity_power": rarity_power,
		"spend": spend, "role": role, "tags": tags, "targets": v.targets, "cost": int(c.get("cost", 1)), "cooldown": cd}


## Roughly how many runners (or defenders) one cast reaches.
static func _targets(c: Dictionary, cid: String, level: int) -> float:
	var prm: Dictionary = c.get("params", {})
	match str(c.get("target", "none")):
		"enemy":
			return 1.0
		"path":
			return 2.0
		"defender":
			return 1.0
		"area":
			if prm.has("width") and prm.has("length"):
				return clampf(1.0 + DB.card_param(cid, "width", level) * DB.card_param(cid, "length", level) / 30.0, 1.0, 4.0)
			return clampf(1.0 + float(c.get("radius", 2.5)) * 0.5, 1.5, 4.0)
	if prm.has("targets"):
		return clampf(DB.card_param(cid, "targets", level), 1.0, 5.0)
	# Instant, no aiming: "every runner" / "all runners" cards hit the whole field, others one runner.
	var txt := (str(c.get("text", "")) + " " + str(c.get("details", ""))).to_lower()
	return 4.0 if ("every" in txt or "all " in txt) else 1.0


static func _frac(x: float) -> float:
	return x / 100.0 if x > 1.0 else x


## Value per kind, from params at `level`. Unknown params are ignored (the rarity baseline covers them).
static func _values(cid: String, level: int) -> Dictionary:
	var c := DB.card(cid)
	var prm: Dictionary = c.get("params", {})
	var p := func(k: String) -> float: return DB.card_param(cid, k, level) if prm.has(k) else 0.0
	var t := _targets(c, cid, level)
	var tgt := str(c.get("target", "none"))
	var hits := 1.0
	if prm.has("balls"):
		hits = maxf(1.0, p.call("balls") * 0.5)
	if prm.has("chains"):
		var f: float = p.call("falloff") if prm.has("falloff") else 0.8
		var extra := 0.0
		for i in int(p.call("chains")):
			extra += pow(f, i + 1)
		t = 1.0 + extra
	if prm.has("charges"):   # a trap: each charge catches one runner
		t = maxf(1.0, p.call("charges"))
	var dmg: float = p.call("damage") * t * hits
	dmg += p.call("burn_dps") * maxf(p.call("burn_time"), 1.0) * t
	dmg += p.call("percent") * 10.0 * t + p.call("threshold") * 400.0
	if prm.has("per_defender"):
		dmg *= 1.0 + p.call("per_defender") * 3.0
	var dur: float = p.call("duration")
	var ctl := 0.0
	ctl += _frac(p.call("slow")) * maxf(dur, maxf(p.call("slow_time"), 3.0)) * t
	ctl += (p.call("stun") * 1.5 + p.call("freeze") * 1.5 + p.call("root") * 1.2 + p.call("confuse")) * t * hits
	ctl += (p.call("pushback") + p.call("pull") + p.call("knockback")) / 3.0 * t + p.call("pull_time") * t
	ctl += _frac(p.call("vulnerability")) * maxf(dur, 3.0) * t * 2.0
	var def: float = p.call("hp") / 60.0 + p.call("shields") * 10.0 + p.call("home_bonus") * 3.0 + p.call("tag_time") * 0.8
	if str(c.get("category", "")) == "defense" and dur > 0.0 and not prm.has("slow"):
		def += dur * 0.8
	var reach: float = 6.0 if tgt == "none" else 1.0 + p.call("radius") * 0.4
	var bonus: float = _frac(p.call("damage_bonus")) + _frac(p.call("speed_bonus")) + _frac(p.call("range_bonus")) + p.call("chain_damage") * 0.5
	var buff: float = bonus * maxf(dur, 1.0) * reach + _frac(p.call("crit_bonus")) * maxf(dur, 1.0) * t
	var eco: float = p.call("energy") + p.call("draw") * 1.5
	var boss: float = p.call("boss_freeze") * 2.0 + p.call("boss_stun") * 2.0 + p.call("boss_percent") + p.call("percent") * 0.6
	return {"damage": dmg, "control": ctl, "defense": def, "buff": buff, "economy": eco, "boss": boss, "targets": t}


static func _tags(c: Dictionary, v: Dictionary) -> Array:
	var prm: Dictionary = c.get("params", {})
	var tags: Array = []
	if float(v.damage) >= 100.0:
		tags.append("damage")
		if float(v.targets) >= 1.8:
			tags.append("aoe")
	if float(v.control) > 0.0:
		tags.append("control")
	if str(c.get("target", "")) == "path" or float(v.defense) > 0.0 or prm.has("root"):
		tags.append("run_stop")
	if str(c.get("category", "")) == "defense":
		tags.append("defense")
	if float(v.boss) > 0.0:
		tags.append("boss")
	if float(v.buff) > 0.0:
		tags.append("buff")
	if float(v.economy) > 0.0:
		tags.append("economy")
	if str(c.get("role", "")) in ROLES and not str(c.role) in tags:
		tags.push_front(str(c.role))
	return tags


static func _primary(v: Dictionary, tags: Array) -> String:
	var best := ""
	var best_n := -1.0
	for k in KINDS:
		var n := float(v[k]) / _norm_of("raw_" + k)
		if n > best_n:
			best_n = n
			best = k
	if best_n <= 0.0:
		return "damage"
	match best:
		"damage":
			return "aoe" if "aoe" in tags else "damage"
		"defense":
			return "run_stop"
	return best


static func _norm_of(key: String) -> float:
	if _norm.is_empty():
		for cid in DB.card_order:
			var c := DB.card(cid)
			var v := _values(cid, 1)
			var spend := maxf(1.0, float(c.get("cost", 1))) + float(c.get("cooldown", 0)) / CD_PER_ENERGY
			for k in KINDS:
				_norm["raw_" + k] = maxf(float(_norm.get("raw_" + k, 0.0)), float(v[k]))
				_norm["eff_" + k] = maxf(float(_norm.get("eff_" + k, 0.0)), float(v[k]) / spend)
	return maxf(0.0001, float(_norm.get(key, 1.0)))


# ================================================================ scoring

## One card's own score in a deck (everything that doesn't depend on the other cards).
static func card_score(a: Dictionary, mode: String, ctx: Dictionary) -> float:
	var cfg: Dictionary = MODE_CFG.get(mode, MODE_CFG.balanced)
	var w := float(cfg.w.get(a.role, 1.0))
	if mode == "boss" and "boss" in a.tags:
		w = maxf(w, float(cfg.w.boss))
	if mode == "boss" and float(a.targets) <= 1.0 and "damage" in a.tags:
		w *= 1.25   # big single hits are what bosses fear
	var s := float(a.power) * w
	var linked := str(DB.card(a.id).get("linked", ""))
	if linked != "":
		if linked in ctx.get("team", []):
			s += SIG_BONUS + (CAPTAIN_BONUS if linked == str(ctx.get("captain", "")) else 0.0)
		else:
			s = s * ABSENT_LINK_POWER - ABSENT_LINK_PENALTY
	if "buff" in a.tags:   # buffs scale with the defenders they boost
		var lv := 0.0
		var dl: Dictionary = ctx.get("defender_levels", {})
		for d in dl.keys():
			lv += float(dl[d])
		if not dl.is_empty():
			s += 0.15 * (lv / dl.size() - 1.0)
	s += 0.25 * float(int(a.level) - 1) + 0.15 * float(ctx.get("mastery", {}).get(a.id, 0))
	return s


static func _count(info: Dictionary, deck: Array) -> Dictionary:
	var n := {"damage": 0, "aoe": 0, "control": 0, "stop": 0, "boss": 0, "economy": 0, "buff": 0, "heavy": 0, "cheap": 0, "cost": 0}
	for cid in deck:
		var a: Dictionary = info[cid]
		var tg: Array = a.tags
		if "damage" in tg or "aoe" in tg:
			n.damage += 1
		if "aoe" in tg:
			n.aoe += 1
		if "control" in tg:
			n.control += 1
		if "run_stop" in tg or "defense" in tg:
			n.stop += 1
		if "boss" in tg:
			n.boss += 1
		if a.role == "economy":
			n.economy += 1
		if a.role == "buff":
			n.buff += 1
		if int(a.cost) >= 6:
			n.heavy += 1
		if int(a.cost) <= 2:
			n.cheap += 1
		n.cost += int(a.cost)
	return n


## The whole deck's score, split into parts (used for the explanation and the tests).
static func deck_score(deck: Array, info: Dictionary, mode: String, ctx: Dictionary, avail: Dictionary) -> Dictionary:
	var cfg: Dictionary = MODE_CFG.get(mode, MODE_CFG.balanced)
	var cards := 0.0
	for cid in deck:
		cards += float(info[cid].score)
	var combos := 0.0
	var team: Array = ctx.get("team", [])
	for cb in DB.combos:
		if cb.cards[0] in deck and cb.cards[1] in deck:
			combos += COMBO_BONUS
			for x in cb.cards:
				if str(DB.card(x).get("linked", "")) in team and str(DB.card(x).get("linked", "")) != "":
					combos += 0.5
					break
	var n := _count(info, deck)
	var cover := 0.0
	for k in cfg.need.keys():
		var want := mini(int(cfg.need[k]), int(avail.get(k, 0)))
		cover -= MISSING_PENALTY * maxi(0, want - int(n[k]))
	cover -= 3.0 * maxi(0, int(n.economy) - 1)
	cover -= 2.5 * maxi(0, int(n.buff) - (3 if mode == "aggressive" else 2))
	var curve := 0.0
	if not deck.is_empty():
		var avg := float(n.cost) / deck.size()
		var band: Array = cfg.band
		var off := maxf(0.0, float(band[0]) - avg) + maxf(0.0, avg - float(band[1]))
		# Steep: half an energy over the band costs about one strong card's worth, so a big pool of
		# expensive Legendaries can't push the deck into a hand you can't afford to play.
		curve -= 18.0 * off * float(deck.size()) / Profile.DECK_SIZE   # partial decks (greedy) count less
		curve -= 8.0 * maxi(0, int(n.heavy) - int(cfg.get("heavy", 2)))
		if deck.size() >= Profile.DECK_SIZE and int(n.cheap) == 0 and int(avail.get("cheap", 0)) > 0:
			curve -= 2.0
	return {"total": cards + combos + cover + curve, "cards": cards, "combos": combos, "coverage": cover, "curve": curve, "counts": n}


# ================================================================ build

## Builds the best deck. `ctx` defaults to the player's profile (profile_context()).
## Returns {deck, mode, summary, reasons: {id: [[chip, sentence]...]}, missing, avg_cost, combos, signatures, score}.
static func build(mode := "balanced", ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty():
		ctx = profile_context()
	if not mode in MODES:
		mode = "balanced"
	var owned: Array = []
	for cid in DB.card_order:   # DB order: stable, valid, no duplicates
		if cid in ctx.get("owned", []) and not cid in owned:
			owned.append(cid)
	var info := {}
	for cid in owned:
		var a := analyze(cid, _ctx_level(ctx, cid))
		a["score"] = card_score(a, mode, ctx)
		info[cid] = a
	var avail := _count(info, owned)
	var size := mini(Profile.DECK_SIZE, owned.size())
	var deck: Array = []
	# Greedy: add the card that raises the deck score the most.
	while deck.size() < size:
		var best := ""
		var best_s := -INF
		for cid in owned:
			if cid in deck:
				continue
			var s := float(deck_score(deck + [cid], info, mode, ctx, avail).total)
			if s > best_s + 0.000001:
				best_s = s
				best = cid
		deck.append(best)
	# Local search: best single swap until nothing improves.
	var cur := float(deck_score(deck, info, mode, ctx, avail).total)
	for it in 30:
		var best_i := -1
		var best_c := ""
		var best_s := cur
		for i in deck.size():
			for cid in owned:
				if cid in deck:
					continue
				var trial := deck.duplicate()
				trial[i] = cid
				var s := float(deck_score(trial, info, mode, ctx, avail).total)
				if s > best_s + 0.0001:
					best_s = s
					best_i = i
					best_c = cid
		if best_i < 0:
			break
		deck[best_i] = best_c
		cur = best_s
	# Show the deck cheapest first, like a hand curve.
	deck.sort_custom(func(x: String, y: String) -> bool:
		var cx := int(info[x].cost)
		var cy := int(info[y].cost)
		return cx < cy if cx != cy else DB.card_order.find(x) < DB.card_order.find(y))
	return _explain(deck, info, mode, ctx, avail)


static func _explain(deck: Array, info: Dictionary, mode: String, ctx: Dictionary, avail: Dictionary) -> Dictionary:
	var cfg: Dictionary = MODE_CFG.get(mode, MODE_CFG.balanced)
	var sc := deck_score(deck, info, mode, ctx, avail)
	var n: Dictionary = sc.counts
	var team: Array = ctx.get("team", [])
	var combos: Array = []
	for cb in DB.combos:
		if cb.cards[0] in deck and cb.cards[1] in deck:
			combos.append(cb)
	var sigs: Array = []
	for cid in deck:
		var l := str(DB.card(cid).get("linked", ""))
		if l != "" and l in team:
			sigs.append(cid)
	# Ranking by own score, for "one of your strongest" reasons.
	var ranked := deck.duplicate()
	ranked.sort_custom(func(x: String, y: String) -> bool: return float(info[x].power) > float(info[y].power))
	var reasons := {}
	for cid in deck:
		var a: Dictionary = info[cid]
		var r: Array = []
		var l := str(DB.card(cid).get("linked", ""))
		if l != "" and l in team:
			r.append(["SIGNATURE", "Signature of %s, who is on your team: full power%s." % [DB.defender(l).name,
				" (your captain)" if l == str(ctx.get("captain", "")) else ""]])
		elif l != "":
			r.append(["NO " + str(DB.defender(l).get("name", l)).to_upper(), "%s isn't on your team, so it casts at 75 %% power. Picked anyway: few better options." % DB.card(cid).name])
		if "boss" in a.tags and int(n.boss) <= 2:
			r.append(["BOSS", "Answers bosses (boss stun, freeze or max-health damage)%s." % (": the only one in the deck" if int(n.boss) == 1 else "")])
		if "aoe" in a.tags and int(n.aoe) <= 2:
			r.append(["AOE", "Hits a crowd: about %.0f runners per cast." % float(a.targets)])
		if ("run_stop" in a.tags or "defense" in a.tags) and int(n.stop) <= 2:
			r.append(["RUN-STOP", "Stops runners before they score."])
		if "control" in a.tags and int(n.control) <= 2 and a.role == "control":
			r.append(["CONTROL", "Slows or holds runners in your defenders' range."])
		if a.role == "economy":
			r.append(["ECONOMY", "Gives energy or cards back."])
		if a.role == "buff":
			r.append(["BUFF", "Boosts your defenders."])
		for cb in combos:
			if cid in cb.cards:
				var other: String = cb.cards[0] if cb.cards[1] == cid else cb.cards[1]
				r.append(["COMBO", "Combo with %s: %s" % [DB.card(other).name, cb.text]])
		if ranked.find(cid) < 3:
			r.append(["POWER %.1f" % float(a.power), "One of your strongest cards (power %.1f at level %d)." % [float(a.power), int(a.level)]])
		if int(a.cost) <= 2:
			r.append(["CHEAP", "Costs %d: keeps the curve low and the hand moving." % int(a.cost)])
		if r.is_empty():
			r.append([ROLE_NAMES.get(a.role, "Card").to_upper(), "%s · power %.1f at level %d." % [ROLE_NAMES.get(a.role, "Card"), float(a.power), int(a.level)]])
		reasons[cid] = r
	# Summary line.
	var covered: Array = []
	for pair in [["aoe", "AoE"], ["control", "control"], ["stop", "run-stop"], ["boss", "boss"], ["economy", "economy"]]:
		if int(n[pair[0]]) > 0:
			covered.append(pair[1])
	var missing: Array = []
	var miss_names := {"damage": "damage", "aoe": "AoE damage", "control": "control", "stop": "a run-stopper", "boss": "a boss answer"}
	for k in ["damage", "aoe", "control", "stop", "boss"]:
		if int(n[k]) == 0 and int(cfg.need.get(k, 0)) > 0:
			missing.append(str(miss_names[k]) + (" (none owned)" if int(avail.get(k, 0)) == 0 else ""))
	var avg := float(n.cost) / maxf(1.0, deck.size())
	var parts: Array = []
	if not covered.is_empty():
		parts.append("Covers " + " + ".join(covered))
	parts.append("avg cost %.1f" % avg)
	parts.append("%d combo%s" % [combos.size(), "" if combos.size() == 1 else "s"])
	if sigs.size() == 1:
		var dl := str(DB.card(sigs[0]).linked)
		parts.append("signature %s (%s is on your team)" % [DB.card(sigs[0]).name, DB.defender(dl).name])
	elif sigs.size() > 1:
		var names: Array = []
		for s in sigs:
			names.append(str(DB.card(s).name))
		parts.append("%d signatures (%s)" % [sigs.size(), ", ".join(names)])
	var summary := " · ".join(parts)
	if not missing.is_empty():
		summary += " · missing " + ", ".join(missing)
	if deck.size() < Profile.DECK_SIZE:
		summary += " · you own only %d cards" % deck.size()
	return {"deck": deck, "mode": mode, "summary": summary, "reasons": reasons, "missing": missing, "avg_cost": avg,
		"combos": combos, "signatures": sigs, "score": float(sc.total), "parts": sc, "counts": n}


## Short role tags for a card ("AoE", "Boss" ...) at a level, for the compare panel and tooltips.
static func role_tags(cid: String, level := 1) -> Array:
	var a := analyze(cid, level)
	var out: Array = []
	for t in a.get("tags", []):
		var nm: String = ROLE_NAMES.get(t, str(t))
		if not nm in out:
			out.append(nm)
	return out
