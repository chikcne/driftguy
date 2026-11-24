shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, fog_disabled;
stencil_mode read, write, compare_not_equal, 1;

// Renders a flat single-pass grey silhouette whenever an enemy is occluded behind
// scenery or smoke clouds. Uses stencil=1 (written by visible enemies, the player car,
// and the first occluded silhouette fragment) to prevent self-occlusion and overlapping
// alpha stacking, matching the flat 2D ghost veil in the BabylonJS version.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 veil_color : source_color = vec4(0.50, 0.48, 0.53, 0.70);
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
