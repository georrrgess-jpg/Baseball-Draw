shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// Billboarded health bar drawn from a quad. Per-instance values avoid material duplication.

instance uniform float fill = 1.0;
instance uniform float shield = 0.0;
instance uniform vec4 bar_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);
instance uniform float visible_alpha = 1.0;
uniform float aspect = 7.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	float border = 0.12;
	vec2 px = vec2(border / aspect, border);
	bool inner = uv.x > px.x && uv.x < 1.0 - px.x && uv.y > px.y && uv.y < 1.0 - px.y;
	vec3 c = vec3(0.02, 0.02, 0.03);
	float a = 0.85;
	if (inner) {
		float x = (uv.x - px.x) / (1.0 - 2.0 * px.x);
		c = vec3(0.12, 0.05, 0.05);
		if (x < fill) {
			c = bar_color.rgb * (0.85 + 0.3 * (1.0 - uv.y));
		}
		if (shield > 0.0 && x < shield) {
			c = mix(c, vec3(0.7, 0.75, 0.8), 0.55);
		}
		float tick = step(0.94, fract(x * 10.0));
		c *= 1.0 - tick * 0.25;
	}
	ALBEDO = c;
	ALPHA = a * visible_alpha;
}
