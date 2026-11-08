shader_type canvas_item;
// Prestige finish (Update 11) for CardView: an iridescent, slowly flowing holo frame, a soft prism
// sheen over the art window and a gentle light sweep. Strength stays modest inside the card so the
// text reads in battle; the frame carries the colour. Same coordinate setup as card_foil.gdshader.

uniform vec2 card_size = vec2(150.0, 210.0);
uniform vec2 rect_origin = vec2(0.0);   // top-left of the card in CardView's drawing space
uniform float hover = 0.0;              // 0..1, brightens the sweep
uniform float phase = 0.0;              // per-card offset so a hand does not shimmer in sync
uniform float stars = 1.0;              // Prestige stars 1-5: a little more colour per star
uniform float calm = 0.0;               // 1 = reduce_flashes: no sweep, slower flow
uniform float period = 4.2;

varying vec2 local_uv;
varying vec2 local_px;

void vertex() {
	local_uv = (VERTEX - rect_origin) / card_size;
	local_px = VERTEX - rect_origin;
}

vec3 prism(float t) {
	// Pastel iridescence: cyan -> violet -> rose -> gold -> mint.
	vec3 c = 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
	return mix(c, vec3(1.0), 0.28);
}

void fragment() {
	vec2 uv = local_uv;
	float s = card_size.x / 150.0;
	// Distance (px) to the card's outer edge; negative outside the card (glows, badges).
	vec2 d2 = min(local_px, card_size - local_px);
	float dist = min(d2.x, d2.y);
	float inside = step(0.0, dist);
	// The metal frame is the outer 5 px (at 150 px wide).
	float frame = inside * (1.0 - smoothstep(4.0 * s, 5.6 * s, dist));
	float diag = uv.x * 0.75 + uv.y * 0.55;
	float flow = TIME * mix(0.16, 0.05, calm);
	vec3 irid = prism(diag * 1.35 - flow + phase);
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float k = clamp(0.62 + 0.06 * stars, 0.0, 0.92);
	// Holo over a pale gold base: the colour drifts through the prism but stays warm and metallic.
	vec3 frame_col = mix(vec3(1.0, 0.86, 0.5), irid, 0.72) * (0.42 + 0.95 * lum);
	vec3 col = mix(COLOR.rgb, frame_col, frame * k);
	// Fine bright filament along the frame's inner edge.
	float filament = inside * exp(-pow((dist - 5.0 * s) / (0.9 * s), 2.0));
	col += irid * filament * 0.35;
	// Faint prism film over the rest of the card (stronger on the art, which sits in the top half).
	float art = inside * (1.0 - frame) * smoothstep(0.62, 0.45, uv.y) * smoothstep(0.08, 0.16, uv.y);
	col += prism(diag * 2.2 + flow * 1.6 + phase + 0.4) * art * 0.08;
	// Light sweep, softer than the Rare foil and off with reduce_flashes.
	float t = fract((TIME + phase) / period);
	float center = mix(-0.4, 1.8, t);
	float band = exp(-pow((diag - center) * 8.0, 2.0)) + exp(-pow((diag - center + 0.16) * 20.0, 2.0)) * 0.5;
	col += band * (0.18 + hover * 0.25) * (1.0 - calm) * mix(vec3(1.0), irid, 0.5) * inside;
	COLOR.rgb = col;
}
