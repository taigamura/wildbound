// A creature face in a card's window (CardView): the sprite crop with the card's dimming applied,
// CSS saturate() + brightness() (off-element: 0.25 / 0.55; dead: 0 / 0.5).
shader_type canvas_item;

uniform float sat = 1.0;
uniform float bright = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(mix(vec3(l), c.rgb, sat) * bright, c.a);
}
