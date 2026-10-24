# Audio asset report

All Baseball Draw audio is synthesized from code. No samples or downloaded assets are used. The
sources are in `tools/audio/`, and every file can be rebuilt deterministically: seeds are fixed per
asset name, WAV dither is seeded, and Ogg is written bit-exact. Two consecutive full builds gave
byte-identical files.

## Rebuild

From the repo root (needs Python 3.10+, numpy, scipy and ffmpeg with libvorbis):

```sh
uv run --no-project --with numpy --with scipy python tools/audio/build_audio.py            # everything, ~1-3 min on 4 cores
uv run --no-project --with numpy --with scipy python tools/audio/build_audio.py --only sfx # or: music, ambience, or asset names
uv run --no-project --with numpy --with scipy python tools/audio/check_audio.py            # analysis table + flags
uv run --no-project --with numpy --with scipy --with matplotlib python tools/audio/check_audio.py --plots /tmp/audio_plots
```

Set `AUDIO_DEBUG=1` to print per-bus RMS and peak while the music renders. This is useful when rebalancing a mix.

| file | role |
|---|---|
| `tools/audio/dsp.py` | DSP library: band-limited polyBLEP saw and pulse oscillators, sine, triangle, FM, additive and modal partials, white/pink/brown and FFT-shaped (periodic) noise, ADSR/perc/breakpoint envelopes, RBJ biquads (static and time-varying), Butterworth, convolution reverb with a synthetic stereo IR, ping-pong delay, chorus, rotary-speaker (Leslie) model, tremolo, tanh saturation, compressor, look-ahead brick-wall limiter, BS.1770 loudness, loop helpers (tail wrap, crossfade, circular processing), WAV writer (with `smpl` loop chunk) and Ogg writer |
| `tools/audio/instruments.py` | Instruments: drum kit pieces (kick, snare, clap, 808-style hats, crash, ride, toms, taiko, timpani, rim, snap, stomp, shaker), bass (analog synth, additive fingered, sub), tonewheel organ, analog brass, FM e-piano, pad, strings, lead, pluck, distorted power-chord guitar, glock/chime/marimba, FM bell, formant choir |
| `tools/audio/crowd.py` | Crowd voices (glottal source + formant bank, per-voice pitch gestures), Poisson clapping, babble talkers |
| `tools/audio/sequencer.py` | Song container: tempo/swing, buses, note cache, melody/chord parsing, drum grids, sidechain duck, mixdown with room/hall sends, master chain (glue comp → loudness normalisation → limiter, run circularly for loops) |
| `tools/audio/music.py` | The seven compositions (scores written in code) |
| `tools/audio/sfx.py` | The 65 sound effects and their registry (name → generator, suggested volume, loop, variant group) |
| `tools/audio/ambience.py` | The two ambience beds |
| `tools/audio/build_audio.py` | Parallel build plus `assets/audio/manifest.json` |
| `tools/audio/check_audio.py` | Analysis: peak, 4× true peak, RMS, LUFS, DC, start/end sample, loop seam, spectral centroid, >8 kHz energy, optional PNG plots |

## Output formats

* **SFX**: `assets/audio/sfx/*.wav`, 44.1 kHz, 16-bit (TPDF-dithered) mono. Peak levels:
  * most effects: −3.0 dBFS
  * UI sounds: −9 dBFS (`ui_hover` −13)
  * `card_draw`, `card_denied`, `coin` (frequent): −6 dBFS
  * `card_hover`: −15 dBFS
  * footsteps: −12 dBFS

  Every effect is high-passed at 30 Hz, has short fades at both ends and passes through a soft-knee peak shaver (no hard clipping).
* **Music**: `assets/audio/music/*.ogg`, Vorbis q5, 44.1 kHz stereo. Loops target −16 LUFS integrated (dugout −17, practice −18) with peaks ≤ −2.2 dBFS true peak. The loops are rendered with their release and reverb tail wrapped onto the start. Every loop length is an exact number of bars.
* **Ambience**: `assets/audio/ambience/*.ogg`, Vorbis q5 stereo, 30.000 s loops at −24 / −27 LUFS, so they sit as quiet beds at 0 dB.
* **Manifest**: `assets/audio/manifest.json` contains:
  * `files[]`: name, `res://` path, category, duration, loop, suggested `volume_db`, `group`, plus `peak_dbfs` for SFX and `bpm`/`bars`/`key` for music
  * `groups`: e.g. `"throw": ["throw_1","throw_2","throw_3"]`
  * `volume_db_by_name`: covers both file names and group names
