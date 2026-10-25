shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A sheet of fire on a 1x1 quad that turns around Y to face the camera. Node scale:
// x = width, y = height. Two scrolling noise layers carve licking tongues out of a
// teardrop body; colour runs from deep red through orange to a yellow-white core.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float energy = 1.7;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

instance uniform float progress = 0.0;   // life 0..1
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.08, 1.0);

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - o;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(to_cam + vec3(0.0001, 0.0, 0.0))));
	vec3 world = o + right * VERTEX.x * w + vec3(0.0, (VERTEX.y + 0.5) * h, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = world;
}

void fragment() {
	float h = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float amp = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(0.5, 1.0, progress) * 0.85);
	float n1 = texture(noise, vec2(UV.x * 1.3 + seed, UV.y * 0.7 + TIME * 1.8)).r;
	float n2 = texture(noise, vec2(UV.x * 2.7 - seed * 1.7, UV.y * 1.5 + TIME * 3.2)).g;
	float n = (n1 * 0.6 + n2 * 0.4 - 0.5) * 2.0;
	float hh = h / max(amp, 0.05);
	float width = max(1.0 - hh * 0.85, 0.0);
	float sway = (n1 - 0.5) * 0.7 * hh;
	float shape = clamp(1.0 - abs(x + sway) / max(width, 0.001), 0.0, 1.0);
	float flame = shape * 1.35 * (1.0 - hh * 0.9) + n * 0.55 * (0.3 + hh);
	flame *= smoothstep(0.0, 0.05, h);
	float body = smoothstep(0.12, 0.45, flame);
	float core = smoothstep(0.55, 1.05, flame);
	vec3 col = mix(vec3(0.7, 0.08, 0.01), tint.rgb, smoothstep(0.15, 0.55, flame));
	col = mix(col, vec3(1.0, 0.8, 0.25), core);
	col += vec3(1.0, 0.95, 0.75) * pow(core, 3.0) * 0.8;
	float a = body * tint.a * (1.0 - smoothstep(0.85, 1.0, progress));
	a *= soft_factor(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, 0.5);
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
