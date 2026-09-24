shader_type canvas_item;

// Passes the live custom masking ViewportTextures from the Node3D script
uniform sampler2D whole_mask : hint_default_white;
uniform sampler2D occlude_mask : hint_default_white;

void fragment() {
    // 1. Fetch the raw background perspective from the live portal viewport camera
    vec4 base_render = texture(TEXTURE, UV);
    
    // 2. Read mask pixel channels (Using the red channel value)
    float mask_w = texture(whole_mask, UV).r;
    float mask_o = texture(occlude_mask, UV).r;
    
    // 3. Execute math pipeline equations: Render x WholeMask x OccludeMask
    vec3 final_color = base_render.rgb * mask_w * mask_o;
    float final_alpha = base_render.a * mask_w * mask_o;
    
    // 4. Output the masked composition directly onto the screen UI
    COLOR = vec4(final_color, final_alpha);
}
