shader_type spatial;
// Foil card pack: printed artwork with iridescent fresnel, a moving specular sweep and an
// inner "charge" glow that builds up while the pack is being opened.

uniform sampler2D art : source_color, filter_linear_mipmap;
uniform vec4 foil_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float charge = 0.0;
uniform float brightness = 1.0;
uniform float is_back = 0.0;

void fragment() {
	vec2 uv = UV;
	vec3 a = texture(art, uv).rgb;
	if (is_back > 0.5) {
		a = mix(a, foil_color.rgb * 0.35, 0.65);
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 irid = 0.5 + 0.5 * cos(6.28318 * (fres * 1.4 + uv.y * 0.7 + TIME * 0.05 + vec3(0.0, 0.33, 0.67)));
	float d = uv.x * 0.7 + uv.y * 0.7;
	float t = fract(TIME * 0.21);
	float band = exp(-pow((d - mix(-0.4, 1.8, t)) * 7.0, 2.0));
	float pulse = 0.65 + 0.35 * sin(TIME * 28.0);
	ALBEDO = a * brightness;
	METALLIC = 0.45;
	ROUGHNESS = 0.24;
	SPECULAR = 0.7;
	// Charge: light leaking from inside, strongest at the top seam and around the rim.
	vec2 e = min(uv, 1.0 - uv);
	float rim = 1.0 - smoothstep(0.0, 0.12, min(e.x, e.y));
	float leak = 0.12 + 1.8 * pow(1.0 - uv.y, 4.0) + rim * 0.9;
	EMISSION = a * 0.22 * brightness + irid * fres * 0.45 + vec3(band * 0.3) + foil_color.rgb * charge * charge * leak * pulse;
}
