class_name Shop
extends RefCounted
## Daily Shop (Update 9): a free gift, card-copy deals, a pack deal and a star deal that refresh at
## local midnight, plus free agents (new defenders signed early for coins). State: Profile.data.shop =
## {date, offers, bought}; prices and slots: data/shop.json.
##
## * The offers are rolled once per local calendar day, deterministically for the date and the profile
##   (its creation time), from the collection as it is at that moment, and kept for the day.
## * Card deals: owned cards that still need copies to reach max level, `deck_weight` times likelier for
##   cards in the current deck, two different cards. A deal holds the copies the card's next level still
##   needs (at least 1, at most max_copies for its rarity) at the per-copy price of its rarity
##   (common 60, uncommon 120, rare 250, epic 500, legendary 1,000 coins). No such card: a discounted
##   Rookie Pack instead.
## * Every offer can be bought once a day; a card deal is refused once its card reached max level.
## * Free agents: defenders with a coin price (data/defenders.json unlock.coins) can be signed before their
##   account level; signing goes through Profile.unlock_defender, so the signature pack comes as usual.
## * Dates come from DailyChallenge.today() (tests pin it with DailyChallenge.date_override).

const DATA_PATH := "res://data/shop.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func default_state() -> Dictionary:
	return {"date": "", "offers": [], "bought": []}


static func state() -> Dictionary:
	if typeof(Profile.data.get("shop")) != TYPE_DICTIONARY:
		Profile.data["shop"] = default_state()
	return Profile.data.shop


## Rolls today's offers when the day changed. Cheap when nothing changed.
static func refresh() -> void:
	if Profile.data.is_empty():
		return
	var s := state()
	var d := DailyChallenge.today()
	if str(s.get("date", "")) != d:
		s.date = d
		s.offers = generate(d)
		s.bought = []


static func card_price(rarity: String) -> int:
	return int(data().get("card_prices", {}).get(rarity, 100))


## Copies still missing for `id` to reach max level (0 when maxed or not owned).
static func copies_to_max(id: String) -> int:
	if not Profile.is_card_owned(id):
		return 0
	var lvl := Profile.card_level(id)
	if lvl >= DB.card_max_level:
		return 0
	var need := 0
	var table: Array = DB.COPIES_TO_UPGRADE[DB.card(id).rarity]
	for l in range(lvl, DB.card_max_level):
		need += int(table[l])
	return maxi(0, need - Profile.card_copies(id))


## Copies a deal for `id` holds: what the next level still needs, between 1 and the rarity's maximum.
static func deal_copies(id: String) -> int:
	var rarity := str(DB.card(id).rarity)
	var lvl := Profile.card_level(id)
	var next_need := int(DB.COPIES_TO_UPGRADE[rarity][mini(lvl, DB.card_max_level - 1)]) - Profile.card_copies(id)
	var cap := int(data().get("max_copies", {}).get(rarity, 2))
	return clampi(maxi(1, next_need), 1, maxi(1, mini(cap, copies_to_max(id))))


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(("shop:%s:%s" % [key, str(Profile.data.get("created", ""))]).hash())
	return rng


static func _discounted(price: int, discount: float) -> int:
	return RunState.round_price(price * (1.0 - discount))


