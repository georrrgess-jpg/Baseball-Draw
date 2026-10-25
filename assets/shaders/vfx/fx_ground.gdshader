shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Procedural ground patterns on a 2x2 plane (node scale = radius). Pattern is chosen per
// material (`mode`); instance uniforms animate it.
//   mode 0 vortex   (curveball / shadow change)   anim.z = twist direction, anim.w = darkness
//   mode 1 magnet   (inward rings + field spokes)
//   mode 2 diamond  (diamond aura)
//   mode 3 radar    (field vision sweep)
//   mode 4 hex disc (base shield)
//   mode 5 rays     (rally cry / stretch sunburst)
//   anim.x = age 0..1, anim.y = visibility
// Pattern coordinates come from world space relative to the node, so parent rotation is ignored.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform int mode = 0;

instance uniform vec4 color : source_color = vec4(0.6, 0.4, 1.0, 1.0);
instance uniform vec4 color2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 anim = vec4(0.0, 1.0, 1.0, 0.0);

varying vec2 v_q;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	v_q = (wp - o).xz / s;
}

float hexdist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

void fragment() {
	vec2 q = v_q;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float inside = 1.0 - smoothstep(0.96, 1.0, r);
	float t = TIME;
	vec3 col = color.rgb;
	float a = 0.0;
	if (mode == 0) {
		float dir = anim.z;
		float sp = ang * 3.0 + log(max(r, 0.02)) * 4.5 * dir - t * 5.0 * dir;
		float arms = pow(0.5 + 0.5 * sin(sp), 3.0);
		float n = texture(noise, vec2(ang * 0.159 + t * 0.1, r * 0.6 - t * 0.3)).r;
		float core = 1.0 - smoothstep(0.0, 0.35, r);
		float rim = exp(-pow((r - 0.95) / 0.05, 2.0));
		float body = arms * (0.4 + 0.6 * n) * (1.0 - smoothstep(0.55, 1.0, r)) + core * 0.6;
		float dark = anim.w;
		col = mix(color.rgb * (1.5 + arms * 2.0), vec3(0.05, 0.0, 0.08), dark * (1.0 - arms * 0.7)) + color2.rgb * rim * 2.0;
		a = (body * mix(0.75, 1.0, dark) + dark * 0.55 * inside + rim) * inside;
	} else if (mode == 1) {
		float rings = pow(0.5 + 0.5 * sin(r * 22.0 + t * 9.0), 5.0);
		float spokes = pow(0.5 + 0.5 * cos(ang * 10.0 + sin(r * 6.0 - t * 2.0) * 0.6), 18.0) * smoothstep(0.15, 0.4, r);
		float core = exp(-r * r * 30.0);
		float rim = exp(-pow((r - 0.96) / 0.03, 2.0));
		col = mix(color.rgb, color2.rgb, spokes) * (1.4 + rings * 1.6 + core * 3.0);
		a = (rings * 0.45 + spokes * 0.55 + core + rim * 0.9 + 0.08) * inside;
	} else if (mode == 2) {
		vec2 p = rot2(t * 0.25) * q;
		float dmd = abs(p.x) + abs(p.y) * 1.25;
		float outline = exp(-pow((dmd - 0.92) / 0.035, 2.0));
		float inner = exp(-pow((dmd - 0.62) / 0.02, 2.0)) * 0.6;
		float facets = step(dmd, 0.92) * (0.18 + 0.12 * step(0.0, p.x * p.y));
		float shine = pow(max(0.0, sin(p.x * 2.5 + p.y * 1.5 - t * 2.2)), 30.0) * step(dmd, 0.92);
		float wash = (1.0 - smoothstep(0.0, 1.0, r)) * 0.15;
		col = color.rgb * (1.3 + outline * 2.4 + shine * 3.0) + color2.rgb * inner;
		a = clamp(outline + inner + facets + shine + wash, 0.0, 1.0) * inside;
	} else if (mode == 3) {
		float sweep_ang = mod(ang - t * 2.6, 6.2831853);
		float sweep = pow(1.0 - sweep_ang / 6.2831853, 8.0);
		float circles = exp(-pow((fract(r * 4.0) - 0.5) / 0.04, 2.0)) * 0.35;
		float cross_l = (exp(-pow(q.x / 0.008, 2.0)) + exp(-pow(q.y / 0.008, 2.0))) * 0.4;
		float rim = exp(-pow((r - 0.97) / 0.025, 2.0));
		col = color.rgb * (1.3 + sweep * 2.5 + rim);
		a = (sweep * 0.7 + circles + cross_l + rim) * inside;
	} else if (mode == 4) {
		vec2 p = q * 5.0;
		vec2 h = vec2(1.0, 1.7320508);
		vec2 a1 = mod(p, h) - h * 0.5;
		vec2 b1 = mod(p - h * 0.5, h) - h * 0.5;
		vec2 g = dot(a1, a1) < dot(b1, b1) ? a1 : b1;
		float edge = smoothstep(0.38, 0.46, hexdist(g));
		float wave = pow(0.5 + 0.5 * sin(r * 12.0 - t * 4.0), 4.0);
		float rim = exp(-pow((r - 0.96) / 0.03, 2.0));
		col = color.rgb * (1.3 + edge * 1.5 + wave * 1.2);
		a = (edge * (0.35 + wave * 0.5) + rim + 0.06) * inside * (1.0 - smoothstep(0.75, 1.0, r) * 0.5);
	} else {
		float rays = pow(0.5 + 0.5 * sin(ang * 12.0 + t * 1.5), 6.0);
		float n = texture(noise, vec2(ang * 0.5, r * 0.3 - t * 0.5)).r;
		float core = exp(-r * r * 6.0);
		col = mix(color.rgb, color2.rgb, rays) * (1.3 + rays * 1.5 + core * 1.5);
		a = (rays * (1.0 - r) * (0.5 + 0.5 * n) + core * 0.5) * inside;
	}
	ALBEDO = col;
	ALPHA = clamp(a * anim.y * color.a, 0.0, 1.0);
}
