class_name Shop
extends RefCounted
## Daily Shop (Update 9): a free gift, card-copy deals, a pack deal and a star deal that refresh at
## local midnight, plus free agents (new defenders signed early for coins). State: Profile.data.shop.
## FOUNDATION STUB: the economy stream (D) implements the rules in docs/plans/UPDATE_9_PLAN.md.

const DATA_PATH := "res://data/shop.json"


static func default_state() -> Dictionary:
	return {"date": "", "offers": [], "bought": []}


## [{id, kind ("gift"|"card"|"pack"|"stars"), card, pack, copies, price {coins, stars}, bought, title, text}]
static func offers() -> Array:
	return []


static func can_buy(_id: String) -> bool:
	return false


static func buy(_id: String) -> Dictionary:
	return {}


static func seconds_to_refresh() -> int:
	var t := Time.get_time_dict_from_system()
	return 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))


## [{id, price, level, signed}]: defenders that can be signed early for coins.
static func free_agents() -> Array:
	var out: Array = []
	for id in DB.defender_order:
		var u: Dictionary = DB.defender(id).get("unlock", {})
		if int(u.get("coins", 0)) > 0:
			out.append({"id": id, "price": int(u.coins), "level": int(u.get("value", 0)), "signed": Profile.is_defender_unlocked(id)})
	return out


static func sign_agent(_id: String) -> bool:
	return false
