// Rounded-rect "div" for the UI: gradient fill (linear at a CSS angle, radial, or diagonal stripes),
// inner border, outer ring, soft glow and a hard drop shadow, all antialiased. Driven by ui/rrect.gd.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rsize = vec2(100.0);
uniform vec4 radii = vec4(8.0);          // tl, tr, br, bl (px)
uniform int mode = 0;                    // 0 linear, 1 radial, 2 stripes (-45deg, 5px)
uniform vec4 c0 : source_color = vec4(1.0);
uniform vec4 c1 : source_color = vec4(1.0);
uniform vec4 c2 : source_color = vec4(1.0);
uniform float s1 = 1.0;                  // stop of c1; >= 1 means a two-stop c0 -> c1 gradient
uniform float s_end = 1.0;               // last stop (CSS "deep 62%")
uniform float angle = 180.0;             // CSS degrees (180 = top to bottom)
uniform vec2 rc = vec2(0.35, 0.3);       // radial centre, fraction of the box
uniform float border_w = 0.0;
uniform vec4 border_c : source_color = vec4(0.0);
uniform float ring_w = 0.0;              // box-shadow: 0 0 0 Npx
uniform vec4 ring_c : source_color = vec4(0.0);
uniform float glow = 0.0;                // box-shadow: 0 0 Npx
uniform vec4 glow_c : source_color = vec4(0.0);
uniform vec2 sh_off = vec2(0.0);         // box-shadow: X Y 0 (hard)
uniform vec4 sh_c : source_color = vec4(0.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, vec4 r) {
	float rr = p.x > 0.0 ? (p.y > 0.0 ? r.z : r.y) : (p.y > 0.0 ? r.w : r.x);
	vec2 q = abs(p) - b + rr;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	if (a <= 0.00001) return vec4(0.0);
	return vec4((top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / a, a);
}

vec4 grad(float t) {
	t = clamp(t / max(s_end, 0.0001), 0.0, 1.0);
	if (s1 >= 1.0) return mix(c0, c1, t);
	if (t < s1) return mix(c0, c1, t / s1);
	return mix(c1, c2, (t - s1) / max(1.0 - s1, 0.0001));
}

void fragment() {
	vec2 hs = rsize * 0.5;
	vec2 p = lp - hs;
	vec4 r = min(radii, vec4(min(hs.x, hs.y)));
	float d = sd_round_box(p, hs, r);
	float aa = max(fwidth(d), 0.001);
	float inside = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);

	vec4 fill;
	if (mode == 1) {
		vec2 c = rc * rsize;
		vec2 far = max(c, rsize - c);
		fill = grad(length((lp - c) / max(far, vec2(0.001))) * 0.70710678);
	} else if (mode == 2) {
		fill = mod(lp.x + lp.y, 14.142) < 7.071 ? c0 : c1;
	} else {
		float a = radians(angle);
		vec2 dir = vec2(sin(a), -cos(a));
		float len = abs(rsize.x * dir.x) + abs(rsize.y * dir.y);
		fill = grad(dot(p, dir) / max(len, 0.001) + 0.5);
	}
	if (border_w > 0.0) {
		float b = smoothstep(-border_w - 0.5 * aa, -border_w + 0.5 * aa, d);
		fill = over(vec4(border_c.rgb, border_c.a * b), fill);
	}
	vec4 col = vec4(fill.rgb, fill.a * inside);

	vec4 outc = vec4(0.0);
	if (sh_c.a > 0.0) {
		float ds = sd_round_box(p - sh_off, hs, r);
		outc = vec4(sh_c.rgb, sh_c.a * (1.0 - smoothstep(-0.5 * aa, 0.5 * aa, ds)));
	}
	if (glow > 0.0 && glow_c.a > 0.0) {
		float g = clamp(1.0 - d / glow, 0.0, 1.0);
		outc = over(vec4(glow_c.rgb, glow_c.a * g * g), outc);
	}
	if (ring_w > 0.0 && ring_c.a > 0.0) {
		float rg = 1.0 - smoothstep(ring_w - 0.5 * aa, ring_w + 0.5 * aa, d);
		outc = over(vec4(ring_c.rgb, ring_c.a * rg), outc);
	}
	COLOR = over(col, outc) * COLOR;
}
