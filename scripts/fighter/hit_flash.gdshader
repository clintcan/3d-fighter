// Hit flash overlay (FighterModel.flash): the tint is added mostly at grazing angles, the
// silhouette's edge, and only `core` of it across the middle, so the fighter keeps their
// shading instead of turning into a flat bright shape.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform float strength = 0.0;
uniform float core = 0.02;

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint * strength * mix(core, 1.0, rim * rim * rim);
}
