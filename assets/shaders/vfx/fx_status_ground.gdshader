shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Status ring under a runner (2x2 plane, scale = radius). Layers, each 0..1:
//   st.x rooted   - glowing chain-link shackle with lock studs
//   st.y slowed   - slow-turning dashed ring in slow_col
//   st.z chilled  - frosty crystal ring
//   st.w magnet   - rings collapsing inward
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D frost_tex : filter_linear_mipmap, repeat_disable;

instance uniform vec4 st = vec4(0.0);
instance uniform vec4 slow_col : source_color = vec4(0.55, 0.45, 1.0, 1.0);

varying vec2 v_q;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	v_q = (wp - o).xz / s;
}

void fragment() {
	vec2 q = v_q;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float t = TIME;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (st.w > 0.01) {
		float rings = pow(0.5 + 0.5 * sin(r * 18.0 + t * 12.0), 6.0) * (1.0 - smoothstep(0.85, 1.0, r));
		float m = rings * st.w;
		col += vec3(1.0, 0.3, 0.25) * 2.0 * m;
		a += m * 0.8;
	}
	if (st.z > 0.01) {
		vec2 uv = (rot2(t * 0.2) * q) * 0.5 + 0.5;
		float f = texture(frost_tex, uv).a;
		float band = smoothstep(0.35, 0.6, r) * (1.0 - smoothstep(0.9, 1.0, r));
		float c = (f * 0.8 + 0.2) * band * st.z;
		col += vec3(0.75, 0.95, 1.0) * 1.6 * c;
		a += c * 0.75;
	}
	if (st.y > 0.01) {
		float dash = step(0.45, fract((ang + t * 0.8) / 6.2831853 * 10.0));
		float ring = exp(-sq((r - 0.86) / 0.045)) * dash;
		float inner = exp(-sq((r - 0.7) / 0.02)) * 0.5;
		float c = (ring + inner) * st.y;
		col += slow_col.rgb * 1.8 * c;
		a += c * 0.85;
	}
	if (st.x > 0.01) {
		float links = 14.0;
		float s = (ang + 3.14159265) / 6.2831853 * links;
		float u = (fract(s) - 0.5) * 2.0;
		float v = (r - 0.66) / 0.13;
		float odd = mod(floor(s), 2.0);
		float ell = abs(sqrt(u * u / 0.81 + v * v) - 0.72);
		float link_o = 1.0 - smoothstep(0.12, 0.24, ell);
		float link_b = (1.0 - smoothstep(0.12, 0.2, abs(v))) * (1.0 - smoothstep(0.6, 0.85, abs(u)));
		float link = mix(link_o, link_b, odd);
		float glow = exp(-sq((r - 0.66) / 0.2)) * 0.35;
		float studs = 0.0;
		for (int i = 0; i < 4; i++) {
			float sa = float(i) * 1.5707963 + 0.785;
			vec2 sp = vec2(cos(sa), sin(sa)) * 0.95;
			studs += 1.0 - smoothstep(0.07, 0.1, length(q - sp));
		}
		float c = clamp(link + glow + studs, 0.0, 1.0) * st.x;
		col += vec3(0.45, 0.8, 1.0) * (1.4 + link * 1.4) * c;
		a += c;
	}
	a = clamp(a, 0.0, 1.0);
	ALBEDO = a > 0.001 ? col / max(a, 0.001) : vec3(0.0);
	ALPHA = a;
}
