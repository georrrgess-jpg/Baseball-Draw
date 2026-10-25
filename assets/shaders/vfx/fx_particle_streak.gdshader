shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Velocity-aligned additive streak (sparks, speed lines). The process shader stores the
// velocity direction, scaled by the streak length, in the particle's Y axis.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float energy = 2.0;
uniform float fade_pow = 1.0;
uniform float aspect = 5.0;   // length / width

varying float v_age;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	axis /= max(len, 0.0001);
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - pos);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 world = pos + side * VERTEX.x * w + axis * (VERTEX.y - 0.4) * len * aspect;
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = world;
}

void fragment() {
	float a = texture(tex, UV).a * COLOR.a * pow(max(1.0 - v_age, 0.0), fade_pow);
	ALBEDO = COLOR.rgb * energy * a;
}
