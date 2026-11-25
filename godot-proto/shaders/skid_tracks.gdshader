shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform vec4 mark_color : source_color = vec4(0.52, 0.31, 0.2, 0.42);
uniform float current_time = 0.0;
uniform float fade_start = 10.0;
uniform float fade_end = 16.0;

void fragment() {
	if (UV.y <= 0.001) {
		discard;
	}
	float fade = 1.0;
	if (fade_end > 0.0) {
		float age = current_time - UV.x;
		fade = 1.0 - smoothstep(fade_start, fade_end, age);
		if (fade <= 0.001) {
			discard;
		}
	}
	ALBEDO = mark_color.rgb;
	ALPHA = clamp(mark_color.a * UV.y * fade, 0.0, 1.0);
}
