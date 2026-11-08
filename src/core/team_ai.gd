class_name TeamAI
extends RefCounted
## Best Team: picks the strongest starting six and captain from the unlocked defenders, and explains why.
## Static, in the style of DeckAI. Everything comes from data (defenders.json stats, traits, roles and
## synergies, gear.json, the formation slots) plus a small table of what each trait is worth.
##
##   team score = Σ defender score + synergies + captain aura
##   defender   = (damage · w_dmg + crowd · w_crowd + boss · w_boss + control · w_ctrl + team boost) / 4
##                + signature card (owned: +0.8; in the deck: +3 and its power back from 75 % to 100 %)
##   damage     = damage × (1 + level, gear, traits, zone) / interval × (1 + speed bonuses)
##                × crits × accuracy × √(range / 11) × the trait's damage factor
##   crowd      = damage × extra runners hit (trait splash / chains / skips, Double-Play Duo ricochet)
##   boss       = damage × the trait's boss factor × (1 + boss damage from the Clutch / Armor Breaker traits)
##                × (1 + armor ignored × 0.5; bosses and captains wear the most armor)
##   level      = DefenderLevels.growth: +6 % per level to 10, then +3 % per level to 20 (Update 11);
##                training traits from all five tiers (levels 3, 6, 9, 12, 16) count through the mods
##   control    = the trait's slow / stun / knock-back value, in damage units
##   team boost = auras that make everyone hit harder (Home Guard, Long Stretch, Pitch Framing)
##   zone       = the battle's position bonus, when the formation puts the defender in a slot of their role
##   synergies  = the battle's own rules (roles, distances in the formation): Battery and Outfield Wall
##                through the stats, Full Squad +4, Fire and Ice +2
##   captain    = the battle's aura: +8 % damage to team-mates within 6 m of the captain's post
##
## Rules kept (the same ones Profile and the battle enforce): at most six (six when six are unlocked),
## no duplicates, unlocked defenders only, and the captain is in the team. There is no hard role rule;
## role coverage is scored through the formation slots, zone bonuses and synergies.
##
## Search: every combination of six from the unlocked defenders (12 defenders = 924 teams), each with
## its best captain. Candidates are visited in DB.defender_order, the current team first, and only a
## strictly higher score replaces the best, so the result is deterministic and never churns on a tie.

