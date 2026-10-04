// Camera-facing additive glow quad (projectiles, flashes, rings, blooms). Drawn on top of the
// scene like the TS glow layer, but placed at a real depth so it gets fog/DOF context.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#ifndef DEPTH_TEST
render_mode depth_test_disabled;
#endif

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 1.6;
uniform float alpha = 1.0;
uniform float spin = 0.0;
uniform bool billboard = true;

void vertex() {
	if (billboard) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
		float c = cos(spin), s = sin(spin);
		vec2 v = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c) * sc;
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
		VERTEX = vec3(v, 0.0);
	}
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = color.rgb * t.rgb * intensity * t.a * color.a * alpha;
	ALPHA = 1.0;
}
