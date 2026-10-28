class_name Hints
extends RefCounted
## First-visit hint cards: a small card (title, one or two sentences, "GOT IT") shown the first
## time a player opens a screen or meets a feature, with an optional arrow and a pulsing outline
## on the element it explains. Only one hint is ever on screen; a screen's hints queue up and show
## one after another. "Seen" flags live in Profile.data.flags.hints_seen. Every screen's "?" button
## replays its hints (Hints.replay). Hints never show during the battle tutorial, in automated
## tests (unless a test turns them on) or when the "Show tips" setting is off.
##
## Usage from a screen:
##   Hints.first_visit(self, "packs", func() -> Dictionary: return {"packs_open": _open_btn})
##   var help := Hints.help_button(self, "packs", same_targets_callable)

## id -> [title, text]
const HINTS := {
	# Main menu (after the first game; the welcome panel covers the very first launch).
	"menu_home": ["YOUR CLUBHOUSE", "PLAY starts a game. Tiles with a badge have something waiting for you: unopened packs, new cards or cards ready to upgrade."],
	"menu_daily": ["DAILY CHALLENGE", "A new game every day with fixed rules, the same for every manager. Your first game and first win each day give a bonus pack; play on back-to-back days for a streak."],
	"menu_promotion": ["PROMOTION CHALLENGE", "You have enough Rank Points to move up a division. Open PLAY and pick Promotion Challenge: win it to get promoted."],
	# Card packs.
	"packs_intro": ["CARD PACKS", "Pick a pack on the shelf and open it. New cards join your collection; a card you already own becomes a copy, used to upgrade that card."],
	"packs_rarity": ["CARD RARITY", "The colour of a card's frame is its rarity: Common (grey), Uncommon (green), Rare (blue), Epic (purple), Legendary (gold). Rarer cards are stronger and show up less often."],
	# Cards & Deck.
	"deck_intro": ["YOUR DECK", "You take these 8 cards into every game. Click a card in your collection to add it, click a deck card to take it out (or drag them)."],
	"deck_mastery": ["CARD MASTERY", "Stars on a card show mastery: play it in real games 10, 40 and 120 times for 1, 2 and 3 stars. Three stars earns a gold MASTERED frame. Cosmetic only."],
	"deck_sets": ["COLLECTION SETS", "Own every card of a set (Offense, Control, Defense, Utility, Signature) to claim a free Pro Pack here. The full collection earns a Champion Pack."],
	# Upgrade Cards.
	"upgrades_intro": ["UPGRADE CARDS", "Each level makes a card stronger in every game. A level costs copies of that card (duplicates from packs) plus coins. READY means you can upgrade it now."],
	# Team.
	"team_intro": ["YOUR TEAM", "Pick a defender on the left to see their stats. The strip at the bottom is your starting six; the captain boosts nearby teammates."],
	"team_road": ["LEVEL ROAD", "Defenders earn XP in every game they play. Each level on the road gives a reward: coins, a pack or a new trait to choose."],
	"team_traits": ["TRAINING TRAITS", "At the levels shown, pick one of two traits for this defender. You can switch your pick any time. Gear (from Progression → Pro Shop) and uniforms (bought with stars) are below."],
	# Play.
	"play_modes": ["CHOOSE A GAME", "Quick Defense is a short 3-inning game; Standard Siege is the full 9 innings with 3 bosses. Higher difficulty means tougher runners and bigger rewards."],
	"play_daily": ["DAILY CHALLENGE", "Today's game has a fixed deck, stadium and twist, the same for everyone. Bonus pack for your first game and first win today. It never touches your saved run."],
	"play_ranked": ["PROMOTION CHALLENGE", "Win games to earn Rank Points (RP). With enough RP this short challenge unlocks: win it to move up a division and earn more rewards."],
	"play_endless": ["THE ENDLESS NINTH", "Survive as long as you can. Every inning adds a random modifier and every third inning brings a boss. Your best inning and score are kept as records."],
	"play_practice": ["PRACTICE FIELD", "A sandbox: spawn any runner and try any card. No rewards and no risk."],
	# Battle dugout (between innings).
	"dugout_intro": ["THE DUGOUT", "Between innings, spend the coins earned in this game on upgrades for the rest of this game. Then press NEXT INNING."],
	# Settings.
	"settings_intro": ["SETTINGS", "Search for any option at the top. Graphics has a benchmark that recommends a quality preset for your computer."],
}