const MODES := ["balanced", "damage", "control", "boss"]
const MODE_NAMES := {"balanced": "Balanced", "damage": "Damage", "control": "Control", "boss": "Boss Killer"}
const MODE_TEXT := {
	"balanced": "Damage, crowd control and a boss answer, with every position covered.",
	"damage": "The most damage per second and the widest splash. Clears waves fast.",
	"control": "Slows, stuns and auras first. Keeps runners off the bases.",
	"boss": "Single-target power, armor piercing and boss damage. Built to take down bosses.",
}
## Component weights per mode.
const MODE_W := {
	"balanced": {"dmg": 1.0, "crowd": 0.6, "boss": 0.4, "ctrl": 1.0, "amp": 1.0, "amp_boss": 0.4},
	"damage": {"dmg": 1.3, "crowd": 0.9, "boss": 0.3, "ctrl": 0.35, "amp": 1.0, "amp_boss": 0.3},
	"control": {"dmg": 0.7, "crowd": 0.5, "boss": 0.2, "ctrl": 2.2, "amp": 0.8, "amp_boss": 0.2},
	"boss": {"dmg": 0.6, "crowd": 0.15, "boss": 1.4, "ctrl": 0.4, "amp": 1.0, "amp_boss": 1.2},
}
## What each trait is worth. dmg / boss = damage factors, crowd = extra runners hit per throw (as a share
## of a throw), ctrl = control in damage units per second, amp = extra damage the whole team deals,
## amp_boss = extra damage on the one runner it marks (counts with the mode's boss weight).
const TRAITS := {
	"fastball": {"dmg": 1.25, "boss": 1.25, "crowd": 0.05, "ctrl": 0.0, "why": "every 4th throw is a double-damage fastball that burns"},
	"home_guard": {"dmg": 1.0, "boss": 1.0, "crowd": 0.0, "ctrl": 9.0, "amp": 0.04, "why": "slows runners near home and makes them take +10 % damage"},
	"quick_hands": {"dmg": 1.3, "boss": 0.9, "crowd": 0.25, "ctrl": 1.0, "why": "second throws and dash-tags"},
	"cannon_arm": {"dmg": 1.1, "boss": 1.3, "crowd": 0.0, "ctrl": 4.0, "why": "throws ignore 60 % of armor and knock runners back"},
	"precision": {"dmg": 1.2, "boss": 1.25, "crowd": 0.0, "ctrl": 0.0, "why": "+50 % damage at long range, 2.5× crits"},
	"heavy_hitter": {"dmg": 1.0, "boss": 1.0, "crowd": 0.5, "ctrl": 6.0, "why": "splash damage and short stuns"},
	"static_charge": {"dmg": 1.0, "boss": 0.95, "crowd": 0.5, "ctrl": 0.0, "why": "every throw arcs to a second runner"},
	"pickoff_artist": {"dmg": 1.15, "boss": 1.05, "crowd": 0.0, "ctrl": 0.0, "why": "double damage to hurt runners"},
	"gap_shooter": {"dmg": 1.12, "boss": 0.95, "crowd": 0.0, "ctrl": 0.0, "why": "+40 % damage to Sprinters, Jumpers and fliers"},
	"long_stretch": {"dmg": 1.0, "boss": 1.0, "crowd": 0.0, "ctrl": 6.0, "amp": 0.07, "why": "runners near him are slower and take +25 % damage"},
	"pitch_framing": {"dmg": 1.0, "boss": 1.0, "crowd": 0.0, "ctrl": 2.0, "amp": 0.05, "amp_boss": 0.3, "why": "frames the most dangerous runner: +35 % damage from everyone"},
	"skipper": {"dmg": 1.0, "boss": 0.95, "crowd": 0.6, "ctrl": 0.0, "why": "after a hit the ball skips on into a second runner"},
}
const CRIT_MULT := 1.75
const CRIT_MULT_PRECISION := 2.5
const PIERCE_DMG := 0.15           # armor ignored: worth this much damage on ordinary waves (armored runners)…
const PIERCE_BOSS := 0.5           # …and this much against bosses and captains
const SCALE := 4.0                 # damage units per score point
const ZONE_BONUS := {"pitcher": {"damage": 0.20, "throw_speed": 0.15}, "catcher": {"damage": 0.15},
	"infielder": {"attack_speed": 0.15}, "outfielder": {"range": 0.20}}
const CAPTAIN_RADIUS := 6.0
const CAPTAIN_BONUS := 0.08
const FULL_SQUAD_BONUS := 4.0
const FIRE_ICE_BONUS := 2.0
const SIG_OWNED := 0.8
const SIG_IN_DECK := 3.0
const EPS := 0.0001
## A typical six's damage per second besides the defender (5 × ~45): what a team boost is worth on its own.
const TEAM_DPS_EST := 225.0


# ================================================================ context

## The player's defenders, levels, gear and traits, deck and formation, as TeamAI needs them.
static func profile_context() -> Dictionary:
	var unlocked: Array = []
	var levels := {}
	var mods := {}
	for id in DB.defender_order:
		levels[id] = Profile.defender_level(id)
		mods[id] = Profile.defender_mods(id)
		if Profile.is_defender_unlocked(id):
			unlocked.append(id)
	var owned: Array = []
	var card_levels := {}
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned.append(cid)
			card_levels[cid] = Profile.card_level(cid)
	return {"unlocked": unlocked, "levels": levels, "mods": mods, "owned_cards": owned, "card_levels": card_levels,
		"deck": Profile.data.get("deck", []).duplicate(), "team": Profile.data.get("team", []).duplicate(),
		"captain": str(Profile.data.get("captain", "")), "formation": str(Profile.data.get("formation", "balanced"))}


## Level-only modifiers (what Profile.defender_mods gives with no gear or traits).
static func level_mods(level: int) -> Dictionary:
	var g := DefenderLevels.growth(level)
	return {"damage": g, "range": 0.0, "attack_speed": 0.0, "throw_speed": 0.0, "accuracy": 0.0,
		"crit": 0.0, "special_power": g, "special_cooldown": 0.0, "boss_damage": 0.0, "stun_guard": 0}


static func _mods(ctx: Dictionary, id: String) -> Dictionary:
	var m: Variant = ctx.get("mods", {}).get(id, null)
	if typeof(m) == TYPE_DICTIONARY:
		return m
	return level_mods(int(ctx.get("levels", {}).get(id, 1)))


static func _level(ctx: Dictionary, id: String) -> int:
	return int(ctx.get("levels", {}).get(id, 1))


