// Pooled particles (MultiMesh of camera-facing quads). Per instance:
//   transform origin = world position, basis x scale = size (world units)
//   COLOR = tint and alpha
//   INSTANCE_CUSTOM = (rotation, streak stretch, atlas cell, 0)
// Atlas: 6 cells (glow, soft, spark, leaf, star, ring), quad aspect per cell.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#ifdef NORMAL_BLEND
render_mode blend_mix;
#else
render_mode blend_add;
#endif

uniform sampler2D atlas : source_color, filter_linear;
uniform float intensity = 0.75;
const float CELLS = 6.0;
// quad width/height per cell, in units of the particle size (TS texture size / visible size)
const vec2 ASPECT[6] = vec2[](vec2(1.0), vec2(1.0), vec2(4.0, 1.0), vec2(1.333), vec2(1.2), vec2(1.185));

varying float cell;

void vertex() {
	float sz = length(MODEL_MATRIX[0].xyz);
	vec4 cd = INSTANCE_CUSTOM;
	cell = cd.z;
	vec2 asp = ASPECT[int(cd.z + 0.5)];
	vec2 v = VERTEX.xy * asp * vec2(sz * cd.y, sz);
	float c = cos(cd.x), s = sin(cd.x);
	v = vec2(v.x * c - v.y * s, v.x * s + v.y * c);
	vec3 world = MODEL_MATRIX[3].xyz + INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	UV = vec2((UV.x + floor(cd.z + 0.5)) / CELLS, UV.y);
}

void fragment() {
	vec4 t = texture(atlas, UV);
#ifdef NORMAL_BLEND
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = t.a * COLOR.a;
#else
	ALBEDO = COLOR.rgb * t.rgb * t.a * COLOR.a * intensity;
	ALPHA = 1.0;
#endif
}
