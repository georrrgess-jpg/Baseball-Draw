shader_type spatial;
// Instanced crowd figures: per-instance colour and phase, bobbing and cheering.

uniform float excitement = 0.2;
uniform float time_offset = 0.0;

varying vec3 v_color;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float energy = INSTANCE_CUSTOM.g;
	float t = TIME + time_offset;
	float bob = sin(t * (2.0 + energy * 3.0) + phase) * 0.04;
	float cheer = max(0.0, sin(t * 7.0 + phase)) * excitement * (0.6 + energy) * 0.35;
	float upper = smoothstep(0.55, 1.1, VERTEX.y);
	VERTEX.y += bob + cheer;
	VERTEX.x += sin(t * 1.3 + phase) * 0.03 * upper;
	// Raised arms: the arm vertices (flagged by UV.x > 0.5) lift when excited.
	VERTEX.y += step(0.5, UV.x) * excitement * (0.25 + 0.25 * sin(t * 9.0 + phase)) * energy;
	v_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.85;
}
