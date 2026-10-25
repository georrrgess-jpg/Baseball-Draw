shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Translucent ice: frosted cyan body, bright fresnel edges, sharp glints. `fade` dissolves
// the crystal in/out through noise (1 = solid).

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

instance uniform float fade = 1.0;
instance uniform vec4 tint : source_color = vec4(0.62, 0.9, 1.0, 1.0);

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float n = texture(noise, v_local.xy * 0.9 + v_local.z * 0.37).r;
	if (n > fade * 1.05) {
		discard;
	}
	float edge = smoothstep(fade * 1.05 - 0.08, fade * 1.05, n);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 frosted = tint.rgb * (0.75 + 0.35 * texture(noise, v_local.xz * 2.3).b);
	ALBEDO = frosted;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = tint.rgb * (0.25 + fres * 1.6) + vec3(0.7, 0.95, 1.0) * edge * 2.5;
	ALPHA = clamp(0.5 + fres * 0.45 + edge, 0.0, 1.0) * tint.a;
}