## The defenders the context allows, in DB order, without duplicates or unknown ids.
static func available(ctx: Dictionary) -> Array:
	var out: Array = []
	for id in DB.defender_order:
		if id in ctx.get("unlocked", []) and not id in out:
			out.append(id)
	return out


# ================================================================ formation

## Posts for a team in a formation, the way Battle.formation_positions assigns them (role slots first,
## then any slot left). Custom formations use their stored positions; unknown ones fall back to Balanced.
static func positions(formation_id: String, team: Array) -> Dictionary:
	var raw: Array = []
	var cf: Dictionary = Profile.data.get("custom_formations", {}).get(formation_id, {}) if not DB.formations.has(formation_id) else {}
	var by_id: Dictionary = cf.get("by_id", {})
	if not by_id.is_empty():
		var rest := positions("balanced", team)
		var out := {}
		for id in team:
			out[id] = Vector3(float(by_id[id][0]), 0, float(by_id[id][1])) if by_id.has(id) else rest[id]
		return out
	raw = cf.get("positions", [])
	if raw.size() < DB.formation_slots.size():
		raw = DB.formations.get(formation_id, DB.formations.balanced).positions
	var slots: Array = DB.formation_slots
	var assigned := {}
	var used := []
	for pass_i in 2:
		for id in team:
			if assigned.has(id):
				continue
			var role: String = DB.defender(id).role
			for s in slots.size():
				if s in used:
					continue
				if pass_i == 1 or slots[s] == role:
					assigned[id] = Vector3(float(raw[s][0]), 0, float(raw[s][1]))
					used.append(s)
					break
	return assigned


static func _in_position(id: String, post: Vector3) -> bool:
	return Field.zone_at(post) == str(DB.roles.get(DB.defender(id).role, {}).get("zone", ""))


## Active synergies for a team at its posts: [{data, members}], with the battle's rules.
static func synergies(team: Array, posts: Dictionary) -> Array:
	var out: Array = []
	for syn in DB.synergies:
		var req: Dictionary = syn.requires
		var members: Array = []
		var ok := true
		if req.has("roles"):
			for role in req.roles.keys():
				var have: Array = []
				for id in team:
					if DB.defender(id).role == role:
						if str(syn.get("effect", {}).get("zone", "")) != "" and Field.zone_at(posts.get(id, Vector3.ZERO)) != str(syn.effect.zone):
							continue
						have.append(id)
				if have.size() < int(req.roles[role]):
					ok = false
					break
				members.append_array(have)
		if ok and req.has("ids"):
			for id in req.ids:
				if id in team:
					members.append(id)
				else:
					ok = false
		if not ok:
			continue
		var within := float(syn.get("within", 0.0))
		if within > 0.0:
			var close: Array = []
			for a in members:
				for b in members:
					if a != b and (DB.defender(a).role != DB.defender(b).role or syn.id == "double_play_duo"):
						if Field.v2(posts.get(a, Vector3.ZERO)).distance_to(Field.v2(posts.get(b, Vector3.ZERO))) <= within:
							if not a in close:
								close.append(a)
			if close.size() < 2:
				continue
			members = close
		out.append({"data": syn, "members": members})
	return out


# ================================================================ one defender

