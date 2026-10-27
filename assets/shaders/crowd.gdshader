shader_type spatial;
// Instanced low-poly fans (see src/stadium/crowd.gd for the mesh layout).
// Per vertex: UV.x = part (0 torso, 1 head, 2 left arm, 3 right arm, 4 legs, 5 cap, 6 hair, 7 foam finger),
//             UV.y = colour class (0 shirt, 1 skin, 2 pants, 3 cap, 4 hair, 5 finger), UV2.x = shade,
//             CUSTOM0.xyz = the vertex position in the standing pose.
// Per instance: the instance colour (arrives in COLOR) = shirt colour,
//             INSTANCE_CUSTOM = (phase, energy, variant / 8, seat angle around the stadium / TAU + 0.5).
// Global reactions (uniforms) are blended per fan by its energy, so the crowd never moves in lockstep.

uniform float excitement = 0.2;   // 0 calm .. 1 roaring (clapping, bouncing)
uniform float cheer = 0.0;        // arms up, jumping
uniform float groan = 0.0;        // hands on heads
uniform float stand = 0.0;        // standing ovation
uniform float wave_pos = -10.0;   // angle (radians) of the stadium wave's crest
uniform float wave_amt = 0.0;
uniform float time_offset = 0.0;
uniform vec3 cap_a = vec3(0.11, 0.18, 0.29);   // sRGB (linearised below)
uniform vec3 cap_b = vec3(0.84, 0.15, 0.18);
uniform vec3 finger_color = vec3(1.0, 0.78, 0.15);
uniform float uniform_mode = 0.0; // 1 = bench players: pants/cap from the uniforms below
uniform vec3 pants_uniform = vec3(0.93, 0.92, 0.9);

varying vec3 v_color;

const vec3 SKIN[6] = vec3[](vec3(0.98, 0.80, 0.66), vec3(0.89, 0.67, 0.50), vec3(0.76, 0.55, 0.38),
	vec3(0.55, 0.37, 0.24), vec3(0.40, 0.26, 0.17), vec3(0.95, 0.74, 0.60));
const vec3 HAIR[5] = vec3[](vec3(0.08, 0.06, 0.05), vec3(0.28, 0.17, 0.09), vec3(0.78, 0.62, 0.32),
	vec3(0.55, 0.22, 0.10), vec3(0.62, 0.62, 0.62));
const vec3 PANTS[4] = vec3[](vec3(0.18, 0.24, 0.38), vec3(0.62, 0.55, 0.42), vec3(0.12, 0.12, 0.14), vec3(0.42, 0.44, 0.47));

float hash(float n) {
	return fract(sin(n * 91.345 + 7.13) * 43758.5453);
}

