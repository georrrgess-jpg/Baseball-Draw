shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Vertical light pillar on an open cylinder: bright where it faces the camera, streaks
// scrolling upward, fading to the top. progress = life 0..1.

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

instance uniform vec4 color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
instance uniform float progress = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float body = pow(facing, 1.6);
	float h = UV.y;   // 0 top .. 1 bottom
	float n = texture(noise, vec2(UV.x * 3.0, h * 0.6 + TIME * 1.4)).r;
	float streak = 0.55 + 0.9 * pow(n, 2.0);
	float vfade = smoothstep(0.0, 0.85, h) * (0.65 + 0.35 * smoothstep(0.85, 1.0, h));
	float life = smoothstep(0.0, 0.12, progress) * pow(1.0 - progress, 1.5);
	ALBEDO = color.rgb * body * streak * vfade * life * 2.2 * color.a;
}
