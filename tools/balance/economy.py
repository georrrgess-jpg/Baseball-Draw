#!/usr/bin/env python3
"""Economy model: projects a player's progress over N hours from the game's reward data.

  tools/balance/economy.py                     # 20 hours, default mix, 200 simulated players
  tools/balance/economy.py --policy bundles    # a player who buys 10-pack bundles whenever possible
  tools/balance/economy.py --hours 30 --players 500 --json out.json

What it reads (so a data change is reflected without editing this file):
  data/packs.json (prices, odds, slots), data/cards.json (rarities), data/defenders.json (XP curve, level road,
  unlock levels, signature cards), data/modes.json + data/difficulties.json (reward multipliers),
  data/ranks.json (RP thresholds), data/gear.json (gear prices), data/achievements.json (stars),
  src/autoload/db.gd (COPIES_TO_UPGRADE, COINS_TO_UPGRADE), src/autoload/profile.gd (starter cards, starting
  coins, account XP curve, level-up coins, bundle size/discount).
What it mirrors by hand (keep in sync): the formulas in src/core/rewards.gd (coins, XP, defender XP, packs, RP),
Profile.roll_pack (60 % preference for unowned cards, commons give 2 copies) and RunState.round_price.

Per-game inputs (in-run coins, outs, game length) come from the balance simulator's averages for a fresh
profile; see GAME_TABLE. The player model: a game mix (Quick / Standard / Endless) at one difficulty with a fixed
win rate, a Promotion Challenge as soon as one is available, every pack opened at once, cards upgraded as soon as
copies and coins allow (cheapest first), spare coins spent on gear and Rookie Packs per --policy.
"""
import argparse
import json
import math
import os
import random
import re
import statistics

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]


def jload(name):
	return json.load(open(os.path.join(ROOT, "data", name)))


def gd_const(path, name):
	text = open(os.path.join(ROOT, path)).read()
	m = re.search(r"const %s\s*:?=\s*(\{.*?\}|\[.*?\])" % name, text, re.S)
	src = m.group(1).replace("\n", " ")
	src = re.sub(r",\s*([}\]])", r"\1", src)
	return json.loads(src)


def gd_number(path, pattern, cast=float):
	text = open(os.path.join(ROOT, path)).read()
	return cast(re.search(pattern, text).group(1))


def round_price(v):
	"""RunState.round_price: 10s under 100, 25s up to 500, 50s above."""
	if v < 100:
		return max(10, int(round(v / 10.0)) * 10)
	if v < 500:
		return int(round(v / 25.0)) * 25
	return int(round(v / 50.0)) * 50


# Per (mode, difficulty, won): in-run coins earned, outs, innings cleared and minutes of play
# (game time from the simulator plus ~40 s per inning of setup/dugout and ~1 min of results/packs).
# Measured with tools/balance/simulate.py on the Update 5 balance (fresh profile, starter deck).
GAME_TABLE = {
	("quick", True): {"coins": 870, "outs": 190, "cleared": 3, "minutes": 7.0},
	("quick", False): {"coins": 560, "outs": 120, "cleared": 2, "minutes": 5.5},
	("standard", True): {"coins": 3300, "outs": 640, "cleared": 9, "minutes": 22.0},
	("standard", False): {"coins": 1900, "outs": 400, "cleared": 6, "minutes": 15.0},
	("endless", False): {"coins": 2600, "outs": 520, "cleared": 9, "minutes": 20.0},
	("ranked", True): {"coins": 870, "outs": 190, "cleared": 3, "minutes": 7.0},
	("ranked", False): {"coins": 560, "outs": 120, "cleared": 2, "minutes": 5.5},
}


