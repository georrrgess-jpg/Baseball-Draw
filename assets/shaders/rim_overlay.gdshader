shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Character overlay: hit flash, status rim colour (frozen, burning, marked, selected).

instance uniform vec4 rim_color : source_color = vec4(0.0);
instance uniform float flash = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	// Hit flash: white-hot at the moment of impact, cooling to a warm glow as it fades.
	vec3 hot = mix(vec3(1.0, 0.5, 0.22), vec3(1.0, 0.97, 0.9), clamp(flash * 1.3, 0.0, 1.0));
	vec3 c = rim_color.rgb * fres * rim_color.a * 1.6 + hot * flash * (0.7 + 0.9 * fres);
	ALBEDO = c;
	ALPHA = 1.0;
}
