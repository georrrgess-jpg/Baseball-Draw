shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Heat shimmer: refracts the screen behind a camera-facing (around Y) quad.
// Node scale: x = width, y = height.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.012;

instance uniform float progress = 0.0;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - o;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(to_cam + vec3(0.0001, 0.0, 0.0))));
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = o + right * VERTEX.x * w + vec3(0.0, (VERTEX.y + 0.5) * h, 0.0);
}

void fragment() {
	float amp = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(0.6, 1.0, progress));
	float mask = (1.0 - smoothstep(0.3, 0.5, abs(UV.x - 0.5))) * smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.75, UV.y);
	vec2 n = texture(noise, vec2(UV.x * 2.0, UV.y * 1.5 + TIME * 1.2)).rg - 0.5;
	vec2 off = n * strength * mask * amp;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = mask * amp;
}