class Data:
	def __init__(self):
		self.cards = jload("cards.json")["cards"]
		self.card_rarity = {c["id"]: c["rarity"] for c in self.cards}
		self.max_level = jload("cards.json").get("max_level", 5)
		self.packs = {p["id"]: p for p in jload("packs.json")["packs"]}
		d = jload("defenders.json")
		self.xp_curve = d["xp_curve"]
		self.level_rewards = d["level_rewards"]
		self.def_max = d.get("max_level", 10)
		self.defenders = d["defenders"]
		self.modes = {m["id"]: m for m in jload("modes.json")["modes"]}
		self.diffs = {x["id"]: x for x in jload("difficulties.json")["difficulties"]}
		self.divisions = jload("ranks.json")["divisions"]
		self.gear_prices = sorted(int(g["price"]) for g in jload("gear.json")["gear"])
		self.achievements = jload("achievements.json")["achievements"]
		self.copies = gd_const("src/autoload/db.gd", "COPIES_TO_UPGRADE")
		self.coins_up = gd_const("src/autoload/db.gd", "COINS_TO_UPGRADE")
		prof = "src/autoload/profile.gd"
		self.starter = gd_const(prof, "STARTER_CARDS")
		self.start_coins = gd_number(prof, r'"coins":\s*(\d+)', int)
		self.bundle_size = gd_number(prof, r"BUNDLE_SIZE\s*:=\s*(\d+)", int)
		self.bundle_discount = gd_number(prof, r"BUNDLE_DISCOUNT\s*:=\s*([\d.]+)")
		m = re.search(r"func xp_to_next.*?return\s+(\d+)\s*\+\s*(\d+)\s*\*", open(os.path.join(ROOT, prof)).read(), re.S)
		self.xp_base, self.xp_step = int(m.group(1)), int(m.group(2))
		self.levelup_coins = gd_number(prof, r"data\.coins \+= (\d+)\n\t\tadd_pack", int)

	def xp_to_next(self, level):
		return self.xp_base + self.xp_step * (level - 1)

	def bundle_price(self, pack):
		return round_price(self.packs[pack]["price_coins"] * self.bundle_size * self.bundle_discount)


