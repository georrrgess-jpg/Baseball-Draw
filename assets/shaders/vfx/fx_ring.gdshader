shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Pooled ground rings on a 2x2 plane (node scale = radius). One shared material, all
// variation through instance uniforms:
//   mode 0 shockwave (progress = age), 1 zone ring (progress = visibility),
//   mode 2 telegraph (progress = fill), 3 thin pulse ring (progress = age),
//   mode 4 imploding ring (progress = age)
//   params: x thickness, y fill, z spin, w dashes
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

instance uniform vec4 color : source_color = vec4(1.0);
instance uniform float progress = 0.0;
instance uniform float mode = 0.0;
instance uniform vec4 params = vec4(0.05, 0.15, 0.0, 0.0);

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float aa = fwidth(r) * 1.5;
	vec3 col = color.rgb;
	float a = 0.0;
	float glow = 0.0;
	if (mode < 0.5 || mode > 2.5) {
		// Expanding shockwave: bright leading edge, soft wake, fades out.
		float k = progress;
		float front = 1.0 - pow(1.0 - k, 3.0);
		if (mode > 3.5) {
			front = 1.0 - k * k;
		}
		float wob = (texture(noise, vec2(ang * 0.3183, k * 0.3)).r - 0.5) * 0.06;
		float d = r - front * (1.0 + wob);
		float th = mix(params.x * 2.5, params.x * 0.6, k);
		float edge = exp(-d * d / (th * th));
		float wake = smoothstep(-0.45, 0.0, d) * (1.0 - smoothstep(0.0, aa + 0.01, d)) * params.y;
		float fade = pow(1.0 - k, 1.4);
		a = (edge + wake * (mode > 2.5 ? 0.0 : 1.0)) * fade;
		glow = edge * fade;
	} else if (mode < 1.5) {
		// Persistent zone: crisp rim, ticks spinning, soft inner gradient and inward ripples.
		float rim = smoothstep(1.0 - params.x - aa, 1.0 - params.x, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r));
		float a2 = ang + TIME * params.z;
		if (params.w > 0.5) {
			float dash = step(0.5, fract(a2 / 6.2831853 * params.w));
			float ticks = smoothstep(1.0 - params.x * 3.5, 1.0 - params.x * 2.0, r) * (1.0 - smoothstep(1.0 - params.x * 1.6, 1.0 - params.x * 1.2, r)) * dash;
			rim += ticks * 0.8;
		}
		float inside = 1.0 - smoothstep(1.0 - aa, 1.0, r);
		float ripple = pow(0.5 + 0.5 * sin(r * 14.0 + TIME * 3.0), 6.0) * 0.35;
		float f = params.y * inside * (0.35 + 0.65 * r * r + ripple);
		a = clamp(rim + f, 0.0, 1.0) * progress;
		glow = rim * progress;
	} else {
		// Telegraph: pulsing rim, sweeping fill toward the hit.
		float rim = smoothstep(1.0 - params.x - aa, 1.0 - params.x, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r));
		float inside = 1.0 - smoothstep(1.0 - aa, 1.0, r);
		float grow = step(r, progress) * inside;
		float edge = exp(-pow((r - progress) / 0.04, 2.0)) * inside;
		float p = 0.75 + 0.25 * sin(TIME * 14.0);
		a = clamp(rim * p + grow * params.y + edge * 0.8 + inside * 0.08, 0.0, 1.0);
		glow = rim + edge;
	}
	ALBEDO = col * (1.0 + glow * 1.6);
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