## Which hints each screen shows (in order) and replays from its "?" button.
const SCREENS := {
	"main_menu": ["menu_home", "menu_daily", "menu_promotion"],
	"packs": ["packs_intro", "packs_rarity"],
	"deck_builder": ["deck_intro", "deck_mastery", "deck_sets"],
	"collection": ["deck_mastery", "deck_sets", "packs_rarity"],
	"card_upgrades": ["upgrades_intro"],
	"roster": ["team_intro", "team_road", "team_traits"],
	"play_menu": ["play_modes", "play_daily", "play_ranked", "play_endless", "play_practice"],
	"dugout": ["dugout_intro"],
	"settings": ["settings_intro"],
}

## Feature hints: part of a screen's "?" replay, but shown automatically only when the screen
## passes them in `extra` (the player has actually met the feature).
const FEATURE_ONLY := ["menu_promotion", "deck_mastery", "deck_sets", "team_traits",
	"play_daily", "play_ranked", "play_endless", "play_practice"]

const ACCENT := UITheme.GOLD
const CARD_W := 440.0

## Tests turn hints on (they are off in automated runs by default).
static var force_enabled := false
static var _current: WeakRef = null


static func enabled() -> bool:
	if force_enabled:
		return true
	var args := OS.get_cmdline_user_args()
	if "--no-help" in args or "--ui-test" in args or "--no-hints" in args or "--smoke-test" in args:
		return false
	return bool(Settings.get_value("gameplay", "tips", true))


static func seen(id: String) -> bool:
	var d: Variant = Profile.data.get("flags", {}).get("hints_seen", {})
	return typeof(d) == TYPE_DICTIONARY and bool((d as Dictionary).get(id, false))


static func mark_seen(id: String) -> void:
	var d: Variant = Profile.data.flags.get("hints_seen", {})
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
	d[id] = true
	Profile.data.flags["hints_seen"] = d
	Profile.save_soon()


## Forgets every "seen" flag (Settings → Gameplay → Show all tips again).
static func reset_seen() -> void:
	Profile.data.flags["hints_seen"] = {}
	Profile.save_soon()


## The open hint overlay (a CanvasLayer holding the card), or null.
static func current() -> Node:
	if _current == null:
		return null
	var c: Variant = _current.get_ref()
	if c == null or not is_instance_valid(c) or (c as Node).is_queued_for_deletion():
		return null
	return c


## The id of the hint on screen ("" when none).
static func current_id() -> String:
	var c := current()
	if c == null:
		return ""
	return str(c.get("current_id"))


static func is_showing() -> bool:
	return current() != null


static func ids_for(screen_id: String) -> Array:
	return SCREENS.get(screen_id, [])


## Shows the first unseen hint of a screen (then the next unseen ones, one at a time), after a
## short delay so the screen's enter animation finishes first. `targets` returns
## {hint_id: Control} for the arrow and outline; `extra` adds feature hints for this visit.
static func first_visit(host: Node, screen_id: String, targets := Callable(), extra: Array = [], delay := 0.7) -> void:
	var ids: Array = ids_for(screen_id).filter(func(i: String) -> bool: return not i in FEATURE_ONLY or i in extra)
	for e in extra:
		if not e in ids:
			ids.append(e)
	show_unseen(host, ids, targets, delay)


## Shows the given hints that have not been seen yet (one at a time). Nothing happens when a hint
## is already on screen, hints are off, or every hint was seen.
static func show_unseen(host: Node, ids: Array, targets := Callable(), delay := 0.0) -> void:
	if not enabled() or host == null:
		return
	var queue := ids.filter(func(i: String) -> bool: return HINTS.has(i) and not seen(i))
	if queue.is_empty():
		return
	if delay > 0.0:
		await host.get_tree().create_timer(delay, true).timeout
		if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion() or Router.busy:
			return   # the player already left the screen
		queue = queue.filter(func(i: String) -> bool: return not seen(i))
		if queue.is_empty():
			return
	if is_showing():
		return
	_open(host, queue, targets, false)


