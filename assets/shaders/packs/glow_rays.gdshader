shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Additive radial glow with optional rotating light rays (rarity auras, pack burst, god rays).

uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform float rays = 0.0;
uniform float ray_count = 14.0;
uniform float spin = 0.15;
uniform float core = 3.5;
uniform float ring_radius = -1.0;  // >= 0: draw a soft expanding ring instead of a centre glow

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float glow = ring_radius < 0.0 ? exp(-r * r * core) : exp(-pow((r - ring_radius) / 0.07, 2.0)) * (1.0 - ring_radius);
	float fade = 1.0 - smoothstep(0.15, 1.0, r);
	float r1 = pow(max(0.0, sin(a * ray_count + TIME * spin * 6.0)), 6.0);
	float r2 = pow(max(0.0, sin(a * ray_count * 0.5 - TIME * spin * 4.0 + 1.3)), 10.0);
	float edge = 1.0 - smoothstep(0.55, 0.98, max(abs(p.x), abs(p.y)));
	ALBEDO = color.rgb * (glow + rays * (r1 * 0.75 + r2 * 0.55) * fade) * intensity * edge;
}
