// Signature foil (CardView): a pink, cyan and gold sheen sweeping right to left across the card,
// clipped to its rounded corners. Port of the mockup's CSS: linear-gradient(115deg) on a 260%-wide
// repeating background whose position runs 120% -> -60% every 3.4 s. `t` is real seconds
// (UiKit.now()), so hit-stop and slow-mo don't freeze it; `sat`/`bright` follow the card's dimming.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 rsize = vec2(85.0, 113.0);
uniform float radius = 6.0;
uniform float t = 0.0;
uniform float sat = 1.0;
uniform float bright = 1.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// premultiplied stops: transparent 22%, pink 34%, cyan 44%, gold 54%, transparent 68%
vec3 sheen(float g) {
	vec3 pink = vec3(1.0, 0.431, 0.784) * 0.30;
	vec3 cyan = vec3(0.431, 0.863, 1.0) * 0.32;
	vec3 gold = vec3(1.0, 0.941, 0.549) * 0.30;
	if (g < 0.22 || g > 0.68) return vec3(0.0);
	if (g < 0.34) return pink * (g - 0.22) / 0.12;
	if (g < 0.44) return mix(pink, cyan, (g - 0.34) / 0.10);
	if (g < 0.54) return mix(cyan, gold, (g - 0.44) / 0.10);
	return gold * (0.68 - g) / 0.14;
}

void fragment() {
	vec2 hs = rsize * 0.5;
	float d = sd_round_box(lp - hs, hs, radius);
	float inside = 1.0 - smoothstep(-0.5, 0.5, d);
	vec2 bs = vec2(rsize.x * 2.6, rsize.y);
	float ox = (rsize.x - bs.x) * mix(1.2, -0.6, fract(t / 3.4));
	vec2 q = vec2(mod(lp.x - ox, bs.x), lp.y) - bs * 0.5;
	float a = radians(115.0);
	vec2 dir = vec2(sin(a), -cos(a));
	float len = abs(bs.x * dir.x) + abs(bs.y * dir.y);
	vec3 c = sheen(dot(q, dir) / len + 0.5);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat) * bright;
	COLOR = vec4(c, inside);
}
