#!/usr/bin/env python3
"""Economy model: projects a player's progress over N hours from the game's reward data.

  tools/balance/economy.py                     # 20 hours, default mix, 200 simulated players
  tools/balance/economy.py --policy bundles    # a player who buys 10-pack bundles whenever possible
  tools/balance/economy.py --hours 30 --players 500 --json out.json
  tools/balance/economy.py --u8                # the Update 8 economy (no Update 9 systems), same cards

What it reads (so a data change is reflected without editing this file):
  data/packs.json (prices, odds, slots, pity, overflow coins), data/cards.json (rarities), data/defenders.json
  (XP curve, level road, unlock levels and coin prices, signature cards), data/modes.json + data/difficulties.json
  (reward multipliers), data/ranks.json (RP thresholds, promotion rewards), data/gear.json (gear prices),
  data/achievements.json (stars), data/account_levels.json (account level road), data/missions.json (mission
  rewards, starter chain), data/daily.json (Daily Challenge bonus), data/season.json (Season Pass XP and tiers),
  data/login_rewards.json (login calendar), data/shop.json (Daily Shop),
  src/autoload/db.gd (COPIES_TO_UPGRADE, COINS_TO_UPGRADE), src/autoload/profile.gd (starter cards, starting
  coins, account XP curve, level-up coins, bundle size/discount, streak bonus), src/core/rewards.gd (constants).
What it mirrors by hand (keep in sync): the formulas in src/core/rewards.gd (coins, XP, defender XP, packs, RP,
streak and first-win bonuses, Endless milestones), Profile.roll_pack and _open_one (60 % preference for unowned
cards, commons give 2 copies, pity, overflow), Shop.generate (deals), Season (tiers, bonus packs) and
RunState.round_price.

Per-game inputs (in-run coins, outs, game length) come from the balance simulator's averages for a fresh
profile; see GAME_TABLE. The player model: a game mix (Quick / Standard / Endless / Boss Rush) at one difficulty
with a fixed win rate, a Promotion Challenge as soon as one is available, every pack opened at once, cards
upgraded as soon as copies and coins allow (cheapest first), spare coins spent on gear and Rookie Packs per
--policy.

Update 6 adds days (--day-minutes of play each, default 60): the third game of each day is the Daily Challenge
(Quick Defense rewards plus the daily bonus), the three daily missions are claimed after the 2nd, 4th and 6th game
of the day, the weekly mission after every 7th day, the "Learn the ropes" starter chain step by step, and the
first-win bonus. --no-missions leaves the missions and the starter chain out.

Update 9 adds (off with --u8): the twelve new cards (taken from cards.json once they are there, else from
U9_CARDS), the Season Pass (tiers claimed as soon as reached; a season is 14 days of play), the login calendar
(one claim a day), the Daily Shop (the gift every day; the card deals, the Pro Pack deal and the star deal bought
when the coins or stars are there above the reserve), free agents (signed once the coins are there, saving up for
them instead of buying packs while one is available), pack pity, coins for extra copies of max-level cards, the
win streak and first-win-of-the-day coin bonuses, promotion rewards, Endless milestones and Boss Rush.

Update 11 (off with --u10): card levels 6-10 behind the Prestige step (copies from COPIES_TO_UPGRADE, coins from
PRESTIGE_COINS in db.gd), and extra copies become coins only when the card can't use them any more (level 10, or
it already holds every copy it needs to get there). The player prestiges as soon as copies and coins allow (the
Upgrade All opt-in), and while a card's copies for its next level are there but the coins are not, keeps those
coins aside instead of buying packs. --u10 = the Update 10 rules (max level 5, copies of level-5 cards to coins).
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
# The Update 9 cards (docs/plans/UPDATE_9_PLAN.md) until they are in data/cards.json.
U9_CARDS = {"scouting_report": "common", "sprinkler_system": "common", "sweet_spot": "uncommon", "rally_monkey": "uncommon",
	"second_wind": "rare", "money_ball": "rare", "scoop_and_tag": "rare", "signal_caller": "rare", "hidden_ball_trick": "epic",
	"worm_burner": "epic", "fireworks_night": "legendary", "ground_rule_double": "legendary"}
U9_SIGNATURES = {"moose": "scoop_and_tag", "rosa": "signal_caller", "sid": "worm_burner"}
U8_LEGENDARY = {"rookie": 0.1, "pro": 0.4, "champion": 1.2}


def jload(name):
	return json.load(open(os.path.join(ROOT, "data", name)))


def jload_opt(name, default):
	path = os.path.join(ROOT, "data", name)
	return json.load(open(path)) if os.path.exists(path) else default


def gd_const(path, name):
	text = open(os.path.join(ROOT, path)).read()
	m = re.search(r"const %s\s*:?=\s*(\{.*?\}|\[.*?\])" % name, text, re.S)
	src = m.group(1).replace("\n", " ")
	src = re.sub(r",\s*([}\]])", r"\1", src)
	return json.loads(src)


def gd_number(path, pattern, cast=float, default=None):
	text = open(os.path.join(ROOT, path)).read()
	m = re.search(pattern, text)
	if m is None:
		return default
	return cast(m.group(1))


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
# Boss Rush (Update 9): three innings that each end with a boss, about 7 minutes (plan estimate until measured).
GAME_TABLE = {
	("quick", True): {"coins": 750, "outs": 165, "cleared": 3, "minutes": 6.0},
	("quick", False): {"coins": 650, "outs": 140, "cleared": 2, "minutes": 5.0},
	("standard", True): {"coins": 3300, "outs": 700, "cleared": 9, "minutes": 20.0},
	("standard", False): {"coins": 2300, "outs": 500, "cleared": 6, "minutes": 14.0},
	("endless", False): {"coins": 3000, "outs": 650, "cleared": 9, "minutes": 18.0},
	("ranked", True): {"coins": 750, "outs": 165, "cleared": 3, "minutes": 6.0},
	("ranked", False): {"coins": 650, "outs": 140, "cleared": 2, "minutes": 5.0},
	("boss_rush", True): {"coins": 900, "outs": 180, "cleared": 3, "minutes": 7.5},
	("boss_rush", False): {"coins": 700, "outs": 140, "cleared": 2, "minutes": 6.0},
}


class Data:
	def __init__(self, args):
		self.cards = jload("cards.json")["cards"]
		self.card_rarity = {c["id"]: c["rarity"] for c in self.cards}
		if not args.no_u9_cards:
			for cid, r in U9_CARDS.items():
				self.card_rarity.setdefault(cid, r)
		else:
			for cid in U9_CARDS:
				self.card_rarity.pop(cid, None)
		self.card_ids = list(self.card_rarity)
		self.max_level = jload("cards.json").get("max_level", 5)
		self.u10 = args.u10 or args.u8 or args.u5
		if self.u10:
			self.max_level = 5
		pk = jload("packs.json")
		self.packs = {p["id"]: p for p in pk["packs"]}
		if args.u8:   # the Update 8 Legendary odds (Update 9 lowered them when pity arrived)
			for t, w in U8_LEGENDARY.items():
				self.packs[t]["weights"]["legendary"] = w
		self.pity = pk.get("pity", {})
		self.overflow = pk.get("overflow_coins", {})
		d = jload("defenders.json")
		self.xp_curve = d["xp_curve"]
		self.level_rewards = d["level_rewards"]
		self.def_max = d.get("max_level", 10)
		self.defenders = d["defenders"]
		self.signature = {}
		for x in self.defenders:
			sig = x.get("signature", "")
			if x["id"] in U9_SIGNATURES and U9_SIGNATURES[x["id"]] in self.card_rarity:
				sig = U9_SIGNATURES[x["id"]]
			self.signature[x["id"]] = sig
		if args.u8:   # Update 8: nine defenders, none for sale
			self.defenders = [x for x in self.defenders if x["id"] not in U9_SIGNATURES]
		self.modes = {m["id"]: m for m in jload("modes.json")["modes"]}
		self.diffs = {x["id"]: x for x in jload("difficulties.json")["difficulties"]}
		self.divisions = jload("ranks.json")["divisions"]
		self.gear_prices = sorted(int(g["price"]) for g in jload("gear.json")["gear"])
		self.achievements = jload("achievements.json")["achievements"]
		self.copies = gd_const("src/autoload/db.gd", "COPIES_TO_UPGRADE")
		self.coins_up = gd_const("src/autoload/db.gd", "COINS_TO_UPGRADE")
		self.prestige_coins = gd_const("src/autoload/db.gd", "PRESTIGE_COINS") if not self.u10 else {}
		self.prestige_level = gd_number("src/autoload/db.gd", r"const PRESTIGE_LEVEL\s*:=\s*(\d+)", int, 5)
		prof = "src/autoload/profile.gd"
		self.starter = gd_const(prof, "STARTER_CARDS")
		self.starter_deck = gd_const(prof, "STARTER_DECK")
		self.start_coins = gd_number(prof, r'"coins":\s*(\d+)', int)
		self.bundle_size = gd_number(prof, r"BUNDLE_SIZE\s*:=\s*(\d+)", int)
		self.bundle_discount = gd_number(prof, r"BUNDLE_DISCOUNT\s*:=\s*([\d.]+)")
		self.streak_step = gd_number(prof, r"STREAK_STEP\s*:=\s*([\d.]+)", float, 0.1)
		self.streak_max = gd_number(prof, r"STREAK_MAX\s*:=\s*([\d.]+)", float, 0.5)
		m = re.search(r"func xp_to_next.*?return\s+(\d+)\s*\+\s*(\d+)\s*\*", open(os.path.join(ROOT, prof)).read(), re.S)
		self.xp_base, self.xp_step = int(m.group(1)), int(m.group(2))
		self.road = jload("account_levels.json")
		self.missions = jload("missions.json")
		self.daily = jload("daily.json").get("rewards", {})
		rw_path = "src/core/rewards.gd"
		rw = open(os.path.join(ROOT, rw_path)).read()
		self.first_win_coins = int(re.search(r"const FIRST_WIN_COINS\s*:=\s*(\d+)", rw).group(1))
		self.first_win_pack = re.search(r'const FIRST_WIN_PACK\s*:=\s*"(\w+)"', rw).group(1)
		self.rw = {k: float(re.search(r"const %s\s*:=\s*([\d.]+)" % k, rw).group(1))
			for k in ["COIN_SHARE", "COINS_PER_INNING", "WIN_COINS", "DEFENDER_XP_SHARE", "DEFENDER_XP_PER_OUT"]}
		self.first_win_today_mult = gd_number(rw_path, r"FIRST_WIN_TODAY_MULT\s*:=\s*([\d.]+)", float, 2.0)
		self.milestone_every = gd_number(rw_path, r"MILESTONE_EVERY\s*:=\s*(\d+)", int, 5)
		self.milestone_coins = gd_number(rw_path, r"MILESTONE_COINS\s*:=\s*(\d+)", int, 150)
		self.season = jload_opt("season.json", {})
		self.login = jload_opt("login_rewards.json", {}).get("days", [])
		self.shop = jload_opt("shop.json", {})

	def level_reward(self, level):
		"""LevelRoad.reward: default, the last matching 'every', then a per-level override."""
		r = self.road.get("default", {})
		for e in self.road.get("every", []):
			if level % int(e.get("n", 1)) == 0:
				r = e
		r = self.road.get("levels", {}).get(str(level), r)
		return int(r.get("coins", 0)), list(r.get("packs", []))

	def xp_to_next(self, level):
		return self.xp_base + self.xp_step * (level - 1)

	def bundle_price(self, pack):
		return round_price(self.packs[pack]["price_coins"] * self.bundle_size * self.bundle_discount)

	def pity_counts(self, pack, rarity):
		"""Profile.pity_counts: 'counts' is a list (every rarity) or {rarity: [pack types]}."""
		c = self.pity.get("counts", ["rookie", "pro", "champion"])
		if isinstance(c, dict):
			c = c.get(rarity, [])
		return pack in c

	def copies_to_max(self, rarity, level, copies):
		return max(0, sum(self.copies[rarity][level:self.max_level]) - copies)

	def coin_cost(self, rarity, level):
		"""DB.upgrade_coins: COINS_TO_UPGRADE up to level 5, then PRESTIGE_COINS by rarity."""
		if level >= self.max_level:
			return 0
		if level < self.prestige_level:
			return self.coins_up[level]
		t = self.prestige_coins[rarity]
		return t[min(level - self.prestige_level, len(t) - 1)]


class Player:
	def __init__(self, data, rng, args):
		self.d, self.rng, self.a = data, rng, args
		self.u9 = not args.u8 and not args.u5
		self.coins = data.start_coins
		self.stars = 0
		self.level, self.xp = 1, 0
		self.rp, self.division = 0, 0
		self.cards = {c: {"owned": c in data.starter, "level": 1, "copies": 0} for c in data.card_ids}
		self.deck = list(data.starter_deck)
		self.team = [x["id"] for x in data.defenders if x.get("unlock", {}).get("type") == "default"][:6]
		self.def_level = {x["id"]: 1 for x in data.defenders}
		self.def_xp = {x["id"]: 0 for x in data.defenders}
		self.unlocked = set(self.team)
		self.packs = []
		self.minutes = 0.0
		self.gear_owned = 0
		self.stats = {"outs": 0, "wins_quick": 0, "wins_standard": 0, "games": 0, "packs_earned": 0, "packs_bought": 0,
			"coins_earned": 0, "upgrades": 0, "coins_upgrades": 0, "coins_packs": 0, "coins_gear": 0, "best_endless": 0,
			"missions": 0, "dailies": 0, "daily_wins": 0, "wins": 0, "packs_opened": 0, "coins_missions": 0,
			"coins_shop": 0, "coins_agents": 0, "shop_deals": 0, "agents": 0, "overflow": 0, "season_xp": 0,
			"season_tier": 0, "best_streak": 0, "wins_boss_rush": 0, "legendary_pity": 0, "prestiges": 0}
		self.coin_src = {}
		self.first_win = False
		self.day = -1
		self.games_today = 0
		self.won_today = False
		self.streak = 0
		self.starter_step = 0
		self.starter_mark = None
		self.achieved = set()
		self.pack_src = {}
		self.timeline = []
		self.by_game = []   # (packs earned, coins earned incl. bonuses, minutes) after each game
		self.pity = {"epic": 0, "legendary": 0}
		self.season_xp = 0
		self.season_claimed = 0      # tiers claimed this season
		self.season_bonus = 0
		self.season_results = []     # tier reached at the end of every finished season
		self.season_t30_day = []     # day of the season tier 30 was reached (1-14)
		self.login_day = 0
		self.shop_today = []
		self.shop_pack = self.shop_stars = False

	def earn(self, n, src):
		self.coins += n
		self.stats["coins_earned"] += n
		self.coin_src[src] = self.coin_src.get(src, 0) + n

	def grant_bundle(self, r, src):
		self.earn(int(r.get("coins", 0)), src)
		self.stars += int(r.get("stars", 0))
		for p in r.get("packs", []):
			self.add_pack(p, src)
		if r.get("pack"):
			self.add_pack(r["pack"], src)

	# ---- rewards.gd mirror
	def play(self, mode, won):
		daily = mode == "daily"
		g = GAME_TABLE[("quick" if daily else mode, won)]
		m, df = self.d.modes[mode], self.d.diffs["standard" if daily else self.a.difficulty]
		mult = m.get("reward_mult", 1.0) * df.get("reward", 1.0)
		cleared = g["cleared"]
		R = self.d.rw
		coins = int(round((g["coins"] * R["COIN_SHARE"] + cleared * R["COINS_PER_INNING"] + (R["WIN_COINS"] if won else 0)) * mult))
		xp = max(15, int(round((g["outs"] * 2.0 + cleared * 30 + (220 if won else 0)) * mult)))
		self.earn(coins, "games")
		if self.u9:
			# Win streak (Endless never counts) and the day's first win.
			if mode != "endless":
				if won:
					bonus = min(self.d.streak_max, self.d.streak_step * self.streak)
					self.earn(int(round(coins * bonus)), "win streak")
					self.streak += 1
					self.stats["best_streak"] = max(self.stats["best_streak"], self.streak)
				else:
					self.streak = 0
			if won and not self.won_today:
				self.won_today = True
				self.earn(int(round(coins * (self.d.first_win_today_mult - 1.0))), "first win of the day")
		self.add_xp(xp)
		outs_each = g["outs"] / 6.0
		for i, did in enumerate(self.team):
			self.add_def_xp(did, int(round((xp * R["DEFENDER_XP_SHARE"] + outs_each * R["DEFENDER_XP_PER_OUT"]) * (1.5 if i == 0 else 1.0))))
		self.add_pack("rookie")
		if mode == "standard":
			if won:
				self.add_pack("champion" if self.a.difficulty in ("veteran", "legend") else "pro")
		elif mode == "endless":
			if self.u9:   # milestones every 5 innings cleared
				ms = 0
				for k in range(self.d.milestone_every, cleared + 1, self.d.milestone_every):
					ms += self.d.milestone_coins * (k // self.d.milestone_every)
					self.add_pack("rookie", "endless milestones")
					if k in (10, 20):
						self.add_pack("pro", "endless milestones")
				self.earn(ms, "endless milestones")
			else:
				for _ in range(min(cleared // 5, 2)):
					self.add_pack("rookie")
			self.stats["best_endless"] = max(self.stats["best_endless"], cleared + 1)
		elif mode == "ranked" and won:
			self.add_pack("pro")
		elif mode == "boss_rush" and won:
			self.add_pack("pro", "boss rush")
			self.stats["wins_boss_rush"] += 1
		if daily:   # DailyChallenge.record_result: first game of the day and first win of the day
			self.earn(int(self.d.daily.get("first_coins", 0)), "daily challenge")
			self.add_pack(self.d.daily.get("first_pack", "rookie"), "daily challenge")
			self.stats["dailies"] += 1
			if won:
				self.add_pack(self.d.daily.get("win_pack", "pro"), "daily challenge")
				self.stats["daily_wins"] += 1
		if won:
			self.stats["wins"] += 1
			if not self.first_win and not self.a.u5:
				self.first_win = True
				self.earn(self.d.first_win_coins, "first win ever")
				self.add_pack(self.d.first_win_pack, "first win bonus")
		rpm = df.get("rp", 1.0)
		rp = {"standard": (60 if won else cleared * 4), "quick": (22 if won else cleared * 3),
			"endless": cleared * 5, "ranked": (30 if won else 0), "daily": 0, "boss_rush": (30 if won else cleared * 4)}[mode]
		self.rp += int(round(rp * rpm))
		if mode == "ranked" and won and self.division < len(self.d.divisions) - 1:
			self.division += 1
			if self.u9:
				self.grant_bundle(self.d.divisions[self.division].get("reward", {}), "promotions")
		if self.u9:
			sx = self.d.season.get("xp", {})
			self.add_season_xp(int(sx.get("game", 100)) + (int(sx.get("win", 60)) if won else 0) + (int(sx.get("daily", 100)) if daily else 0))
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
			if self.a.u5:   # Update 5: 100 coins and a Rookie Pack, a Pro Pack every 5th level
				self.earn(100, "account levels")
				self.add_pack("pro" if self.level % 5 == 0 else "rookie", "account level")
			else:
				coins, packs = self.d.level_reward(self.level)
				self.earn(coins, "account levels")
				for pk in packs:
					self.add_pack(pk, "account level")
			for x in self.d.defenders:
				u = x.get("unlock", {})
				if u.get("type") == "level" and self.level >= int(u["value"]) and x["id"] not in self.unlocked:
					self.unlock(x["id"])

	def unlock(self, did):
		self.unlocked.add(did)
		sig = self.d.signature.get(did, "")
		if sig in self.cards and not self.cards[sig]["owned"]:
			self.packs.append(("signature", sig))
			self.pack_src["signature"] = self.pack_src.get("signature", 0) + 1

	def add_def_xp(self, did, n):
		self.def_xp[did] += n
		lv = self.def_level[did]
		while lv < self.d.def_max and self.def_xp[did] >= self.d.xp_curve[lv] - self.d.xp_curve[lv - 1]:
			self.def_xp[did] -= self.d.xp_curve[lv] - self.d.xp_curve[lv - 1]
			lv += 1
			r = self.d.level_rewards.get(str(lv), {})
			self.earn(int(r.get("coins", 0)), "defender levels")
			if "pack" in r:
				self.add_pack(r["pack"], "defender level")
		self.def_level[did] = lv

	def add_pack(self, t, src="game"):
		self.packs.append((t, None))
		self.stats["packs_earned"] += 1
		self.pack_src[src] = self.pack_src.get(src, 0) + 1

	# ---- Season Pass (season.gd mirror): tiers claimed as soon as reached
	def add_season_xp(self, n):
		self.season_xp += n
		self.stats["season_xp"] += n
		per = 500
		tiers = self.d.season.get("tiers", {})
		reached = min(30, self.season_xp // per)
		while self.season_claimed < reached:
			self.season_claimed += 1
			r = dict(tiers.get(str(self.season_claimed), {}))
			r.pop("uniform", None)
			self.grant_bundle(r, "season pass")
			if self.season_claimed == 30:
				self.season_t30_day.append(self.day % 14 + 1)
		bonus = self.d.season.get("bonus", {})
		earned = max(0, self.season_xp - 30 * per) // int(bonus.get("xp", 1000))
		while self.season_bonus < earned:
			self.season_bonus += 1
			self.grant_bundle({"packs": bonus.get("packs", ["pro"])}, "season pass")
		self.stats["season_tier"] = reached

	def end_season(self):
		self.season_results.append(min(30, self.season_xp // 500))
		self.season_xp = self.season_claimed = self.season_bonus = 0

	# ---- Profile._open_one mirror (pity, overflow)
	def open_packs(self):
		while self.packs:
			t, fixed = self.packs.pop()
			if fixed:
				self.grant(fixed)
				continue
			p = self.d.packs[t]
			counts = {r: self.u9 and self.d.pity_counts(t, r) for r in ("epic", "legendary")}
			forced = None
			if counts["legendary"] and self.pity["legendary"] >= int(self.d.pity.get("legendary", 30)) - 1:
				forced = "legendary"
			elif counts["epic"] and self.pity["epic"] >= int(self.d.pity.get("epic", 10)) - 1:
				forced = "epic"
			out = []
			slots = p["slots"]
			for si, slot in enumerate(slots):
				r = self.roll_rarity(p["weights"])
				mn = slot.get("min", "common")
				if forced and si == len(slots) - 1 and RARITIES.index(forced) > RARITIES.index(mn):
					mn = forced
				if RARITIES.index(r) < RARITIES.index(mn):
					r = mn
				pool = [c for c, rr in self.d.card_rarity.items() if rr == r and c not in out] or \
					[c for c in self.d.card_rarity if c not in out]
				unowned = [c for c in pool if not self.cards[c]["owned"]]
				choice = unowned if unowned and self.rng.random() < 0.6 else pool
				out.append(self.rng.choice(choice))
			if forced == "legendary":
				self.stats["legendary_pity"] += 1
			best = max(RARITIES.index(self.d.card_rarity[c]) for c in out)
			for r, idx in (("epic", 3), ("legendary", 4)):
				if best >= idx:
					self.pity[r] = 0
				elif counts[r]:
					self.pity[r] += 1
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

	def grant(self, cid, copies=None):
		c = self.cards[cid]
		rarity = self.d.card_rarity[cid]
		n = copies if copies is not None else (2 if rarity == "common" else 1)
		if not c["owned"]:
			c["owned"] = True
		elif self.u9 and c["level"] >= self.d.max_level:
			coins = n * int(self.d.overflow.get(rarity, 0))
			self.earn(coins, "extra copies")
			self.stats["overflow"] += coins
		elif self.u9 and not self.d.u10:   # Update 11: Profile.spare_copies
			room = self.d.copies_to_max(rarity, c["level"], c["copies"])
			extra = max(0, n - room)
			if extra:
				coins = extra * int(self.d.overflow.get(rarity, 0))
				self.earn(coins, "extra copies")
				self.stats["overflow"] += coins
			c["copies"] += n - extra
		else:
			c["copies"] += n

	# ---- spending
	def upgrade_cost(self, cid):
		lv = self.cards[cid]["level"]
		if lv >= self.d.max_level:
			return None
		r = self.d.card_rarity[cid]
		return self.d.copies[r][lv], self.d.coin_cost(r, lv)

	def upgrade_all(self):
		changed = True
		while changed:
			changed = False
			best = None
			saving = self.saving_for_upgrade()
			for cid, c in self.cards.items():
				cost = self.upgrade_cost(cid)
				if c["owned"] and cost and c["copies"] >= cost[0] and self.coins >= cost[1]:
					# Update 11: cards outside the deck level up only from coins beyond what the deck's next
					# Prestige level-up needs.
					if self.focus(cid) and self.coins < cost[1] + saving:
						continue
					if best is None or cost[1] < best[1][1]:
						best = (cid, cost)
			if best:
				cid, (cp, co) = best
				self.cards[cid]["copies"] -= cp
				if self.cards[cid]["level"] == self.d.prestige_level:
					self.stats["prestiges"] += 1
				self.cards[cid]["level"] += 1
				self.coins -= co
				self.stats["upgrades"] += 1
				self.stats["coins_upgrades"] += co
				changed = True

	def next_agent(self):
		"""The next free agent worth signing: not unlocked, and its account level more than --agent-lead levels away."""
		if not self.u9 or self.a.no_agents:
			return None
		for x in self.d.defenders:
			u = x.get("unlock", {})
			if int(u.get("coins", 0)) > 0 and x["id"] not in self.unlocked and self.level < int(u.get("value", 0)) - self.a.agent_lead:
				return x
		return None

	def spend(self):
		self.upgrade_all()
		# Free agents: signed once the coins are there (a saver also keeps the price aside instead of buying packs).
		agent = self.next_agent()
		if agent and self.coins >= int(agent["unlock"]["coins"]) + self.a.reserve:
			price = int(agent["unlock"]["coins"])
			self.coins -= price
			self.stats["coins_agents"] += price
			self.stats["agents"] += 1
			self.unlock(agent["id"])
			agent = self.next_agent()
		if not self.a.save_for_agents:
			agent = None
		# Daily Shop deals.
		if self.u9:
			self.shop_deals()
			self.upgrade_all()
		# Gear: one piece at a time once the player has a cushion.
		if self.gear_owned < len(self.d.gear_prices) and self.coins >= self.d.gear_prices[self.gear_owned] + self.a.reserve:
			self.coins -= self.d.gear_prices[self.gear_owned]
			self.stats["coins_gear"] += self.d.gear_prices[self.gear_owned]
			self.gear_owned += 1
		if self.collection_done() and all(c["level"] >= self.d.max_level for c in self.cards.values()):
			return
		rookie = self.d.packs["rookie"]["price_coins"]
		bundle = self.d.bundle_price("rookie")
		keep = self.a.reserve + (int(agent["unlock"]["coins"]) if agent else 0) + self.saving_for_upgrade()
		if self.a.policy == "bundles":
			while self.coins >= bundle + (keep - self.a.reserve):
				self.buy("rookie", self.d.bundle_size, bundle)
		elif self.a.policy == "balanced":
			if self.coins >= bundle + keep:
				self.buy("rookie", self.d.bundle_size, bundle)
			while self.coins >= rookie + keep:
				self.buy("rookie", 1, rookie)
		# Stars: Champion Packs.
		cs = self.d.packs["champion"]["price_stars"]
		while self.stars >= cs:
			self.stars -= cs
			self.packs.append(("champion", None))
			self.pack_src["stars (champion)"] = self.pack_src.get("stars (champion)", 0) + 1

	def focus(self, cid):
		"""Update 11: True for a card outside the deck (its level-ups wait while the deck saves for a Prestige level)."""
		return not self.d.u10 and cid not in self.deck

	def saving_for_upgrade(self):
		"""Update 11: coins kept aside (instead of buying packs) for the cheapest Prestige level-up of a deck card
		whose copies are already there."""
		if self.d.u10:
			return 0
		best = 0
		for cid in self.deck:
			c = self.cards[cid]
			cost = self.upgrade_cost(cid)
			if c["owned"] and cost and c["level"] >= self.d.prestige_level and c["copies"] >= cost[0] and (best == 0 or cost[1] < best):
				best = cost[1]
		return best

	def buy(self, t, n, price):
		self.coins -= price
		self.stats["coins_packs"] += price
		self.stats["packs_bought"] += n
		for _ in range(n):
			self.packs.append((t, None))

	def collection_done(self):
		return all(c["owned"] for c in self.cards.values())

	# ---- Daily Shop (shop.gd mirror)
	def new_shop_day(self):
		"""Shop.generate: the gift (claimed at once) and two card deals weighted toward the deck."""
		sh = self.d.shop
		gifts = sh.get("gifts", [])
		x = self.rng.random() * sum(float(g.get("weight", 1)) for g in gifts)
		for g in gifts:
			x -= float(g.get("weight", 1))
			if x <= 0:
				self.grant_bundle({k: v for k, v in g.items() if k != "weight"}, "shop gift")
				break
		pool = [cid for cid, c in self.cards.items() if c["owned"] and
			self.d.copies_to_max(self.d.card_rarity[cid], c["level"], c["copies"]) > 0]
		weights = [float(sh.get("deck_weight", 4)) if cid in self.deck else 1.0 for cid in pool]
		deals = []
		for _ in range(int(sh.get("card_deals", 2))):
			if not pool:
				break
			y = self.rng.random() * sum(weights)
			pick = 0
			for j, w in enumerate(weights):
				y -= w
				if y <= 0:
					pick = j
					break
			cid = pool.pop(pick)
			weights.pop(pick)
			c = self.cards[cid]
			r = self.d.card_rarity[cid]
			nxt = self.d.copies[r][min(c["level"], self.d.max_level - 1)] - c["copies"]
			cap = int(sh.get("max_copies", {}).get(r, 2))
			n = max(1, min(max(1, nxt), max(1, min(cap, self.d.copies_to_max(r, c["level"], c["copies"])))))
			deals.append((cid, n, n * int(sh.get("card_prices", {}).get(r, 100))))
		self.shop_today = deals
		self.shop_pack = True
		self.shop_stars = True

	def shop_deals(self):
		sh = self.d.shop
		keep = self.a.reserve + self.saving_for_upgrade()
		for deal in list(self.shop_today):
			cid, n, price = deal
			c = self.cards[cid]
			if self.d.copies_to_max(self.d.card_rarity[cid], c["level"], c["copies"]) <= 0:
				continue
			if self.coins >= price + keep:
				self.coins -= price
				self.stats["coins_shop"] += price
				self.stats["shop_deals"] += 1
				self.grant(cid, n)
				self.shop_today.remove(deal)
		pd = sh.get("pack_deal", {})
		price = round_price(self.d.packs[pd.get("pack", "pro")]["price_coins"] * (1 - float(pd.get("discount", 0.25))))
		if self.shop_pack and self.coins >= price + keep:
			self.shop_pack = False
			self.coins -= price
			self.stats["coins_shop"] += price
			self.stats["shop_deals"] += 1
			self.packs.append((pd.get("pack", "pro"), None))
			self.pack_src["shop deals"] = self.pack_src.get("shop deals", 0) + 1
		sd = sh.get("star_deal", {})
		if self.shop_stars and self.stars >= int(sd.get("price_stars", 40)):
			self.shop_stars = False
			self.stars -= int(sd.get("price_stars", 40))
			self.stats["shop_deals"] += 1
			self.packs.append((sd.get("pack", "champion"), None))
			self.pack_src["shop deals"] = self.pack_src.get("shop deals", 0) + 1

	# ---- missions.gd mirror (Update 6)
	def grant_reward(self, r, src):
		self.earn(int(r.get("coins", 0)), "missions")
		self.stats["coins_missions"] += int(r.get("coins", 0))
		self.stars += int(r.get("stars", 0))
		if r.get("pack"):
			self.add_pack(r["pack"], src)
		self.stats["missions"] += 1
		if self.u9:
			self.add_season_xp(int(self.d.season.get("xp", {}).get("mission", 80)))

	def missions_after_game(self, mode, won):
		rw = self.d.missions["rewards"]
		tier = {2: "1", 4: "2", 6: "3"}.get(self.games_today)
		if tier:
			self.grant_reward(rw[tier], "missions")
		# Starter chain: each step needs its event after the previous step was claimed.
		steps = self.d.missions.get("starter", [])
		if self.starter_step < len(steps):
			s = self.stats
			now = {"cards_played": s["games"], "win": s["wins"], "packs_opened": s["packs_opened"],
				"cards_upgraded": s["upgrades"], "daily_played": s["dailies"]}
			if self.starter_mark is None:
				self.starter_mark = dict(now)
			while self.starter_step < len(steps):
				st = steps[self.starter_step]
				if now[st["event"]] - self.starter_mark[st["event"]] < (1 if st["event"] == "cards_played" else st["goal"]):
					break
				self.grant_reward(st["reward"], "starter missions")
				self.starter_step += 1
				self.starter_mark = dict(now)

	def new_day(self):
		self.games_today = 0
		self.won_today = False
		self.day += 1
		if self.day > 0 and self.day % 7 == 0 and not self.a.no_missions:
			self.grant_reward(self.d.missions["rewards"]["weekly"], "missions")
		if self.u9:
			if self.day > 0 and self.day % 14 == 0:
				self.end_season()
			if self.d.login:   # the login calendar: one claim a day
				self.grant_bundle(self.d.login[self.login_day % len(self.d.login)], "login calendar")
				self.login_day += 1
			self.new_shop_day()

	def check_achievements(self, mode, won):
		s = self.stats
		stat = {"total_outs": s["outs"], "wins_quick": s["wins_quick"], "wins_standard": s["wins_standard"],
			"boss_iron_slugger": s["wins_quick"] + s["wins_standard"], "boss_phantom_captain": s["wins_standard"],
			"boss_grand_slammer": s["wins_standard"], "double_plays": s["games"], "triple_plays": s["games"],
			"grand_combos": s["games"], "clean_innings": s["games"] * 2, "cards_played": s["games"] * 25,
			"shield_saves": s["games"] // 3, "max_card_level": max(c["level"] for c in self.cards.values()),
			"max_defender_level": max(self.def_level.values()), "cards_owned": sum(c["owned"] for c in self.cards.values()),
			"defenders_owned": len(self.unlocked), "division": self.division, "best_endless_inning": s["best_endless"],
			"missions_completed": s["missions"], "dailies_finished": s["dailies"], "daily_streak": self.day + 1 if s["dailies"] else 0,
			"daily_wins": s["daily_wins"], "account_level": self.level, "bosses_defeated": s["wins_quick"] + 3 * s["wins_standard"],
			"mastery_stars": s["games"] // 3, "cards_mastered": 1 if s["games"] > 60 else 0, "caught_stealing": s["games"] // 4,
			"new_cards_owned": 0, "wins_boss_rush": s["wins_boss_rush"], "boons_drafted": s["games"] // 2,
			"best_win_streak": s["best_streak"], "shop_purchases": s["shop_deals"], "free_agents_signed": s["agents"],
			"season_best_tier": max([s["season_tier"]] + self.season_results), "login_streak": self.day + 1 if self.u9 else 0}
		for a in self.d.achievements:
			if a["id"] not in self.achieved and stat.get(a["stat"], 0) >= a["goal"]:
				self.achieved.add(a["id"])
				self.stars += int(a.get("stars", 0))

	def snapshot(self):
		owned = {r: 0 for r in RARITIES}
		maxed = {r: 0 for r in RARITIES}
		lvl5 = {r: 0 for r in RARITIES}
		prestiged = 0
		for cid, c in self.cards.items():
			r = self.d.card_rarity[cid]
			owned[r] += c["owned"]
			maxed[r] += c["level"] >= self.d.max_level
			lvl5[r] += c["level"] >= 5
			prestiged += c["level"] > self.d.prestige_level
		return {"hours": self.minutes / 60.0, "owned": owned, "maxed": maxed, "lvl5": lvl5, "prestiged": prestiged,
			"level": self.level, "coins": self.coins,
			"division": self.division, "def_avg": statistics.mean(self.def_level[d] for d in self.team), "def_max": max(self.def_level.values()),
			"card_levels": sum(c["level"] - 1 for c in self.cards.values()), "defenders": len(self.unlocked),
			"upgrade_coins_left": sum(sum(self.d.coin_cost(self.d.card_rarity[cid], l) for l in range(c["level"], self.d.max_level))
				for cid, c in self.cards.items() if c["owned"]),
			**{k: v for k, v in self.stats.items()}}


def run_player(data, args, seed):
	rng = random.Random(seed)
	p = Player(data, rng, args)
	mix = [("quick", args.quick), ("standard", args.standard), ("endless", args.endless)]
	if p.u9:
		mix.append(("boss_rush", args.boss_rush))
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
		day = int(p.minutes // args.day_minutes)
		while p.day < day:
			p.new_day()
		if not args.u5 and p.games_today == 2:
			mode, won = "daily", rng.random() < args.win
		p.games_today += 1
		p.play(mode, won)
		if not args.u5 and not args.no_missions:
			p.missions_after_game(mode, won)
		p.stats["packs_opened"] += len(p.packs)
		p.by_game.append((p.stats["packs_earned"], p.stats["coins_earned"] + data.start_coins, p.minutes))
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
	ap.add_argument("--win", type=float, default=0.65, help="win rate in Quick, Standard and Boss Rush games")
	ap.add_argument("--ranked-win", type=float, default=0.6)
	ap.add_argument("--quick", type=float, default=0.45, help="share of games that are Quick Defense")
	ap.add_argument("--standard", type=float, default=0.3)
	ap.add_argument("--endless", type=float, default=0.15)
	ap.add_argument("--boss-rush", type=float, default=0.1, help="share of games that are Boss Rush (Update 9)")
	ap.add_argument("--policy", default="balanced", choices=["balanced", "bundles", "none"],
		help="spare coins: balanced = bundles/packs above a reserve, bundles = every bundle affordable, none = no packs")
	ap.add_argument("--reserve", type=int, default=600, help="coins kept for upgrades before buying packs or gear")
	ap.add_argument("--day-minutes", type=float, default=60, help="minutes of play per calendar day (daily missions, Daily Challenge)")
	ap.add_argument("--no-missions", action="store_true", help="leave out missions and the starter chain")
	ap.add_argument("--no-agents", action="store_true", help="never sign free agents (they still join at their account level)")
	ap.add_argument("--agent-lead", type=int, default=0, help="sign a free agent only while its account level is more than this many levels away")
	ap.add_argument("--save-for-agents", action="store_true", help="keep the next free agent's price aside instead of buying packs")
	ap.add_argument("--pity", default="", help="override the pity rules as JSON (tuning)")
	ap.add_argument("--legendary-weights", default="", help="override Legendary weights per pack type as JSON (tuning)")
	ap.add_argument("--u5", action="store_true", help="the Update 5 economy: no daily games, missions, level road or first-win bonus")
	ap.add_argument("--u8", action="store_true", help="the Update 8 economy: none of the Update 9 systems and the Update 8 Legendary odds, "
		"with the Update 9 cards (add --no-u9-cards and --quick 0.5 --standard 0.35 for the Update 8 projection itself)")
	ap.add_argument("--no-u9-cards", action="store_true", help="leave the twelve Update 9 cards out")
	ap.add_argument("--u10", action="store_true", help="the Update 10 card rules: max level 5, copies of level-5 cards become coins")
	ap.add_argument("--json", default="")
	args = ap.parse_args()
	if args.u8:
		args.boss_rush = 0.0
	data = Data(args)
	if args.pity:
		data.pity = json.loads(args.pity)
	if args.legendary_weights:
		for t, w in json.loads(args.legendary_weights).items():
			data.packs[t]["weights"]["legendary"] = w
	players = [run_player(data, args, 1000 + i) for i in range(args.players)]
	tls = [p.timeline for p in players]
	H = int(args.hours)
	counts = {r: sum(1 for c in data.card_ids if data.card_rarity[c] == r) for r in RARITIES}
	n_cards = len(data.card_ids)

	def med(h, key, sub=None):
		vals = []
		for tl in tls:
			s = min(tl, key=lambda x: abs(x["hours"] - h))
			vals.append(s[key][sub] if sub else s[key])
		return statistics.median(vals)

	u9 = not args.u8 and not args.u5
	print("# Economy projection: %d players, %g h, %s difficulty, win %.0f %%, mix quick/standard/endless/boss rush %g/%g/%g/%g, policy %s, %d cards%s\n" % (
		args.players, args.hours, args.difficulty, args.win * 100, args.quick, args.standard, args.endless, args.boss_rush if u9 else 0,
		args.policy, n_cards, "" if u9 else " (Update 8 economy)"))
	print("| Hour | Games | Account lvl | Division | Team avg lvl | Packs earned | Packs bought | Cards owned | Card upgrades | Coins earned | Coins on upgrades / packs / gear / shop / agents | Coins held |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	rows = []
	for h in [1, 2, 3, 5, 8, 12, 16, 20, 25, 30, 35, 40, 50, 60]:
		if h > H:
			break
		owned = sum(med(h, "owned", r) for r in RARITIES)
		row = (h, med(h, "games"), med(h, "level"), data.divisions[int(med(h, "division"))]["name"], med(h, "def_avg"),
			med(h, "packs_earned"), med(h, "packs_bought"), owned, med(h, "upgrades"), med(h, "coins_earned"),
			"%d / %d / %d / %d / %d" % (med(h, "coins_upgrades"), med(h, "coins_packs"), med(h, "coins_gear"), med(h, "coins_shop"),
				med(h, "coins_agents")), med(h, "coins"))
		rows.append(row)
		print("| %d | %d | %d | %s | %.1f | %d | %d | %d / %d | %d | %d | %s | %d |" % (row[:7] + (owned, n_cards) + row[8:]))
	if not data.u10:
		print("\n| Hour | Cards prestiged | Commons at 5 / 10 | Card levels gained | Coins held |")
		print("|---|---|---|---|---|")
		for h in [5, 8, 10, 12, 16, 20, 25, 30, 35, 40, 50, 60]:
			if h > H:
				break
			print("| %d | %g | %g / %g | %g | %d |" % (h, med(h, "prestiged"), med(h, "lvl5", "common"), med(h, "maxed", "common"),
				med(h, "card_levels"), med(h, "coins")))
	print("\n| Milestone | Median hour |")
	print("|---|---|")
	ms = {}
	for r in RARITIES:
		ms["all %s owned (%d)" % (r, counts[r])] = first_hour(tls, lambda s, r=r: s["owned"][r] >= counts[r])
	ms["whole collection owned (%d)" % n_cards] = first_hour(tls, lambda s: sum(s["owned"].values()) >= n_cards)
	ms["first epic owned"] = first_hour(tls, lambda s: s["owned"]["epic"] >= 1)
	ms["first legendary owned"] = first_hour(tls, lambda s: s["owned"]["legendary"] >= 1)
	if not data.u10:
		for r in RARITIES:
			ms["first %s card at level 5" % r] = first_hour(tls, lambda s, r=r: s["lvl5"][r] >= 1)
		ms["all commons at level 5"] = first_hour(tls, lambda s: s["lvl5"]["common"] >= counts["common"])
		ms["first Prestige (any card at level 6)"] = first_hour(tls, lambda s: s["prestiged"] >= 1)
		ms["5 cards prestiged"] = first_hour(tls, lambda s: s["prestiged"] >= 5)
	for r in RARITIES:
		ms["first %s card at max level (%d)" % (r, data.max_level)] = first_hour(tls, lambda s, r=r: s["maxed"][r] >= 1)
	ms["all commons at max level (%d)" % data.max_level] = first_hour(tls, lambda s: s["maxed"]["common"] >= counts["common"])
	ms["team average level 5"] = first_hour(tls, lambda s: s["def_avg"] >= 5)
	ms["team average level 10"] = first_hour(tls, lambda s: s["def_avg"] >= 10)
	if data.def_max >= 20:   # Update 11 (stream B): defender levels to 20
		ms["team average level 15"] = first_hour(tls, lambda s: s["def_avg"] >= 15)
		ms["team average level 20"] = first_hour(tls, lambda s: s["def_avg"] >= 20)
		ms["first defender at level 20"] = first_hour(tls, lambda s: s["def_max"] >= 20)
	all_defs = len(data.defenders)
	ms["all %d defenders" % all_defs] = first_hour(tls, lambda s: s["defenders"] >= all_defs)
	for i, dv in enumerate(data.divisions[1:], 1):
		ms["%s division" % dv["name"]] = first_hour(tls, lambda s, i=i: s["division"] >= i)
	for k, v in ms.items():
		print("| %s | %s |" % (k, "%.1f" % v if v is not None else "> %g" % args.hours))
	print("\n| First session | Packs earned | Coins received | Minutes played |")
	print("|---|---|---|---|")
	for n in (1, 2, 3, 6, 10):
		rows_g = [pl.by_game[n - 1] for pl in players if len(pl.by_game) >= n]
		print("| after game %d | %g | %d | %.0f |" % (n, statistics.median(r[0] for r in rows_g), statistics.median(r[1] for r in rows_g),
			statistics.median(r[2] for r in rows_g)))
	last = [tl[-1] for tl in tls]
	hours = statistics.mean(s["hours"] for s in last)
	print("\nPer hour (whole run): %.1f packs earned, %.1f bought, %.1f card upgrades, %d coins earned." % (
		statistics.mean(s["packs_earned"] for s in last) / hours, statistics.mean(s["packs_bought"] for s in last) / hours,
		statistics.mean(s["upgrades"] for s in last) / hours, statistics.mean(s["coins_earned"] for s in last) / hours))
	src = {}
	for p in players:
		for k, v in p.pack_src.items():
			src[k] = src.get(k, 0) + v
	print("Packs per hour by source: " + ", ".join("%s %.1f" % (k, v / len(players) / hours) for k, v in sorted(src.items())))
	csrc = {}
	for p in players:
		for k, v in p.coin_src.items():
			csrc[k] = csrc.get(k, 0) + v
	print("Game coins per hour (the Update 8 'coins per hour'): %d; every source except extra copies (which recycle pack spending): %d." % (
		sum(p.coin_src.get("games", 0) for p in players) / len(players) / hours,
		sum(sum(v for k, v in p.coin_src.items() if k != "extra copies") for p in players) / len(players) / hours))
	print("Coins per hour by source: " + ", ".join("%s %d" % (k, v / len(players) / hours) for k, v in sorted(csrc.items(), key=lambda kv: -kv[1])))
	print("Coins spent per hour: upgrades %d, packs %d, gear %d, shop deals %d, free agents %d." % tuple(
		statistics.mean(s[k] for s in last) / hours for k in ("coins_upgrades", "coins_packs", "coins_gear", "coins_shop", "coins_agents")))
	income = sum(sum(v for k, v in p.coin_src.items() if k != "extra copies") for p in players) / len(players) / hours
	print("Rookie bundle: %d coins = %.2f h of coin income (without extra-copy coins); Pro bundle %d coins." % (data.bundle_price("rookie"),
		data.bundle_price("rookie") / income, data.bundle_price("pro")))
	print("Coin cost of the card upgrades still open at the end: median %d coins." % statistics.median(s["upgrade_coins_left"] for s in last))
	if not data.u10:
		print("Prestiges per player at the end: median %g (cards prestiged %g)." % (statistics.median(p.stats["prestiges"] for p in players),
			statistics.median(s["prestiged"] for s in last)))
	if u9:
		seasons = [r for p in players for r in p.season_results]
		t30 = [d for p in players for d in p.season_t30_day]
		days = args.day_minutes
		if seasons:
			print("Season Pass (%g min a day): median tier at the end of a season %d; tier 30 reached in %.0f %% of seasons, median on day %s of 14." % (
				days, statistics.median(seasons), 100.0 * sum(1 for r in seasons if r >= 30) / len(seasons),
				("%.0f" % statistics.median(t30)) if t30 else "-"))
		print("Free agents signed: %.1f per player (%.0f %% sign at least one); legendaries from pity per player: %.1f." % (
			statistics.mean(p.stats["agents"] for p in players), 100.0 * sum(1 for p in players if p.stats["agents"] > 0) / len(players),
			statistics.mean(p.stats["legendary_pity"] for p in players)))
	if args.json:
		json.dump({"milestones": ms, "rows": rows}, open(args.json, "w"), indent=1, default=str)


if __name__ == "__main__":
	main()
