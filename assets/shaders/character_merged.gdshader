shader_type spatial;
// Single-material character shader for merged meshes: per-vertex colour carries
// albedo (linear) and emission strength (alpha); UV2 carries roughness/metallic.

varying vec2 v_rm;

void vertex() {
	v_rm = UV2;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = v_rm.x;
	METALLIC = v_rm.y;
	SPECULAR = 0.45;
	// Soft rim light so characters stand out from the field at gameplay distance.
	RIM = 0.32;
	RIM_TINT = 0.45;
	EMISSION = COLOR.rgb * COLOR.a * 8.0;
}