mat3 rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_z(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float energy = INSTANCE_CUSTOM.g;
	int variant = int(INSTANCE_CUSTOM.b * 8.0 + 0.5);
	float seat_ang = (INSTANCE_CUSTOM.a - 0.5) * 6.2831;
	int part = int(UV.x + 0.5);
	float t = TIME + time_offset;

	// Variant parts: 0-3 hair, 4-5 cap, 6 cap + foam finger, 7 hair + foam finger.
	bool has_cap = variant >= 4 && variant <= 6;
	bool has_finger = variant >= 6;
	bool hide = (part == 5 && !has_cap) || (part == 6 && has_cap) || (part == 7 && !has_finger);

	// How strongly this fan joins each reaction.
	// A small reaction moves only the keenest fans (fully); a big one moves everybody.
	float gloom = hash(phase + 5.1);
	float d = mod(seat_ang - wave_pos + 3.14159, 6.2831) - 3.14159;
	float wave_w = wave_amt * exp(-d * d * 9.0);
	float cheer_w = smoothstep(1.0 - cheer * 1.1, 1.12 - cheer * 1.1, energy) * step(0.01, cheer);
	float groan_w = smoothstep(1.0 - groan * 1.1, 1.12 - groan * 1.1, gloom) * step(0.01, groan) * (1.0 - cheer_w);
	float clap_w = smoothstep(0.35, 0.85, excitement) * step(0.35, energy) * (1.0 - cheer_w) * (1.0 - groan_w);
	float stand_w = max(max(stand * step(0.15, energy), wave_w), cheer_w * step(0.6, energy) * 0.9);
	stand_w = smoothstep(0.0, 1.0, stand_w);

	vec3 p = mix(VERTEX, CUSTOM0.xyz, stand_w);
	vec3 n = NORMAL;

	// Arms rotate about the shoulder (which follows the standing pose).
	if (part == 2 || part == 3 || part == 7) {
		float side_sign = part == 2 ? -1.0 : 1.0;
		vec3 pivot = vec3(0.215 * side_sign, 0.86, 0.0) + vec3(0.0, 0.42, 0.08) * stand_w;
		float fwd = 0.5 + 0.08 * sin(t * 1.1 + phase);
		float side = 0.1;
		// Clapping: arms forward, hands meeting in front of the chest.
		float clap = sin(t * 13.0 + phase);
		fwd = mix(fwd, 1.2, clap_w);
		side = mix(side, -0.3 - 0.12 * clap, clap_w);
		// Cheering: arms up in a V, pumping; foam fingers wave harder.
		float pump = sin(t * (8.0 + energy * 3.0) + phase + side_sign);
		float up = max(cheer_w, wave_w);
		float finger_boost = (has_finger && side_sign > 0.0) ? 1.0 : 0.0;
		fwd = mix(fwd, 0.25 + 0.15 * pump, up);
		side = mix(side, 2.55 + 0.25 * pump, up);
		// A few keen fans with foam fingers wave them even when calm.
		float idle_wave = finger_boost * smoothstep(0.55, 0.9, energy) * (1.0 - up) * (0.5 + 0.5 * excitement);
		fwd = mix(fwd, 0.4, idle_wave);
		side = mix(side, 2.3 + 0.35 * sin(t * 4.0 + phase), idle_wave);
		// Groan: hands up to the head.
		fwd = mix(fwd, 2.75, groan_w);
		side = mix(side, -0.32, groan_w);
		mat3 r = rot_x(-fwd) * rot_z(side * side_sign);
		p = pivot + r * (p - pivot);
		n = r * n;
	}

	// Whole-body motion: idle sway, bouncing with excitement, jumping when cheering, slumping on a groan.
	float upper = smoothstep(0.4, 1.0, VERTEX.y);
	float sway = sin(t * (1.3 + energy) + phase) * (0.025 + 0.03 * excitement);
	p.x += sway * upper;
	float bounce = abs(sin(t * 6.5 + phase)) * 0.04 * clap_w;
	float jump = max(0.0, sin(t * 7.0 + phase)) * 0.16 * cheer_w * step(0.5, energy);
	p.y += bounce + jump;
	p.z -= groan_w * 0.06 * upper;
	if (part == 1 || part == 5 || part == 6) {
		p.y -= groan_w * 0.03;
		p.x += sin(t * 0.7 + phase * 1.7) * 0.02;
	}
	if (hide) {
		p = vec3(0.0);
	}
	VERTEX = p;
	NORMAL = n;

	// Colour by class.
	int cls = int(UV.y + 0.5);
	float h1 = hash(phase);
	float h2 = hash(phase + 3.7);
	vec3 c = COLOR.rgb;
	if (cls == 1) {
		c = SKIN[int(h1 * 5.99)];
	} else if (cls == 2) {
		c = uniform_mode > 0.5 ? pants_uniform : PANTS[int(h2 * 3.99)];
	} else if (cls == 3) {
		c = uniform_mode > 0.5 ? cap_a : (h2 < 0.5 ? cap_a : (h2 < 0.8 ? cap_b : COLOR.rgb * 0.7));
	} else if (cls == 4) {
		c = HAIR[int(hash(phase + 9.1) * 4.99)];
	} else if (cls == 5) {
		c = finger_color;
	}
	v_color = pow(c, vec3(2.2)) * UV2.x;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	// A soft rim keeps silhouettes readable against the dark stands.
	RIM = 0.35;
	RIM_TINT = 0.4;
}
