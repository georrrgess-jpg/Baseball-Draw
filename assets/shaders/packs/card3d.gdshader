shader_type spatial;
render_mode unshaded, cull_disabled;
// Double-sided 3D card for pack reveals: the front texture is a live CardView viewport,
// the back is the shared card-back viewport. A soft gloss follows the viewing angle.

uniform sampler2D front_tex : source_color, filter_linear;
uniform sampler2D back_tex : source_color, filter_linear;
uniform float brightness = 1.0;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow = 0.0;

void fragment() {
	vec4 c = FRONT_FACING ? texture(front_tex, UV) : texture(back_tex, vec2(1.0 - UV.x, UV.y));
	vec3 r = reflect(-VIEW, NORMAL);
	float gloss = pow(clamp(dot(r, normalize(vec3(0.35, 0.55, 0.75))), 0.0, 1.0), 28.0);
	ALBEDO = c.rgb * brightness + vec3(gloss * 0.22) + glow_color.rgb * glow * 0.35;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
