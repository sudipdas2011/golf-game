shader_type canvas_item;

uniform sampler2D cam_texture;
uniform sampler2D mask_texture;

void fragment() {
	vec4 cam = texture(cam_texture, UV);
	float mask = texture(mask_texture, UV).r;

	COLOR = vec4(cam.rgb * mask, 1.0);
}