// Train stage ground: a static plane whose textures slide by `scroll` metres, so the
// fields and track beds rush past the train. Two track beds of gravel ballast with
// wooden sleepers (our track at z = 0, the other line at z = track2_z), grass fields
// elsewhere with large-scale colour variation (crop patches). Every tiling divides
// TrainMotion.WRAP, so wrapping `scroll` never shows a jump.
shader_type spatial;

uniform float scroll = 0.0;
uniform float track2_z = -4.5;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 gravel_tint : source_color = vec4(1.0);
uniform vec4 sleeper_color : source_color = vec4(0.22, 0.16, 0.11, 1.0);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 inside a track bed (with a soft gravel shoulder), 0 in the fields.
float bed(float z, float center) {
	return 1.0 - smoothstep(1.7, 2.3, abs(z - center));
}

// Sleepers every 0.6 m across the bed, 2.4 m long and 0.24 m wide.
float sleeper(vec2 p, float center) {
	float along = abs(fract(p.x / 0.6) - 0.5) * 0.6;
	return step(along, 0.12) * step(abs(p.y - center), 1.2);
}

void fragment() {
	vec2 p = vec2(world.x + scroll, world.z);
	float track = max(bed(p.y, 0.0), bed(p.y, track2_z));
	vec3 grass = texture(grass_albedo, p / 12.0).rgb * grass_tint.rgb;
	// A patchwork of fields: 60 m along the line (40 per wrap, so it repeats seamlessly),
	// 45 m deep, each a crop picked by a hash: golden wheat, green, ploughed earth or
	// meadow, with crop rows across the line (they make the speed visible) and dark
	// hedgerows between. The verges beside the line stay meadow.
	float field = mod(floor(p.x / 60.0), 40.0);
	float band = floor((p.y + 6.0) / 45.0);
	float h = fract(sin(field * 12.9898 + band * 78.233) * 43758.5453);
	vec3 crop = h < 0.3 ? vec3(1.45, 1.15, 0.55) : (h < 0.6 ? vec3(0.8, 1.15, 0.6) : (h < 0.78 ? vec3(0.95, 0.68, 0.48) : vec3(1.0)));
	float verge = 1.0 - smoothstep(7.0, 9.0, abs(p.y - track2_z * 0.5));
	crop = mix(crop, vec3(1.0), verge);
	float rows = 0.88 + 0.12 * sin(p.x * 4.2);
	grass *= crop * mix(rows, 1.0, verge);
	float edge_x = min(fract(p.x / 60.0), 1.0 - fract(p.x / 60.0)) * 60.0;
	float edge_z = min(fract((p.y + 6.0) / 45.0), 1.0 - fract((p.y + 6.0) / 45.0)) * 45.0;
	float hedge = (1.0 - smoothstep(0.2, 0.6, min(edge_x, edge_z))) * (1.0 - verge);
	grass = mix(grass, vec3(0.1, 0.11, 0.05), hedge * 0.8);
	// Big, soft patches of slightly different colour (period 240 m).
	float patch = texture(grass_albedo, p / 240.0).g;
	grass *= mix(0.85, 1.15, smoothstep(0.2, 0.6, patch));
	vec3 gravel = texture(gravel_albedo, p / 2.4).rgb * gravel_tint.rgb;
	float sleepers = max(sleeper(p, 0.0), sleeper(p, track2_z));
	vec3 color = mix(grass, gravel, track);
	color = mix(color, sleeper_color.rgb, sleepers * track);
	ALBEDO = color;
	NORMAL_MAP = mix(texture(grass_normal, p / 12.0).rgb, texture(gravel_normal, p / 2.4).rgb, track);
	ROUGHNESS = mix(0.95, 0.9, track);
	SPECULAR = 0.25;
}
