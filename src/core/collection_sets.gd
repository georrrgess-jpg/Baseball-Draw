class_name CollectionSets
extends RefCounted
## Collection book: card sets per category (Offense, Control, Defense, Utility), the
## Signature set (cards linked to a defender) and the full collection. Completing a set
## gives a one-time pack, claimed from Cards & Deck. Sets are computed from the card data,
## so new cards join their set automatically; a reward already claimed stays claimed.

## [id, name, icon, reward pack]
const SETS := [
	["offense", "OFFENSE", "offense", "pro"],
	["control", "CONTROL", "control", "pro"],
	["defense", "DEFENSE", "defense", "pro"],
	["utility", "UTILITY", "utility", "pro"],
	["signature", "SIGNATURE", "star", "pro"],
	["all", "FULL COLLECTION", "collection", "champion"],
]


static func ids() -> Array:
	return SETS.map(func(s: Array) -> String: return s[0])


static func info(set_id: String) -> Array:
	for s in SETS:
		if s[0] == set_id:
			return s
	return []


static func cards_in(set_id: String) -> Array:
	var out: Array = []
	for cid in DB.card_order:
		var c := DB.card(cid)
		var hit := false
		match set_id:
			"all": hit = true
			"signature": hit = str(c.get("linked", "")) != ""
			_: hit = str(c.category) == set_id
		if hit:
			out.append(cid)
	return out


## {"owned", "total"}
static func progress(set_id: String) -> Dictionary:
	var cards := cards_in(set_id)
	var owned := 0
	for cid in cards:
		if Profile.is_card_owned(cid):
			owned += 1
	return {"owned": owned, "total": cards.size()}


static func is_complete(set_id: String) -> bool:
	var p := progress(set_id)
	return int(p.total) > 0 and int(p.owned) >= int(p.total)


static func is_claimed(set_id: String) -> bool:
	return Profile.data.sets_claimed.has(set_id)


static func can_claim(set_id: String) -> bool:
	return is_complete(set_id) and not is_claimed(set_id)


static func claimable_count() -> int:
	var n := 0
	for s in SETS:
		if can_claim(s[0]):
			n += 1
	return n


static func reward_pack(set_id: String) -> String:
	var s := info(set_id)
	return str(s[3]) if not s.is_empty() else "pro"


## Gives the set's pack once. Returns the pack type, or "" when it cannot be claimed.
static func claim(set_id: String) -> String:
	if not can_claim(set_id):
		return ""
	var pack := reward_pack(set_id)
	Profile.data.sets_claimed[set_id] = Time.get_datetime_string_from_system()
	Profile.add_pack(pack, "%s set complete" % str(info(set_id)[1]).capitalize())
	Profile.bump_stat("sets_completed")
	Profile.save_soon()
	return pack
