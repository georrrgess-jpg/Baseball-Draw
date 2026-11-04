#!/usr/bin/env python3
"""Balance simulator: plays autopilot games headlessly and summarises them.

  tools/balance/simulate.py run --mode quick --difficulty rookie,standard,veteran,legend --games 25 --out build/balance/before
  tools/balance/simulate.py report build/balance/before            # writes games.csv, cards.csv, summary.md

Every game is one `godot --headless --fixed-fps 30 -- --test-battle=<mode> --auto` process with a fresh
profile (level-1 cards and defenders, the starter team). The autopilot prints one `[AUTO] STATS {json}` line
at the end (see src/battle/autopilot.gd); `run` appends it to <out>/games.jsonl, so several runs can share a
folder and an interrupted run can be resumed (games already in the file are skipped by seed).

Extra game arguments go through --extra (write it as --extra=... because the values start with dashes):
  --extra=--team=nova,rico,dex,jax,hana,bruno     a fixed team (first id is the captain)
  --extra=--shop=scouting_report,stronger_arm     dugout purchase order (or --shop=none)
  --extra=--cast-gap=3,6                          seconds between autopilot casts (a slower player)
  --extra=--no-cards                              defenders only
  --extra="--card-level=3 --defender-level=5"     a "mid" profile: deck cards and team at those levels
  --extra=--boon-pick=random                      Dugout Draft picks at random (default: by ai_value)
  --extra=--boon=giant_killer                     always take that boon when it is offered
Modes: standard, quick, endless, boss_rush (Update 9), ranked, daily. Games with different --extra arguments
are reported as separate rows (the extra arguments are shown next to the difficulty).
The report adds per-card damage / outs per energy, the card's win rate and runs per inning against its
mode/difficulty group (random decks), per-defender shares (also when on the team), Rico's Home Guard
assist, the dugout upgrades bought and (Update 9) the median inning reached and game time per row, early
calls, and the Dugout Draft boons: how often each is offered and taken, and the win rate when taken.

The numbers measure the autopilot, not a human: it casts the first affordable card in its hand every
1-2.5 s at a simple target (lead runner, densest cluster), never saves cards for bosses and buys dugout
upgrades in a fixed order. Treat win rates as a relative difficulty curve, not as what players will see.
"""
import argparse
import collections
import concurrent.futures as cf
import csv
import json
import os
import statistics
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIFFS = ["rookie", "standard", "veteran", "legend"]


def play(mode, diff, seed, deck, speed, extra, timeout):
	args = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "30", "--",
		"--test-battle=" + mode, "--difficulty=" + diff, "--auto", "--seed=%d" % seed,
		"--profile=bal_%s_%s_%d_%d" % (mode, diff, seed, os.getpid()), "--fresh-profile"]
	if deck:
		args.append("--deck=" + deck)
	if speed != 1.0:
		args.append("--speed=%g" % speed)
	args += extra
	t0 = time.time()
	try:
		out = subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout
	except subprocess.TimeoutExpired:
		return None, "timeout", time.time() - t0
	errors = [l for l in out.splitlines() if "SCRIPT ERROR" in l]
	for line in out.splitlines():
		if line.startswith("[AUTO] STATS "):
			d = json.loads(line[len("[AUTO] STATS "):])
			d["wall_s"] = round(time.time() - t0, 1)
			d["script_errors"] = len(errors)
			if deck:
				d["deck_tag"] = deck
			if extra:
				d["extra_tag"] = " ".join(extra)
			return d, "", time.time() - t0
	return None, (errors[0] if errors else "no STATS line"), time.time() - t0


def random_deck(seed):
	"""A random 8-card deck from the whole pool (for per-card win-rate comparisons)."""
	import random
	ids = [c["id"] for c in json.load(open(os.path.join(ROOT, "data", "cards.json")))["cards"]]
	return ",".join(random.Random(seed * 7919).sample(ids, 8))


