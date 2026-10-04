// Lightning bolt strips (vertex colours), additive, fading.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
uniform float alpha = 1.0;
uniform float intensity = 1.8;
void fragment() {
	ALBEDO = COLOR.rgb * COLOR.a * alpha * intensity;
	ALPHA = 1.0;
}