## The "?" button: shows all of a screen's hints again, seen or not.
static func replay(host: Node, screen_id: String, targets := Callable(), extra: Array = []) -> void:
	var ids: Array = ids_for(screen_id).duplicate()
	for e in extra:
		if not e in ids:
			ids.append(e)
	var c := current()
	if c:
		c.queue_free()
		_current = null
	if host and not ids.is_empty():
		_open(host, ids, targets, true)


## A round "?" button that replays the screen's hints.
static func help_button(host: Node, screen_id: String, targets := Callable(), extra_fn := Callable()) -> Button:
	var b := UITheme.button("?", "secondary", 30, "", UITheme.GOLD)
	b.name = "HelpButton"
	b.custom_minimum_size = Vector2(UITheme.BTN_H, UITheme.BTN_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Tips for this screen"
	b.pressed.connect(func() -> void:
		var extra: Array = extra_fn.call() if extra_fn.is_valid() else []
		replay(host, screen_id, targets, extra))
	return b


static func _open(host: Node, queue: Array, targets: Callable, replaying: bool) -> void:
	var old := current()
	if old:   # never two hints at once
		old.queue_free()
	var layer := HintLayer.new()
	layer.queue = queue.duplicate()
	layer.targets = targets
	layer.replaying = replaying
	host.add_child(layer)
	_current = weakref(layer)


## The overlay that holds one hint card at a time (CanvasLayer above the screen's UI).
class HintLayer extends CanvasLayer:
	var queue: Array = []
	var targets := Callable()
	var replaying := false
	var current_id := ""
	var root: Control
	var _index := 0
	var _total := 0
	var _card: PanelContainer
	var _draw_node: HintDraw
	var _target: Control

	func _init() -> void:
		layer = 60
		process_mode = Node.PROCESS_MODE_ALWAYS
		root = Control.new()
		root.name = "HintRoot"
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

	func _ready() -> void:
		_total = queue.size()
		_show_next()

	func _show_next() -> void:
		for c in root.get_children():
			root.remove_child(c)   # at once, so the next card can take the HintCard name
			c.queue_free()
		if queue.is_empty():
			queue_free()
			return
		var id: String = queue.pop_front()
		current_id = id
		_index += 1
		var h: Array = Hints.HINTS.get(id, ["", ""])
		_target = null
		if targets.is_valid():
			var t: Variant = targets.call()
			if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has(id):
				var c: Variant = t[id]
				if c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree():
					_target = c
		_draw_node = HintDraw.new()
		_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_draw_node)
		_card = _build_card(id, str(h[0]), str(h[1]))
		root.add_child(_card)
		_card.modulate.a = 0.0
		_place.call_deferred()
		Audio.ui("ui_slide", -8.0)

	func _build_card(id: String, title: String, text: String) -> PanelContainer:
		var p := UITheme.card_panel(Color(Hints.ACCENT, 0.85), 18, Color(0.05, 0.08, 0.14, 0.97), 2)
		p.name = "HintCard"
		p.set_meta("hint_id", id)
		p.custom_minimum_size = Vector2(Hints.CARD_W, 0)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		p.add_child(vb)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		vb.add_child(head)
		var ic := UITheme.icon_rect("info", 30, Hints.ACCENT)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
		var tl := UITheme.label(title, UITheme.FS_H3, Hints.ACCENT, UITheme.font_display())
		tl.name = "HintTitle"
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(tl)
		if _total > 1:
			head.add_child(UITheme.label("%d / %d" % [_index, _total], UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		var body := UITheme.label(text, UITheme.FS_BODY, UITheme.OFFWHITE)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(Hints.CARD_W - 36, 0)
		vb.add_child(body)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_END
		vb.add_child(row)
		if not queue.is_empty():
			var skip := UITheme.button("SKIP TIPS", "ghost", UITheme.FS_SMALL)
			skip.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
			skip.tooltip_text = "Hide the rest of this screen's tips (the ? button shows them again)"
			skip.pressed.connect(func() -> void:
				Hints.mark_seen(id)
				for q in queue:
					Hints.mark_seen(str(q))
				queue.clear()
				_close())
			row.add_child(skip)
		var ok := UITheme.button("GOT IT", "primary", UITheme.FS_LEAD, "check")
		ok.custom_minimum_size = Vector2(150, UITheme.BTN_H_SMALL)
		ok.pressed.connect(func() -> void:
			Hints.mark_seen(id)
			Audio.ui("ui_click")
			_show_next.call_deferred())
		row.add_child(ok)
		return p

	## Puts the card next to its target (below, above, right or left, whichever fits), or in the
	## lower middle of the screen when the hint has no target.
	func _place() -> void:
		if _card == null or not is_instance_valid(_card):
			return
		var vs := root.get_viewport_rect().size
		var cs := _card.get_combined_minimum_size()
		_card.size = cs
		# No target: top right, under the screen header (clear of the main buttons).
		var pos := Vector2(vs.x - cs.x - 40.0, 124.0)
		var tr := Rect2()
		if _target and is_instance_valid(_target):
			var xf := _target.get_global_transform_with_canvas()
			tr = Rect2(xf.origin, _target.size * xf.get_scale())
			var gap := 34.0
			var m := 16.0
			var cands := [
				Vector2(tr.get_center().x - cs.x * 0.5, tr.end.y + gap),
				Vector2(tr.get_center().x - cs.x * 0.5, tr.position.y - gap - cs.y),
				Vector2(tr.end.x + gap, tr.get_center().y - cs.y * 0.5),
				Vector2(tr.position.x - gap - cs.x, tr.get_center().y - cs.y * 0.5),
			]
			var placed := false
			for k in cands.size():
				var c: Vector2 = cands[k]
				# Slide along the free axis to stay on screen; reject if it then covers the target.
				if k < 2:
					c.x = clampf(c.x, m, vs.x - cs.x - m)
				else:
					c.y = clampf(c.y, m, vs.y - cs.y - m)
				var r := Rect2(c, cs)
				if r.position.x >= m and r.position.y >= m and r.end.x <= vs.x - m and r.end.y <= vs.y - m and not r.intersects(tr.grow(8)):
					pos = c
					placed = true
					break
			if not placed:
				pos = Vector2(vs.x - cs.x - 40.0, 124.0)
		_card.position = pos
		_draw_node.target_rect = tr
		_draw_node.card_rect = Rect2(pos, cs)
		_draw_node.has_target = tr.size != Vector2.ZERO
		_draw_node.queue_redraw()
		_card.pivot_offset = cs * 0.5
		_card.scale = Vector2(0.94, 0.94)
		var tw := _card.create_tween().set_parallel()
		tw.tween_property(_card, "modulate:a", 1.0, UITheme.T_MED)
		tw.tween_property(_card, "scale", Vector2.ONE, UITheme.T_MED).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _close() -> void:
		queue.clear()
		queue_free()

	## Esc closes the hint (it counts as seen) instead of leaving the screen.
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			if _card and is_instance_valid(_card):
				Hints.mark_seen(str(_card.get_meta("hint_id", "")))
			Audio.ui("ui_back")
			_close()
			get_viewport().set_input_as_handled()


## Draws the pulsing outline around the target and the arrow from the card to it.
class HintDraw extends Control:
	var target_rect := Rect2()
	var card_rect := Rect2()
	var has_target := false
	var _t := 0.0

	func _process(delta: float) -> void:
		if has_target:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if not has_target:
			return
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		var col := Color(Hints.ACCENT, 0.55 + 0.4 * pulse)
		var r := target_rect.grow(6.0 + 3.0 * pulse)
		draw_rect(r, Color(Hints.ACCENT, 0.06), true)
		draw_rect(r, col, false, 3.0)
		# Arrow: from the card edge closest to the target to the target outline.
		var tc := r.get_center()
		var from := Vector2(clampf(tc.x, card_rect.position.x, card_rect.end.x), clampf(tc.y, card_rect.position.y, card_rect.end.y))
		var to := Vector2(clampf(from.x, r.position.x, r.end.x), clampf(from.y, r.position.y, r.end.y))
		if from.distance_to(to) < 12.0:
			return
		var dir := (to - from).normalized()
		var tip := to - dir * 4.0
		draw_line(from, tip - dir * 14.0, col, 4.0, true)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + side * 10.0, tip - dir * 18.0 - side * 10.0]), col)
