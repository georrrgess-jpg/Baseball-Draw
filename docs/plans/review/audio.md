# Update 5 review: audio (Stream G)

Measured with `tools/audio/check_audio.py` (loudness, true peak, DC, loop seams, spectrum) plus a per-call-site
level script: *in-game level* = file loudness (max momentary LUFS for effects, integrated LUFS for music) +
manifest `volume_db`; call-site offsets come on top. Priority = Severity (1–4) × Reach (1–4) ÷ Effort (S=1, M=2, L=3).

## Inventory (before)

* 7 music tracks, 2 ambience loops, 73 effects (82 files, 16.1 MB). All loops seamless (jump/derivative ratio ≤ 0.95),
  no DC, no true-peak overs, every effect peak-normalised to −3 dBFS.
* One battle track (`battle_theme`) for all six arenas, swapped for `boss_theme` on boss waves.

## Findings

| # | Finding | Sev | Reach | Effort | Prio | Status |
|---|---|---|---|---|---|---|
| 1 | One battle track for all six arenas; no intensity change between setup, wave, boss and a game on the line | 3 | 4 | L | 4.0 | fixed: 6 arena variations × 4 synced layers |
| 2 | `Audio.ui()` ignored the manifest volumes: UI sounds spread over 11 dB (ui_back −17.2 vs card_hover −28.4); `purchase` played 4 dB louder on the Packs screen (ui) than everywhere else (play) | 3 | 4 | S | 12.0 | fixed |
| 3 | Card effects spread over 14.6 dB: Time Out whistle −12.6 (5 dB above any other cast), frost −15.5, lightning −20.7 | 3 | 4 | S | 12.0 | fixed (6.5 dB incl. loops; casts within 1 dB) |
| 4 | Rarity reveals not monotonic: Epic (−19.2) quieter than Rare (−17.2) | 2 | 3 | S | 6.0 | fixed (−20 / −18 / −16.5 / −15) |
| 5 | Rapid hits: fixed 45 ms rate limit only; 3 ball-hit variants chosen at random (back-to-back repeats), no voice cap, no level variation → machine-gun effect at 3x speed | 3 | 4 | M | 6.0 | fixed |
| 6 | Crowd: one cheer group, one groan, one ooh; no reaction to single outs, boss hits, tension; groan on every run is the same file | 3 | 4 | M | 6.0 | fixed |
| 7 | No sound when a card is drawn into the battle hand; `energy_full.wav` existed but was never played | 2 | 4 | S | 8.0 | fixed (from BattleAudio, no hook needed) |
| 8 | `duck_music` tweened one player's volume: overlapping ducks fought, and a cross-fade during a duck restored the wrong level | 2 | 2 | S | 4.0 | fixed (duck bus, deepest duck wins) |
| 9 | Slow motion pitched every effect by `Engine.time_scale`: a hit-stop (tiny time scale) would drop sounds by octaves | 2 | 3 | S | 6.0 | fixed (mild pitch only, ≥ 0.75) |
| 10 | Combo stingers not escalating: Grand (−15.0) quieter than Double (−14.3) | 2 | 3 | S | 6.0 | fixed (−15.5 / −14.5 / −13.5) |
| 11 | Shield block (a run saved) at −22 sat under ordinary hits; run scored −17 under wave clear | 2 | 3 | S | 6.0 | fixed (−19.5 / −15.5) |
| 12 | No boss entrance / boss defeat music cue | 2 | 3 | M | 3.0 | fixed (stings) |
| 13 | Ambience static: the stadium bed does not follow the game's excitement | 1 | 4 | S | 4.0 | fixed (±3 dB swell) |
| 14 | `pack_shake` has 10 % energy above 8 kHz (crinkle) — intentional, not harsh at −21 | 1 | 2 | S | 2.0 | kept |
| 15 | `reveal_legendary` peaks at −2.0 dBFS (flag threshold −2.5) | 1 | 1 | S | 1.0 | kept (master limiter) |

## Category targets (base level, LUFS) and spread before → after

| Category | Target | Spread before | Spread after |
|---|---|---|---|
| Music loops | −23 (stems calm+wave −23) | 1.0 | 0.5 |
| Stingers | −15 … −17 (combos rise) | 6.6 | 6.5 (by design: coin −20) |
| Card effects | −18 | 14.6 | 6.5 (casts ±0.5; loops/draw lower) |
| Hits | −20 (throw −22, footsteps −34) | 18.3 | 16.0 (footsteps by design) |
| UI | −19 / −22 clicks / −24 hovers | 11.2 | 5.1 |
| Packs | rising by rarity | 7.8 | 6.9 |

Targets live in `tools/audio/mix.py`; `build_audio.py` sets each manifest volume to *target − measured loudness*.
