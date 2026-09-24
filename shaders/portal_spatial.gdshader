shader_type spatial;
// DISABLE CULLING: This renders both the Front and Back faces of the mesh
render_mode unshaded, cull_disabled; 

uniform sampler2D portal_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	// 1. Calculate screen coordinates
	vec2 proj_uv = SCREEN_UV;
	
	// 2. Sample the camera view
	// Because the camera physically moves behind the portal in the script,
	// this texture will automatically show the "back" of the destination room!
	vec4 color = texture(portal_texture, proj_uv);
	
	// 3. Output the view
	ALBEDO = color.rgb;
}
