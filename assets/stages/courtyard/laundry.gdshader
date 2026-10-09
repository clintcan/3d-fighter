shader_type spatial;
render_mode cull_disabled;
// Laundry on the lines (build_courtyard_stage.gd): each piece hangs from its top edge
// (UV.y 0) and swings at the hem (UV.y 1) in a light breeze. CourtyardLife raises `gust`
// on knockdowns, supers, K.O.s and the jet's pass, so the washing billows and settles.
// Vertex colour = the cloth's colour.

uniform float breeze = 0.05;
uniform float gust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wind = vec3(0.35, 0.0, 1.0);

void vertex() {
	float hang = UV.y * UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world.x * 1.7 + world.z * 0.9;
	float sway = sin(TIME * 1.6 + phase) * 0.6 + sin(TIME * 2.9 + phase * 1.3) * 0.4;
	float amount = (breeze + gust * 0.4) * hang;
	VERTEX += normalize(wind) * amount * (0.5 + sway);
	VERTEX.y += amount * 0.3 * gust * sin(TIME * 9.0 + phase * 3.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
}
