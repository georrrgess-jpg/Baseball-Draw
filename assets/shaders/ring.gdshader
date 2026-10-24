shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Flat ground ring used for ranges, ability targets, auras and telegraphs.
// The quad spans [-1,1] in UV-space; the ring sits at the outer edge.

uniform vec4 color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float thickness = 0.04;
uniform float fill = 0.12;
uniform float dashes = 0.0;
uniform float pulse = 0.0;
uniform float progress = 1.0;   // 0..1 sweep (telegraph timers)
uniform float spin = 0.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float aa = fwidth(r) * 1.5;
	float ring = smoothstep(1.0 - thickness - aa, 1.0 - thickness, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r));
	float a = atan(q.y, q.x) + TIME * spin;
	if (dashes > 0.5) {
		ring *= step(0.45, fract(a / 6.2831853 * dashes));
	}
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float sweep = step(fract((atan(q.x, -q.y) / 6.2831853) + 1.0), progress);
	float p = 1.0 + pulse * 0.35 * sin(TIME * 6.0);
	float f = fill * inside * (0.6 + 0.4 * r * r) * mix(1.0, sweep * 1.6, step(progress, 0.999));
	float alpha = clamp(ring * p + f, 0.0, 1.0) * color.a;
	ALBEDO = color.rgb;
	EMISSION = color.rgb * (ring * 1.5 + f);
	ALPHA = alpha;
}