## What one defender is worth. `in_pos` = standing in a slot of their role; `syn` = the bonuses the team's
## synergies give them ({attack_speed, range, ricochet}).
static func rate(id: String, ctx: Dictionary, mode := "balanced", in_pos := true, syn := {}) -> Dictionary:
	var d := DB.defender(id)
	if d.is_empty():
		return {}
	var w: Dictionary = MODE_W.get(mode, MODE_W.balanced)
	var st: Dictionary = d.stats
	var pm := _mods(ctx, id)
	var role := str(d.role)
	var dmg_b := float(pm.get("damage", 0.0))
	var spd_b := float(pm.get("attack_speed", 0.0)) + float(syn.get("attack_speed", 0.0))
	var rng_b := float(pm.get("range", 0.0)) + float(syn.get("range", 0.0))
	if in_pos:
		var zb: Dictionary = ZONE_BONUS.get(role, {})
		dmg_b += float(zb.get("damage", 0.0))
		spd_b += float(zb.get("attack_speed", 0.0))
		rng_b += float(zb.get("range", 0.0))
	var tid := str(d.get("trait", {}).get("id", ""))
	var tr: Dictionary = TRAITS.get(tid, {})
	var damage := float(st.damage) * (1.0 + dmg_b)
	var interval := float(st.interval) / (1.0 + spd_b)
	var rng := float(st.range) * (1.0 + rng_b)
	var acc := clampf(float(st.accuracy) + float(pm.get("accuracy", 0.0)), 0.0, 100.0)
	var crit := clampf(0.05 + (acc - 50.0) * 0.002 + float(pm.get("crit", 0.0)), 0.0, 0.8)
	var cm := (CRIT_MULT_PRECISION if tid == "precision" else CRIT_MULT) + float(pm.get("crit_damage", 0.0))
	var pierce := clampf(float(pm.get("pierce", 0.0)), 0.0, 1.0)
	var dps := damage / maxf(interval, 0.05) * (1.0 + crit * (cm - 1.0)) * (0.75 + 0.25 * acc / 100.0)
	var reach := sqrt(rng / 11.0)
	var eff := dps * reach * float(tr.get("dmg", 1.0)) * (1.0 + PIERCE_DMG * pierce)
	var crowd := dps * reach * (float(tr.get("crowd", 0.0)) + float(syn.get("ricochet", 0.0)))
	var boss := dps * reach * float(tr.get("boss", 1.0)) * (1.0 + float(pm.get("boss_damage", 0.0))) * (1.0 + PIERCE_BOSS * pierce)
	var ctrl := float(tr.get("ctrl", 0.0)) * reach
	var own := (eff * float(w.dmg) + crowd * float(w.crowd) + boss * float(w.boss) + ctrl * float(w.ctrl)) / SCALE
	var sig := signature_value(id, ctx)
	return {"id": id, "level": _level(ctx, id), "role": role, "in_position": in_pos, "damage": damage, "interval": interval,
		"range": rng, "accuracy": acc, "crit": crit, "dps": dps, "eff": eff, "crowd": crowd, "boss": boss, "control": ctrl,
		"amp": float(tr.get("amp", 0.0)), "amp_boss": float(tr.get("amp_boss", 0.0)),
		"boss_v": boss + float(tr.get("amp_boss", 0.0)) * TEAM_DPS_EST, "crowd_v": crowd + float(tr.get("amp", 0.0)) * TEAM_DPS_EST * 0.5, "own": own, "signature": sig,
		"score": own + sig, "trait": tid}


## Signature card value: owned +0.8; in the deck +3 plus the quarter of its power the card loses
## when its defender is missing.
static func signature_value(id: String, ctx: Dictionary) -> float:
	var sig := str(DB.defender(id).get("signature", ""))
	if sig == "" or not sig in ctx.get("owned_cards", []):
		return 0.0
	if not sig in ctx.get("deck", []):
		return SIG_OWNED
	var lvl := int(ctx.get("card_levels", {}).get(sig, 1))
	var sp := float(_mods(ctx, id).get("special_power", 0.0))
	return SIG_IN_DECK + 0.25 * float(DeckAI.analyze(sig, lvl).get("power", 0.0)) * (1.0 + sp)


## A defender on their own (in their position, no synergies): the number the compare panel shows.
static func defender_score(id: String, ctx: Dictionary = {}, mode := "balanced") -> float:
	if ctx.is_empty():
		ctx = profile_context()
	return float(rate(id, ctx, mode).get("score", 0.0))


# ================================================================ team

