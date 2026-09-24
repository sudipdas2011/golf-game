shader_type spatial;
render_mode unshaded, cull_disabled; 

uniform sampler2D portal_texture : source_color, filter_linear_mipmap, repeat_disable;
// The professional cheat: this tint color masks where the 3-bounce rendering depth stops
uniform vec4 fallback_color : source_color = vec4(0.0, 0.4, 0.8, 1.0); 

void fragment() {
	vec2 proj_uv = SCREEN_UV;
	vec4 color = texture(portal_texture, proj_uv);
	
	// If the viewport rendering loop stops, smoothly fade into the portal fog color
	ALBEDO = mix(color.rgb, fallback_color.rgb, 1.0 - color.a);
}
