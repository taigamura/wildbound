// Shield bubble around the active partner: soft fill, bright ring, rotating hexagon (TS initShield).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform float alpha = 0.0;
uniform float rot = 0.0;
uniform vec3 ring_col : source_color = vec3(0.561, 0.89, 1.0);
uniform vec3 fill_col : source_color = vec3(0.247, 0.714, 1.0);

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	VERTEX = vec3(VERTEX.xy * sc, 0.0);
}

// pointy-top hexagon (vertices at 30 + k*60 deg, circumradius 1): apothem 0.866
float hex_dist(vec2 p) {
	p = abs(p);
	return max(p.x, dot(p, vec2(0.5, 0.8660254)));
}

void fragment() {
	// quad spans radius 1.1 (fill 2.2r wide): p in units of the ring radius
	vec2 p = (UV - 0.5) * 2.2;
	float d = length(p);
	float fill = 0.22 * pow(clamp(1.0 - d / 1.1, 0.0, 1.0), 1.2);
	float ring = smoothstep(0.1, 0.0, abs(d - 1.0)) + 0.35 * smoothstep(0.25, 0.0, abs(d - 1.0));
	float c = cos(rot), s = sin(rot);
	vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float hx = smoothstep(0.04, 0.0, abs(hex_dist(q) - 0.866)) * 0.7;
	vec3 col = fill_col * fill + ring_col * (ring + hx);
	ALBEDO = col * alpha;
	ALPHA = 1.0;
}
