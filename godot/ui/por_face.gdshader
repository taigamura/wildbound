// A creature face in a round portrait (UiKit.face_por): the sprite crop masked to a circle in local
// space (an AtlasTexture's UV covers only its region, so the mask uses the vertex position instead),
// with CSS saturate() + brightness() for a knocked-out creature.
shader_type canvas_item;

uniform vec2 rsize = vec2(48.0, 48.0);
uniform float sat = 1.0;
uniform float bright = 1.0;
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	float r = rsize.x * 0.5;
	float d = length(lp - rsize * 0.5);
	float m = clamp(r - d + 0.5, 0.0, 1.0);
	COLOR = vec4(mix(vec3(l), c.rgb, sat) * bright, c.a * m);
}
