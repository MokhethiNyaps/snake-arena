// §3.5 Phase 10 — the boundary "energy wall": translucent cyan hex lattice,
// slowly scrolling, breathing pulse, fresnel glow at grazing angles. Fully
// TIME-driven (zero CPU per frame). Additive blend over the dark background.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3 line_color : source_color = vec3(0.10, 0.85, 1.00);
uniform vec3 glow_color : source_color = vec3(0.03, 0.30, 0.45);
// Lattice cell size in UV units (v spans the 6 u wall height).
uniform float cell_size : hint_range(0.02, 0.5) = 0.115;
uniform float scroll_speed = 0.010;
uniform float pulse_hz = 0.35;
// Circumference / height for the stock boundary cylinder (2π·120 / 6).
const float ASPECT = 125.664;
const float SQRT3 = 1.7320508;

// Distance inside a hex cell: ~0 at the centre, 0.5 at the edge.
float hex_edge_dist(vec2 p) {
	vec2 r = vec2(1.0, SQRT3);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p + h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	vec2 e = abs(gv);
	return max(e.x * 0.8660254 + e.y * 0.5, e.x);
}

void fragment() {
	// Aspect-corrected, slowly scrolling lattice coordinates.
	vec2 p = vec2(UV.x * ASPECT, UV.y + TIME * scroll_speed) / cell_size;
	float d = hex_edge_dist(p);
	float line = smoothstep(0.42, 0.50, d);
	// Breathing energy + a soft travelling shimmer around the ring.
	float pulse = 0.72 + 0.28 * sin(TAU * pulse_hz * TIME);
	float shimmer = 0.75 + 0.25 * sin((UV.x * TAU * 6.0) - TIME * 0.7);
	// Stronger near the ground, fading out at the top edge.
	float vfade = smoothstep(1.0, 0.55, UV.y) * 0.85 + 0.15;
	// Grazing-angle glow.
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);

	vec3 col = line_color * line * pulse * shimmer * vfade
		+ glow_color * fres * pulse * 0.6;
	float alpha = clamp(line * 0.55 * pulse + fres * 0.35 + 0.04, 0.0, 0.75);
	ALBEDO = col;
	ALPHA = alpha * vfade;
}
