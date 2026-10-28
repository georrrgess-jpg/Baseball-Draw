class_name NextSteps
extends RefCounted
## "What's next" suggestions: the most useful things the player can do right now, best first.
## Used by the Results screen (a row of one-click buttons) and the main menu. Each suggestion is
## {"id", "text", "detail", "icon", "accent", "go": Callable}.

const DAILY_ACCENT := Color("#FF8A3D")


## `just_played_daily`: the game that just ended was today's Daily Challenge (do not suggest it).
static func suggestions(just_played_daily := false) -> Array:
	var out: Array = []
	# 1. Promotion: the biggest step there is.
	if Profile.promotion_available():
		out.append({"id": "promotion", "text": "PROMOTION CHALLENGE", "icon": "crown", "accent": UITheme.GOLD,
			"detail": "Win it to move up to %s" % str(Profile.next_division().get("name", "the next division")),
			"go": func() -> void:
				Session.menu_tab = "ranked"
				Router.goto("play_menu")})
	# 2. Missions finished (progression stream; only when its API exists).
	var missions := mission_ready_count()
	if missions > 0:
		out.append({"id": "missions", "text": "CLAIM %d MISSION%s" % [missions, "S" if missions > 1 else ""], "icon": "check",
			"accent": UITheme.GREEN, "detail": "Mission rewards are waiting", "go": func() -> void: Router.goto(mission_screen())})
	# 3. Unopened packs.
	var packs := Profile.pack_count()
	if packs > 0:
		out.append({"id": "packs", "text": "OPEN %d PACK%s" % [packs, "S" if packs > 1 else ""], "icon": "gift", "accent": UITheme.GOLD,
			"detail": "New cards and upgrade copies", "go": func() -> void: Router.goto("packs")})
	# 4. A card ready to upgrade.
	var ready: Array = []
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			ready.append(cid)
	if not ready.is_empty():
		out.append({"id": "upgrade", "text": "UPGRADE %s" % str(DB.card(str(ready[0])).name).to_upper() if ready.size() == 1 else "UPGRADE %d CARDS" % ready.size(),
			"icon": "upgrade", "accent": UITheme.GREEN, "detail": "You have the copies and coins",
			"go": func() -> void: Router.goto("card_upgrades")})
	# 5. A defender trait to choose.
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id) and Profile.pending_traits(id) > 0:
			out.append({"id": "trait", "text": "CHOOSE %s'S TRAIT" % str(DB.defender(id).name).to_upper(), "icon": "star", "accent": UITheme.BLUE,
				"detail": "A new training trait is unlocked", "go": func() -> void: Router.goto("roster")})
			break
	# 6. A collection set reward to claim.
	if CollectionSets.claimable_count() > 0:
		out.append({"id": "set", "text": "CLAIM SET REWARD", "icon": "collection", "accent": UITheme.GOLD,
			"detail": "A completed collection set gives a pack", "go": func() -> void:
				Session.menu_tab = "deck"
				Router.goto("deck_builder")})
	# 7. Today's Daily Challenge, not played yet.
	if not just_played_daily and not DailyChallenge.played():
		out.append({"id": "daily", "text": "TRY TODAY'S DAILY", "icon": "calendar", "accent": DAILY_ACCENT,
			"detail": "Bonus pack for your first game today", "go": func() -> void:
				Session.menu_tab = "daily"
				Router.goto("play_menu")})
	# 8. New cards that are not in the deck yet.
	if Profile.fresh_card_count() > 0:
		out.append({"id": "deck", "text": "TRY YOUR NEW CARDS", "icon": "deck", "accent": UITheme.BLUE,
			"detail": "Put new cards into your deck", "go": func() -> void:
				Session.menu_tab = "deck"
				Router.goto("deck_builder")})
	return out


## Missions ready to claim, if the progression code provides missions (Profile or a Missions class).
static func mission_ready_count() -> int:
	for m in ["claimable_mission_count", "missions_claimable_count", "mission_claimable_count"]:
		if Profile.has_method(m):
			return int(Profile.call(m))
	var cls := _global_class("Missions")
	if cls:
		for m in ["claimable_count", "ready_count"]:
			if cls.has_method(m):
				return int(cls.call(m))
	return 0


## The screen that shows missions (the progression screen unless a missions screen exists).
static func mission_screen() -> String:
	return "missions" if Router.SCENES.has("missions") else "progression"


static func _global_class(name: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == name:
			return load(str(c.path)) as Script
	return null


## A compact one-click suggestion button (icon, title, small detail line).
static func button(s: Dictionary, width := 300.0) -> Button:
	var b := UITheme.button(str(s.text), "secondary", UITheme.FS_BODY, str(s.icon), s.accent)
	b.name = "Next_" + str(s.id)
	b.custom_minimum_size = Vector2(width, UITheme.BTN_H)
	b.tooltip_text = str(s.get("detail", ""))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	var go: Callable = s.go
	b.pressed.connect(func() -> void: go.call())
	return b