def cmd_run(a):
	os.makedirs(a.out, exist_ok=True)
	path = os.path.join(a.out, "games.jsonl")
	done = set()
	if os.path.exists(path):
		for l in open(path):
			d = json.loads(l)
			done.add((d["mode"], d["difficulty"], d["seed"], d.get("deck_tag", ""), d.get("extra_tag", "")))
	extra = a.extra.split() if a.extra else []
	jobs = []
	for i in range(a.games):          # interleaved, so a partial run covers every difficulty
		for diff in a.difficulty.split(","):
			seed = a.seed_base + i
			deck = random_deck(seed) if a.deck == "random" else a.deck
			if (a.mode, diff, seed, deck or "", " ".join(extra)) not in done:
				jobs.append((a.mode, diff, seed, deck))
	print("%d games to play (%d already in %s)" % (len(jobs), len(done), path), flush=True)
	with cf.ThreadPoolExecutor(a.jobs) as ex, open(path, "a") as f:
		futs = {ex.submit(play, m, d, s, dk, a.speed, extra, a.timeout): (m, d, s) for m, d, s, dk in jobs}
		for fu in cf.as_completed(futs):
			m, d, s = futs[fu]
			res, err, wall = fu.result()
			if res is None:
				print("  %s/%s seed %d FAILED: %s" % (m, d, s, err), flush=True)
				continue
			f.write(json.dumps(res) + "\n")
			f.flush()
			print("  %s/%s seed %d: %s inning %d runs %d (%.0fs)" % (m, d, s, "WIN " if res["won"] else "loss",
				res["inning"], res["runs"], wall), flush=True)


def pct(x):
	return "%.0f %%" % (100.0 * x)


def mean(xs):
	return statistics.mean(xs) if xs else 0.0


def load(folders):
	games = []
	for fo in folders:
		p = os.path.join(fo, "games.jsonl") if os.path.isdir(fo) else fo
		games += [json.loads(l) for l in open(p) if l.strip()]
	return games


def median(xs):
	return statistics.median(xs) if xs else 0.0


def label(k):
	"""Row label for a (mode, difficulty, extra) group: the difficulty plus any extra game arguments."""
	return k[1] + (" (%s)" % k[2] if k[2] else "")


