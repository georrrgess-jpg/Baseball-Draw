shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Additive camera-facing particle (glows, embers, magic, stars, flashes).
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float energy = 1.5;
uniform float fade_in = 0.05;
uniform float fade_pow = 1.0;
uniform float soft = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying float v_age;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, INSTANCE_CUSTOM.x);
}

void fragment() {
	float a = texture(tex, UV).a * COLOR.a * age_fade(v_age, fade_in, fade_pow);
	if (soft > 0.0) {
		a *= soft_factor(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft);
	}
	ALBEDO = COLOR.rgb * energy * a;
}
