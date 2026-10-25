// Shared helpers for the VFX shaders.

float sq(float x) {
	return x * x;
}

// Camera-facing billboard for a particle; INSTANCE_CUSTOM.x is the screen-space angle.
void billboard_vertex(inout vec3 vtx, inout mat4 modelview, mat4 model, mat4 view, mat4 inv_view, float angle) {
	vec2 sc = vec2(length(model[0].xyz), length(model[1].xyz));
	float c = cos(angle);
	float s = sin(angle);
	vec2 v = vtx.xy * sc;
	v = vec2(c * v.x - s * v.y, s * v.x + c * v.y);
	modelview = view * mat4(inv_view[0], inv_view[1], inv_view[2], model[3]);
	vtx = vec3(v, 0.0);
}

float age_fade(float age, float fade_in, float power) {
	return smoothstep(0.0, max(fade_in, 0.0001), age) * pow(max(1.0 - age, 0.0), power);
}

// Soft-particle factor: fades geometry that intersects the scene depth.
float soft_factor(sampler2D depth_tex, vec2 screen_uv, mat4 inv_proj, float frag_z, float dist) {
	float d = texture(depth_tex, screen_uv).r;
	vec4 vp = inv_proj * vec4(screen_uv * 2.0 - 1.0, d, 1.0);
	float scene_z = -vp.z / vp.w;
	return clamp((scene_z + frag_z) / dist, 0.0, 1.0);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}
