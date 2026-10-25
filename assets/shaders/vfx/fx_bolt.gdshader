shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Camera-facing ribbons (lightning, beams, ball trails). UV.x runs across the ribbon:
// a white-hot core with a coloured glow around it. Vertex colour = tint and alpha.

uniform float core_width = 0.16;
uniform float energy = 1.0;

instance uniform float intensity = 1.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float core = exp(-x * x / (core_width * core_width));
	float glow = exp(-x * x * 3.0);
	float halo = exp(-x * x * 9.0);
	vec3 c = mix(COLOR.rgb, vec3(1.0), 0.7) * core * 2.6 + COLOR.rgb * (glow * 0.9 + halo * 0.9);
	ALBEDO = c * COLOR.a * intensity * energy;
}
