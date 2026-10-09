shader_type spatial;
// Neighbours and pigeons (CourtyardLife's MultiMeshes): vertex colours carry skin, hair
// and trousers, and the alpha marks the shirt, which takes the instance's custom colour.

varying vec3 tint;

void vertex() {
	tint = mix(COLOR.rgb, INSTANCE_CUSTOM.rgb, COLOR.a);
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
}
