// Spectators (Crowd, a MultiMesh): the vertex colours times the per-seat colour, with a
// little life. Each instance sways on its own rhythm, and with `jump` > 0 now and then
// springs up out of its seat (cheering). Purely visual, driven by TIME.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float sway = 0.02; // metres of bob
uniform float jump = 0.0; // metres a cheering spectator rises
uniform float roughness = 0.9;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float phase = hash(id) * 6.2831;
	VERTEX.y += sin(TIME * (1.4 + hash(id + 3.0)) + phase) * sway;
	// A narrow peak of a slow wave: up for a moment roughly every 5-9 s.
	float cheer = pow(max(0.0, sin(TIME * (0.7 + 0.5 * hash(id + 7.0)) + phase * 7.0)), 30.0);
	VERTEX.y += cheer * jump;
}

void fragment() {
	// Vertex and instance colours are sRGB; light in linear space.
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = roughness;
}
