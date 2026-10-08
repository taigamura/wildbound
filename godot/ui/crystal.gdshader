// The energy crystal's orb (Crystal): a dark glass disc with a gold rim, filled from the bottom with
// crystal liquid (the card crystal colours #e6fbff → #57c8ff → #2178c2) whose surface waves a little.
// `t` is game-clock seconds passed in by Crystal (never TIME, so UI-check shots stay deterministic).
shader_type canvas_item;

uniform vec2 rsize = vec2(52.0, 52.0);
uniform float level = 0.0;     // 0..1 liquid height
uniform float t = 0.0;
uniform float full = 0.0;      // 1 at max energy: a brighter, calmer surface
uniform vec4 c_top : source_color = vec4(0.902, 0.984, 1.0, 1.0);
uniform vec4 c_mid : source_color = vec4(0.341, 0.784, 1.0, 1.0);
uniform vec4 c_bot : source_color = vec4(0.129, 0.471, 0.761, 1.0);
uniform vec4 glass : source_color = vec4(0.043, 0.078, 0.188, 1.0);
uniform vec4 rim : source_color = vec4(0.788, 0.635, 0.29, 1.0);

void fragment() {
	vec2 p = UV * rsize;
	float r = rsize.x * 0.5;
	float d = length(p - rsize * 0.5);
	float inside = clamp(r - d + 0.5, 0.0, 1.0);
	float y = UV.y;
	float amp = mix(0.025, 0.008, full) * step(0.001, level) * step(level, 0.999);
	float surf = 1.0 - level + sin(UV.x * 9.0 + t * 3.2) * amp + sin(UV.x * 5.0 - t * 2.1) * amp * 0.6;
	float liquid = smoothstep(surf - 0.012, surf + 0.012, y);
	// gradient: bright at the surface, deep at the bottom
	float k = clamp((y - surf) / max(1.0 - surf, 0.05), 0.0, 1.0);
	vec3 lc = k < 0.35 ? mix(c_top.rgb, c_mid.rgb, k / 0.35) : mix(c_mid.rgb, c_bot.rgb, (k - 0.35) / 0.65);
	// a thin bright meniscus on the surface
	float men = (1.0 - smoothstep(0.0, 0.035, abs(y - surf))) * step(0.001, level);
	vec3 col = mix(glass.rgb, lc, liquid);
	col = mix(col, c_top.rgb, men * 0.8);
	// glass sheen in the upper left
	float sh = 1.0 - smoothstep(0.0, 0.32, length(UV - vec2(0.32, 0.26)));
	col += vec3(0.16) * sh;
	// gold rim 1.5px
	float rimk = clamp(1.5 - (r - d), 0.0, 1.0) * inside;
	col = mix(col, rim.rgb, rimk);
	COLOR = vec4(col, inside);
}