def summarize(games):
	"""Returns markdown text with the tables used in the balance report."""
	out = []
	groups = collections.defaultdict(list)
	for g in games:
		groups[(g["mode"], g["difficulty"], g.get("extra_tag", ""))].append(g)
	order = sorted(groups, key=lambda k: (k[0], DIFFS.index(k[1]) if k[1] in DIFFS else 9, k[2]))

	out.append("### Win rate and run flow\n")
	out.append("Inning reached counts the inning the game ended in. Game time is game seconds from the first pitch to the end, "
		"including breaks (the autopilot calls every wave early) but not the dugout or the draft.\n")
	out.append("| Mode | Difficulty | Games | Win rate | Avg inning reached | Median inning | Runs allowed / game | Loss inning (histogram) | Median game time (min) | Early calls / game | Energy wasted / game | Time at max energy | Coins earned / spent | Reward coins | Packs / game | Max combo |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for k in order:
		gs = groups[k]
		wins = sum(1 for g in gs if g["won"])
		losses = collections.Counter(g["inning"] for g in gs if not g["won"])
		hist = ", ".join("%d:%d" % (i, n) for i, n in sorted(losses.items())) or "-"
		cap = mean([g["capped_time"] / max(g["wave_time"], 1) for g in gs])
		gtime = median([g.get("time", g["game_time"]) / 60.0 for g in gs])
		out.append("| %s | %s | %d | %s | %.1f | %.1f | %.2f | %s | %.1f | %.1f | %.1f | %s | %.0f / %.0f | %.0f | %.1f | %.1f |" % (k[0], label(k), len(gs), pct(wins / len(gs)),
			mean([g["inning"] for g in gs]), median([g["inning"] for g in gs]), mean([g["runs"] for g in gs]), hist, gtime,
			mean([g.get("early_calls", 0) for g in gs]), mean([g["energy_wasted"] for g in gs]), pct(cap),
			mean([g["coins_earned"] for g in gs]), mean([g["coins_spent"] for g in gs]), mean([g["reward_coins"] for g in gs]),
			mean([len(g["reward_packs"]) for g in gs]), mean([g["max_combo"] for g in gs])))

	out.append("\n### Runs allowed by inning (average per game that reached the inning)\n")
	maxi = max((len(g["runs_by_inning"]) for g in games), default=0)
	out.append("| Mode | Difficulty | " + " | ".join("I%d" % (i + 1) for i in range(maxi)) + " |")
	out.append("|---|---|" + "---|" * maxi)
	for k in order:
		gs = groups[k]
		cells = []
		for i in range(maxi):
			v = [g["runs_by_inning"][i] for g in gs if len(g["runs_by_inning"]) > i]
			cells.append("%.2f" % mean(v) if v else "")
		out.append("| %s | %s | %s |" % (k[0], label(k), " | ".join(cells)))

	out.append("\n### Runs allowed per runner type (runs per 100 runners of that type that spawned)\n")
	types = sorted({t for g in games for t in g["spawned_by_type"]})
	out.append("| Mode | Difficulty | " + " | ".join(types) + " |")
	out.append("|---|---|" + "---|" * len(types))
	for k in order:
		gs = groups[k]
		cells = []
		for t in types:
			sp = sum(g["spawned_by_type"].get(t, 0) for g in gs)
			rn = sum(g["runs_by_type"].get(t, 0) for g in gs)
			cells.append("%.1f (%d)" % (100.0 * rn / sp, rn) if sp else "")
		out.append("| %s | %s | %s |" % (k[0], label(k), " | ".join(cells)))

	out.append("\n### Bosses\n")
	out.append("| Mode | Difficulty | Boss | Seen | Beaten | Scored | Avg time to kill (s) | Games lost in the boss inning |")
	out.append("|---|---|---|---|---|---|---|---|")
	for k in order:
		gs = groups[k]
		by = collections.defaultdict(list)
		for g in gs:
			for b in g["bosses"]:
				by[b["id"]].append((b, g))
		for bid, lst in sorted(by.items()):
			kills = [b["ttk"] for b, g in lst if b["result"] == "out"]
			scored = sum(1 for b, g in lst if b["result"] == "scored")
			lost_here = sum(1 for b, g in lst if not g["won"] and g["inning"] == b["inning"])
			out.append("| %s | %s | %s | %d | %d | %d | %.1f | %d |" % (k[0], label(k), bid, len(lst), len(kills), scored, mean(kills), lost_here))

	out += boon_table(games)
	out += card_table(games)
	out += defender_table(games)
	out += upgrade_table(games)
	return "\n".join(out) + "\n"


def boon_table(games):
	"""Dugout Draft (Update 9): per boon, times offered and taken, and the win rate of games that took it
	against their group (mode / difficulty / extra)."""
	offered = collections.Counter()
	taken = collections.Counter()
	wins = collections.Counter()
	delta = collections.defaultdict(list)
	drafts = 0
	res = residuals(games)
	for g in games:
		for b, n in g.get("boons_offered", {}).items():
			offered[b] += n
		for b in g.get("boons", []):
			taken[b] += 1
			wins[b] += int(g["won"])
			delta[b].append(res[id(g)])
		drafts += len(g.get("boons", []))
	if not offered:
		return []
	out = ["\n### Dugout Draft boons\n", "%d boons taken in %d games. 'vs group' = win rate of games that took the boon minus "
		"their mode/difficulty group's (a boon taken in a game that was going well looks better than it is).\n" % (drafts, len(games)),
		"| Boon | Offered | Taken | Pick rate | Win rate when taken | vs group |", "|---|---|---|---|---|---|"]
	for b in sorted(offered, key=lambda x: -taken[x]):
		out.append("| %s | %d | %d | %s | %s | %+.0f |" % (b, offered[b], taken[b], pct(taken[b] / offered[b]) if offered[b] else "-",
			pct(wins[b] / taken[b]) if taken[b] else "-", 100.0 * mean(delta[b]) if delta[b] else 0.0))
	return out


def residuals(games, key=lambda g: int(g["won"])):
	"""key(game) minus its average over the game's (mode, difficulty, extra) group: compares cards across
	mixed samples (default key: won)."""
	groups = collections.defaultdict(list)
	for g in games:
		groups[(g["mode"], g["difficulty"], g.get("extra_tag", ""))].append(g)
	res = {}
	for gs in groups.values():
		wr = mean([key(g) for g in gs])
		for g in gs:
			res[id(g)] = key(g) - wr
	return res


def card_table(games):
	"""Per card: decks, plays, damage / outs per play and per energy, win rate with the card and its
	difference to the game's group (only meaningful for random decks)."""
	cost = {c["id"]: max(1, int(c["cost"])) for c in json.load(open(os.path.join(ROOT, "data", "cards.json")))["cards"]}
	res = residuals(games)
	# Runs allowed per inning played, so a game lost early doesn't look like a good one.
	rres = residuals(games, lambda g: g["runs"] / max(len(g["runs_by_inning"]), 1))
	rdelta = collections.defaultdict(list)
	plays = collections.Counter()
	dmg = collections.Counter()
	outs = collections.Counter()
	in_decks = collections.Counter()
	wins_with = collections.Counter()
	delta = collections.defaultdict(list)
	waves = collections.Counter()
	for g in games:
		for c in set(g["deck"]):
			in_decks[c] += 1
			wins_with[c] += int(g["won"])
			delta[c].append(res[id(g)])
			rdelta[c].append(rres[id(g)])
			waves[c] += max(g["wave_time"], 1.0) / 60.0
		for c, n in g["card_plays"].items():
			plays[c] += n
		for c, v in g["card_impact"].items():
			dmg[c] += v["damage"]
			outs[c] += v["outs"]
	total_plays = sum(plays.values()) or 1
	base_wr = sum(int(g["won"]) for g in games) / len(games)
	out = ["\n### Cards (all games)\n"]
	out.append("Win rate over all games: %s. 'Win rate with card' and 'vs group' only mean something for random decks "
		"('vs group' = average of won minus the win rate of the game's mode/difficulty group; +-1/(2 sqrt n) is one standard error).\n" % pct(base_wr))
	out.append("| Card | Cost | In decks | Win rate with card | vs group | Runs / inning vs group | Plays / wave-min | Play share | Damage / play | Damage / energy | Outs / play | Outs / energy |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for c, _ in sorted(in_decks.items(), key=lambda kv: -mean(delta[kv[0]])):
		n = plays[c]
		e = n * cost.get(c, 1)
		out.append("| %s | %d | %d | %s | %+.0f | %+.2f | %.2f | %s | %s | %s | %s | %s |" % (c, cost.get(c, 0), in_decks[c], pct(wins_with[c] / in_decks[c]),
			100.0 * mean(delta[c]), mean(rdelta[c]), n / max(waves[c], 0.01), pct(n / total_plays),
			"%.0f" % (dmg[c] / n) if n and dmg[c] else "-", "%.0f" % (dmg[c] / e) if e and dmg[c] else "-",
			"%.2f" % (outs[c] / n) if n and outs[c] else "-", "%.2f" % (outs[c] / e) if e and outs[c] else "-"))
	return out


def defender_table(games):
	"""Share of team damage and outs over all games, and per game the defender was on the team."""
	dd = collections.Counter()
	do = collections.Counter()
	share_d = collections.defaultdict(list)
	share_o = collections.defaultdict(list)
	present = collections.Counter()
	assist = collections.Counter()
	for g in games:
		team = g.get("team") or list(g["damage_by"].keys())
		gd = sum(g["damage_by"].values()) or 1.0
		go = sum(g["outs_by"].values()) or 1
		for d in team:
			present[d] += 1
			share_d[d].append(g["damage_by"].get(d, 0.0) / gd)
			share_o[d].append(g["outs_by"].get(d, 0) / go)
		for d, v in g["damage_by"].items():
			dd[d] += v
		for d, v in g["outs_by"].items():
			do[d] += v
		assist["rico"] += g.get("assist_by", {}).get("home_guard", 0.0)
	td = sum(dd.values()) or 1
	to = sum(do.values()) or 1
	out = ["\n### Defenders (share of team damage and outs)\n"]
	out.append("'Aura assist' = extra damage other throws and cards dealt because of Rico's Home Guard (+10 %), as a share of team damage.\n")
	out.append("| Defender | Games | Damage share | Outs share | Damage share when on team | Outs share when on team | Aura assist |")
	out.append("|---|---|---|---|---|---|---|")
	for d in sorted(present, key=lambda x: -mean(share_d[x])):
		out.append("| %s | %d | %s | %s | %s | %s | %s |" % (d, present[d], pct(dd[d] / td), pct(do[d] / to), pct(mean(share_d[d])), pct(mean(share_o[d])),
			pct(assist[d] / td) if assist[d] else "-"))
	return out


def upgrade_table(games):
	"""Dugout purchases (autopilot shopping order, see --shop in autopilot.gd)."""
	bought = collections.Counter()
	games_with = collections.Counter()
	res = residuals(games)
	delta = collections.defaultdict(list)
	for g in games:
		for u, n in g.get("upgrades_bought", {}).items():
			bought[u] += n
			games_with[u] += 1
			delta[u].append(res[id(g)])
	if not bought:
		return []
	out = ["\n### Dugout upgrades bought\n", "| Upgrade | Levels bought / game | Games with it | vs group |", "|---|---|---|---|"]
	for u in sorted(bought, key=lambda x: -bought[x]):
		out.append("| %s | %.2f | %d | %+.0f |" % (u, bought[u] / len(games), games_with[u], 100.0 * mean(delta[u])))
	return out


def write_csv(games, folder):
	with open(os.path.join(folder, "games.csv"), "w", newline="") as f:
		w = csv.writer(f)
		w.writerow(["mode", "difficulty", "seed", "deck_tag", "won", "inning", "runs", "outs", "score", "game_time", "wave_time",
			"capped_time", "energy_wasted", "coins_earned", "coins_spent", "reward_coins", "reward_xp", "reward_rp", "packs",
			"runs_by_inning", "boss_results", "cards_played"])
		for g in games:
			w.writerow([g["mode"], g["difficulty"], g["seed"], g.get("deck_tag", ""), int(g["won"]), g["inning"], g["runs"], g["outs"],
				g["score"], round(g["game_time"]), round(g["wave_time"]), round(g["capped_time"], 1), round(g["energy_wasted"], 1),
				g["coins_earned"], g["coins_spent"], g["reward_coins"], g["reward_xp"], g["reward_rp"], len(g["reward_packs"]),
				" ".join(map(str, g["runs_by_inning"])), " ".join("%s:%s:%.0f" % (b["id"], b["result"], b["ttk"]) for b in g["bosses"]),
				sum(g["card_plays"].values())])
	with open(os.path.join(folder, "cards.csv"), "w", newline="") as f:
		w = csv.writer(f)
		w.writerow(["mode", "difficulty", "seed", "card", "plays", "damage", "outs"])
		for g in games:
			for c in g["deck"]:
				imp = g["card_impact"].get(c, {})
				w.writerow([g["mode"], g["difficulty"], g["seed"], c, g["card_plays"].get(c, 0), round(imp.get("damage", 0)), imp.get("outs", 0)])


def cmd_report(a):
	games = load(a.folders)
	if not games:
		sys.exit("no games found")
	text = summarize(games)
	folder = a.folders[0] if os.path.isdir(a.folders[0]) else os.path.dirname(a.folders[0])
	write_csv(games, folder)
	with open(os.path.join(folder, "summary.md"), "w") as f:
		f.write("# Balance simulation summary\n\n%d games. Autopilot proxy: see tools/balance/simulate.py.\n\n" % len(games) + text)
	print(text)


def main():
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	sub = p.add_subparsers(dest="cmd", required=True)
	r = sub.add_parser("run")
	r.add_argument("--mode", default="quick")
	r.add_argument("--difficulty", default=",".join(DIFFS))
	r.add_argument("--games", type=int, default=25)
	r.add_argument("--seed-base", type=int, default=1000)
	r.add_argument("--deck", default="", help="comma-separated card ids, or 'random' for a random deck per seed (default: the starter deck)")
	r.add_argument("--speed", type=float, default=1.0)
	r.add_argument("--jobs", type=int, default=2)
	r.add_argument("--timeout", type=int, default=1800)
	r.add_argument("--extra", default="", help="extra game arguments, e.g. --no-cards or \"--card-level=3 --defender-level=5\"")
	r.add_argument("--out", default=os.path.join(ROOT, "build", "balance", "latest"))
	r.set_defaults(fn=cmd_run)
	s = sub.add_parser("report")
	s.add_argument("folders", nargs="+")
	s.set_defaults(fn=cmd_report)
	a = p.parse_args()
	a.fn(a)


if __name__ == "__main__":
	main()
