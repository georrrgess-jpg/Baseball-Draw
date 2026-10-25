shader_type particles;
// Shared process shader for every pooled VFX particle system. Particles are only spawned
// from script with emit_particle(); CUSTOM carries per-particle data:
//   x = billboard angle / seed, y = age (0..1), z = size multiplier, w = lifetime multiplier.

uniform vec3 gravity = vec3(0.0, -9.8, 0.0);
uniform float damping = 1.0;          // exponential velocity damping per second
uniform float base_scale = 0.2;
uniform int size_mode = 0;            // 0 shrink, 1 pop, 2 grow, 3 flame, 4 hold, 5 flash, 6 twinkle
uniform float spin = 0.0;             // radians / second (sign randomised)
uniform float turbulence = 0.0;
uniform float floor_y = -100.0;       // bounce plane (debris)
uniform bool align_velocity = false;  // streaks: Y axis follows velocity
uniform float stretch = 0.0;          // extra streak length per unit of speed
uniform bool tumble = false;          // mesh particles: 3D rotation

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

mat3 axis_angle(vec3 a, float ang) {
	float c = cos(ang), s = sin(ang), t = 1.0 - c;
	return mat3(
		vec3(t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y),
		vec3(t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x),
		vec3(t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c));
}

float size_curve(float k, float rnd) {
	if (size_mode == 0) return 1.0 - k;
	if (size_mode == 1) return smoothstep(0.0, 0.12, k) * (1.0 - k * k);
	if (size_mode == 2) return 0.35 + 0.65 * sqrt(k);
	if (size_mode == 3) return sin(3.14159 * pow(k, 0.6)) * (1.0 - 0.35 * k);
	if (size_mode == 4) return 1.0 - smoothstep(0.75, 1.0, k);
	if (size_mode == 5) return 0.55 + 0.75 * sqrt(k);
	return (0.65 + 0.35 * sin(k * 38.0 + rnd * 6.28)) * (1.0 - k * k);
}

void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(hash(float(NUMBER)) * 6.2831, 0.0, 1.0, 1.0);
	} else {
		CUSTOM.y = 0.0;
		CUSTOM.x = hash(float(NUMBER) + CUSTOM.x) * 6.2831;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0);
	}
}

void process() {
	float life = LIFETIME * max(CUSTOM.w, 0.05);
	CUSTOM.y += DELTA / life;
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float k = clamp(CUSTOM.y, 0.0, 1.0);
	float rnd = hash(float(INDEX) * 1.37);
	VELOCITY += gravity * DELTA;
	if (turbulence > 0.0) {
		vec3 p = TRANSFORM[3].xyz * 0.9 + vec3(TIME * 1.3);
		VELOCITY += vec3(sin(p.y * 2.1 + rnd * 6.0), cos(p.z * 1.7 + rnd * 4.0) * 0.5, sin(p.x * 1.9 - rnd * 5.0)) * turbulence * DELTA;
	}
	VELOCITY *= max(0.0, 1.0 - damping * DELTA);
	if (TRANSFORM[3].y < floor_y && VELOCITY.y < 0.0) {
		TRANSFORM[3].y = floor_y;
		VELOCITY.y *= -0.32;
		VELOCITY.xz *= 0.55;
	}
	float s = base_scale * CUSTOM.z * max(size_curve(k, rnd), 0.0);
	CUSTOM.x += spin * DELTA * (rnd > 0.5 ? 1.0 : -1.0) * (0.5 + rnd);
	if (align_velocity) {
		float spd = length(VELOCITY);
		vec3 y = spd > 0.001 ? VELOCITY / spd : vec3(0.0, 1.0, 0.0);
		vec3 x = normalize(abs(y.y) < 0.95 ? cross(y, vec3(0.0, 1.0, 0.0)) : cross(y, vec3(1.0, 0.0, 0.0)));
		vec3 z = cross(x, y);
		TRANSFORM[0].xyz = x * s;
		TRANSFORM[1].xyz = y * s * (1.0 + stretch * spd);
		TRANSFORM[2].xyz = z * s;
	} else if (tumble) {
		vec3 ax = normalize(vec3(hash(float(INDEX)) - 0.5, hash(float(INDEX) + 3.1) - 0.5, hash(float(INDEX) + 7.7) - 0.5) + vec3(0.001));
		mat3 r = axis_angle(ax, CUSTOM.x);
		TRANSFORM[0].xyz = r[0] * s;
		TRANSFORM[1].xyz = r[1] * s;
		TRANSFORM[2].xyz = r[2] * s;
	} else {
		TRANSFORM[0].xyz = vec3(s, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, s, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, s);
	}
}