## Scores a team. `captain` "" = pick the best captain. Returns {total, captain, rows: {id: rate},
## synergies: [ids], syn_score, aura, aura_targets, amp_score, posts}.
static func team_score(team: Array, ctx: Dictionary, mode := "balanced", captain := "") -> Dictionary:
	var w: Dictionary = MODE_W.get(mode, MODE_W.balanced)
	var posts := positions(str(ctx.get("formation", "balanced")), team)
	var syns := synergies(team, posts)
	var bonus := {}
	var syn_ids: Array = []
	var syn_members := {}
	var syn_score := 0.0
	for s in syns:
		var eff: Dictionary = s.data.effect
		syn_ids.append(str(s.data.id))
		syn_members[str(s.data.id)] = s.members
		match str(s.data.id):
			"full_squad":
				syn_score += FULL_SQUAD_BONUS
			"fire_and_ice":
				syn_score += FIRE_ICE_BONUS
		for id in team:
			if str(eff.get("scope", "team")) == "members" and not id in s.members:
				continue
			var b: Dictionary = bonus.get(id, {})
			for k in ["attack_speed", "range", "ricochet"]:
				if eff.has(k):
					b[k] = float(b.get(k, 0.0)) + float(eff[k])
			bonus[id] = b
	var rows := {}
	var total := 0.0
	var dmg_sum := 0.0
	for id in team:
		var r := rate(id, ctx, mode, _in_position(id, posts.get(id, Vector3.ZERO)), bonus.get(id, {}))
		rows[id] = r
		total += float(r.score)
		dmg_sum += float(r.eff) * float(w.dmg) + float(r.boss) * float(w.boss)
	# Team boosts: an aura that makes everyone hit harder is worth a share of the team's damage.
	var amp_score := 0.0
	var boss_sum := 0.0
	for id in team:
		boss_sum += float(rows[id].boss)
	for id in team:
		amp_score += float(rows[id].amp) * float(w.amp) * dmg_sum / SCALE
		amp_score += float(rows[id].amp_boss) * float(w.amp_boss) * boss_sum / SCALE / 2.0
	# Captain aura.
	var best_c := ""
	var best_a := -1.0
	var best_t: Array = []
	var order: Array = []
	if captain != "" and captain in team:
		order = [captain]
	else:
		var cur := str(ctx.get("captain", ""))
		if cur in team:
			order.append(cur)   # the current captain wins ties
		for id in team:
			if not id in order:
				order.append(id)
	for c in order:
		var a := 0.0
		var tg: Array = []
		for id in team:
			if id != c and Field.v2(posts.get(id, Vector3.ZERO)).distance_to(Field.v2(posts.get(c, Vector3.ZERO))) <= CAPTAIN_RADIUS:
				a += CAPTAIN_BONUS * float(rows[id].own)
				tg.append(id)
		if a > best_a + EPS:
			best_a = a
			best_c = c
			best_t = tg
	total += syn_score + amp_score + maxf(best_a, 0.0)
	return {"total": total, "captain": best_c, "rows": rows, "synergies": syn_ids, "syn_members": syn_members, "syn_score": syn_score,
		"aura": maxf(best_a, 0.0), "aura_targets": best_t, "amp_score": amp_score, "posts": posts}


## Whether a team follows the game's team rules for this context.
static func is_valid(team: Array, captain: String, ctx: Dictionary) -> bool:
	var avail := available(ctx)
	if team.is_empty() or team.size() != mini(Profile.TEAM_SIZE, avail.size()) or not captain in team:
		return false
	var seen := {}
	for id in team:
		if seen.has(id) or not id in avail:
			return false
		seen[id] = true
	return true


# ================================================================ build

