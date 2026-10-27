#!/usr/bin/env python3
"""Balance simulator: plays autopilot games headlessly and summarises them.

  tools/balance/simulate.py run --mode quick --difficulty rookie,standard,veteran,legend --games 25 --out build/balance/before
  tools/balance/simulate.py report build/balance/before            # writes games.csv, cards.csv, summary.md

Every game is one `godot --headless --fixed-fps 30 -- --test-battle=<mode> --auto` process with a fresh
profile (level-1 cards and defenders, the starter team). The autopilot prints one `[AUTO] STATS {json}` line
at the end (see src/battle/autopilot.gd); `run` appends it to <out>/games.jsonl, so several runs can share a
folder and an interrupted run can be resumed (games already in the file are skipped by seed).

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
			done.add((d["mode"], d["difficulty"], d["seed"], d.get("deck_tag", "")))
	jobs = []
	for i in range(a.games):          # interleaved, so a partial run covers every difficulty
		for diff in a.difficulty.split(","):
			seed = a.seed_base + i
			deck = random_deck(seed) if a.deck == "random" else a.deck
			if (a.mode, diff, seed, deck or "") not in done:
				jobs.append((a.mode, diff, seed, deck))
	print("%d games to play (%d already in %s)" % (len(jobs), len(done), path), flush=True)
	extra = a.extra.split() if a.extra else []
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


def summarize(games):
	"""Returns markdown text with the tables used in the balance report."""
	out = []
	groups = collections.defaultdict(list)
	for g in games:
		groups[(g["mode"], g["difficulty"])].append(g)
	order = sorted(groups, key=lambda k: (k[0], DIFFS.index(k[1]) if k[1] in DIFFS else 9))

	out.append("### Win rate and run flow\n")
	out.append("| Mode | Difficulty | Games | Win rate | Avg inning reached | Runs allowed / game | Loss inning (histogram) | Energy wasted / game | Time at max energy | Coins earned / spent | Reward coins | Packs / game | Max combo |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for k in order:
		gs = groups[k]
		wins = sum(1 for g in gs if g["won"])
		losses = collections.Counter(g["inning"] for g in gs if not g["won"])
		hist = ", ".join("%d:%d" % (i, n) for i, n in sorted(losses.items())) or "-"
		cap = mean([g["capped_time"] / max(g["wave_time"], 1) for g in gs])
		out.append("| %s | %s | %d | %s | %.1f | %.2f | %s | %.1f | %s | %.0f / %.0f | %.0f | %.1f | %.1f |" % (k[0], k[1], len(gs), pct(wins / len(gs)),
			mean([g["inning"] for g in gs]), mean([g["runs"] for g in gs]), hist, mean([g["energy_wasted"] for g in gs]), pct(cap),
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
		out.append("| %s | %s | %s |" % (k[0], k[1], " | ".join(cells)))

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
		out.append("| %s | %s | %s |" % (k[0], k[1], " | ".join(cells)))

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
			out.append("| %s | %s | %s | %d | %d | %d | %.1f | %d |" % (k[0], k[1], bid, len(lst), len(kills), scored, mean(kills), lost_here))

	out.append("\n### Cards (all games)\n")
	plays = collections.Counter()
	dmg = collections.Counter()
	outs = collections.Counter()
	in_decks = collections.Counter()
	wins_with = collections.Counter()
	for g in games:
		for c in set(g["deck"]):
			in_decks[c] += 1
			wins_with[c] += int(g["won"])
		for c, n in g["card_plays"].items():
			plays[c] += n
		for c, v in g["card_impact"].items():
			dmg[c] += v["damage"]
			outs[c] += v["outs"]
	total_plays = sum(plays.values()) or 1
	base_wr = sum(int(g["won"]) for g in games) / len(games)
	out.append("Win rate over all games: %s. 'Win rate with card' only means something for random decks.\n" % pct(base_wr))
	out.append("| Card | In decks | Win rate with card | Plays / game | Play share | Damage / play | Outs / play |")
	out.append("|---|---|---|---|---|---|---|")
	for c, _ in sorted(in_decks.items(), key=lambda kv: -plays[kv[0]] / max(kv[1], 1)):
		n = plays[c]
		out.append("| %s | %d | %s | %.1f | %s | %s | %s |" % (c, in_decks[c], pct(wins_with[c] / in_decks[c]), n / max(in_decks[c], 1), pct(n / total_plays),
			"%.0f" % (dmg[c] / n) if n and dmg[c] else "-", "%.2f" % (outs[c] / n) if n and outs[c] else "-"))

	out.append("\n### Defenders (share of team damage and outs)\n")
	dd = collections.Counter()
	do = collections.Counter()
	for g in games:
		for d, v in g["damage_by"].items():
			dd[d] += v
		for d, v in g["outs_by"].items():
			do[d] += v
	td = sum(dd.values()) or 1
	to = sum(do.values()) or 1
	out.append("| Defender | Damage share | Outs share |")
	out.append("|---|---|---|")
	for d in sorted(set(dd) | set(do), key=lambda x: -dd[x]):
		out.append("| %s | %s | %s |" % (d, pct(dd[d] / td), pct(do[d] / to)))
	return "\n".join(out) + "\n"


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
	r.add_argument("--extra", default="", help="extra game arguments, e.g. --no-cards")
	r.add_argument("--out", default=os.path.join(ROOT, "build", "balance", "latest"))
	r.set_defaults(fn=cmd_run)
	s = sub.add_parser("report")
	s.add_argument("folders", nargs="+")
	s.set_defaults(fn=cmd_report)
	a = p.parse_args()
	a.fn(a)


if __name__ == "__main__":
	main()
