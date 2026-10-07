// Train stage scenery that streams past the train (trees, poles, mountains). Every
// object (or MultiMesh instance) slides along -X by `scroll` metres and jumps back by
// `period` once it's half a period behind, so a finite strip of scenery loops forever.
// The jump happens far outside the view. Colour comes from vertex colours times
// `albedo`. Purely visual: TrainMotion sets `scroll` from real time, never the simulation.
shader_type spatial;
render_mode world_vertex_coords, cull_back;

uniform float scroll = 0.0;
uniform float period = 480.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// Distant mountains: drawn as their own colour (already hazed), not lit by the low sun.
uniform bool unlit = false;

void vertex() {
	float origin = MODEL_MATRIX[3].x;
	float moved = mod(origin - scroll + period * 0.5, period) - period * 0.5;
	VERTEX.x += moved - origin;
}

void fragment() {
	if (unlit) {
		ALBEDO = vec3(0.0);
		EMISSION = albedo.rgb * COLOR.rgb;
		SPECULAR = 0.0;
	} else {
		ALBEDO = albedo.rgb * COLOR.rgb;
		SPECULAR = 0.2;
	}
	ROUGHNESS = roughness;
}
