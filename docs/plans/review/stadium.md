# Stadium review (Stream B + feature 7)

Scope: everything around the playing field: crowd, stands, dugouts, props, field surface, lighting and sky per
arena, the scoreboard, and the main menu's stadium backdrop. Captures were rendered by the game
(1600×900, High preset, lavapipe) from the default battle camera, a close camera on the third-base side and
the main menu.

Scoring: **Severity** 1 cosmetic … 4 breaks the experience; **Reach** 1 rare … 4 every battle;
**Effort** S = 1, M = 2, L = 3. Priority = Severity × Reach ÷ Effort.

| # | Finding | Sev | Reach | Effort | Priority | Status |
|---|---|---|---|---|---|---|
| 1 | **Crowd is blocky cubes** (seed 1). From the default camera the stands fill both sides of the screen and every fan is four boxes in one flat colour: the least polished thing on screen. Their only motion is a bob. | 3 | 4 | M | 6.0 | Fixed |
| 2 | **Dugouts read as grey slabs** (seed 2). The prop has a bench, rail and steps, but from the battle camera only the bare concrete roof is visible, and it is raised 0.6 m so it looks like a box sitting on the ground. No team colour, no people. | 3 | 4 | M | 6.0 | Fixed |
| 3 | **Foul territory is bare concrete** right up to the foul lines: the field looks like a slice cut out of a car park, and the dugouts sit on asphalt. | 2 | 4 | S | 8.0 | Fixed |
| 4 | **Field surface is a hard checkerboard** (seed 5): one diagonal 5 m checker everywhere, uniform noise, razor-sharp dirt edges, perfect chalk. | 2 | 4 | S | 8.0 | Fixed |
| 5 | **The stadium never reacts** beyond the crowd bouncing harder. Outs, combos, runs, boss defeats and wins look the same in the stands; the scoreboard only flashes text. (Feature 7.) | 2 | 4 | M | 4.0 | Fixed |
| 6 | **Night arenas do not read as night** from the battle camera (Neon Diamond, Iron Fortress): the concourse outside the walls is pale grey-lavender and the light towers are just geometry. | 2 | 2 | S | 4.0 | Improved |
| 7 | **No ballpark furniture**: no foul poles, no sponsor boards, no on-deck circles, no coaches' boxes. The outfield wall is a long dark band. | 1 | 4 | S | 4.0 | Fixed (bullpen deferred) |
| 8 | Large empty concourse below home plate in the default view (behind the backstop). Hidden mostly by the hand. | 1 | 4 | M | 2.0 | Partly (apron + on-deck circles) |
| 9 | Main menu: stands behind the lineup show the same cube crowd; dugout on the right edge is a grey box. | 2 | 4 | — | — | Fixed by 1–2 |
| 10 | **Frostpark is washed out** to a flat grey-white from the battle camera (fog + snow haze over a pale palette); runners and chalk lose contrast. | 2 | 1 | S | 2.0 | Improved (thinner haze, more contrast) |
| 11 | Steel Yard and Sunset Grounds look almost identical from the battle camera (same layout, similar orange light); the difference is only visible in the sky. | 1 | 2 | M | 1.0 | Open (sky is off-screen in battle) |
| 12 | Gate/wall/light-tower props, sky gradients and per-arena sun colours are good; no z-fighting or floating props found. | — | — | — | — | No change |

### Lighting and mood per arena (battle camera)

| Arena | Time | Before | After |
|---|---|---|---|
| Steel Yard | sunset | Warm, readable; concrete foul ground | Same light; grass foul ground, crowd and boards add colour |
| Sunset Grounds | golden | Very close to Steel Yard | Same, dust motes; distinct crowd colours |
| Neon Diamond | night | Did not read as night: pale concourse | Darkened concourse, lamp halos on the light towers, back-lit ad boards |
| Iron Fortress | storm | Grey, rain, fine | Concourse slightly darker, lamp halos, back-lit boards |
| Frostpark | dusk snow | Washed out, low contrast | Half the haze, more contrast and saturation |
| Champion's Citadel | twilight | Purple twilight, distinctive | Lamp halos, concourse slightly darker |

Seed items 3 (Base Shield dome), 4 (aura domes) and others belong to Stream A and are not covered here.

## What was done

See the stream report (Update 5, Stream B) for the full list. In short: an instanced, shader-animated crowd
with reactions and the wave; procedural dugouts with bench players; a reworked field shader (stripes, grass
variation, lipped dirt edges, scuffs, worn chalk, coaches' boxes, on-deck circles, foul-territory grass and
warning tracks); sponsor boards and foul poles; night dimming and lamp halos; and stadium life (jumbotron live
feed of big moments, the mascot between waves, fireworks on boss defeats and wins).

## Verification

* Before/after captures (default battle camera for all six arenas, a close camera on Steel Yard, the main menu),
  plus the mascot, the jumbotron live feed, its Low fallback and the victory fireworks were looked at closely:
  crowd readable, gates, routes, runners and home plate unobstructed, no z-fighting or floating props.
* Autopilot Quick Defense game in each arena, headless: all six finished with no script errors.
* `tools/check_scripts.sh`: 62 scripts, 0 failed. System suite: 957 checks, 0 failed.

## Cost

* Fans per battle (all stands): about 1,800 on High, 1,000 on Medium, 580 on Low (crowd setting 1.0 / 0.6 / 0.35).
  One draw call per grandstand, animated entirely in the vertex shader; 240 triangles per fan on High/Medium,
  140 on Low. Worst case about 0.43 M triangles on High (was about 0.08 M with the cube fans), 0.08 M on Low.
* Dugouts: one merged mesh each plus one MultiMesh of players; foul poles and ad boards one mesh each.
* Jumbotron feed: a 576×256 second camera, rendered only while a moment is on screen (3–9 s); not on Low.
* Fireworks: a pool of 6 bursts (30–170 sparks each, scaled by the particle setting) plus 6 rocket trails.

## Deferred

* Bullpen (mound and plate in foul territory along a line): would sit on the foul-line routes of the
  Neon Diamond layout; left out to keep the routes readable.
* A true replay (recorded positions) instead of the live camera on the jumbotron.
* Sky differences between Steel Yard and Sunset Grounds are invisible from the battle camera (finding 11).
