class_name CardMastery
extends RefCounted
## Card mastery: every card earns mastery from being played in real games (not Practice).
## Three stars at fixed play counts. Purely cosmetic: star pips on the card, and a gold
## "mastered" trim at three stars. Plays are counted per run in run.stats.card_casts (so a
## continued run keeps them) and added to the profile when the run ends (Rewards.apply).

const THRESHOLDS := [10, 40, 120]
const MAX_STARS := 3


static func stars_for(plays: int) -> int:
	var s := 0
	for t in THRESHOLDS:
		if plays >= int(t):
			s += 1
	return s


static func stars(card_id: String) -> int:
	return stars_for(Profile.card_plays(card_id))


## Plays needed for the next star (0 when mastered).
static func next_threshold(plays: int) -> int:
	for t in THRESHOLDS:
		if plays < int(t):
			return int(t)
	return 0


## Progress 0..1 from the previous star to the next one (1 when mastered).
static func progress(plays: int) -> float:
	var nxt := next_threshold(plays)
	if nxt == 0:
		return 1.0
	var s := stars_for(plays)
	var prev := 0 if s == 0 else int(THRESHOLDS[s - 1])
	return clampf(float(plays - prev) / float(nxt - prev), 0.0, 1.0)


## One-line status: "23 plays · 17 more for ★★".
static func status_text(plays: int) -> String:
	var nxt := next_threshold(plays)
	if nxt == 0:
		return "%d plays · MASTERED" % plays
	return "%d play%s · %d more for %s" % [plays, "" if plays == 1 else "s", nxt - plays, "★".repeat(stars_for(plays) + 1)]


## Adds the run's card plays to the profile. Returns one entry per card played:
## {"id", "plays" (this run), "before", "after", "stars_before", "stars_after"}, star earners first.
static func apply_run(run: RunState) -> Array:
	var casts: Variant = run.stats.get("card_casts", {})
	var out: Array = []
	if typeof(casts) != TYPE_DICTIONARY:
		return out
	for cid in (casts as Dictionary).keys():
		var n := int(casts[cid])
		if n <= 0 or not DB.cards.has(str(cid)):
			continue
		var before := Profile.card_plays(str(cid))
		Profile.add_card_plays(str(cid), n)
		var after := Profile.card_plays(str(cid))
		out.append({"id": str(cid), "plays": n, "before": before, "after": after,
			"stars_before": stars_for(before), "stars_after": stars_for(after)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ga := int(a.stars_after) - int(a.stars_before)
		var gb := int(b.stars_after) - int(b.stars_before)
		if ga != gb:
			return ga > gb
		return int(a.plays) > int(b.plays))
	return out


static func mastered_count() -> int:
	var n := 0
	for cid in DB.card_order:
		if stars(cid) >= MAX_STARS:
			n += 1
	return n
