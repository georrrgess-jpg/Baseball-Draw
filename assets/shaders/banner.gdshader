shader_type spatial;
render_mode cull_disabled;
// Cloth banner waving in the wind.

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float wind = 1.0;
uniform float phase = 0.0;

void vertex() {
	float k = UV.y * (0.35 + 0.65 * UV.x);
	float w = sin(TIME * 2.4 + UV.x * 3.0 + UV.y * 5.0 + phase) * 0.22 * k * wind;
	w += sin(TIME * 4.1 + UV.y * 9.0 + phase) * 0.06 * k * wind;
	VERTEX.z += w;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, w * 0.5));
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.8;
	float fold = 0.85 + 0.15 * sin(UV.x * 18.0 + TIME * 2.4 + phase);
	ALBEDO *= fold;
}
