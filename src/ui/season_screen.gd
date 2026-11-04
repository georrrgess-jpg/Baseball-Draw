class_name SeasonScreen
extends MenuScreen
## The Season Pass (Update 9): the season's name and countdown, the current tier with its XP
## bar, CLAIM ALL, and a horizontally scrolling track of the 30 free tiers (reward picture and
## text; claimed / ready to claim / reached / locked), ending with the post-tier-30 bonus.
## Data and rules: Season (src/core/season.gd).

const NODE_W := 190
const NODE_H := 420
const CARD_H := 300
## After the last tier, a Pro Pack every BONUS_XP season XP (docs/plans/UPDATE_9_PLAN.md).
const BONUS_XP := 1000
## How season XP is earned (plan values; data/season.json "xp" overrides them when present).
const XP_SOURCES := [["inning", "Play a game", "game", 100], ["trophy", "Win a game", "win", 60],
	["target", "Claim a mission", "mission", 80], ["calendar", "Daily Challenge", "daily", 100]]

var _root: VBoxContainer
var _scroll: ScrollContainer
var _track: HBoxContainer
var _claim_all: Button
var _countdown: Label
var _ready_label: Label
## tier -> its node on the track (a flat Button: focusable, Enter/click claims it).
var tier_buttons := {}
var _flash_tiers: Array = []
var _tick := 0.0


func _ready() -> void:
	setup_screen("SEASON PASS", "Earn season XP in every game: 30 tiers of free rewards")
	_root = VBoxContainer.new()
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 14)
	content.add_child(_root)
	_root.add_child(_header_panel())
	_root.add_child(_track_panel())
	_root.add_child(_earn_panel())
	_refresh()
	if Hints.SCREENS.has("season"):
		set_help("season", func() -> Dictionary: return {"season_intro": _track})
	_scroll_to_current.call_deferred()


func _enter_targets() -> Array:
	return _root.get_children() if _root else []


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or _countdown == null:
		return
	_tick = 1.0
	_countdown.text = "ENDS IN  " + format_left(int(Season.current().get("seconds_left", 0)))


## "12d 04h" while more than a day is left, then "05:12:33".
static func format_left(secs: int) -> String:
	secs = maxi(0, secs)
	if secs >= 86400:
		return "%dd %02dh" % [secs / 86400, (secs / 3600) % 24]
	return "%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]


# ---------------------------------------------------------------- header

func _header_panel() -> Control:
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.4), 18)
	p.name = "SeasonHeader"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	p.add_child(hb)
	return p


