shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Textured ground decals on a 2x2 plane (node scale = radius). The material picks the
// texture and mode; instance uniforms animate each decal.
//   mode 0 scorch  (tex.a blot, tex.r ember cracks)   anim.x = age (heat cools)
//   mode 1 crater  (tex.a cracks, tex.r bowl)          anim.x = age
//   mode 2 frost   (tex.a crystals, tex.r spread order) anim.w = spread 0..1
//   mode 3 runes   (tex.a glyph ring)                  anim.z = rotation, anim.w = flare
//   mode 4 clock   (tex.a face)                        anim.z = hand angle, anim.w = flare
//   mode 5 web / net                                   anim.w = draw-in 0..1
//   anim.y = overall visibility
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform int mode = 0;

instance uniform vec4 color : source_color = vec4(0.1, 0.07, 0.05, 0.8);
instance uniform vec4 color2 : source_color = vec4(1.0, 0.45, 0.1, 1.0);
instance uniform vec4 anim = vec4(0.0, 1.0, 0.0, 1.0);

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	vec3 col = color.rgb;
	float a = 0.0;
	if (mode == 0 || mode == 1) {
		vec4 t = texture(tex, UV);
		float heat = sq(clamp(1.0 - anim.x, 0.0, 1.0));
		float n = texture(noise, UV * 1.5 + vec2(TIME * 0.05, 0.0)).r;
		if (mode == 0) {
			float glow = t.r * heat * (0.6 + 0.8 * n) + t.a * heat * heat * 0.5 * smoothstep(0.7, 0.0, r);
			col = mix(color.rgb, color2.rgb * 3.5, clamp(glow, 0.0, 1.0));
			a = max(clamp(t.a * color.a * 1.4, 0.0, 1.0), clamp(glow, 0.0, 1.0));
		} else {
			float bowl = t.r;
			float cracks = t.a;
			float glow = cracks * heat * (0.7 + 0.6 * n) + bowl * heat * heat * 0.6;
			col = mix(color.rgb * (1.0 - bowl * 0.4), color2.rgb * 3.0, clamp(glow, 0.0, 1.0));
			a = clamp(bowl * 0.65 + cracks * 0.85, 0.0, 1.0) * color.a;
			a = max(a, clamp(glow, 0.0, 1.0));
		}
	} else if (mode == 2) {
		vec4 t = texture(tex, UV);
		float spread = anim.w;
		float vis = smoothstep(t.r - 0.02, t.r + 0.01, spread);
		float edge = (1.0 - smoothstep(0.0, 0.07, spread - t.r)) * vis * step(t.r, 0.98);
		float shimmer = 0.75 + 0.25 * sin(TIME * 2.0 + t.r * 20.0);
		float wash = (0.25 + 0.2 * (1.0 - r)) * vis * (1.0 - smoothstep(0.92, 1.0, r));
		float lines = t.a * vis;
		col = mix(color.rgb, vec3(1.0), lines * 0.6) * (1.0 + lines * 0.9 * shimmer) + color2.rgb * edge * 3.0;
		a = clamp(wash + lines * 0.75 + edge, 0.0, 1.0) * color.a * (1.0 - smoothstep(0.9, 1.0, r));
	} else if (mode == 3 || mode == 4) {
		vec2 uv = (rot2(anim.z) * q) * 0.5 + 0.5;
		float g = mode == 3 ? texture(tex, uv).a : texture(tex, UV).a;
		if (mode == 4) {
			// Clock hand.
			vec2 hd = vec2(sin(anim.z), -cos(anim.z));
			float along = dot(q, hd);
			float across = abs(q.x * hd.y - q.y * hd.x);
			float hand = step(-0.06, along) * step(along, 0.74) * (1.0 - smoothstep(0.012, 0.03, across));
			// Sweep trail behind the hand.
			float ang = atan(q.x, -q.y);
			float da = mod(anim.z - ang, 6.2831853);
			float trail = (1.0 - smoothstep(0.0, 1.4, da)) * step(r, 0.86) * 0.18 * anim.w;
			g = max(g, hand) + trail;
		}
		float flare = anim.w;
		col = color.rgb * (1.4 + flare * 2.5) + color2.rgb * g * flare;
		a = clamp(g, 0.0, 1.0) * color.a * (1.0 - smoothstep(0.97, 1.0, r));
	} else {
		vec4 t = texture(tex, UV);
		float ang = atan(q.y, q.x) / 6.2831853 + 0.5;
		float drawn = step(r, anim.w * 1.05) * step(ang, anim.w * 1.2);
		float pulse = 0.8 + 0.2 * sin(TIME * 4.0 - r * 8.0);
		col = color.rgb * (1.2 + pulse * 0.8);
		a = t.a * drawn * color.a * pulse + (1.0 - smoothstep(0.85, 1.0, r)) * 0.12 * anim.w;
	}
	ALBEDO = col;
	ALPHA = clamp(a * anim.y, 0.0, 1.0);
}
