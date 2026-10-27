shader_type spatial;
// Procedural baseball field surface: mowed grass (straight outfield stripes with a view-dependent
// sheen, a finer cross-cut on the infield grass, patchy colour variation and blade grain),
// infield dirt with a soft lipped grass edge, rake marks and clay scuffs around the bases,
// worn chalk lines, batter's and coaches' boxes, on-deck circles, warning tracks, foul-territory
// grass up to the side walls, worn runner routes with animated direction chevrons and an
// optional placement-zone overlay.

uniform vec3 grass_a : source_color = vec3(0.25, 0.54, 0.23);
uniform vec3 grass_b : source_color = vec3(0.30, 0.60, 0.27);
uniform vec3 dirt_color : source_color = vec3(0.69, 0.42, 0.24);
uniform vec3 track_color : source_color = vec3(0.45, 0.30, 0.20);
uniform vec3 chalk_color : source_color = vec3(0.96, 0.95, 0.92);
uniform vec3 route_color : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 zone_color : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 team_color : source_color = vec3(0.11, 0.18, 0.29);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec4 segs[48];
uniform float seg_start[48];
uniform int seg_count = 0;
uniform float zones_alpha = 0.0;
uniform float route_glow = 1.0;
uniform float wall_radius = 36.0;
uniform float surround_dim = 0.0;   // darkens the concourse outside the walls at night

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - (a + ab * t));
}

float seg_d(vec2 p, vec2 a, vec2 b) {
	float t;
	return seg_dist(p, a, b, t);
}

float band(float x, float center, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(x - center));
}

