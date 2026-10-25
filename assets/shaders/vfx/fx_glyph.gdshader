shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A big camera-facing icon from the 4x4 atlas (padlock, eye, gem, chevrons...) with a
// soft glow halo. anim.x = age 0..1 (pop in, hold, fade), anim.y = cell.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D icons : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec4 color : source_color = vec4(1.0);
instance uniform vec4 anim = vec4(0.0, 0.0, 0.0, 0.0);

void vertex() {
	billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, 0.0);
}

void fragment() {
	float k = anim.x;
	float pop = 1.0 + 0.6 * sq(1.0 - smoothstep(0.0, 0.18, k)) - 0.4 * (1.0 - smoothstep(0.0, 0.06, k));
	vec2 d = (UV - 0.5) * pop * 1.15 + 0.5;
	vec2 c = vec2(mod(anim.y, 4.0), floor(anim.y / 4.0));
	float m = 0.0;
	if (d.x >= 0.0 && d.y >= 0.0 && d.x <= 1.0 && d.y <= 1.0) {
		m = texture(icons, (d + c) / 4.0).a;
	}
	float halo = exp(-dot(UV - 0.5, UV - 0.5) * 12.0) * 0.45 * (1.0 - smoothstep(0.32, 0.5, length(UV - 0.5)));
	float life = smoothstep(0.0, 0.05, k) * (1.0 - smoothstep(0.7, 1.0, k));
	float flash = 1.0 + 2.5 * (1.0 - smoothstep(0.0, 0.2, k));
	vec3 col = mix(color.rgb * 1.6, vec3(1.0), m * 0.35) * flash;
	ALBEDO = col;
	ALPHA = clamp(m + halo * (1.0 - m), 0.0, 1.0) * life * color.a;
}
