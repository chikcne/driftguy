shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.886, 0.271, 0.184, 0.75);
uniform float inner_radius = 0.45;
uniform float outer_radius = 1.05;
uniform float intensity = 0.0;
uniform float flash = 0.0;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float vig = smoothstep(inner_radius, outer_radius, r);
	float alpha = clamp(vig * tint.a * intensity + flash * 0.55, 0.0, 0.95);
	COLOR = vec4(mix(tint.rgb, vec3(0.84, 0.95, 1.0), clamp(flash, 0.0, 1.0)), alpha);
}