* **Total size**: 15.1 MB (SFX 7.0 MB, music 6.9 MB, ambience 1.0 MB).

## Integration notes for the game code

* `src/autoload/audio_manager.gd` reads `files[].volume_db` keyed by file basename. A grouped name such as `play("throw")` or `play("ball_hit")` therefore gets no override. Reading `volume_db_by_name` (or `groups`) instead fixes this, because it includes the group names.
* `fire_loop.wav` carries a RIFF `smpl` forward loop over the whole file. Godot's default WAV import (`edit/loop_mode = Detect From WAV`) picks it up. `loop_end` is written as the sample count, which is the exclusive end that Godot uses.
* Ogg loops need `stream.loop = true`. The audio manager already does this at runtime for music (except `victory` and `defeat`) and for ambience. Leave the import `bpm` and `beat_count` at 0 so the loop wraps at the true end of the stream. The real BPM and bar counts are in the manifest if beat-synced logic is wanted.
* `AudioManager.play()` adds ±6 % pitch jitter. This stacks well with the 2 to 3 recorded variants per group.
* The suggested `volume_db` puts music about 6 to 7 dB under full scale, so that SFX peaks at −3 dBFS clearly cut through.
## Loudness and technical verification

`check_audio.py` decodes every shipped file (the Ogg files are decoded back from Vorbis) and checks:

* peak and 4×-oversampled true peak
* RMS
* BS.1770 loudness: integrated for music and ambience, maximum momentary for SFX
* DC offset
* first and last sample level, to catch clicks on one-shots
* for loops, the step and curvature across the loop point. These are compared with the largest step and curvature the audio itself makes within ±93 ms of the seam. A ratio ≤ 1 means the seam is no rougher than the surrounding audio.

The final run is clean: **74 files, 0 flags**.

* All SFX peaks are at their targets, with true peak no more than 0.8 dB above the sample peak. |DC| is at most 0.0008 of full scale. No file has more than 1.5 % of its energy above 8 kHz (the highest is `card_draw`, a paper flick).
* All throws, hits, catches and footsteps are 0.11 to 0.27 s long. The throws and hits have their energy concentrated in the first 50 to 100 ms.
* Music sits at −16.0 to −16.1 LUFS for the main loops, with RMS around −18 dBFS and true peak ≤ −2.2 dBFS. The other pieces are deliberately quieter: dugout −17, practice −18, defeat −17.5. Victory is −14.9 because it is a short stinger.
* Seams. The float render of `wind_industrial`, measured before encoding, gave a seam ratio of 0.005, so it is mathematically continuous; the loops use the same construction. After Vorbis encoding, every loop stays under 1.0, with the worst at 0.95 for `practice_theme`'s curvature. The codec error at the stream edges was measured at −51 to −56 dBFS, which is no larger than the codec error in the middle of the file.
* Octave-band balance of the music, relative to 1 kHz, is roughly +3 to +8 dB at 63 Hz, −3 to −5 dB at 2 kHz, −6 dB at 4 kHz and −8 to −11 dB at 8 kHz. That is a normal mixed-music tilt. `practice_theme` and `defeat` are intentionally darker.

I cannot listen to anything, so I checked by analysis instead:

* I rendered spectrograms and waveforms of every SFX and of whole-track and zoomed music sections, and looked at each one to confirm envelopes, transients, note contours and section changes.
* I rendered single notes of every instrument and checked them for pitch accuracy, envelopes and spectra.
* A throwaway harmony checker went over every melody note at least an eighth note long and compared it against the chord tones and bass sounding at that moment. It found five real clashes, all now fixed. The remaining hits are deliberate passing tones and maj7/9 colours.

Problems the checks caught and that I fixed during development:

* a filter start-up transient that made the ambience seam click
* hard truncation clicks in layered SFX
* notes humanised before the downbeat losing their attack (they now wrap to the loop end)
* `ball_hit` energy sitting too low (60 Hz) to read on small speakers
* a peak limiter that softened attacks (replaced with a soft-knee shaver)
* Ogg serial numbers making builds non-reproducible

## Design notes

### Music (all with real chord progressions, bass lines, hooks and drum grooves)

