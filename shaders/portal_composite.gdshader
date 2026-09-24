shader_type canvas_item;

// This uniform receives the live black-and-white stencil pass from GDScript
uniform sampler2D mask_viewport_texture : hint_default_black;

void fragment() {
	// 1. Sample the live camera render view at the current UI coordinate
	vec4 base_render = texture(TEXTURE, UV);
	
	// 2. Sample the white/black mask texture at the exact same coordinate
	// White portal frame = 1.0, Black environmental background = 0.0
	float mask_value = texture(mask_viewport_texture, UV).r;
	
	// 3. Keep the rgb colors intact, but multiply alpha by the mask.
	// This makes everything outside the portal frame 100% transparent!
	COLOR = vec4(base_render.rgb, base_render.a * mask_value);
}
