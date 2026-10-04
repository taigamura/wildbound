// Light shaft: additive tall card from the upper left, slow shimmer. No volumetrics needed.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform float strength = 0.2;
uniform float phase = 0.0;

void fragment() {
	vec4 t = texture(tex, UV);
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.7 + phase + UV.y * 3.0);
	ALBEDO = color.rgb * t.a * strength * shimmer;
	ALPHA = 1.0;
}