* **menu_theme**: D major, 116 BPM, 44 bars (91.0 s).
  * Form: stomp-and-clap intro with organ, then A (brass anthem melody over D–G–Em–A–D–G–A–D), then B (stadium-organ riff over Bm–G–D–A–Bm–G–E7–A, answered by brass stabs), then a bridge (G–A–F#m–Bm–G–A–Em7–Asus4/A) with strings and a tom/snare build and riser, then A′ (melody with organ doubling and glockenspiel), then an outro tag that turns around on A back into the intro.
  * Sound: Hammond-style organ through overdrive and fast Leslie; detuned-saw brass with filter swell, scoop and delayed vibrato; fingered bass; rock kit with claps and stomps; stadium hall reverb.
* **battle_theme**: E minor, 134 BPM, 60 bars (107.5 s).
  * Form: filtered-drum intro with 16th arpeggio, then A1 (synth-lead hook over Em–C–D–Em / Em–C–Am–B with palm-muted power chords), then A2 (hook variation, open power chords, 16th hats), then B1 and B2, then a breakdown (bells and pluck motif, half-time toms, building to a riser), then A3 (hook with octave doubling), then an outro on the B dominant.
  * The B sections are a distinct four-on-the-floor electronic groove over Am–Em–C–D, with off-beat bass, side-chained pads and a saw lead with delay.
* **boss_theme**: C minor (harmonic-minor and Phrygian colour), 146 BPM, 48 bars (78.9 s).
  * Form: intro with growling low-brass chord hits (Cm–Db–Cm–G), taiko, a doom bell and a timpani roll; then A (16th spiccato-string ostinato, double-kick gallop, ominous low-brass theme C–Eb–D… doubled at the octave); then B (high brass and choir over Ab–Fm–Db–G); then A′ with a lead doubling; then a half-time taiko break with an "oh" choir and string line; then a climax C section; then a brass-hit turnaround.
* **dugout_theme**: A dorian funk, 98 BPM with light 16th swing, 24 bars (58.8 s).
  * Chords: Am7–D9 vamp, a Dm9–G13–Cmaj9–Am9–Bm7b5–E7#9 bridge, and an Fmaj7–G6 lift.
  * Instruments: syncopated additive fingered bass with chromatic approaches; tremolo FM e-piano comping; slow-Leslie organ pad; organ melody in the last section; ghost-note funk kit.
* **practice_theme**: F major, 80 BPM, 20 bars (60.0 s). A chill, minimal piece: Fmaj7–Em7–Dm9–Cmaj9–Bbmaj7–Am7–Gm9–C9sus4, soft e-piano, sub bass, rim/shaker kit, a marimba melody in the second pass, glock fragments and a barely audible vinyl crackle.
* **victory**: C major, 12.5 s, one-shot. Timpani and snare roll, a brass triplet pickup and fanfare, a triumphant ♭VI–♭VII–I (Ab–Bb–C) cadence, timpani hits, cymbals, a glockenspiel sparkle and a crowd cheer under the final chord.
* **defeat**: A minor, 8.4 s, one-shot. Am–F–Dm6–E7–Am, a descending e-piano line with a soft muted horn an octave below, string pad, and one soft timpani note.

### Ambience
* **stadium_crowd**: pink-noise vowel-resonance bed, 30 babble talkers (random syllables with intonation and pauses, panned across the stands), four distant crowd swells (three cheers and one "ooh"), scattered clapping and a large reverb. The 3 s pre-roll plus a 3 s equal-power crossfade make the 30 s loop seamless. The circular high-pass and limiter keep the seam steady.
* **wind_industrial**: gusty band-passed pink and brown wind with faint whistle resonances, a distant 50 Hz-family hum with slow beating, a low machine throb, and seven distant metal clanks and chain rattles in a long reverb.

### SFX highlights
* **Throws and whooshes**: noise through a time-varying band-pass whose centre follows a rise-and-fall doppler curve, plus a body layer. Three variants with different lengths, sweep ranges and peak timing.
* **Hits**:
  * Short pitched thumps (around 90 to 185 Hz rather than sub-bass, so they read on laptop speakers), plus a textured "thwack" band, a leathery smack and a tiny click, saturated for density.
  * `crit_hit` adds a heavier body, modal "crack" partials and a quick glockenspiel sparkle.
  * `bat_crack` is a modal wood bar with an impulse and a short room reverb.
* **Abilities**:
  * `fire_loop` is built entirely circularly (FFT noise, integer-cycle modulation, crackles wrapped modulo the length), so it loops perfectly.
  * The other abilities layer the same building blocks: modal bells, crackle grains, filtered noise sweeps, FM and reversed reverb.
* **Game flow**:
  * `inning_end` is the traditional (public-domain) "Charge!" bugle call on stadium organ with Leslie, followed by a crowd answer.
  * The fanfares and stingers use the brass, timpani and glockenspiel instruments from the music.
  * `boss_roar` is a jittered saw/sub-octave source with 33 Hz growl modulation through an "ah" to "oh" formant morph.
* **UI**: soft sine/triangle blips and short modal ticks, all under 0.35 s and at −9 dBFS or lower.
* **Crowd**: 36 to 72 synthesized voices, each a glottal source with a pitch gesture (a rise for cheers, a fall for groans, a swell for "ooh") through a formant bank, plus a vowel-shaped noise bed, Poisson claps, an occasional finger whistle and stadium reverb.

## Limitations

* **Nothing was auditioned by ear.** Quality was checked analytically (levels, seams, spectra, envelopes, a harmony check). Subjective issues such as an instrument timbre that sounds cheesy, a mix balance that is slightly off, or a melody that is less catchy than intended may remain. The mixes can be retuned per bus in `music.py` (`levels` and `sends`).
* **The instruments are approximations**, built from analog-style subtractive, FM and additive synthesis:
  * The brass, organ, strings and choir will not pass for real recordings.
  * The power-chord "guitar" is a distorted saw stack.
  * The crowd and babble come across as plausible texture rather than intelligible voices.
* **Vorbis is lossy.** Seams are continuous to within codec noise (about −50 dBFS), not sample-exact.
* **Godot import was not exercised by me**, although `.import` files from another process appeared beside the assets. The WAV `smpl` loop follows the layout Godot's importer parses. Ogg looping relies on the runtime `loop = true` that the audio manager already sets.
* **The loudness meter** follows BS.1770-4 but reads about 0.25 dB low on the 1 kHz reference tone. Mono SFX are measured as a single channel.
* **Full builds take about 1 to 3 minutes on 4 cores**, mostly the music.

## File list and statistics

Durations are in seconds. `volume_db` is the suggested playback volume from the manifest. "Seam ratio" is the loop-point step and curvature divided by the largest local step and curvature (≤ 1 means seamless).

### Music

| name | dur (s) | loop | volume_db | tempo / key | peak dBFS | true peak | RMS dBFS | integrated LUFS | seam ratio (step / curvature) |
|---|---|---|---|---|---|---|---|---|---|
| `menu_theme` | 91.03 | yes | -6 | 116 BPM, D major | -2.3 | -2.3 | -18.2 | -16.1 | 0.37/0.50 |
| `battle_theme` | 107.46 | yes | -7 | 134 BPM, E minor | -2.3 | -2.2 | -18.0 | -16.0 | 0.10/0.35 |
| `boss_theme` | 78.90 | yes | -7 | 146 BPM, C minor | -3.4 | -3.4 | -17.4 | -16.1 | 0.25/0.43 |
| `dugout_theme` | 58.78 | yes | -6 | 98 BPM, A dorian | -3.7 | -3.7 | -18.5 | -17.0 | 0.12/0.16 |
| `practice_theme` | 60.00 | yes | -6 | 80 BPM, F major | -4.1 | -4.1 | -19.0 | -18.0 | 0.12/0.95 |
| `victory` | 12.50 | no | -4 | 120 BPM, C major | -3.0 | -3.0 | -17.8 | -14.9 | - |
| `defeat` | 8.40 | no | -4 | 72 BPM, A minor | -6.6 | -6.6 | -19.9 | -17.5 | - |

### Ambience

| name | dur (s) | loop | volume_db | tempo / key | peak dBFS | true peak | RMS dBFS | integrated LUFS | seam ratio (step / curvature) |
|---|---|---|---|---|---|---|---|---|---|
| `stadium_crowd` | 30.00 | yes | -6 | - | -10.1 | -10.1 | -27.0 | -24.2 | 0.34/0.82 |
| `wind_industrial` | 30.00 | yes | -6 | - | -11.9 | -11.9 | -28.1 | -27.1 | 0.16/0.38 |

### Sound effects

| name | dur (s) | loop | volume_db | peak dBFS | RMS dBFS | max momentary LUFS | DC | centroid Hz |
|---|---|---|---|---|---|---|---|---|
| `throw_1` | 0.19 | no | -8 | -3.0 | -16.4 | -15.0 | 0.0000 | 1810 |
| `throw_2` | 0.23 | no | -8 | -3.0 | -16.3 | -15.2 | 0.0001 | 1614 |
| `throw_3` | 0.27 | no | -8 | -3.0 | -15.3 | -13.7 | 0.0001 | 2089 |
| `ball_hit_1` | 0.24 | no | -5 | -3.0 | -14.0 | -15.7 | 0.0003 | 109 |
| `ball_hit_2` | 0.24 | no | -5 | -3.0 | -12.7 | -14.7 | 0.0001 | 87 |
| `ball_hit_3` | 0.24 | no | -5 | -3.0 | -13.8 | -15.2 | 0.0000 | 123 |
| `crit_hit` | 0.90 | no | -3 | -3.0 | -15.8 | -14.2 | 0.0002 | 869 |
| `glove_catch_1` | 0.20 | no | -6 | -3.0 | -15.2 | -16.3 | 0.0001 | 181 |
| `glove_catch_2` | 0.20 | no | -6 | -3.0 | -14.4 | -15.5 | 0.0002 | 172 |
| `bat_crack` | 0.60 | no | -3 | -3.0 | -15.9 | -14.2 | 0.0001 | 660 |
| `enemy_out_1` | 0.62 | no | -5 | -3.0 | -14.5 | -14.7 | 0.0000 | 376 |
| `enemy_out_2` | 0.69 | no | -5 | -3.0 | -14.8 | -14.6 | 0.0001 | 480 |
| `defender_stunned` | 1.09 | no | -5 | -3.0 | -21.0 | -17.4 | 0.0001 | 2173 |
| `swing_whoosh` | 0.46 | no | -5 | -3.0 | -16.1 | -15.3 | 0.0000 | 1165 |
| `wall_break` | 1.29 | no | -4 | -3.0 | -16.8 | -15.8 | 0.0001 | 143 |
| `shield_block` | 0.85 | no | -5 | -3.0 | -20.5 | -17.1 | 0.0001 | 1091 |
| `run_scored` | 2.50 | no | -3 | -3.0 | -17.9 | -14.0 | 0.0001 | 382 |
| `gate_open` | 2.60 | no | -4 | -3.0 | -16.2 | -12.5 | 0.0001 | 332 |
| `footstep_dirt_1` | 0.11 | no | -10 | -12.0 | -23.6 | -25.5 | 0.0001 | 209 |
| `footstep_dirt_2` | 0.11 | no | -10 | -12.0 | -23.4 | -25.6 | 0.0002 | 245 |
| `card_draw` | 0.12 | no | -6 | -6.0 | -19.4 | -16.6 | 0.0000 | 3677 |
| `card_hover` | 0.04 | no | -6 | -15.0 | -30.9 | -28.4 | 0.0004 | 2341 |
| `card_play` | 1.10 | no | -4 | -3.0 | -20.4 | -15.4 | 0.0000 | 1577 |
| `card_denied` | 0.28 | no | -4 | -6.0 | -17.0 | -18.1 | 0.0002 | 191 |
| `energy_full` | 1.30 | no | -5 | -3.0 | -14.5 | -9.0 | 0.0001 | 1968 |
| `fire_cast` | 1.35 | no | -3 | -3.0 | -18.3 | -15.2 | 0.0000 | 593 |
| `fire_loop` | 2.00 | yes | -10 | -6.0 | -15.7 | -17.2 | 0.0000 | 201 |
| `frost_cast` | 1.50 | no | -3 | -3.0 | -18.9 | -12.5 | 0.0000 | 2799 |
| `shadow_cast` | 1.15 | no | -3 | -3.0 | -15.9 | -14.5 | 0.0001 | 241 |
| `lightning_zap` | 0.98 | no | -4 | -3.0 | -18.8 | -16.7 | 0.0000 | 880 |
| `magnet_pull` | 1.25 | no | -5 | -3.0 | -12.2 | -11.3 | 0.0008 | 328 |
| `earth_rumble` | 1.80 | no | -3 | -3.0 | -15.0 | -14.1 | 0.0008 | 73 |
| `barrage_impact` | 1.60 | no | -3 | -3.0 | -18.6 | -15.6 | 0.0000 | 119 |
| `time_out_whistle` | 1.10 | no | -6 | -3.0 | -11.2 | -6.6 | 0.0000 | 2496 |
| `rally_horn` | 1.90 | no | -5 | -3.0 | -15.4 | -12.7 | 0.0004 | 914 |
| `aura_hum` | 2.20 | no | -6 | -3.0 | -17.0 | -12.9 | 0.0000 | 745 |
| `heal_chime` | 1.50 | no | -5 | -3.0 | -14.9 | -11.1 | 0.0002 | 1057 |
| `explosion_small` | 0.67 | no | -4 | -3.0 | -16.9 | -17.6 | 0.0001 | 83 |
| `wave_start` | 2.20 | no | -2 | -3.0 | -17.4 | -15.4 | 0.0002 | 214 |
| `wave_clear` | 1.60 | no | -3 | -3.0 | -16.0 | -11.9 | 0.0001 | 994 |
| `inning_end` | 3.30 | no | -3 | -3.0 | -14.0 | -12.0 | 0.0001 | 1290 |
| `combo_double` | 0.90 | no | -4 | -3.0 | -13.0 | -10.3 | 0.0002 | 1334 |
| `combo_triple` | 1.20 | no | -3 | -3.0 | -14.4 | -11.0 | 0.0001 | 1286 |
| `combo_grand` | 2.00 | no | -2 | -3.0 | -14.7 | -13.0 | 0.0002 | 226 |
| `boss_warning` | 3.30 | no | -2 | -3.0 | -12.3 | -12.3 | 0.0000 | 76 |
| `boss_slam` | 2.60 | no | -2 | -3.0 | -14.8 | -16.0 | 0.0000 | 49 |
| `boss_roar` | 2.00 | no | -3 | -3.0 | -13.1 | -13.6 | 0.0004 | 268 |
| `victory_fanfare` | 4.60 | no | -3 | -3.0 | -14.1 | -12.1 | 0.0001 | 341 |
| `defeat_sting` | 3.40 | no | -3 | -3.0 | -13.4 | -12.1 | 0.0001 | 383 |
| `level_up` | 1.50 | no | -4 | -3.0 | -15.9 | -11.4 | 0.0000 | 1578 |
| `achievement` | 2.30 | no | -4 | -3.0 | -15.7 | -11.9 | 0.0001 | 1043 |
| `coin` | 0.45 | no | -6 | -6.0 | -15.6 | -14.6 | 0.0002 | 1630 |
| `purchase` | 1.06 | no | -4 | -3.0 | -16.7 | -10.7 | 0.0000 | 2326 |
| `ui_hover` | 0.04 | no | -6 | -13.0 | -24.8 | -23.7 | 0.0001 | 1739 |
| `ui_click` | 0.07 | no | -4 | -9.0 | -23.6 | -23.8 | 0.0007 | 831 |
| `ui_back` | 0.17 | no | -4 | -9.0 | -17.3 | -17.2 | 0.0000 | 1011 |
| `ui_confirm` | 0.32 | no | -4 | -9.0 | -19.9 | -19.3 | 0.0000 | 1571 |
| `ui_error` | 0.19 | no | -4 | -9.0 | -17.1 | -18.0 | 0.0001 | 283 |
| `ui_tab` | 0.09 | no | -4 | -9.0 | -23.4 | -23.5 | 0.0003 | 959 |
| `ui_slide` | 0.24 | no | -5 | -9.0 | -21.3 | -20.7 | 0.0000 | 1349 |
| `ui_toggle` | 0.10 | no | -4 | -9.0 | -26.1 | -24.0 | 0.0004 | 2479 |
| `crowd_cheer_1` | 2.60 | no | -6 | -3.0 | -16.2 | -13.6 | 0.0000 | 687 |
| `crowd_cheer_2` | 2.90 | no | -6 | -3.0 | -16.6 | -13.5 | 0.0000 | 735 |
| `crowd_groan` | 2.00 | no | -6 | -3.0 | -17.6 | -14.5 | 0.0000 | 624 |
| `crowd_ooh` | 1.90 | no | -6 | -3.0 | -17.5 | -14.5 | 0.0000 | 483 |