## The offers for `date` with the collection as it is now. Deterministic for a date, profile and collection.
static func generate(date: String) -> Array:
	var d := data()
	var rng := _rng(date)
	var out: Array = []
	# Free gift.
	var gifts: Array = d.get("gifts", [{"coins": 100}])
	var total := 0.0
	for g in gifts:
		total += float(g.get("weight", 1))
	var x := rng.randf() * total
	var gift: Dictionary = gifts[0]
	for g in gifts:
		x -= float(g.get("weight", 1))
		if x <= 0.0:
			gift = g
			break
	var reward := {}
	for k in ["coins", "stars", "packs"]:
		if gift.has(k):
			reward[k] = gift[k]
	var gift_packs := Rewards.bundle_packs(reward)
	out.append(_offer("gift", "gift", "", str(gift_packs[0]) if not gift_packs.is_empty() else "", 0,
		{"coins": 0, "stars": 0}, "FREE GIFT", Rewards.bundle_text(reward), {"reward": reward}))
	# Card deals: owned cards that still need copies, weighted toward the deck.
	var pool: Array = []
	var weights: Array = []
	for id in DB.card_order:
		if copies_to_max(id) > 0:
			pool.append(id)
			weights.append(float(d.get("deck_weight", 4)) if id in Profile.data.deck else 1.0)
	for i in int(d.get("card_deals", 2)):
		var slot_id := "card_%d" % (i + 1)
		if pool.is_empty():
			var fb: Dictionary = d.get("fallback_deal", {"pack": "rookie", "discount": 0.25})
			var fp := str(fb.get("pack", "rookie"))
			var full := int(DB.pack(fp).get("price_coins", 200))
			out.append(_offer(slot_id, "pack", "", fp, 1, {"coins": _discounted(full, float(fb.get("discount", 0.25))), "stars": 0},
				str(DB.pack(fp).get("name", fp)), "%d %% off" % int(round(float(fb.get("discount", 0.25)) * 100)),
				{"full_price": full, "discount": float(fb.get("discount", 0.25))}))
			continue
		var wt := 0.0
		for w in weights:
			wt += float(w)
		var y := rng.randf() * wt
		var pick := 0
		for j in pool.size():
			y -= float(weights[j])
			if y <= 0.0:
				pick = j
				break
		var cid: String = pool[pick]
		pool.remove_at(pick)
		weights.remove_at(pick)
		var rarity := str(DB.card(cid).rarity)
		var n := deal_copies(cid)
		out.append(_offer(slot_id, "card", cid, "", n, {"coins": n * card_price(rarity), "stars": 0}, str(DB.card(cid).name),
			"%d %s cop%s · %s" % [n, rarity.capitalize(), "y" if n == 1 else "ies", "in your deck" if cid in Profile.data.deck else "for upgrades"],
			{"rarity": rarity, "unit_price": card_price(rarity), "in_deck": cid in Profile.data.deck}))
	# Pack deal.
	var pd: Dictionary = d.get("pack_deal", {"pack": "pro", "discount": 0.25})
	var pp := str(pd.get("pack", "pro"))
	var pfull := int(DB.pack(pp).get("price_coins", 500))
	var disc := float(pd.get("discount", 0.25))
	out.append(_offer("pack", "pack", "", pp, 1, {"coins": _discounted(pfull, disc), "stars": 0}, str(DB.pack(pp).get("name", pp)),
		"%d %% off today" % int(round(disc * 100)), {"full_price": pfull, "discount": disc}))
	# Star deal.
	var sd: Dictionary = d.get("star_deal", {"pack": "champion", "price_stars": 40})
	var sp := str(sd.get("pack", "champion"))
	var sfull := int(DB.pack(sp).get("price_stars", 50))
	out.append(_offer("stars", "stars", "", sp, 1, {"coins": 0, "stars": int(sd.get("price_stars", 40))}, str(DB.pack(sp).get("name", sp)),
		"Paid with stars · %d★ instead of %d★" % [int(sd.get("price_stars", 40)), sfull], {"full_price_stars": sfull}))
	return out


static func _offer(id: String, kind: String, card: String, pack: String, copies: int, price: Dictionary, title: String,
		text: String, extra := {}) -> Dictionary:
	var o := {"id": id, "kind": kind, "card": card, "pack": pack, "copies": copies, "price": price, "bought": false,
		"title": title, "text": text}
	o.merge(extra)
	return o


