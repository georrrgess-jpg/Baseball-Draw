shader_type canvas_item;
render_mode blend_add;
// Screen-space accent for Legendary card casts (Update 8): radial light streaks that race
// out from the impact point and a coloured glow along the screen edges. Additive, short
// (under half a second) and kept away from the centre of the impact so the runners, the
// health bars and the field underneath stay readable.
//   t = progress 0..1, strength = overall intensity, streaks = 0..1 (0 with reduce_flashes)

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.3, 0.7, 1.0);
uniform vec2 center = vec2(0.5, 0.5);
uniform float t = 0.0;
uniform float strength = 0.0;
uniform float streaks = 1.0;
uniform float aspect = 1.7778;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 d = (UV - center) * vec2(aspect, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x);
	// Radial streaks: thin angular bands with random length, travelling outward.
	float bands = 46.0;
	float cell = floor((ang / 6.2831853 + 0.5) * bands);
	float h = hash11(cell + seed * 17.0);
	float h2 = hash11(cell * 1.7 + 3.0 + seed * 5.0);
	float within = fract((ang / 6.2831853 + 0.5) * bands);
	float thin = 1.0 - smoothstep(0.0, 0.18 + 0.2 * h2, abs(within - 0.5));
	float front = mix(0.08, 1.6, pow(t, 0.55)) * (0.6 + 0.6 * h);
	float tail = front - (0.25 + 0.35 * h2);
	float along = smoothstep(tail, front - 0.02, r) * (1.0 - smoothstep(front - 0.02, front, r));
	float keep_clear = smoothstep(0.06, 0.2, r);   // never over the impact itself
	float streak = thin * along * keep_clear * step(0.45, h) * streaks;
	// Edge glow: a soft frame that blooms and fades.
	vec2 e = min(UV, 1.0 - UV);
	float edge = pow(1.0 - smoothstep(0.0, 0.16, min(e.x * aspect / 1.7778, e.y)), 2.0);
	float life = sin(3.14159 * clamp(t, 0.0, 1.0));
	vec3 col = mix(color.rgb, color2.rgb, clamp(r * 0.9 + 0.2 * h, 0.0, 1.0)) * streak * (1.0 - t) * 1.4
		+ mix(color2.rgb, color.rgb, 0.5 + 0.5 * sin(ang * 2.0 + t * 3.0)) * edge * life * 0.85;
	COLOR = vec4(col * strength, 1.0);
}