func _fill_header() -> void:
	var p: PanelContainer = _root.get_node("SeasonHeader")
	var hb: HBoxContainer = p.get_child(0)
	for c in hb.get_children():
		c.queue_free()
	var cur := Season.current()
	# Season name and countdown.
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.custom_minimum_size = Vector2(330, 0)
	hb.add_child(nv)
	# The theme ("Opening Day") is the headline when the season has one, else its name.
	var nm := str(cur.get("theme", ""))
	if nm == "":
		nm = str(cur.get("name", ""))
	if nm == "":
		nm = "Season %d" % int(cur.get("number", 1))
	var cap := "SEASON %d" % int(cur.get("number", 1))
	if nm.to_upper() == cap:
		cap = "CURRENT SEASON"
	if int(cur.get("days", 0)) > 0:
		cap += "  ·  DAY %d OF %d" % [int(cur.get("day", 1)), int(cur.days)]
	nv.add_child(UITheme.label(cap, UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold()))
	var tl := UITheme.title(nm.to_upper(), 50, UITheme.OFFWHITE)
	tl.name = "SeasonName"
	nv.add_child(tl)
	var cd := HBoxContainer.new()
	cd.add_theme_constant_override("separation", 8)
	nv.add_child(cd)
	cd.add_child(UITheme.icon_rect("calendar", 26, UITheme.GOLD))
	_countdown = UITheme.label("ENDS IN  " + format_left(int(cur.get("seconds_left", 0))), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header())
	_countdown.name = "SeasonCountdown"
	cd.add_child(_countdown)
	# After a rollover: the old season's unclaimed rewards were paid out automatically.
	var ss: Variant = Profile.data.get("season", {})
	var ro: Dictionary = (ss as Dictionary).get("last_rollover", {}) if ss is Dictionary else {}
	if not ro.is_empty() and int(ro.get("to", 0)) == int(cur.get("id", 0)) and not (ro.get("tiers", []) as Array).is_empty():
		var n := (ro.tiers as Array).size()
		var rl := UITheme.label("Season %d ended: %d unclaimed reward%s added to your account." % [int(ro.get("season", 0)), n, "" if n == 1 else "s"],
			UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size = Vector2(330, 0)
		nv.add_child(rl)
	# Current tier and XP bar.
	var pr := Season.tier_progress()
	var tier := int(pr.get("tier", 0))
	var maxed := tier >= Season.TIERS
	var tv := HBoxContainer.new()
	tv.add_theme_constant_override("separation", 18)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tv)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.GOLD, 0.18), UITheme.GOLD, 3, 52, 4))
	badge.custom_minimum_size = Vector2(104, 104)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", -10)
	badge.add_child(bv)
	var bt := UITheme.label("TIER", UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold())
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(bt)
	var bn := UITheme.title(str(tier), 54, UITheme.GOLD)
	bn.name = "TierNumber"
	bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(bn)
	tv.add_child(badge)
	var xv := VBoxContainer.new()
	xv.alignment = BoxContainer.ALIGNMENT_CENTER
	xv.add_theme_constant_override("separation", 6)
	xv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(xv)
	var xp_in := int(pr.get("xp_in", 0))
	var xp_need := maxi(1, int(pr.get("xp_need", Season.XP_PER_TIER)))
	if maxed:
		var bonus_in := maxi(0, Season.xp() - Season.TIERS * Season.XP_PER_TIER) % BONUS_XP
		xv.add_child(UITheme.label("ALL 30 TIERS REACHED  ·  BONUS ROUND", UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_header()))
		var bb := UITheme.bar(UITheme.GOLD, 18, BONUS_XP, bonus_in)
		bb.name = "TierBar"
		xv.add_child(bb)
		xv.add_child(UITheme.label("%s / %s XP to the next bonus Pro Pack" % [UITheme.format_int(bonus_in), UITheme.format_int(BONUS_XP)], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold()))
	else:
		xv.add_child(UITheme.label("TIER %d  ▶  %d" % [tier, tier + 1], UITheme.FS_H3, UITheme.OFFWHITE, UITheme.font_header()))
		var bar := UITheme.bar(UITheme.GOLD, 18, xp_need, 0)
		bar.name = "TierBar"
		xv.add_child(bar)
		bar.create_tween().tween_property(bar, "value", float(xp_in), 0.8).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var nxt := _tier_entry(tier + 1)
		var nt := "%s / %s XP to tier %d" % [UITheme.format_int(xp_in), UITheme.format_int(xp_need), tier + 1]
		if not nxt.is_empty():
			nt += "  ·  next: " + reward_label(nxt.get("reward", {}))
		var nl := UITheme.label(nt, UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold())
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.custom_minimum_size = Vector2(200, 0)
		xv.add_child(nl)
	# CLAIM ALL.
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 4)
	hb.add_child(cv)
	var n := _claimable().size()
	_claim_all = UITheme.button("CLAIM ALL (%d)" % n if n > 0 else "CLAIM ALL", "primary", UITheme.FS_LEAD, "gift", UITheme.GOLD.darkened(0.25))
	_claim_all.name = "ClaimAll"
	_claim_all.custom_minimum_size = Vector2(250, UITheme.BTN_H_LARGE)
	_claim_all.disabled = n == 0
	_claim_all.tooltip_text = "Claim every reward you have reached" if n > 0 else "Nothing to claim yet: play games to earn season XP"
	_claim_all.pressed.connect(_on_claim_all)
	cv.add_child(_claim_all)
	_ready_label = UITheme.label("%d reward%s ready" % [n, "" if n == 1 else "s"] if n > 0 else "Total season XP: %s" % UITheme.format_int(Season.xp()),
		UITheme.FS_SMALL, UITheme.GOLD if n > 0 else UITheme.MUTED, UITheme.font_body_bold())
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_ready_label)


# ---------------------------------------------------------------- track

