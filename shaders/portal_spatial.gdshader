shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D portal_texture : source_color, filter_linear, repeat_disable;
uniform float brightness = 1.0;  // < 1 for deeper recursion copies

uniform mat4 portal_map;        // world (at display portal) -> world (at source portal)
uniform mat4 portal_view_proj;  // virtual camera projection * view

void fragment() {
	vec4 world = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);

	vec4 clip = portal_view_proj * (portal_map * world);
	if (clip.w <= 0.00001) {
		discard;
	}

	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	uv.y = 1.0 - uv.y;
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	vec4 color = texture(portal_texture, uv);
	ALBEDO = color.rgb * brightness;
}
