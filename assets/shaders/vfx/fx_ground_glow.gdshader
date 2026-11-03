shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Light pooled on the ground under a card effect (Update 8): a hot centre, a
// soft halo and a brighter rim, with its colour cooling along a ramp row as it ages.
// Lives on a 2x2 plane; node scale = radius.
//   anim.x = age 0..1 (walks the ramp), anim.y = visibility, anim.z = time seed,
//   anim.w = rim strength. row = ramp row centre (0..1).
#include "res://assets/shaders/vfx/fx_common.gdshaderinc"

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float energy = 1.6;

instance uniform vec4 anim = vec4(0.0, 1.0, 0.0, 0.6);
instance uniform float row = 0.5;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	if (r > 1.0) {
		discard;
	}
	float k = clamp(anim.x, 0.0, 1.0);
	// The centre stays a step hotter than the edge.
	vec3 c_mid = texture(ramp, vec2(0.15 + k * 0.8, row)).rgb;
	vec3 c_core = texture(ramp, vec2(0.02 + k * 0.7, row)).rgb;
	float n = texture(noise, q * 0.45 + vec2(anim.z * 0.37, TIME * 0.04)).r;
	float a2 = atan(q.y, q.x);
	float rays = 0.75 + 0.25 * sin(a2 * 9.0 + anim.z * 5.0 + n * 3.0);
	float halo = sq(1.0 - r) * (0.55 + 0.45 * n);
	float centre = pow(max(1.0 - r * 1.6, 0.0), 2.0);
	float rim = smoothstep(0.62, 0.86, r) * (1.0 - smoothstep(0.86, 1.0, r)) * anim.w * rays;
	// Mixed over the ground (not added) so a saturated colour stays saturated on bright
	// dirt and grass instead of washing out to pastel; the HDR energy still feeds the glow.
	float body = halo * 0.9 + rim * 1.6;
	float hotc = centre * 1.4;
	float mask = body + hotc;
	vec3 col = (c_mid * body + c_core * hotc) / max(mask, 0.001);
	ALBEDO = col * energy;
	ALPHA = clamp(mask * 0.8, 0.0, 0.85) * anim.y;
}