// Outline of an axis-aligned rectangle in (x, y) coordinates.
float rect_line(vec2 q, vec2 lo, vec2 hi, float w, float aa) {
	vec2 c = (lo + hi) * 0.5;
	vec2 h = (hi - lo) * 0.5;
	vec2 d = abs(q - c) - h;
	float outside = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	return band(outside, 0.0, w, aa);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 home = vec2(0.0, 10.0);
	vec2 rel = p - home;
	float dh = length(rel);
	float ang = degrees(atan(rel.x, -rel.y));
	float u = dot(rel, vec2(0.70710678, -0.70710678));   // along the first-base line
	float v = dot(rel, vec2(-0.70710678, -0.70710678));  // along the third-base line
	float aa = max(fwidth(dh) * 1.2, 0.02);

	float n = texture(noise_tex, p * 0.035).r;
	float n2 = texture(noise_tex, p * 0.23 + vec2(13.0, 7.0)).r;
	float n3 = texture(noise_tex, p * 1.7 + vec2(3.0, 41.0)).r;      // fine grain / chalk wear
	float n4 = texture(noise_tex, p * 0.012 + vec2(71.0, 5.0)).r;    // very large patches

	// ---- Grass: straight outfield stripes (mower wobble), cross-cut on the infield grass.
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float wob = (n2 - 0.5) * 0.5;
	float stripe_w = 4.2;
	float sx = (p.x + wob) / stripe_w;
	float stripe = smoothstep(0.42, 0.58, abs(fract(sx) - 0.5) * 2.0);
	// Blades laid in alternate directions catch the light differently depending on the view.
	float lay = (stripe * 2.0 - 1.0) * clamp(view_w.z * 0.8 + 0.25, -1.0, 1.0);
	float ig_zone = step(u, 13.0) * step(v, 13.0);
	float c1 = smoothstep(0.44, 0.56, abs(fract((u + wob) / 2.4) - 0.5) * 2.0);
	float c2 = smoothstep(0.44, 0.56, abs(fract((v + wob) / 2.4) - 0.5) * 2.0);
	float cross_cut = abs(c1 - c2);
	float mow = mix(0.5 + 0.5 * lay, cross_cut, ig_zone);
	vec3 grass = mix(grass_a, grass_b, clamp(mow, 0.0, 1.0));
	// Patchy variation: large soft patches, mid-scale mottling and blade grain.
	grass *= 0.9 + 0.2 * n4;
	grass *= 0.9 + 0.18 * n;
	grass *= 0.95 + 0.1 * n2;
	grass *= 0.93 + 0.14 * n3;
	// Slightly yellowed, worn turf in the high-traffic areas (in front of the bases, around home).
	float wear = (1.0 - smoothstep(1.5, 4.0, length(p - vec2(9.5, 0.5))))
		+ (1.0 - smoothstep(1.5, 4.0, length(p - vec2(-9.5, 0.5))))
		+ (1.0 - smoothstep(2.0, 5.0, length(p - vec2(0.0, -9.0))));
	grass = mix(grass, grass * vec3(1.08, 1.0, 0.72), clamp(wear, 0.0, 1.0) * 0.35 * n2);
	vec3 col = grass;
	float rough = 0.82;

	// ---- Infield dirt: arc behind the bases minus the infield grass square, mound, home circle.
	// The grass edge is perturbed slightly so it is not a perfect line.
	float edge_n = (n2 - 0.5) * 0.18;
	float arc = (1.0 - smoothstep(20.6 - aa, 20.6 + aa, dh + edge_n)) * (1.0 - smoothstep(46.0, 47.5, abs(ang)));
	float ig = smoothstep(1.7 - aa, 1.7 + aa, u + edge_n) * (1.0 - smoothstep(11.7 - aa, 11.7 + aa, u - edge_n))
			* smoothstep(1.7 - aa, 1.7 + aa, v + edge_n) * (1.0 - smoothstep(11.7 - aa, 11.7 + aa, v - edge_n));
	float mound_d = length(p - vec2(0.0, 1.0));
	float mound = 1.0 - smoothstep(2.75 - aa, 2.75 + aa, mound_d + edge_n);
	float homec = 1.0 - smoothstep(4.1 - aa, 4.1 + aa, dh + edge_n);
	float dirt_mask = max(arc * (1.0 - ig), max(mound, homec));
	vec3 dirt = dirt_color * (0.84 + 0.26 * n2) * (0.93 + 0.12 * n);
	// Rake marks: faint concentric grooves around home plate in the infield.
	float rake = sin(dh * 22.0 + n2 * 6.0) * 0.5 + 0.5;
	dirt *= 0.96 + 0.06 * rake;
	// Clay scuffs and cleat marks along the base paths and around every base.
	vec2 b1 = vec2(9.5, 0.5);
	vec2 b2 = vec2(0.0, -9.0);
	vec2 b3 = vec2(-9.5, 0.5);
	float path_d = min(min(seg_d(p, b1, b2), seg_d(p, b2, b3)), min(seg_d(p, home, b1), seg_d(p, home, b3)));
	float base_d = min(min(length(p - b1), length(p - b2)), min(length(p - b3), dh));
	float scuff = (1.0 - smoothstep(0.4, 1.1, path_d)) * 0.6 + (1.0 - smoothstep(0.6, 1.8, base_d));
	scuff *= smoothstep(0.35, 0.7, n3 * 0.6 + n2 * 0.6);
	dirt = mix(dirt, dirt * vec3(0.78, 0.74, 0.72), clamp(scuff, 0.0, 1.0) * 0.55);
	// The batter's boxes and the area in front of the rubber are dug out and darker.
	float dug = (1.0 - smoothstep(0.3, 0.9, length(vec2(abs(rel.x) - 1.15, rel.y) * vec2(1.4, 0.8))))
		+ (1.0 - smoothstep(0.2, 0.7, length(p - vec2(0.0, 1.6))));
	dirt = mix(dirt, dirt * 0.82, clamp(dug, 0.0, 1.0) * 0.6 * (0.6 + 0.4 * n3));

	// ---- Boundaries: outfield wall, side walls (foul poles to the dugouts) and the backstop.
	vec2 sa = vec2(26.456, -15.456);
	vec2 sn = vec2(0.9402, 0.3410);
	float side_d = dot(vec2(abs(p.x), p.y) - sa, sn);          // > 0 beyond the side walls
	float out_wall = smoothstep(wall_radius + 0.5, wall_radius + 1.5, dh);
	float out_side = smoothstep(-0.3, 0.6, side_d);
	float out_back = max(smoothstep(12.8, 13.4, p.y), smoothstep(7.7, 8.2, dh) * smoothstep(10.6, 11.2, p.y));
	float outside = max(max(out_wall, out_side), out_back);

	// Warning tracks: in front of the outfield wall and the side walls, and the backstop apron.
	float track = smoothstep(wall_radius - 3.4 - aa, wall_radius - 3.4 + aa, dh + edge_n);
	track = max(track, smoothstep(-2.6, -2.4, side_d + edge_n));
	track = max(track, smoothstep(4.0, 4.3, dh + edge_n) * smoothstep(9.8, 10.6, p.y));
	vec3 track_col = track_color * (0.85 + 0.25 * n2) * (0.95 + 0.1 * n3);
	col = mix(col, track_col, track);

	// ---- Worn runner routes and moving chevrons that show the direction of travel.
	float route_mask = 0.0;
	float chev = 0.0;
	float edge = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= seg_count) {
			break;
		}
		vec4 s = segs[i];
		float t;
		float d = seg_dist(p, s.xy, s.zw, t);
		route_mask = max(route_mask, 1.0 - smoothstep(0.75, 1.25, d + n2 * 0.25));
		edge = max(edge, band(d, 1.05, 0.05, aa));
		if (d < 0.9) {
			float along = seg_start[i] + t * length(s.zw - s.xy);
			float k = fract((along - d * 0.7 - TIME * 1.3) / 3.2);
			float c = smoothstep(0.0, 0.04, k) * (1.0 - smoothstep(0.07, 0.13, k));
			chev = max(chev, c * (1.0 - smoothstep(0.3, 0.6, d)));
		}
	}
	vec3 lane = mix(dirt, vec3(dot(dirt, vec3(0.33))), 0.35) * 0.8;
	col = mix(col, lane, route_mask * 0.55 * (1.0 - dirt_mask));
	col = mix(col, route_color * 0.9, chev * 0.35);
	// Grass lip: a darker, lusher band right at the edge of the dirt.
	float fair = 1.0 - smoothstep(46.0, 47.5, abs(ang));
	float ig_in = smoothstep(1.7, 2.1, u + edge_n) * (1.0 - smoothstep(11.3, 11.7, u - edge_n))
			* smoothstep(1.7, 2.1, v + edge_n) * (1.0 - smoothstep(11.3, 11.7, v - edge_n));
	float lip = max(band(dh + edge_n, 20.8, 0.2, 0.1) * fair, ig * (1.0 - ig_in));
	lip = max(lip, max(band(mound_d + edge_n, 2.95, 0.2, 0.08), band(dh + edge_n, 4.3, 0.2, 0.08)));
	col *= 1.0 - lip * (1.0 - dirt_mask) * 0.22;
	col = mix(col, dirt, dirt_mask);
	rough = mix(rough, 0.96, max(dirt_mask, route_mask * 0.7));

	// ---- Chalk: foul lines, batter's boxes, coaches' boxes, home circle edge; worn in places.
	float chalk = 0.0;
	float fl_w = 0.075;
	chalk = max(chalk, band(u, 0.0, fl_w, aa * 0.5) * step(0.0, v) * step(dh, wall_radius - 0.2));
	chalk = max(chalk, band(v, 0.0, fl_w, aa * 0.5) * step(0.0, u) * step(dh, wall_radius - 0.2));
	float boxes = max(rect_line(rel, vec2(-1.7, -1.0), vec2(-0.6, 1.0), 0.04, aa),
		rect_line(rel, vec2(0.6, -1.0), vec2(1.7, 1.0), 0.04, aa));
	boxes = max(boxes, rect_line(vec2(u, v), vec2(11.0, -3.1), vec2(15.0, -1.9), 0.045, aa));
	boxes = max(boxes, rect_line(vec2(u, v), vec2(-3.1, 11.0), vec2(-1.9, 15.0), 0.045, aa));
	chalk = max(chalk, boxes);
	// Wear: broken up by fine noise, scuffed most near home plate and the bases.
	float worn = smoothstep(0.18, 0.5, n3) * (0.75 + 0.25 * n2);
	worn *= mix(0.55, 1.0, smoothstep(1.0, 3.5, min(dh, base_d)));
	col = mix(col, chalk_color * (0.9 + 0.1 * n2), chalk * 0.95 * worn);

	// ---- On-deck circles (team colour with a chalk ring).
	vec2 od = vec2(abs(p.x) - 7.6, p.y - 9.0);
	float odd = length(od);
	float od_fill = 1.0 - smoothstep(0.78, 0.82, odd);
	col = mix(col, team_color * (0.85 + 0.2 * n3), od_fill * 0.85);
	col = mix(col, chalk_color, band(odd, 0.8, 0.04, aa) * 0.9 * (0.8 + 0.2 * n3));

	// ---- Placement-zone overlay (shown while positioning defenders).
	vec3 emission = route_color * chev * route_glow * 0.22 + route_color * edge * 0.03 * route_glow;
	if (zones_alpha > 0.001) {
		float ring_m = band(length(p - vec2(0.0, 1.0)), 2.7, 0.06, aa);
		float ring_h = band(dh, 4.6, 0.06, aa);
		float dash = step(0.5, fract(atan(rel.x, -rel.y) * 30.0));
		float ring_i = band(dh, 21.0, 0.07, aa) * dash * step(abs(ang), 52.0);
		float zone_fill = (1.0 - smoothstep(2.6, 2.8, length(p - vec2(0.0, 1.0)))) * 0.25 + (1.0 - smoothstep(4.5, 4.7, dh)) * 0.15;
		float rings = max(max(ring_m, ring_h), ring_i);
		col = mix(col, zone_color, (zone_fill * 0.5 + rings * 0.8) * zones_alpha);
		emission += zone_color * rings * zones_alpha * 0.6;
	}

	// ---- Outside the walls: worn concrete concourse with expansion joints.
	vec2 joint = abs(fract(p / 4.0) - 0.5);
	float joints = 1.0 - smoothstep(0.47, 0.49, max(joint.x, joint.y));
	vec3 concrete = vec3(0.26, 0.26, 0.28) * (0.8 + 0.3 * n) * (0.9 + 0.15 * n2) * (1.0 - (1.0 - joints) * 0.25);
	concrete *= 1.0 - surround_dim * 0.55;
	col = mix(col, concrete, outside);
	rough = mix(rough, 0.9, outside);
	emission *= 1.0 - outside;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	NORMAL_MAP = texture(detail_normal, p * 0.6).rgb;
	NORMAL_MAP_DEPTH = mix(0.5, 1.2, dirt_mask);
	EMISSION = emission;
}