func _track_panel() -> Control:
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.25), 14)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UITheme.section_header("SEASON REWARDS", "trophy", UITheme.GOLD, UITheme.FS_H3))
	_scroll = ScrollContainer.new()
	_scroll.name = "SeasonTrack"
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 300)
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_track = HBoxContainer.new()
	_track.add_theme_constant_override("separation", 0)
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_track)
	return p


func _fill_track() -> void:
	for c in _track.get_children():
		c.queue_free()
	tier_buttons.clear()
	var tiers := Season.tiers()
	if tiers.is_empty():
		var l := UITheme.label("This season's rewards are on their way. Keep playing: season XP still counts.", UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold())
		l.custom_minimum_size = Vector2(900, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_track.add_child(l)
		return
	var cur := Season.tier()
	var claimable := _claimable()
	for e in tiers:
		_track.add_child(_tier_node(e, cur, int(e.tier) in claimable, tiers.size()))
	_track.add_child(_bonus_node(cur >= Season.TIERS))


func _tier_entry(t: int) -> Dictionary:
	for e in Season.tiers():
		if int(e.get("tier", 0)) == t:
			return e
	return {}


## One tier: the reward card, the track with the tier number, and its state underneath.
func _tier_node(e: Dictionary, cur: int, can_claim: bool, count: int) -> Control:
	var t := int(e.tier)
	var reward: Dictionary = e.get("reward", {})
	var claimed := bool(e.get("claimed", false))
	var reached := bool(e.get("reached", t <= cur))
	var nxt := t == cur + 1
	var big := is_big_reward(reward)
	var col := reward_color(reward)
	var b := Button.new()
	b.name = "Tier%d" % t
	b.custom_minimum_size = Vector2(NODE_W, NODE_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	var flat := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, flat)
	var fs := UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.9), 2, 12, 0)
	b.add_theme_stylebox_override("focus", fs)
	b.tooltip_text = "Tier %d (%s XP): %s%s" % [t, UITheme.format_int(t * Season.XP_PER_TIER), reward_label(reward),
		"\nClaimed" if claimed else ("\nReady to claim!" if can_claim else "")]
	b.pressed.connect(_on_tier_pressed.bind(t))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 4
	v.offset_bottom = -4
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	# Reward card.
	var card := PanelContainer.new()
	var border := Color(col, 0.75) if (big or can_claim) else Color(1, 1, 1, 0.14)
	var bg := Color(0.05, 0.08, 0.13, 0.95)
	if can_claim:
		border = UITheme.GOLD
		bg = Color(0.2, 0.15, 0.04, 0.96)
	elif nxt:
		border = Color(UITheme.GOLD, 0.6)
	card.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 3 if (can_claim or big) else 1, 12, 8))
	card.custom_minimum_size = Vector2(NODE_W - 18, CARD_H)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(card)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 4)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var pic := reward_picture(reward, 172 if big else 150)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cv.add_child(pic)
	var rl := UITheme.label(reward_label(reward, true), UITheme.FS_LEAD + 2, col.lightened(0.25) if not claimed else UITheme.MUTED, UITheme.font_header())
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.max_lines_visible = 2
	rl.custom_minimum_size = Vector2(NODE_W - 34, 0)
	cv.add_child(rl)
	if claimed or (not reached and not nxt):
		pic.modulate = Color(0.5, 0.5, 0.55) if claimed else Color(0.75, 0.75, 0.8)
	if claimed:
		pic.add_child(UITheme.icon_rect("check", 48, UITheme.GREEN))   # centred over the picture
	# Track: line, tier circle, line.
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	for side in 2:
		var line := ColorRect.new()
		var lit := (t <= cur) if side == 0 else (t < cur)
		line.color = Color(UITheme.GOLD, 0.85) if lit else Color(1, 1, 1, 0.12)
		if side == 0 and t == 1:
			line.color = Color(0, 0, 0, 0)
		line.custom_minimum_size = Vector2(0, 6)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.add_child(line)
		if side == 0:
			var circ := PanelContainer.new()
			var fill := Color(UITheme.GOLD, 0.9) if reached else Color(0.08, 0.1, 0.16, 0.95)
			var cb := Color.WHITE if nxt or t == cur else (Color(UITheme.GOLD.lightened(0.3), 0.9) if reached else Color(1, 1, 1, 0.18))
			circ.add_theme_stylebox_override("panel", UITheme.panel_style(fill, cb, 3 if t == cur else 2, 22, 2))
			circ.custom_minimum_size = Vector2(48, 48)
			circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var nl := UITheme.label(str(t), 23, Color(0.1, 0.08, 0.02) if reached else UITheme.OFFWHITE.darkened(0.3), UITheme.font_header())
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			circ.add_child(nl)
			tr.add_child(circ)
	# State.
	var st: Control
	if can_claim:
		st = UITheme.badge("CLAIM", UITheme.GOLD.darkened(0.2), UITheme.FS_LEAD)
		_pulse(card)
	elif claimed:
		st = UITheme.label("CLAIMED", UITheme.FS_SMALL, UITheme.GREEN, UITheme.font_body_bold())
	elif nxt:
		var pr := Season.tier_progress()
		st = UITheme.label("%d / %d XP" % [int(pr.xp_in), int(pr.xp_need)], UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold())
	else:
		st = UITheme.label("%s XP" % UITheme.format_int(t * Season.XP_PER_TIER), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if st is Label:
		(st as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	if t in _flash_tiers:
		card.modulate = Color(2.0, 1.8, 1.2)
		card.create_tween().tween_property(card, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tier_buttons[t] = b
	return b


## The bonus after tier 30: a Pro Pack for every BONUS_XP season XP.
func _bonus_node(open: bool) -> Control:
	var b := Button.new()
	b.name = "TierBonus"
	b.custom_minimum_size = Vector2(NODE_W + 70, NODE_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var flat := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, flat)
	b.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.9), 2, 12, 0))
	var earned := int(Profile.data.get("season", {}).get("bonus_claimed", 0))
	b.tooltip_text = "After tier 30, every %s season XP earns a Pro Pack." % UITheme.format_int(BONUS_XP)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_top = 4
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.12, 0.06, 0.2, 0.95), Color(UITheme.PURPLE.lightened(0.3), 0.9 if open else 0.4), 2, 12, 8))
	card.custom_minimum_size = Vector2(NODE_W + 40, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(card)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 2)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var cap := UITheme.label("BONUS ROUND", UITheme.FS_MIN, UITheme.PURPLE.lightened(0.4), UITheme.font_body_bold())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cap)
	var pic := reward_picture({"pack": "pro"}, 150)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not open:
		pic.modulate = Color(0.7, 0.7, 0.75)
	cv.add_child(pic)
	var tl := UITheme.label("Pro Pack every\n%s XP" % UITheme.format_int(BONUS_XP), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header())
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(tl)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 48)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var st := UITheme.label("%d earned" % earned if open else "After tier 30", UITheme.FS_SMALL, UITheme.PURPLE.lightened(0.4) if open else UITheme.MUTED, UITheme.font_body_bold())
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	tier_buttons[0] = b
	return b


