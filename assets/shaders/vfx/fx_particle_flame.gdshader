shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Additive flame tongue: the flame texture is warped by scrolling noise and shifts from
// white-hot to the particle colour to dark red over its life.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float energy = 2.2;
uniform float soft = 0.4;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	// Flames stay mostly upright.
	billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, sin(INSTANCE_CUSTOM.x) * 0.22);
}

void fragment() {
	vec2 n = texture(noise, vec2(UV.x * 0.6 + v_seed, UV.y * 0.5 + TIME * 1.6 + v_seed * 3.0)).rg - 0.5;
	vec2 uv = UV + n * vec2(0.35, 0.22) * (1.0 - UV.y * 0.6);
	vec4 t = texture(tex, uv);
	float a = t.a * COLOR.a * age_fade(v_age, 0.06, 1.2);
	float hot = t.r * (1.0 - v_age);
	vec3 col = mix(COLOR.rgb, vec3(1.0, 0.95, 0.75), hot * 0.55);
	col = mix(col, vec3(0.6, 0.08, 0.02), smoothstep(0.45, 1.0, v_age));
	if (soft > 0.0) {
		a *= soft_factor(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft);
	}
	ALBEDO = col * energy * a;
}
