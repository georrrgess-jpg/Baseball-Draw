shader_type spatial;
render_mode cull_disabled;
// Heat-sealed crimp at the ends of a foil pack: metallic with fine horizontal ridges.

uniform vec4 color : source_color = vec4(0.8, 0.85, 0.95, 1.0);
uniform float charge = 0.0;

void fragment() {
	float ridge = 0.5 + 0.5 * sin(UV.x * 220.0);
	ALBEDO = color.rgb * (0.75 + 0.25 * ridge);
	METALLIC = 0.85;
	ROUGHNESS = 0.18 + 0.2 * ridge;
	EMISSION = color.rgb * charge * charge * 1.6;
}
