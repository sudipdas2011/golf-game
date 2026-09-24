shader_type spatial;
render_mode unshaded; // Disables all game lighting, reflections, and shadows

void fragment() {
	// Forces the mesh to output absolute, solid white
	ALBEDO = vec3(1.0, 1.0, 1.0);
}
