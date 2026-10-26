class_name CardSystem
extends RefCounted
## Deck, hand (max 5), draw and discard piles, energy (max 10) and per-card cooldowns.
## The hand keeps fixed slots: a played card leaves an empty slot ("") that the next drawn
## card fills, so the other cards never move under the player's cursor.

signal hand_changed
signal energy_changed
signal card_drawn(id: String)

const MAX_HAND := 5
const MAX_ENERGY := 10.0
const BASE_REGEN := 1.0 / 2.2     # energy per second
const BASE_DRAW_INTERVAL := 4.5

var deck: Array = []
var draw_pile: Array = []
var discard: Array = []
var hand: Array = []
var energy := 5.0
var regen_mult := 1.0
var draw_interval := BASE_DRAW_INTERVAL
var cooldown_mult := 1.0
var draw_timer := 0.0
var cooldowns: Dictionary = {}   # card id -> seconds left
var infinite_energy := false
var played_this_run := 0
var rng := RandomNumberGenerator.new()


func setup(deck_ids: Array, start_energy: float, seed_value: int) -> void:
	rng.seed = seed_value
	deck = deck_ids.duplicate()
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)
	discard.clear()
	hand.clear()
	energy = clampf(start_energy, 0.0, MAX_ENERGY)
	draw(4)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func add_card(id: String) -> void:
	deck.append(id)
	draw_pile.insert(rng.randi_range(0, draw_pile.size()), id)


func draw(n: int) -> int:
	var drawn := 0
	for i in n:
		if hand_count() >= MAX_HAND:
			break
		if draw_pile.is_empty():
			if discard.is_empty():
				break
			draw_pile = discard.duplicate()
			discard.clear()
			_shuffle(draw_pile)
		var id: String = draw_pile.pop_back()
		var slot := hand.find("")
		if slot >= 0:
			hand[slot] = id
		else:
			hand.append(id)
		drawn += 1
		card_drawn.emit(id)
	if drawn > 0:
		hand_changed.emit()
	return drawn


## Refill the hand at the start of an inning.
func refill() -> void:
	draw(MAX_HAND - hand_count())


## Cards in hand (empty slots don't count).
func hand_count() -> int:
	return hand.size() - hand.count("")


func tick(delta: float, active: bool) -> void:
	for k in cooldowns.keys():
		cooldowns[k] = float(cooldowns[k]) - delta
		if cooldowns[k] <= 0.0:
			cooldowns.erase(k)
	if not active:
		return
	var before := energy
	energy = minf(MAX_ENERGY, energy + BASE_REGEN * regen_mult * delta)
	if infinite_energy:
		energy = MAX_ENERGY
	if int(before) != int(energy) or (energy >= MAX_ENERGY and before < MAX_ENERGY):
		energy_changed.emit()
	if hand_count() < MAX_HAND:
		draw_timer += delta
		if draw_timer >= draw_interval:
			draw_timer = 0.0
			draw(1)
	else:
		draw_timer = 0.0


func cost_of(id: String) -> int:
	return int(DB.card(id).get("cost", 0))


func cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


## Returns "" when playable, otherwise a short reason.
func check(index: int) -> String:
	if index < 0 or index >= hand.size() or hand[index] == "":
		return "No card"
	var id: String = hand[index]
	if cooldown_left(id) > 0.0:
		return "Cooling down"
	if energy + 0.0001 < cost_of(id):
		return "Not enough energy"
	return ""


## Spends energy, moves the card to discard and starts its cooldown.
func commit(index: int, cooldown_scale := 1.0) -> String:
	var id: String = hand[index]
	energy -= cost_of(id)
	hand[index] = ""
	discard.append(id)
	var cd := float(DB.card(id).get("cooldown", 0.0)) * cooldown_mult * cooldown_scale
	if cd > 0.0:
		cooldowns[id] = cd
	played_this_run += 1
	hand_changed.emit()
	energy_changed.emit()
	return id


func add_energy(n: float) -> void:
	energy = clampf(energy + n, 0.0, MAX_ENERGY)
	energy_changed.emit()


func next_draw_progress() -> float:
	return clampf(draw_timer / draw_interval, 0.0, 1.0)
