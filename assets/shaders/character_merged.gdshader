shader_type spatial;
// Single-material character shader for merged meshes: per-vertex colour carries
// albedo (linear) and emission strength (alpha); UV2 carries roughness/metallic.
// UV carries the material class (x) and a smooth rest-pose noise value (y), set by
// CharacterModel for the defenders; class 0 (runners, bosses) keeps the plain look.
//   1 fabric (jersey, pants, socks, undershirt, cap): soft coloured sheen, matte,
//     slight roughness variation;
//   2 skin: warm light bleed on the shadow side and a warm rim;
//   3 leather (glove, belt, shoes): darker and glossier;
//   4 metal (cleat spikes, mask, buckle); 5 glossy (eyes, catcher gear, visor);
//   6 hair: soft tinted sheen; 7 decals (numbers, emblem outline): a touch of lift.

// Defender silhouette rim (team / accent colour). Stronger with distance so the
// defenders read at the battle camera without glowing in close-ups.
instance uniform vec4 team_rim : source_color = vec4(0.0);

varying vec2 v_rm;
varying vec2 v_mat;

void vertex() {
	v_rm = UV2;
	v_mat = UV;
}

void fragment() {
	vec3 alb = COLOR.rgb;
	float rough = v_rm.x;
	float metal = v_rm.y;
	float spec = 0.45;
	float rim = 0.32;
	float rim_tint = 0.45;
	vec3 emis = COLOR.rgb * COLOR.a * 8.0;
	vec3 back = vec3(0.0);
	int cls = int(v_mat.x + 0.5);
	float n = v_mat.y - 0.5;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (cls == 1) {
		// Fabric: matte with a soft sheen that picks up the cloth colour at grazing angles.
		rough = clamp(rough + 0.06 + n * 0.14, 0.0, 1.0);
		// (light cloth keeps more specular so white pants stay bright)
		spec = mix(0.3, 0.42, dot(alb, vec3(0.3, 0.6, 0.1)));
		// (capped so white pants do not bloom at the edges)
		vec3 sheen = min(alb * 1.4 + vec3(0.012), max(alb, vec3(0.88)));
		alb = mix(alb, sheen, pow(fres, 2.2) * 0.55);
		rim = mix(0.42, 0.2, dot(alb, vec3(0.3, 0.6, 0.1)));
		rim_tint = 0.8;
	} else if (cls == 2) {
		// Skin: light bleeds warm into the shadow side (cheap subsurface), warm rim.
		rough = 0.5 + n * 0.08;
		spec = 0.36;
		alb = mix(alb, alb * vec3(1.1, 0.95, 0.9), fres * 0.45);
		back = alb * vec3(0.45, 0.2, 0.14);
		rim = 0.36;
		rim_tint = 0.92;
	} else if (cls == 3) {
		// Leather: darker, oiled.
		alb *= 0.72;
		rough = clamp(0.36 + n * 0.12, 0.0, 1.0);
		spec = 0.55;
		rim = 0.22;
		rim_tint = 0.6;
	} else if (cls == 4) {
		metal = 0.78;
		rough = 0.26;
		spec = 0.6;
		alb = min(alb * 1.15, vec3(1.0));
	} else if (cls == 5) {
		rough = min(rough, 0.2);
		spec = 0.6;
	} else if (cls == 6) {
		rough = 0.46 + n * 0.1;
		spec = 0.5;
		rim = 0.38;
		rim_tint = 0.85;
	} else if (cls == 7) {
		spec = 0.4;
		emis += alb * 0.06;
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	// Soft rim light so characters stand out from the field at gameplay distance.
	RIM = rim;
	RIM_TINT = rim_tint;
	BACKLIGHT = back;
	if (team_rim.a > 0.0) {
		float far = smoothstep(7.0, 24.0, length(VERTEX));
		emis += team_rim.rgb * smoothstep(mix(0.62, 0.5, far), 0.95, fres) * team_rim.a * mix(0.3, 1.0, far);
	}
	EMISSION = emis;
}
