shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D portal_texture : source_color, filter_linear, repeat_disable;
uniform vec4 fallback_color : source_color = vec4(0.0, 0.4, 0.8, 1.0);

uniform mat4 portal_map;        // world (at display portal) -> world (at source portal)
uniform mat4 portal_view_proj;  // virtual camera projection * view

void fragment() {
	// fragment on the display portal, in world space
	vec4 world = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);

	// same point seen from the other side of the portal pair, through the virtual camera
	vec4 clip = portal_view_proj * (portal_map * world);
	if (clip.w <= 0.00001) {
		discard;
	}

	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	uv.y = 1.0 - uv.y;
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	vec4 color = texture(portal_texture, uv);
	ALBEDO = mix(fallback_color.rgb, color.rgb, color.a);
}
