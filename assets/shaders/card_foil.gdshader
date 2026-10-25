shader_type canvas_item;
// Foil finish for Rare+ cards drawn by CardView: a periodic light sweep across the card,
// plus a holographic rainbow on the frame for Epic and Legendary. Works on the card's
// custom drawing (frame, art and text), using local coordinates for the effect.

uniform vec2 card_size = vec2(150.0, 210.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float sheen = 0.5;          // strength of the moving light band
uniform float holo = 0.0;           // rainbow strength on the frame (epic / legendary)
uniform float hover = 0.0;          // 0..1, brightens and speeds up the sweep
uniform float phase = 0.0;          // per-card offset so a hand does not flash in sync
uniform float period = 3.6;

varying vec2 local_uv;

void vertex() {
	local_uv = VERTEX / card_size;
}

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	vec2 uv = local_uv;
	// Diagonal coordinate for the sweep band.
	float d = uv.x * 0.8 + uv.y * 0.6;
	float t = fract((TIME + phase) / mix(period, period * 0.55, hover));
	float center = mix(-0.4, 1.8, t);
	float band = exp(-pow((d - center) * 9.0, 2.0));
	float band2 = exp(-pow((d - center + 0.18) * 22.0, 2.0)) * 0.6;
	vec3 add = (band + band2) * (sheen + hover * 0.35) * mix(vec3(1.0), tint.rgb, 0.35);
	// Frame mask: strongest near the card edges, absent in the middle.
	vec2 e = min(uv, 1.0 - uv);
	float edge = 1.0 - smoothstep(0.02, 0.09, min(e.x, e.y * 1.4));
	vec3 holo_col = rainbow(d * 1.6 - TIME * 0.12 + phase) * holo * edge * 0.55;
	COLOR.rgb += (add + holo_col) * COLOR.a;
}
