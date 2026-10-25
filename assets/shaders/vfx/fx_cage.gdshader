shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"
// Binding cage on an open cylinder: glowing bars rise from the ground, chain bands lock
// at the top and bottom. progress 0..1 rises the bars, `vis` fades the whole cage.

uniform sampler2D chain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float bars = 8.0;

instance uniform vec4 color : source_color = vec4(0.35, 0.7, 1.0, 1.0);
instance uniform float progress = 1.0;
instance uniform float vis = 1.0;

void fragment() {
	float h = 1.0 - UV.y;   // 0 at the ground
	float bx = abs(fract(UV.x * bars) - 0.5);
	float bar = 1.0 - smoothstep(0.035, 0.07, bx);
	float chain = texture(chain_tex, vec2(fract(UV.x * bars) * 4.0 - 1.5, h * 3.0)).a * (1.0 - smoothstep(0.1, 0.13, bx));
	float rise = step(h, progress);
	float tip = exp(-sq((h - progress) / 0.05)) * step(progress, 0.99);
	float band = exp(-sq((h - 0.06) / 0.03)) + exp(-sq((h - min(progress, 0.94)) / 0.025)) * smoothstep(0.6, 1.0, progress);
	float facing = 0.55 + 0.45 * abs(dot(NORMAL, VIEW));
	float v = (max(bar * 0.6, chain) * rise + tip * 2.0 + band * 1.4) * facing;
	ALBEDO = color.rgb * v * 2.0 * vis * (0.85 + 0.15 * sin(TIME * 9.0));
}
