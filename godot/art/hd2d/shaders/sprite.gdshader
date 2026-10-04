// Pixel-art creature sprite standing upright in the diorama (Actor).
// Nearest sampling, alpha cut-out (so it writes depth and casts a real shadow), wrap lighting
// so the flat card never goes black, plus hit flash, shiny hue shift and silhouette.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform float flash = 0.0;        // 0..1 hit flash (TS brightness 1 + v * 2.2)
uniform float shiny = 0.0;        // 1 = hue shift 150 deg, +25% saturation
uniform float silhouette = 0.0;   // 1 = solid dark shape
uniform float self_light = 0.3;   // unlit share, keeps sprites readable in dark biomes
uniform float light_gain = 0.5;   // lit share: the scene's lights tint the sprite without blowing it out
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float rim = 0.0;          // arena-tinted rim on the outline pixels

vec3 hue_rotate(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = c.rgb;
	if (shiny > 0.5) {
		col = max(hue_rotate(col, radians(150.0)), vec3(0.0));
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = clamp(mix(vec3(l), col, 1.25), 0.0, 1.0);
	}
	if (silhouette > 0.5) {
		ALBEDO = vec3(0.02, 0.02, 0.04);
		EMISSION = vec3(0.0);
		ROUGHNESS = 1.0;
	} else {
		ALBEDO = col * (1.0 - self_light);
		EMISSION = col * self_light + col * flash * 2.2;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
	NORMAL = vec3(0.0, 0.0, 1.0) * (FRONT_FACING ? 1.0 : -1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap * light_gain / PI;
}