## Finds the best team. `ctx` defaults to the player's profile (profile_context()).
## Returns {team, captain, mode, score, current_score, current_valid, ins, outs, captain_changed,
## already_best, reasons: {id: [[chip, sentence]...]}, summary, synergies, parts}.
static func best_team(mode := "balanced", ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty():
		ctx = profile_context()
	if not mode in MODES:
		mode = "balanced"
	var avail := available(ctx)
	var n := mini(Profile.TEAM_SIZE, avail.size())
	var current: Array = []
	for id in ctx.get("team", []):
		if id in avail and not id in current:
			current.append(id)
	var cur_valid := current.size() == n and n > 0
	var cur_score := -INF
	var best: Array = []
	var best_s := -INF
	var best_r := {}
	if cur_valid:
		var cs := team_score(current, ctx, mode)
		cur_score = float(team_score(current, ctx, mode, str(ctx.get("captain", ""))).total) if str(ctx.get("captain", "")) in current else float(cs.total)
		best = current.duplicate()
		best_s = float(cs.total)
		best_r = cs
	elif not current.is_empty():
		cur_score = float(team_score(current, ctx, mode).total)
	if n > 0:
		for combo in _combinations(avail, n):
			var r := team_score(combo, ctx, mode)
			if float(r.total) > best_s + EPS:
				best_s = float(r.total)
				best = combo
				best_r = r
	if best.is_empty():
		return {"team": [], "captain": "", "mode": mode, "score": 0.0, "current_score": 0.0, "current_valid": false,
			"ins": [], "outs": [], "captain_changed": false, "already_best": true, "reasons": {}, "summary": "No defenders unlocked.",
			"synergies": [], "parts": {}}
	# Show the team in formation-slot order (pitcher, catcher, infield, outfield), current members first on ties.
	var ordered := _slot_order(best, current)
	var ins: Array = []
	var outs: Array = []
	for id in ordered:
		if not id in current:
			ins.append(id)
	for id in current:
		if not id in ordered:
			outs.append(id)
	var cap := str(best_r.captain)
	var same := ins.is_empty() and outs.is_empty() and cur_valid
	var cap_changed := cap != str(ctx.get("captain", ""))
	# On the same six, keep the player's captain unless the best one is strictly better.
	if same and cap_changed and float(best_r.total) <= cur_score + EPS:
		cap = str(ctx.get("captain", ""))
		cap_changed = false
	var final_r := team_score(ordered, ctx, mode, cap)
	var reasons := _explain(ordered, cap, final_r, ctx, mode)
	var already := same and not cap_changed
	return {"team": ordered, "captain": cap, "mode": mode, "score": float(final_r.total),
		"current_score": cur_score if cur_score > -INF else 0.0, "current_valid": cur_valid, "ins": ins, "outs": outs,
		"captain_changed": cap_changed, "already_best": already, "reasons": reasons,
		"summary": _summary(ordered, cap, final_r, mode), "synergies": final_r.synergies, "parts": final_r}


## All combinations of `k` from `items`, in order.
static func _combinations(items: Array, k: int) -> Array:
	var out: Array = []
	var idx: Array = []
	for i in k:
		idx.append(i)
	var n := items.size()
	if k > n or k <= 0:
		return out
	while true:
		var c: Array = []
		for i in idx:
			c.append(items[i])
		out.append(c)
		var j := k - 1
		while j >= 0 and int(idx[j]) == n - k + j:
			j -= 1
		if j < 0:
			break
		idx[j] = int(idx[j]) + 1
		for m in range(j + 1, k):
			idx[m] = int(idx[m - 1]) + 1
	return out


static func _slot_order(team: Array, current: Array) -> Array:
	var role_i := {"pitcher": 0, "catcher": 1, "infielder": 2, "outfielder": 3}
	var out := team.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(role_i.get(DB.defender(a).role, 9))
		var rb := int(role_i.get(DB.defender(b).role, 9))
		if ra != rb:
			return ra < rb
		var ca := current.find(a)
		var cb := current.find(b)
		if (ca >= 0) != (cb >= 0):
			return ca >= 0
		if ca >= 0 and ca != cb:
			return ca < cb
		return DB.defender_order.find(a) < DB.defender_order.find(b))
	return out


static func _name(id: String) -> String:
	return str(DB.defender(id).get("name", id))


static func _syn_name(sid: String) -> String:
	for s in DB.synergies:
		if str(s.id) == sid:
			return str(s.name)
	return sid


## Reasons per pick: [[CHIP, sentence], ...], strongest first.
static func _explain(team: Array, captain: String, r: Dictionary, ctx: Dictionary, mode: String) -> Dictionary:
	var rows: Dictionary = r.rows
	var by_dps := team.duplicate()
	by_dps.sort_custom(func(a: String, b: String) -> bool: return float(rows[a].eff) > float(rows[b].eff))
	var by_boss := team.duplicate()
	by_boss.sort_custom(func(a: String, b: String) -> bool: return float(rows[a].boss) > float(rows[b].boss))
	var out := {}
	for id in team:
		var row: Dictionary = rows[id]
		var d := DB.defender(id)
		var tr: Dictionary = TRAITS.get(str(row.trait), {})
		var list: Array = []
		if id == captain:
			var names: Array = []
			for t in r.aura_targets:
				names.append(_name(t))
			list.append(["CAPTAIN", "Captain: the +8 %% aura reaches %s." % (", ".join(names) if not names.is_empty() else "no one in this formation")])
		if by_dps.find(id) == 0:
			list.append(["TOP DAMAGE", "%s: highest damage at Lv %d (%.0f per second)." % [_name(id), int(row.level), float(row.eff)]])
		elif by_dps.find(id) <= 2:
			list.append(["DAMAGE", "%s: %.0f damage per second at Lv %d." % [_name(id), float(row.eff), int(row.level)]])
		if mode == "boss" and by_boss.find(id) <= 1:
			list.append(["BOSS", "%s: one of the best boss hitters (%.0f per second on bosses)." % [_name(id), float(row.boss)]])
		if float(tr.get("crowd", 0.0)) >= 0.25:
			list.append(["CROWD", "%s: %s." % [d.trait.name, str(tr.why)]])
		if float(tr.get("ctrl", 0.0)) >= 4.0 or float(tr.get("amp", 0.0)) > 0.0:
			list.append(["CONTROL" if float(tr.get("amp", 0.0)) == 0.0 else "TEAM BOOST", "%s: %s." % [d.trait.name, str(tr.why)]])
		for sid in r.syn_members.keys():
			if str(sid) == "full_squad" or not id in r.syn_members[sid]:
				continue
			var others: Array = []
			for o in r.syn_members[sid]:
				if o != id and not _name(o) in others:
					others.append(_name(o))
			if not others.is_empty():
				list.append(["SYNERGY", "%s + %s: %s." % [_name(id), " + ".join(others), _syn_name(str(sid))]])
		if bool(row.in_position):
			list.append(["POSITION", "%s: %s." % [str(DB.roles[d.role].name), str(DB.roles[d.role].bonus_text)]])
		var sig := str(d.get("signature", ""))
		if float(row.signature) >= SIG_IN_DECK:
			list.append(["SIGNATURE", "%s is in your deck: full power with %s on the team." % [str(DB.card(sig).name), _name(id)]])
		elif float(row.signature) > 0.0:
			list.append(["SIGNATURE", "You own %s, %s's signature card." % [str(DB.card(sig).name), _name(id)]])
		if list.is_empty():
			list.append(["SCORE %.1f" % float(row.score), "%s: score %.1f at Lv %d." % [_name(id), float(row.score), int(row.level)]])
		out[id] = list
	return out


