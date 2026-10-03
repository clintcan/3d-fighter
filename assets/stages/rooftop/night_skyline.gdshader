shader_type sky;
// Night city sky for the rooftop stage. The skyline is a cropped band (horizon up to
// `top_elevation` degrees) of the equirectangular Shanghai Bund panorama (Poly Haven,
// CC0); above it the sky fades to a flat night color, and below the horizon a hazy
// city glow with scattered lights suggests the streets far below the roof.
// The panorama was shot at street level, so only its distant skyline section (between
// `section_start` and `section_end`, no nearby trees or buildings) is used, mirrored
// twice around the horizon.

uniform sampler2D skyline : source_color, filter_linear_mipmap, repeat_enable;
uniform float top_elevation = 55.0; // degrees at the band's top row
uniform float u_offset = 0.8; // turns the sky so the main towers sit behind the fight
uniform float section_start = 0.335;
uniform float section_end = 0.805;
uniform vec3 zenith_color : source_color = vec3(0.27, 0.25, 0.36);
uniform vec3 haze_color : source_color = vec3(0.2, 0.15, 0.22);
uniform float energy = 1.0;
uniform float city_light_density = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float elevation = degrees(asin(clamp(dir.y, -1.0, 1.0)));
	float around = fract(atan(dir.x, -dir.z) / TAU + 0.5 + u_offset) * 2.0;
	float f = fract(around);
	if (mod(floor(around), 2.0) > 0.5) {
		f = 1.0 - f; // mirrored copy, so the seams match
	}
	float u = mix(section_start, section_end, f);
	vec3 horizon = texture(skyline, vec2(u, 0.995)).rgb;
	vec3 color;
	if (elevation >= 0.0) {
		float v = 1.0 - elevation / top_elevation; // 0 = top of the band, 1 = horizon
		vec3 band = texture(skyline, vec2(u, clamp(v, 0.002, 0.995))).rgb;
		color = mix(band, zenith_color, smoothstep(top_elevation - 12.0, top_elevation, elevation));
	} else {
		float depth = clamp(-elevation / 25.0, 0.0, 1.0);
		vec3 base = mix(haze_color, haze_color * 0.2, depth);
		vec2 cell = floor(vec2(u * 1800.0, -elevation * 30.0));
		float lit = step(1.0 - city_light_density, hash(cell)) * (1.0 - depth);
		vec3 light_color = mix(vec3(1.0, 0.72, 0.38), vec3(0.6, 0.8, 1.0), hash(cell + 7.0));
		color = base + light_color * lit * 0.9;
		color = mix(horizon * 0.8, color, smoothstep(0.0, 2.0, -elevation));
	}
	COLOR = color * energy;
}
