shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Alpha-blended soft particle (smoke, dust, mist). The texture is a 2x2 atlas of puffs
// whose RGB holds fake self-shading.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas = vec2(2.0, 2.0);
uniform float fade_in = 0.15;
uniform float fade_pow = 1.3;
uniform float soft = 0.6;
uniform float shade = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying float v_age;
varying float v_frame;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	v_frame = floor(fract(float(INSTANCE_ID) * 0.371) * atlas.x * atlas.y);
	billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, INSTANCE_CUSTOM.x);
}

void fragment() {
	vec2 cell = vec2(mod(v_frame, atlas.x), floor(v_frame / atlas.x));
	vec4 t = texture(tex, (UV + cell) / atlas);
	float a = t.a * COLOR.a * age_fade(v_age, fade_in, fade_pow);
	if (soft > 0.0) {
		a *= soft_factor(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft);
	}
	ALBEDO = COLOR.rgb * mix(1.0, t.r * 1.25, shade);
	ALPHA = clamp(a, 0.0, 1.0);
}