func _pulse(c: Control) -> void:
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "modulate", Color(1.25, 1.18, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- reward helpers

## True for the rewards drawn bigger on the track (Champion Packs, uniforms, and Pro Packs).
static func is_big_reward(r: Dictionary) -> bool:
	return str(r.get("pack", "")) in ["champion", "pro"] or str(r.get("uniform", "")) != "" or "champion" in (r.get("packs", []) as Array)


static func reward_color(r: Dictionary) -> Color:
	if str(r.get("uniform", "")) != "":
		return UITheme.SCARLET.lightened(0.15)
	var pk := _main_pack(r)
	if pk != "":
		return Color(str(DB.pack(pk).get("accent", "#9FD3FF")))
	if int(r.get("stars", 0)) > 0:
		return UITheme.STAR
	if str(r.get("card", "")) != "":
		return DB.rarity_color(str(DB.card(str(r.card)).get("rarity", "common")))
	return UITheme.GOLD


static func _main_pack(r: Dictionary) -> String:
	if str(r.get("pack", "")) != "":
		return str(r.pack)
	var packs: Array = r.get("packs", [])
	for best in ["champion", "pro", "signature", "rookie"]:
		if best in packs:
			return best
	return str(packs[0]) if not packs.is_empty() else ""


## Reward text: Season.reward_text when it has one, else built from the reward's keys
## (coins, stars, pack/packs, uniform, card + copies). `short` drops the word "coins"/"stars".
static func reward_label(r: Dictionary, short := false) -> String:
	if r.is_empty():
		return "—"
	if not short:
		var t := Season.reward_text(r)
		if t != "":
			return t
	var parts: Array[String] = []
	if str(r.get("uniform", "")) != "":
		var u: Dictionary = DB.uniforms.get(str(r.uniform), {})
		parts.append("%s uniform" % str(u.get("name", "Season")))
	var packs: Array = (r.get("packs", []) as Array).duplicate()
	if str(r.get("pack", "")) != "":
		for i in maxi(1, int(r.get("count", 1))):
			packs.append(r.pack)
	var counts := {}
	for p in packs:
		counts[p] = int(counts.get(p, 0)) + 1
	for p in counts:
		var nm := str(DB.pack(str(p)).get("name", p))
		parts.append(nm if int(counts[p]) == 1 else "%d %ss" % [int(counts[p]), nm])
	if str(r.get("card", "")) != "":
		parts.append("%d× %s" % [maxi(1, int(r.get("copies", 1))), DB.card(str(r.card)).get("name", r.card)])
	if int(r.get("coins", 0)) > 0:
		parts.append("%s coins" % UITheme.format_int(int(r.coins)))
	if int(r.get("stars", 0)) > 0:
		parts.append("%d stars" % int(r.stars))
	return " + ".join(parts) if not parts.is_empty() else "—"


## A picture for a reward, `h` pixels tall: pack art, a card face, a uniform swatch, or a big
## coin / star icon.
static func reward_picture(r: Dictionary, h := 92.0) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(h * 0.85, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pk := _main_pack(r)
	if str(r.get("uniform", "")) != "":
		var u: Dictionary = DB.uniforms.get(str(r.uniform), {})
		var jer := JerseyIcon.new()
		jer.colors = u.get("colors", {})
		jer.custom_minimum_size = Vector2(h * 0.84, h * 0.78)
		holder.add_child(jer)
		if pk != "":   # the uniform comes with a pack: a small pack in the corner
			var pa := PackArt.new(pk)
			pa.custom_minimum_size = Vector2(h * 0.3, h * 0.46)
			pa.size = pa.custom_minimum_size
			pa.position = Vector2(h * 0.84 - h * 0.24, h * 0.78 - h * 0.36)
			pa.rotation = deg_to_rad(8.0)
			jer.add_child(pa)
	elif pk != "":
		var pa := PackArt.new(pk, str(r.get("card", "")) if pk == "signature" else "")
		pa.custom_minimum_size = Vector2(h * 0.65, h)
		holder.add_child(pa)
		var n := int(r.get("count", 1)) if str(r.get("pack", "")) != "" else (r.get("packs", []) as Array).size()
		if n > 1:
			var bd := UITheme.badge("×%d" % n, UITheme.SCARLET)
			bd.position = Vector2(h * 0.65 - 26, -6)
			pa.add_child(bd)
	elif str(r.get("card", "")) != "" and DB.cards.has(str(r.card)):
		var cv := CardView.new(str(r.card), 1)
		cv.set_card(str(r.card), maxi(1, Profile.card_level(str(r.card))))
		cv.custom_minimum_size = Vector2(h * 0.71, h)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.show_level = false
		holder.add_child(cv)
	elif int(r.get("stars", 0)) > 0:
		holder.add_child(UITheme.icon_rect("star", h * 0.78, UITheme.STAR))
	else:
		holder.add_child(UITheme.icon_rect("coin", h * 0.72, UITheme.GOLD))
	return holder


# ---------------------------------------------------------------- earn XP

func _earn_panel() -> Control:
	var p := UITheme.card_panel(UITheme.BORDER, 14)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var l := UITheme.label("EARN SEASON XP", UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_header())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	var overrides: Dictionary = Season.data().get("xp", {}) if Season.data().get("xp", {}) is Dictionary else {}
	for s in XP_SOURCES:
		var t := UITheme.tile_panel(Color(UITheme.GOLD, 0.2), 8)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 10)
		t.add_child(th)
		th.add_child(UITheme.icon_rect(str(s[0]), 30, UITheme.GOLD))
		var tl := UITheme.label(str(s[1]), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(tl)
		th.add_child(UITheme.label("+%d XP" % int(overrides.get(str(s[2]), s[3])), UITheme.FS_BODY, UITheme.GOLD, UITheme.font_header()))
		hb.add_child(t)
	return p


# ---------------------------------------------------------------- claiming

func _refresh() -> void:
	var focus_tier := _focused_tier()
	_fill_header()
	_fill_track()
	refresh_currency()
	_flash_tiers = []
	if focus_tier != -1:
		_restore_focus.call_deferred(focus_tier)


## Season.claimable() as plain ints.
static func _claimable() -> Array:
	return Season.claimable().map(func(x: Variant) -> int: return int(x))


func _on_tier_pressed(t: int) -> void:
	if not t in _claimable():
		Audio.ui("ui_error", -6.0)
		return
	var r := Season.claim(t)
	if r.is_empty():
		Audio.ui("ui_error")
		Router.toast("That reward can't be claimed right now.", "warn")
		return
	Audio.play("purchase")
	Router.toast("Tier %d reward: %s" % [t, reward_label(r if not r.has("reward") else r.reward)], "level")
	_flash_tiers = [t]
	_refresh()


func _on_claim_all() -> void:
	var tiers := _claimable()
	if tiers.is_empty():
		return
	var got := Season.claim_all()
	if got.is_empty():
		Audio.ui("ui_error")
		return
	Audio.play("purchase")
	Audio.play("level_up")
	Router.toast("Claimed %d season reward%s!" % [got.size(), "" if got.size() == 1 else "s"], "level")
	_flash_tiers = tiers
	_refresh()


func _scroll_to_current() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_scroll):
		return
	var claim := _claimable()
	var target: int = int(claim[0]) if not claim.is_empty() else clampi(Season.tier() + 1, 1, Season.TIERS)
	_scroll.scroll_horizontal = maxi(0, (target - 3) * NODE_W)
	var b: Button = tier_buttons.get(target)
	if b and is_instance_valid(b):
		b.grab_focus()
	elif _claim_all and not _claim_all.disabled:
		_claim_all.grab_focus()


func _focused_tier() -> int:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null:
		return -1
	if f == _claim_all:
		return -2
	for t in tier_buttons:
		if tier_buttons[t] == f:
			return int(t)
	return -1


func _restore_focus(t: int) -> void:
	if t == -2:
		if _claim_all and not _claim_all.disabled:
			_claim_all.grab_focus()
			return
		t = clampi(Season.tier() + 1, 1, Season.TIERS)
	var b: Button = tier_buttons.get(t)
	if b and is_instance_valid(b):
		b.grab_focus()



## A baseball jersey drawn in a uniform's colours (Season Pass uniform rewards).
class JerseyIcon extends Control:
	var colors: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := Color(str(colors.get("Jersey", "#C8102E")))
		var trim := Color(str(colors.get("JerseyTrim", "#F5B82E")))
		var num := Color(str(colors.get("Number", "#F4F1EA")))
		# Shirt silhouette: shoulders, short sleeves, a V neck.
		var pts := PackedVector2Array([
			Vector2(w * 0.36, h * 0.04), Vector2(w * 0.5, h * 0.2), Vector2(w * 0.64, h * 0.04),
			Vector2(w * 0.86, h * 0.12), Vector2(w * 1.0, h * 0.4), Vector2(w * 0.82, h * 0.48),
			Vector2(w * 0.78, h * 0.36), Vector2(w * 0.78, h * 0.98), Vector2(w * 0.22, h * 0.98),
			Vector2(w * 0.22, h * 0.36), Vector2(w * 0.18, h * 0.48), Vector2(0.0, h * 0.4),
			Vector2(w * 0.14, h * 0.12)])
		draw_colored_polygon(pts, body)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, trim, maxf(2.0, w * 0.035), true)
		# Button placket and the number.
		draw_line(Vector2(w * 0.5, h * 0.2), Vector2(w * 0.5, h * 0.96), Color(trim, 0.8), maxf(1.5, w * 0.02))
		var f := UITheme.font_display()
		var fs := int(h * 0.32)
		var t := "30"
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := Vector2(w * 0.5 - ts.x * 0.5, h * 0.66)
		draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 8), trim)
		draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num)
