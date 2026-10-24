shader_type spatial;
// Procedural baseball field surface: mowed grass, infield dirt, chalk lines,
// warning track, worn runner routes with animated direction chevrons and
// an optional placement-zone overlay.

uniform vec3 grass_a : source_color = vec3(0.25, 0.54, 0.23);
uniform vec3 grass_b : source_color = vec3(0.30, 0.60, 0.27);
uniform vec3 dirt_color : source_color = vec3(0.69, 0.42, 0.24);
uniform vec3 track_color : source_color = vec3(0.45, 0.30, 0.20);
uniform vec3 chalk_color : source_color = vec3(0.96, 0.95, 0.92);
uniform vec3 route_color : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 zone_color : source_color = vec3(0.35, 0.75, 1.0);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec4 segs[48];
uniform float seg_start[48];
uniform int seg_count = 0;
uniform float zones_alpha = 0.0;
uniform float route_glow = 1.0;
uniform float wall_radius = 36.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - (a + ab * t));
}

float band(float x, float center, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(x - center));
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

	// Mowed grass: diagonal checkerboard stripes aligned with the base lines.
	float s1 = smoothstep(0.47, 0.53, fract(u / 5.0));
	float s2 = smoothstep(0.47, 0.53, fract(v / 5.0));
	float checker = abs(s1 - s2);
	vec3 grass = mix(grass_a, grass_b, checker);
	grass *= 0.86 + 0.28 * n;
	grass *= 0.94 + 0.12 * n2;
	vec3 col = grass;
	float rough = 0.82;

	// Infield dirt: the arc behind the bases minus the infield grass square,
	// plus the mound and the circle around home plate.
	float arc = (1.0 - smoothstep(20.6 - aa, 20.6 + aa, dh)) * (1.0 - smoothstep(46.0, 47.5, abs(ang)));
	float ig = smoothstep(1.7 - aa, 1.7 + aa, u) * (1.0 - smoothstep(11.7 - aa, 11.7 + aa, u))
			* smoothstep(1.7 - aa, 1.7 + aa, v) * (1.0 - smoothstep(11.7 - aa, 11.7 + aa, v));
	float mound = 1.0 - smoothstep(2.75 - aa, 2.75 + aa, length(p - vec2(0.0, 1.0)));
	float homec = 1.0 - smoothstep(4.1 - aa, 4.1 + aa, dh);
	float dirt_mask = max(arc * (1.0 - ig), max(mound, homec));
	vec3 dirt = dirt_color * (0.82 + 0.3 * n2) * (0.92 + 0.12 * n);

	// Warning track in front of the wall.
	float track = smoothstep(wall_radius - 3.4 - aa, wall_radius - 3.4 + aa, dh);
	col = mix(col, track_color * (0.85 + 0.25 * n2), track);

	// Worn runner routes and moving chevrons that show the direction of travel.
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
	col = mix(col, dirt, dirt_mask);
	rough = mix(rough, 0.96, max(dirt_mask, route_mask * 0.7));

	// Chalk: foul lines out to the wall, batter's boxes, and the edge of the home circle.
	float chalk = 0.0;
	float fl_w = 0.075;
	chalk = max(chalk, band(u, 0.0, fl_w, aa * 0.5) * step(0.0, v) * step(dh, wall_radius - 0.2));
	chalk = max(chalk, band(v, 0.0, fl_w, aa * 0.5) * step(0.0, u) * step(dh, wall_radius - 0.2));
	vec2 box_l = rel - vec2(-1.15, 0.0);
	vec2 box_r = rel - vec2(1.15, 0.0);
	float bl = max(band(abs(box_l.x), 0.55, 0.04, aa), 0.0) * step(abs(box_l.y), 1.0)
			+ band(abs(box_l.y), 1.0, 0.04, aa) * step(abs(box_l.x), 0.55);
	float br = band(abs(box_r.x), 0.55, 0.04, aa) * step(abs(box_r.y), 1.0)
			+ band(abs(box_r.y), 1.0, 0.04, aa) * step(abs(box_r.x), 0.55);
	chalk = max(chalk, clamp(bl + br, 0.0, 1.0));
	col = mix(col, chalk_color * (0.9 + 0.1 * n2), chalk * 0.92);

	// Placement-zone overlay (shown while positioning defenders).
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

	// Outside the walls: worn concrete concourse.
	float outside = max(smoothstep(wall_radius + 0.5, wall_radius + 1.5, dh),
		smoothstep(52.0, 54.0, abs(ang)) * smoothstep(6.0, 8.0, dh));
	outside = max(outside, smoothstep(13.5, 14.5, p.y));
	vec3 concrete = vec3(0.26, 0.26, 0.28) * (0.8 + 0.3 * n) * (0.9 + 0.15 * n2);
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
