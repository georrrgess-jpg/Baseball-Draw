shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Character overlay: hit flash, status rim colour (frozen, burning, marked, selected).

instance uniform vec4 rim_color : source_color = vec4(0.0);
instance uniform float flash = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec3 c = rim_color.rgb * fres * rim_color.a * 1.6 + vec3(1.0, 0.95, 0.85) * flash * (0.35 + fres);
	ALBEDO = c;
	ALPHA = 1.0;
}
