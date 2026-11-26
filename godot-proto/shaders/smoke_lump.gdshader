shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;

uniform vec3 sun_dir = vec3(0.55, 0.58, 0.46);
uniform vec3 drift = vec3(0.0, 0.0, 0.0);
uniform vec3 shade_tint = vec3(0.74, 0.69, 0.75);
uniform vec3 rim_color = vec3(1.0, 0.93, 0.84);
uniform vec3 fog_color : source_color = vec3(0.953, 0.788, 0.627);
uniform vec2 fog_range = vec2(120.0, 320.0);

varying vec3 v_world_pos;
varying vec3 v_world_norm;
varying vec3 v_tint;
varying float v_glow;

// Puff tints are authored as sRGB; the lighting below runs in linear space.
vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// Smooth 3D lumpy displacement for cel-shaded clustered smoke clouds
float lump_field(vec3 p) {
	float a = sin(p.x * 1.7 + p.y * 1.3) * cos(p.z * 1.6 - p.y * 1.1);
	float b = sin(p.z * 3.1 - p.x * 2.4 + p.y * 2.7) * 0.5;
	float c = cos(p.y * 4.2 + p.x * 3.5 + p.z * 2.9) * 0.25;
	return (a + b + c) * 0.57;
}

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float seed = INSTANCE_CUSTOM.b * 6.2831853;
	vec3 q = (wpos - drift) * 0.34 + vec3(seed, seed * 0.37, -seed * 0.61);
	float disp = lump_field(q) * 0.22;
	VERTEX += NORMAL * disp;

	// Finite-difference normal perturbation in local space for crisp lumpy cel shading
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float eps = 0.28;
	vec3 grad = vec3(
		lump_field(q + vec3(eps, 0.0, 0.0)) - lump_field(q - vec3(eps, 0.0, 0.0)),
		lump_field(q + vec3(0.0, eps, 0.0)) - lump_field(q - vec3(0.0, eps, 0.0)),
		lump_field(q + vec3(0.0, 0.0, eps)) - lump_field(q - vec3(0.0, 0.0, eps))
	) / (2.0 * eps);
	v_world_norm = normalize(wn - grad * 0.45);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tint = srgb_to_linear(COLOR.rgb);
	v_glow = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 n = normalize(v_world_norm);
	// Secondary fine cel-shaded lobe normal perturbation in fragment space
	vec3 fq = (v_world_pos - drift) * 0.65;
	float f1 = sin(fq.x * 2.1 + fq.z * 1.7) * cos(fq.y * 2.3 - fq.x * 1.5);
	float f2 = cos(fq.z * 2.7 - fq.y * 1.9);
	n = normalize(n + vec3(f1, f2 * 0.6, -f1) * 0.16);

	vec3 sdir = normalize(sun_dir);
	float facing = dot(n, sdir);
	float lit = smoothstep(0.18, 0.28, facing);

	// Soft crease darkening at lower/inner lobes
	float crease = smoothstep(-0.35, -0.75, n.y) * 0.12;

	// Rim light in view space
	vec3 view_n = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float grazing = 1.0 - max(dot(view_n, VIEW), 0.0);
	float rim = smoothstep(0.55, 1.0, grazing) * 0.4;

	vec3 col = mix(v_tint * shade_tint, mix(v_tint, vec3(1.0), 0.09) * 0.94, lit);
	col *= (1.0 - crease);
	col = mix(col, rim_color, rim * (1.0 - 0.5 * lit));

	// Emissive heat glow for fire, ember, and toxic smoke
	float heat = smoothstep(0.05, 0.11, v_glow) + smoothstep(0.47, 0.53, v_glow);
	col += v_tint * heat * 0.32;

	// Linear distance fog matching desert haze
	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
	float fog = clamp((dist - fog_range.x) / (fog_range.y - fog_range.x), 0.0, 1.0);
	col = mix(col, fog_color, fog);

	ALBEDO = col;
}
