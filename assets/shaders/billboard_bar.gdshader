shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
// Runner health bar: a camera-facing quad drawn on top of everything (never hidden by
// its own model or by a crowd). It keeps at least `min_px` pixels of width when the
// camera is far away and grows upward from its anchor so it never covers the head.
// Per-instance values (fill, chip trail, hit pulse) avoid material duplication; one
// shared material per bar style (runner / elite / boss).

instance uniform float fill = 1.0;
instance uniform float chip = 1.0;          // white "damage taken" segment that drains after a hit
instance uniform float pulse = 0.0;         // 1 on a hit, decays to 0 (scale pop + white flash)
instance uniform float shield = 0.0;
instance uniform float visible_alpha = 1.0;
uniform vec2 bar_size = vec2(1.3, 0.24);    // world size of the quad (matches the QuadMesh)
uniform float min_px = 58.0;                // minimum on-screen width in pixels at 1000 px viewport height
uniform float max_grow = 3.2;               // cap on the distance compensation
uniform float border = 0.2;                 // outline thickness, as a fraction of the height
uniform vec4 frame_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform vec4 trim_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);  // elite / boss accent line
uniform float ticks = 10.0;
uniform bool colorblind = false;

void vertex() {
	vec3 origin = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float dist = max(-origin.z, 0.1);
	// Pixels covered by one metre at this depth (vertical FOV based; works for both projections).
	float px_per_m = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / dist;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		px_per_m = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5;
	}
	float want_px = min_px * clamp(VIEWPORT_SIZE.y / 1000.0, 0.8, 2.2);
	float grow = clamp(want_px / max(bar_size.x * px_per_m, 0.001), 1.0, max_grow);
	float pop = 1.0 + 0.28 * pulse;
	float s = grow * pop;
	vec2 v = VERTEX.xy * s;
	// Keep the bottom edge where the unscaled bar's bottom edge was.
	v.y += bar_size.y * 0.5 * (grow - 1.0);
	VERTEX = origin + vec3(v, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec3 health_color(float f) {
	vec3 hi = colorblind ? vec3(0.15, 0.55, 1.0) : vec3(0.12, 0.88, 0.18);
	vec3 mid = colorblind ? vec3(1.0, 0.82, 0.1) : vec3(1.0, 0.8, 0.06);
	vec3 lo = colorblind ? vec3(1.0, 0.42, 0.02) : vec3(1.0, 0.14, 0.1);
	vec3 c = mix(lo, mid, smoothstep(0.22, 0.38, f));
	return mix(c, hi, smoothstep(0.52, 0.66, f));
}

void fragment() {
	vec2 uv = UV;
	float aspect = bar_size.x / bar_size.y;
	vec2 px = vec2(border / aspect, border);
	bool inner = uv.x > px.x && uv.x < 1.0 - px.x && uv.y > px.y && uv.y < 1.0 - px.y;
	vec3 c = frame_color.rgb;
	if (trim_color.a > 0.0) {
		// Thin bright line around the outline for elites / bosses.
		vec2 e = min(uv, 1.0 - uv) / px;
		float edge = min(e.x, e.y);
		c = mix(c, trim_color.rgb, trim_color.a * (1.0 - smoothstep(0.25, 0.55, edge)));
	}
	float a = 0.95;
	if (inner) {
		float x = (uv.x - px.x) / (1.0 - 2.0 * px.x);
		float y = (uv.y - px.y) / (1.0 - 2.0 * px.y);
		c = vec3(0.16, 0.05, 0.05);
		if (x < chip) {
			c = vec3(1.0, 0.97, 0.9);
		}
		if (x < fill) {
			// Over-bright so the colour survives the scene's tonemapping.
			c = health_color(fill) * (1.2 - 0.38 * y);
			// Gloss on the top third.
			c += vec3(0.12) * (1.0 - smoothstep(0.0, 0.4, y));
		}
		if (shield > 0.0 && x < shield) {
			c = mix(c, vec3(0.7, 0.75, 0.8), 0.55);
		}
		if (ticks > 0.0) {
			float tick = step(1.0 - 0.06 * ticks / 10.0, fract(x * ticks));
			c *= 1.0 - tick * 0.3;
		}
		c = mix(c, vec3(1.0), pulse * 0.55);
	}
	ALBEDO = c;
	ALPHA = a * visible_alpha;
}