class Player:
	def __init__(self, data, rng, args):
		self.d, self.rng, self.a = data, rng, args
		self.coins = data.start_coins
		self.stars = 0
		self.level, self.xp = 1, 0
		self.rp, self.division = 0, 0
		self.cards = {c["id"]: {"owned": c["id"] in data.starter, "level": 1, "copies": 0} for c in data.cards}
		self.team = [x["id"] for x in data.defenders if x.get("unlock", {}).get("type") == "default"][:6]
		self.def_level = {x["id"]: 1 for x in data.defenders}
		self.def_xp = {x["id"]: 0 for x in data.defenders}
		self.unlocked = set(self.team)
		self.packs = []
		self.minutes = 0.0
		self.gear_owned = 0
		self.stats = {"outs": 0, "wins_quick": 0, "wins_standard": 0, "games": 0, "packs_earned": 0, "packs_bought": 0,
			"coins_earned": 0, "upgrades": 0, "coins_upgrades": 0, "coins_packs": 0, "coins_gear": 0, "best_endless": 0}
		self.achieved = set()
		self.timeline = []

	# ---- rewards.gd mirror
	def play(self, mode, won):
		g = GAME_TABLE[(mode, won)]
		m, df = self.d.modes[mode], self.d.diffs[self.a.difficulty]
		mult = m.get("reward_mult", 1.0) * df.get("reward", 1.0)
		cleared = g["cleared"]
		coins = int(round((g["coins"] * 0.55 + cleared * 22 + (160 if won else 0)) * mult))
		xp = max(15, int(round((g["outs"] * 2.0 + cleared * 30 + (220 if won else 0)) * mult)))
		self.coins += coins
		self.stats["coins_earned"] += coins
		self.add_xp(xp)
		outs_each = g["outs"] / 6.0
		for i, did in enumerate(self.team):
			self.add_def_xp(did, int(round((xp * 0.55 + outs_each * 3) * (1.5 if i == 0 else 1.0))))
		self.add_pack("rookie")
		if mode == "standard":
			for _ in range(cleared // 3):
				self.add_pack("rookie")
			if won:
				self.add_pack("champion" if self.a.difficulty in ("veteran", "legend") else "pro")
		elif mode == "quick" and won:
			self.add_pack("rookie")
		elif mode == "endless":
			for _ in range(min(cleared // 3, 4)):
				self.add_pack("rookie")
			self.stats["best_endless"] = max(self.stats["best_endless"], cleared + 1)
		elif mode == "ranked" and won:
			self.add_pack("pro")
		rpm = df.get("rp", 1.0)
		rp = {"standard": (60 if won else cleared * 4), "quick": (22 if won else cleared * 3),
			"endless": cleared * 5, "ranked": (30 if won else 0)}[mode]
		self.rp += int(round(rp * rpm))
		if mode == "ranked" and won:
			self.division = min(self.division + 1, len(self.d.divisions) - 1)
		self.stats["outs"] += g["outs"]
		self.stats["games"] += 1
		if won and mode in ("quick", "standard"):
			self.stats["wins_" + mode] += 1
		self.minutes += g["minutes"]
		self.check_achievements(mode, won)

	def add_xp(self, n):
		self.xp += n
		while self.level < 50 and self.xp >= self.d.xp_to_next(self.level):
			self.xp -= self.d.xp_to_next(self.level)
			self.level += 1
			self.coins += self.d.levelup_coins
			self.add_pack("pro" if self.level % 5 == 0 else "rookie")
			for x in self.d.defenders:
				u = x.get("unlock", {})
				if u.get("type") == "level" and self.level >= int(u["value"]) and x["id"] not in self.unlocked:
					self.unlocked.add(x["id"])
					self.packs.append(("signature", x["signature"]))

	def add_def_xp(self, did, n):
		self.def_xp[did] += n
		lv = self.def_level[did]
		while lv < self.d.def_max and self.def_xp[did] >= self.d.xp_curve[lv] - self.d.xp_curve[lv - 1]:
			self.def_xp[did] -= self.d.xp_curve[lv] - self.d.xp_curve[lv - 1]
			lv += 1
			r = self.d.level_rewards.get(str(lv), {})
			self.coins += int(r.get("coins", 0))
			if "pack" in r:
				self.add_pack(r["pack"])
		self.def_level[did] = lv

	def add_pack(self, t, card=None):
		self.packs.append((t, card))
		self.stats["packs_earned"] += 1

	# ---- Profile.roll_pack mirror
	def open_packs(self):
		while self.packs:
			t, fixed = self.packs.pop()
			if fixed:
				self.grant(fixed)
				continue
			p = self.d.packs[t]
			out = []
			for slot in p["slots"]:
				r = self.roll_rarity(p["weights"])
				mn = slot.get("min", "common")
				if RARITIES.index(r) < RARITIES.index(mn):
					r = mn
				pool = [c for c, rr in self.d.card_rarity.items() if rr == r and c not in out] or \
					[c for c in self.d.card_rarity if c not in out]
				unowned = [c for c in pool if not self.cards[c]["owned"]]
				choice = unowned if unowned and self.rng.random() < 0.6 else pool
				out.append(self.rng.choice(choice))
			for c in out:
				self.grant(c)

	def roll_rarity(self, w):
		total = sum(w.get(r, 0) for r in RARITIES)
		x = self.rng.random() * total
		for r in RARITIES:
			x -= w.get(r, 0)
			if x <= 0:
				return r
		return "common"

	def grant(self, cid):
		c = self.cards[cid]
		if not c["owned"]:
			c["owned"] = True
		else:
			c["copies"] += 2 if self.d.card_rarity[cid] == "common" else 1

	# ---- spending
	def upgrade_cost(self, cid):
		lv = self.cards[cid]["level"]
		if lv >= self.d.max_level:
			return None
		return self.d.copies[self.d.card_rarity[cid]][lv], self.d.coins_up[lv]

	def spend(self):
		changed = True
		while changed:
			changed = False
			best = None
			for cid, c in self.cards.items():
				cost = self.upgrade_cost(cid)
				if c["owned"] and cost and c["copies"] >= cost[0] and self.coins >= cost[1]:
					if best is None or cost[1] < best[1][1]:
						best = (cid, cost)
			if best:
				cid, (cp, co) = best
				self.cards[cid]["copies"] -= cp
				self.cards[cid]["level"] += 1
				self.coins -= co
				self.stats["upgrades"] += 1
				self.stats["coins_upgrades"] += co
				changed = True
		# Gear: one piece at a time once the player has a cushion.
		if self.gear_owned < len(self.d.gear_prices) and self.coins >= self.d.gear_prices[self.gear_owned] + self.a.reserve:
			self.coins -= self.d.gear_prices[self.gear_owned]
			self.stats["coins_gear"] += self.d.gear_prices[self.gear_owned]
			self.gear_owned += 1
		if self.collection_done():
			return
		rookie = self.d.packs["rookie"]["price_coins"]
		bundle = self.d.bundle_price("rookie")
		if self.a.policy == "bundles":
			while self.coins >= bundle:
				self.buy("rookie", self.d.bundle_size, bundle)
		elif self.a.policy == "balanced":
			if self.coins >= bundle + self.a.reserve:
				self.buy("rookie", self.d.bundle_size, bundle)
			while self.coins >= rookie + self.a.reserve:
				self.buy("rookie", 1, rookie)
		# Stars: Champion Packs.
		cs = self.d.packs["champion"]["price_stars"]
		while self.stars >= cs:
			self.stars -= cs
			self.add_pack("champion")
			self.stats["packs_earned"] -= 1
			self.stats["packs_bought"] += 1

	def buy(self, t, n, price):
		self.coins -= price
		self.stats["coins_packs"] += price
		self.stats["packs_bought"] += n
		for _ in range(n):
			self.packs.append((t, None))

	def collection_done(self):
		return all(c["owned"] for c in self.cards.values())

	def check_achievements(self, mode, won):
		s = self.stats
		stat = {"total_outs": s["outs"], "wins_quick": s["wins_quick"], "wins_standard": s["wins_standard"],
			"boss_iron_slugger": s["wins_quick"] + s["wins_standard"], "boss_phantom_captain": s["wins_standard"],
			"boss_grand_slammer": s["wins_standard"], "double_plays": s["games"], "triple_plays": s["games"],
			"grand_combos": s["games"], "clean_innings": s["games"] * 2, "cards_played": s["games"] * 25,
			"shield_saves": s["games"] // 3, "max_card_level": max(c["level"] for c in self.cards.values()),
			"max_defender_level": max(self.def_level.values()), "cards_owned": sum(c["owned"] for c in self.cards.values()),
			"defenders_owned": len(self.unlocked), "division": self.division, "best_endless_inning": s["best_endless"]}
		for a in self.d.achievements:
			if a["id"] not in self.achieved and stat.get(a["stat"], 0) >= a["goal"]:
				self.achieved.add(a["id"])
				self.stars += int(a.get("stars", 0))

	def snapshot(self):
		owned = {r: 0 for r in RARITIES}
		maxed = {r: 0 for r in RARITIES}
		for cid, c in self.cards.items():
			r = self.d.card_rarity[cid]
			owned[r] += c["owned"]
			maxed[r] += c["level"] >= self.d.max_level
		return {"hours": self.minutes / 60.0, "owned": owned, "maxed": maxed, "level": self.level, "coins": self.coins,
			"division": self.division, "def_avg": statistics.mean(self.def_level[d] for d in self.team),
			"card_levels": sum(c["level"] - 1 for c in self.cards.values()), **{k: v for k, v in self.stats.items()}}


def run_player(data, args, seed):
	rng = random.Random(seed)
	p = Player(data, rng, args)
	mix = [("quick", args.quick), ("standard", args.standard), ("endless", args.endless)]
	total = sum(w for _, w in mix)
	next_mark = 0.0
	while p.minutes < args.hours * 60:
		nd = data.divisions[p.division + 1] if p.division + 1 < len(data.divisions) else None
		if nd and p.rp >= nd["rp_required"]:
			mode = "ranked"
			won = rng.random() < args.ranked_win
		else:
			x = rng.random() * total
			mode = "quick"
			for m, w in mix:
				x -= w
				if x <= 0:
					mode = m
					break
			won = False if mode == "endless" else rng.random() < args.win
		p.play(mode, won)
		p.open_packs()
		p.spend()
		p.open_packs()
		while p.minutes / 60.0 >= next_mark:
			p.timeline.append(p.snapshot())
			next_mark += 1.0
	p.timeline.append(p.snapshot())
	return p


def first_hour(timelines, fn):
	"""Median hour at which fn(snapshot) first holds (None if not within the horizon for most players)."""
	hits = []
	for tl in timelines:
		h = next((s["hours"] for s in tl if fn(s)), None)
		hits.append(h if h is not None else math.inf)
	hits.sort()
	med = hits[len(hits) // 2]
	return None if med == math.inf else med


def main():
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--hours", type=float, default=20)
	ap.add_argument("--players", type=int, default=200)
	ap.add_argument("--difficulty", default="standard")
	ap.add_argument("--win", type=float, default=0.65, help="win rate in Quick and Standard games")
	ap.add_argument("--ranked-win", type=float, default=0.6)
	ap.add_argument("--quick", type=float, default=0.5, help="share of games that are Quick Defense")
	ap.add_argument("--standard", type=float, default=0.35)
	ap.add_argument("--endless", type=float, default=0.15)
	ap.add_argument("--policy", default="balanced", choices=["balanced", "bundles", "none"],
		help="spare coins: balanced = bundles/packs above a reserve, bundles = every bundle affordable, none = no packs")
	ap.add_argument("--reserve", type=int, default=600, help="coins kept for upgrades before buying packs or gear")
	ap.add_argument("--json", default="")
	args = ap.parse_args()
	data = Data()
	players = [run_player(data, args, 1000 + i) for i in range(args.players)]
	tls = [p.timeline for p in players]
	H = int(args.hours)
	counts = {r: sum(1 for c in data.cards if c["rarity"] == r) for r in RARITIES}

	def med(h, key, sub=None):
		vals = []
		for tl in tls:
			s = min(tl, key=lambda x: abs(x["hours"] - h))
			vals.append(s[key][sub] if sub else s[key])
		return statistics.median(vals)

	print("# Economy projection: %d players, %g h, %s difficulty, win %.0f %%, mix quick/standard/endless %g/%g/%g, policy %s\n" % (
		args.players, args.hours, args.difficulty, args.win * 100, args.quick, args.standard, args.endless, args.policy))
	print("| Hour | Games | Account lvl | Division | Team avg lvl | Packs earned | Packs bought | Cards owned | Card upgrades | Coins earned | Coins on upgrades / packs / gear | Coins held |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	rows = []
	for h in [1, 2, 3, 5, 8, 12, 16, 20, 25, 30]:
		if h > H:
			break
		owned = sum(med(h, "owned", r) for r in RARITIES)
		row = (h, med(h, "games"), med(h, "level"), data.divisions[int(med(h, "division"))]["name"], med(h, "def_avg"),
			med(h, "packs_earned"), med(h, "packs_bought"), owned, med(h, "upgrades"), med(h, "coins_earned"),
			"%d / %d / %d" % (med(h, "coins_upgrades"), med(h, "coins_packs"), med(h, "coins_gear")), med(h, "coins"))
		rows.append(row)
		print("| %d | %d | %d | %s | %.1f | %d | %d | %d / %d | %d | %d | %s | %d |" % (row[:7] + (owned, len(data.cards)) + row[8:]))
	print("\n| Milestone | Median hour |")
	print("|---|---|")
	ms = {}
	for r in RARITIES:
		ms["all %s owned (%d)" % (r, counts[r])] = first_hour(tls, lambda s, r=r: s["owned"][r] >= counts[r])
	ms["whole collection owned (%d)" % len(data.cards)] = first_hour(tls, lambda s: sum(s["owned"].values()) >= len(data.cards))
	for r in RARITIES:
		ms["first %s card at max level" % r] = first_hour(tls, lambda s, r=r: s["maxed"][r] >= 1)
	ms["all commons at max level"] = first_hour(tls, lambda s: s["maxed"]["common"] >= counts["common"])
	ms["team average level 5"] = first_hour(tls, lambda s: s["def_avg"] >= 5)
	ms["team average level 10"] = first_hour(tls, lambda s: s["def_avg"] >= 10)
	for i, dv in enumerate(data.divisions[1:], 1):
		ms["%s division" % dv["name"]] = first_hour(tls, lambda s, i=i: s["division"] >= i)
	for k, v in ms.items():
		print("| %s | %s |" % (k, "%.1f" % v if v is not None else "> %g" % args.hours))
	last = [tl[-1] for tl in tls]
	hours = statistics.mean(s["hours"] for s in last)
	print("\nPer hour (whole run): %.1f packs earned, %.1f bought, %.1f card upgrades, %d coins earned." % (
		statistics.mean(s["packs_earned"] for s in last) / hours, statistics.mean(s["packs_bought"] for s in last) / hours,
		statistics.mean(s["upgrades"] for s in last) / hours, statistics.mean(s["coins_earned"] for s in last) / hours))
	print("Rookie bundle: %d coins = %.1f h of coin income; Pro bundle %d coins." % (data.bundle_price("rookie"),
		data.bundle_price("rookie") / (statistics.mean(s["coins_earned"] for s in last) / hours), data.bundle_price("pro")))
	if args.json:
		json.dump({"milestones": ms, "rows": rows}, open(args.json, "w"), indent=1, default=str)


if __name__ == "__main__":
	main()
