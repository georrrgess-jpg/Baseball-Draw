shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Energy hemispheres.
//   mode 0: Base Shield dome - hex cells with a fresnel rim, assembled bottom-up by `build`,
//           impact ripples (ripple.xyz = local direction, ripple.w = age 0..1).
//   mode 1: shout / pulse bubble - fresnel shell fading with `build` as age.
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

instance uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float strength = 1.0;
instance uniform float build = 1.0;
instance uniform vec4 ripple = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float mode = 0.0;

varying vec3 v_dir;

void vertex() {
	// Model-space normal: on a sphere it is the direction from the centre (the pole vertex can be degenerate).
	v_dir = normalize(NORMAL + vec3(0.0, 1e-5, 0.0));
}

float hexdist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

void fragment() {
	float fres = pow(max(1.0 - abs(dot(NORMAL, VIEW)), 0.0), 2.4);
	if (mode > 0.5) {
		float k = build;
		float life = pow(max(1.0 - k, 0.0), 1.6);
		float bands = 0.6 + 0.4 * sin(v_dir.y * 18.0 - TIME * 10.0);
		ALBEDO = color.rgb * (fres * 2.2 + 0.08) * bands * life * strength;
	} else {
		float az = atan(v_dir.z, v_dir.x);
		float el = asin(clamp(v_dir.y, -1.0, 1.0)) / 1.5707963;
		vec2 p = vec2(az / 6.2831853 * 26.0, el * 7.5);
		vec2 h = vec2(1.0, 1.7320508);
		vec2 a1 = mod(p, h) - h * 0.5;
		vec2 b1 = mod(p - h * 0.5, h) - h * 0.5;
		vec2 g = dot(a1, a1) < dot(b1, b1) ? a1 : b1;
		vec2 id = floor((p - g) * 2.0 + 0.5);
		float rnd = hash12(id);
		float edge = smoothstep(0.36, 0.47, hexdist(g));
		float built = smoothstep(0.0, 0.08, build * 1.25 - (rnd * 0.35 + clamp(el, 0.0, 1.0) * 0.75));
		float twinkle = 0.55 + 0.45 * sin(TIME * 2.3 + rnd * 40.0);
		float fill = step(0.86, rnd) * 0.35 * twinkle;
		float scan = pow(0.5 + 0.5 * sin(el * 18.0 - TIME * 3.0), 12.0) * 0.4;
		float d = acos(clamp(dot(v_dir, normalize(ripple.xyz)), -1.0, 1.0));
		float rk = ripple.w;
		float ring = exp(-sq((d - rk * 2.4) / 0.14)) * (1.0 - rk) * step(rk, 0.999);
		float hit_glow = exp(-d * d * 6.0) * pow(max(1.0 - rk, 0.0), 3.0) * step(rk, 0.999);
		float base = exp(-max(el, 0.0) * 14.0);
		float front = exp(-sq((el - (build * 1.25 - 0.35)) / 0.05)) * step(build, 0.999);
		float v = fres * 0.95 + edge * 0.32 * twinkle + fill * 0.7 + scan * 0.6 + base * 0.6;
		v = v * built + front * 1.5 + (ring * 2.5 + hit_glow * 1.5) * (0.4 + edge);
		ALBEDO = color.rgb * v * strength;
	}
}
