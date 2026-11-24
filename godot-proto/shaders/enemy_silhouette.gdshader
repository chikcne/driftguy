shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix;

// Renders a grey silhouette whenever an enemy is occluded behind scenery or smoke clouds.
// Uses view-space linearized depth so it is immune to Reverse-Z depth encoding on Metal/Vulkan.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 veil_color : source_color = vec4(0.50, 0.48, 0.53, 0.68);
uniform float depth_slack = 0.5;

void fragment() {
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 scene_view = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -scene_view.z / scene_view.w;
	float frag_z = -VERTEX.z;
	if (frag_z <= scene_z + depth_slack) {
		discard;
	}
	ALBEDO = veil_color.rgb;
	ALPHA = veil_color.a;
}
