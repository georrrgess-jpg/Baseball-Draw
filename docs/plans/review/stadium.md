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
| 10 | Gate/wall/light-tower props, sky gradients and per-arena sun colours are good; no z-fighting or floating props found. | — | — | — | — | No change |

Seed items 3 (Base Shield dome), 4 (aura domes) and others belong to Stream A and are not covered here.

## What was done

See the stream report (Update 5, Stream B) for the full list. In short: an instanced, shader-animated crowd
with reactions and the wave; procedural dugouts with bench players; a reworked field shader (stripes, grass
variation, lipped dirt edges, scuffs, worn chalk, coaches' boxes, on-deck circles, foul-territory grass and
warning tracks); sponsor boards and foul poles; night dimming and lamp halos; and stadium life (jumbotron live
feed of big moments, the mascot between waves, fireworks on boss defeats and wins).
