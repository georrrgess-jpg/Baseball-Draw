shader_type sky;
// Stylised stadium sky: gradient, sun disk with glow, layered procedural clouds
// lit by the sun colour, and stars for night arenas.

uniform vec3 top_color : source_color = vec3(0.11, 0.17, 0.31);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.54, 0.24);
uniform vec3 ground_color : source_color = vec3(0.12, 0.09, 0.09);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.7, 0.4);
uniform float sun_size = 0.035;
uniform float sun_glow = 0.6;
uniform float cloud_amount = 0.55;
uniform float cloud_speed = 0.004;
uniform float stars = 0.0;
uniform float horizon_height = 0.0;
uniform float exposure = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y - horizon_height;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.45);
		col = mix(horizon_color, top_color, t);
	} else {
		col = mix(horizon_color * 0.5, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = dot(dir, sun_dir);
	float glow = pow(max(sd, 0.0), 8.0) * sun_glow + pow(max(sd, 0.0), 64.0) * sun_glow;
	col += sun_tint * glow * LIGHT0_ENERGY * 0.35;
	float disk = smoothstep(1.0 - sun_size * 0.02, 1.0 - sun_size * 0.015, sd);
	col = mix(col, sun_tint * 3.0, disk * step(0.0, h + 0.02));
	// Clouds on a dome above the horizon.
	if (h > 0.0 && cloud_amount > 0.0) {
		vec2 uv = dir.xz / (h + 0.18);
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float c = fbm(uv * 1.3);
		float c2 = fbm(uv * 3.1 + 7.0);
		float cover = smoothstep(1.0 - cloud_amount, 1.05 - cloud_amount * 0.4, c * 0.75 + c2 * 0.35);
		cover *= smoothstep(0.0, 0.18, h);
		float lit = pow(max(sd, 0.0), 3.0);
		vec3 cloud_col = mix(top_color * 1.3 + horizon_color * 0.25, sun_tint * 1.4, lit * 0.8 + (1.0 - h) * 0.25);
		col = mix(col, cloud_col, cover * 0.85);
	}
	if (stars > 0.0 && h > 0.0) {
		vec2 sp = dir.xz / (h + 0.3) * 60.0;
		float s = step(0.996, hash(floor(sp))) * (0.6 + 0.4 * sin(TIME * 2.0 + hash(floor(sp)) * 20.0));
		col += vec3(s) * stars * smoothstep(0.05, 0.4, h);
	}
	COLOR = col * exposure;
}
