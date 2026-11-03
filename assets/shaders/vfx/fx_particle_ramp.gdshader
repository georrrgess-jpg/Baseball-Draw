shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Additive particle whose colour follows a ramp over its life (card effects, Update 8).
// COLOR.a picks the ramp row (row centre in 0..1), COLOR.rgb tints it. The ramp runs from
// a white-hot core at birth through the saturated body colour to a deep edge colour, and
// the brightness starts in HDR so the core blooms through the tonemapper.
// streak = true draws a velocity-aligned streak (the process shader stores the velocity
// direction, scaled by the streak length, in the particle's Y axis).
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float energy = 2.0;        // body brightness
uniform float hot = 2.5;           // extra brightness at birth (decays over hot_time)
uniform float hot_time = 0.25;
uniform float fade_in = 0.02;
uniform float fade_pow = 1.0;
uniform float core = 0.6;          // how much the sprite's centre whitens
uniform bool streak = false;
uniform float aspect = 6.0;

varying float v_age;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	if (streak) {
		vec3 axis = MODEL_MATRIX[1].xyz;
		float len = length(axis);
		axis /= max(len, 0.0001);
		vec3 pos = MODEL_MATRIX[3].xyz;
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - pos);
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
		float w = length(MODEL_MATRIX[0].xyz);
		VERTEX = pos + side * VERTEX.x * w + axis * (VERTEX.y - 0.4) * len * aspect;
		MODELVIEW_MATRIX = VIEW_MATRIX;
	} else {
		billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, INSTANCE_CUSTOM.x);
	}
}

void fragment() {
	float k = clamp(v_age, 0.0, 1.0);
	vec3 c = texture(ramp, vec2(0.01 + k * 0.98, COLOR.a)).rgb * COLOR.rgb;
	float t = texture(tex, UV).a;
	// The centre of the sprite runs hotter (whiter) than its edge while the particle is young.
	float young = 1.0 - smoothstep(0.0, 0.45, k);
	c = mix(c, vec3(1.0), smoothstep(0.55, 1.0, t) * core * young);
	float bright = energy * (1.0 + hot * (1.0 - smoothstep(0.0, max(hot_time, 0.001), k)));
	float a = t * age_fade(k, fade_in, fade_pow);
	ALBEDO = c * bright * a;
}
