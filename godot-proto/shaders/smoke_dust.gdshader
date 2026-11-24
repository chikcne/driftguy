shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;

uniform vec3 fog_color = vec3(0.953, 0.788, 0.627);
uniform vec2 fog_range = vec2(120.0, 320.0);

varying vec3 v_world_pos;
varying float v_alpha;
varying vec3 v_tint;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tint = COLOR.rgb;
	v_alpha = INSTANCE_CUSTOM.r;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
	float fog = clamp((dist - fog_range.x) / (fog_range.y - fog_range.x), 0.0, 1.0);
	ALBEDO = mix(v_tint, fog_color, fog);
	ALPHA = v_alpha * (1.0 - fog);
}
