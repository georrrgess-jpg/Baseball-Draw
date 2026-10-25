shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Status icons floating over a unit (camera-facing quad, 2:1). Layers, each 0..1:
//   st.x stunned  - three stars orbiting
//   st.y confused - bobbing question mark + spiral
//   st.z marked   - turning target reticle
//   st.w armor broken - cracked shield
// Icons come from the 4x4 icons atlas.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D icons : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec4 st = vec4(0.0);

void vertex() {
	billboard_vertex(VERTEX, MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, 0.0);
}

float icon(vec2 p, vec2 center, float size, float cell, float ang) {
	vec2 d = rot2(ang) * ((p - center) / size) + 0.5;
	if (d.x < 0.0 || d.y < 0.0 || d.x > 1.0 || d.y > 1.0) {
		return 0.0;
	}
	vec2 c = vec2(mod(cell, 4.0), floor(cell / 4.0));
	return texture(icons, (d + c) / 4.0).a;
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 1.0);   // x -1..1, y -0.5..0.5 (y down)
	float t = TIME;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (st.z > 0.01) {
		float pulse = 1.0 + 0.12 * sin(t * 6.0);
		float m = icon(p, vec2(0.0, 0.02), 0.62 * pulse, 2.0, t * 1.2) * st.z;
		col += vec3(1.0, 0.35, 0.9) * 2.2 * m;
		a = max(a, m * 0.95);
	}
	if (st.w > 0.01) {
		float m = icon(p, vec2(0.62, 0.05), 0.34, 15.0, 0.0) * st.w;
		col += vec3(0.8, 0.5, 1.0) * 2.0 * m;
		a = max(a, m);
	}
	if (st.y > 0.01) {
		float bob = sin(t * 4.0) * 0.06;
		float m = icon(p, vec2(0.0, -0.05 + bob), 0.5, 1.0, sin(t * 3.0) * 0.25) * st.y;
		float sp = icon(p, vec2(0.0, 0.08), 0.75, 11.0, -t * 4.0) * st.y * 0.5;
		col += vec3(0.85, 0.65, 1.0) * 2.2 * m + vec3(0.6, 0.4, 1.0) * 1.5 * sp;
		a = max(a, max(m, sp * 0.7));
	}
	if (st.x > 0.01) {
		for (int i = 0; i < 3; i++) {
			float ph = t * 4.0 + float(i) * 2.0943951;
			vec2 c = vec2(cos(ph) * 0.62, sin(ph) * 0.16 + 0.05);
			float depth = 0.6 + 0.4 * sin(ph);
			float m = icon(p, c, 0.26 * (0.75 + 0.25 * depth), 0.0, t * 3.0) * st.x;
			col += vec3(1.0, 0.88, 0.3) * (1.4 + depth) * m;
			a = max(a, m * (0.55 + 0.45 * depth));
		}
	}
	a = clamp(a, 0.0, 1.0);
	ALBEDO = a > 0.001 ? col / max(a, 0.001) : vec3(0.0);
	ALPHA = a;
}