static func _summary(team: Array, captain: String, r: Dictionary, mode: String) -> String:
	var parts: Array = []
	var roles := {}
	for id in team:
		roles[DB.defender(id).role] = int(roles.get(DB.defender(id).role, 0)) + 1
	parts.append("%s style" % MODE_NAMES.get(mode, "Balanced"))
	var syn_names: Array = []
	for s in r.synergies:
		syn_names.append(_syn_name(str(s)))
	if not syn_names.is_empty():
		parts.append(", ".join(syn_names))
	if captain != "":
		parts.append("captain %s" % _name(captain))
	return " · ".join(parts)


# ================================================================ compare

## A one-line verdict between two defenders: "Rosa: better vs bosses, Rico: better vs crowds".
static func verdict(a: String, b: String, ctx: Dictionary = {}, mode := "balanced") -> String:
	if ctx.is_empty():
		ctx = profile_context()
	if a == b:
		return "The same defender."
	var ra := rate(a, ctx, mode)
	var rb := rate(b, ctx, mode)
	var na := _name(a)
	var nb := _name(b)
	var wins_a: Array = []
	var wins_b: Array = []
	# boss_v / crowd_v include team boosts (rate(): the share of a typical six's damage they add).
	for pair in [["boss_v", "vs bosses", 1.1], ["crowd_v", "vs crowds", 1.15], ["control", "at control", 1.2], ["eff", "at damage", 1.08], ["range", "at range", 1.1]]:
		var va := float(ra[pair[0]])
		var vb := float(rb[pair[0]])
		if va > vb * float(pair[2]) + 0.5:
			wins_a.append(pair[1])
		elif vb > va * float(pair[2]) + 0.5:
			wins_b.append(pair[1])
	var parts: Array = []
	if not wins_a.is_empty():
		parts.append("%s: better %s" % [na, " and ".join(wins_a.slice(0, 2))])
	if not wins_b.is_empty():
		parts.append("%s: better %s" % [nb, " and ".join(wins_b.slice(0, 2))])
	if parts.is_empty():
		var sa := float(ra.score)
		var sb := float(rb.score)
		if absf(sa - sb) < 0.3:
			return "%s and %s are about even." % [na, nb]
		return "%s scores higher overall (%.1f vs %.1f)." % [na if sa > sb else nb, maxf(sa, sb), minf(sa, sb)]
	return ", ".join(parts)


## The team after putting `incoming` in for `outgoing`, keeping the rules (the incoming player takes the
## outgoing one's place, and the captaincy when they had it). Returns {team, captain} or {} when not allowed.
static func swap_in(team: Array, captain: String, incoming: String, outgoing: String, unlocked: Array) -> Dictionary:
	if not incoming in unlocked or incoming in team or not outgoing in team:
		return {}
	var t := team.duplicate()
	t[t.find(outgoing)] = incoming
	return {"team": t, "captain": incoming if captain == outgoing else captain}