## [{id, kind ("gift"|"card"|"pack"|"stars"), card, pack, copies, price {coins, stars}, bought, title, text}]
## (+ affordable, and per kind: reward, rarity, unit_price, in_deck, full_price, discount, full_price_stars).
static func offers() -> Array:
	refresh()
	var s := state()
	var out: Array = []
	for o in s.offers:
		var c: Dictionary = (o as Dictionary).duplicate(true)
		c.bought = str(c.id) in s.bought
		c["affordable"] = int(Profile.data.coins) >= int(c.price.get("coins", 0)) and int(Profile.data.stars) >= int(c.price.get("stars", 0))
		out.append(c)
	return out


static func _find(id: String) -> Dictionary:
	refresh()
	for o in state().offers:
		if str(o.id) == id:
			return o
	return {}


static func can_buy(id: String) -> bool:
	var o := _find(id)
	if o.is_empty() or id in state().bought:
		return false
	if str(o.kind) == "card" and copies_to_max(str(o.card)) <= 0:
		return false
	return int(Profile.data.coins) >= int(o.price.get("coins", 0)) and int(Profile.data.stars) >= int(o.price.get("stars", 0))


## Buys (or, for the free gift, claims) offer `id` once today. Returns {id, kind, card, copies, pack, price,
## granted, text}, or {} when it cannot be bought.
static func buy(id: String) -> Dictionary:
	if not can_buy(id):
		return {}
	var o := _find(id)
	var coins := int(o.price.get("coins", 0))
	var stars := int(o.price.get("stars", 0))
	Profile.data.coins = int(Profile.data.coins) - coins
	Profile.data.stars = int(Profile.data.stars) - stars
	var got := {}
	match str(o.kind):
		"gift":
			got = Rewards.grant_bundle(o.get("reward", {}), "Daily Shop gift")
		"card":
			var n := mini(int(o.copies), copies_to_max(str(o.card)))
			Profile.grant_card(str(o.card), n)
			got = {"card": str(o.card), "copies": n}
		_:
			for i in maxi(1, int(o.copies)):
				Profile.add_pack(str(o.pack), "Daily Shop")
			got = {"packs": [str(o.pack)]}
	(state().bought as Array).append(id)
	if str(o.kind) == "gift":
		Profile.bump_stat("shop_gifts")
	else:
		Profile.bump_stat("shop_purchases")
		Profile.bump_stat("shop_coins_spent", float(coins))
	Profile.changed.emit()
	Profile.save_soon()
	return {"id": id, "kind": str(o.kind), "card": str(o.card), "copies": int(o.copies), "pack": str(o.pack), "price": o.price,
		"granted": got, "text": str(o.text)}


## True while the free gift is waiting today (a badge on the hub and the Shop button).
static func gift_available() -> bool:
	return can_buy("gift")


static func seconds_to_refresh() -> int:
	return DailyChallenge.seconds_to_next()


# ---------------------------------------------------------------- free agents

## [{id, price, level, signed}]: defenders that can be signed early for coins (+ name, affordable).
static func free_agents() -> Array:
	var out: Array = []
	for id in DB.defender_order:
		var u: Dictionary = DB.defender(id).get("unlock", {})
		if int(u.get("coins", 0)) > 0:
			out.append({"id": id, "price": int(u.coins), "level": int(u.get("value", 0)), "signed": Profile.is_defender_unlocked(id),
				"name": str(DB.defender(id).get("name", id)), "affordable": int(Profile.data.coins) >= int(u.coins)})
	return out


static func can_sign(id: String) -> bool:
	for fa in free_agents():
		if fa.id == id:
			return not bool(fa.signed) and bool(fa.affordable)
	return false


## Signs free agent `id` for coins: unlocks the defender now (signature pack included). False when the
## defender is already on the team, has no coin price, or the coins are short.
static func sign_agent(id: String) -> bool:
	if not can_sign(id):
		return false
	var price := int(DB.defender(id).unlock.coins)
	if not Profile.spend_coins(price):
		return false
	Profile.unlock_defender(id)
	Profile.bump_stat("free_agents_signed")
	Profile.data.stats["free_agent_coins"] = Profile.stat("free_agent_coins") + price
	Profile.save_soon()
	return true
