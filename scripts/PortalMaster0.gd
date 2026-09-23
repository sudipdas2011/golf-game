extends Node3D

#####
@export var P1_rot : Vector3
@export var P2_rot : Vector3
#####

##############################
# Auto-managed render/visibility layers.
# These bits are reserved for portal masks only — _ready() stamps them
# onto the mask meshes and derives every camera's cull_mask from them,
# so nothing needs to be hand-set in the .tscn and re-parenting/renaming
# nodes can't silently desync a cull_mask again.
##############################
const MASK1_LAYER_BIT: int = 3  # 1-based Godot layer number (layer 4)
const MASK2_LAYER_BIT: int = 4  # 1-based Godot layer number (layer 5)

# GLSL source for the live portal-surface shader, built and assigned at
# runtime in configure_portal_view_shaders(). Renders what the OTHER
# portal's render-camera sees, clipped to this portal's mask silhouette,
# projected in screen space so it looks correct from any viewing angle.
const PORTAL_VIEW_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D cam_texture : source_color, filter_linear;
uniform sampler2D mask_texture : source_color, filter_linear;

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec4 cam = texture(cam_texture, screen_uv);
	float mask = texture(mask_texture, screen_uv).r;

	if (mask < 0.5) {
		discard;
	}

	ALBEDO = cam.rgb;
}
"""

@onready var player_cam: PlayerCamera = $PlayerCamera
@onready var cam3d: Camera3D = get_node("../PlayerCamera/Camera3D")

@onready var p1_mask := $Portal1/Mask
@onready var p2_mask := $Portal2/Mask

##############################
##############################

@onready var cam1: Camera3D = %CAM1
@onready var cam2: Camera3D = %CAM2

@onready var render_viewport1: SubViewport = $RenderViewport1
@onready var render_viewport2: SubViewport = $RenderViewport2

@onready var render_cam1: Camera3D = $RenderViewport1/RenderCam1
@onready var render_cam2: Camera3D = $RenderViewport2/RenderCam2

var cam1_render: Texture2D
var cam2_render: Texture2D

@onready var mask_viewport1: SubViewport = $MaskViewport1
@onready var mask_cam1: Camera3D = $MaskViewport1/MaskCam1

@onready var mask_viewport2: SubViewport = $MaskViewport2
@onready var mask_cam2: Camera3D = $MaskViewport2/MaskCam2

var mask1_render: Texture2D
var mask2_render: Texture2D

@onready var debug_material: ShaderMaterial = $CanvasLayer/DebugRender.material

# Runtime-built portal-surface materials, auto-assigned to the Mask quads
# in configure_portal_view_shaders(). Portal1's surface shows what
# RenderCam2 sees (the view through Portal2), and vice versa.
var portal1_view_material: ShaderMaterial
var portal2_view_material: ShaderMaterial

##############################
##############################


var p1_pos: Vector3
var p2_pos: Vector3

var cam1_pos: Vector3
var cam2_pos: Vector3


func _ready() -> void:
	#####
	P1_rot = %Portal1.rotation
	P2_rot = %Portal2.rotation
	#####
	
	# Make the render viewports use the same 3D world as the main viewport.
	render_viewport1.world_3d = get_viewport().world_3d
	render_viewport2.world_3d = get_viewport().world_3d
	
	resize_viewports()
	get_viewport().size_changed.connect(resize_viewports)
	#####
	render_viewport1.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	#####
	mask_viewport1.world_3d = get_viewport().world_3d
	mask_viewport1.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_viewport1.transparent_bg = true
	#####
	mask_viewport2.world_3d = get_viewport().world_3d
	mask_viewport2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_viewport2.transparent_bg = true
	#####
	configure_portal_layers()
	configure_portal_view_shaders()


func configure_portal_view_shaders() -> void:
	# Build one shared Shader resource and two independent ShaderMaterial
	# instances (each portal needs its own uniform values) at runtime,
	# then assign them as material_override on the mask quads — this is
	# the surface the player actually sees when looking at a portal.
	var portal_shader := Shader.new()
	portal_shader.code = PORTAL_VIEW_SHADER_CODE

	portal1_view_material = ShaderMaterial.new()
	portal1_view_material.shader = portal_shader
	p1_mask.material_override = portal1_view_material

	portal2_view_material = ShaderMaterial.new()
	portal2_view_material.shader = portal_shader
	p2_mask.material_override = portal2_view_material


func configure_portal_layers() -> void:
	# 1. Stamp each mask mesh with its own dedicated, exclusive layer bit.
	#    This overrides whatever was set by hand in the .tscn so the two
	#    masks can never collide on the same bit again.
	p1_mask.layers = 0
	p1_mask.set_layer_mask_value(MASK1_LAYER_BIT, true)

	p2_mask.layers = 0
	p2_mask.set_layer_mask_value(MASK2_LAYER_BIT, true)

	# 2. Render cameras should see the normal world PLUS both masks, but
	#    never the mask belonging to the portal on the other side of the
	#    render (avoids feeding a mask quad back into its own render).
	#    Layer 1 is Godot's default world layer.
	var render1_mask := 0
	render1_mask |= 1  # default/world layer
	render1_mask |= (1 << MASK1_LAYER_BIT)
	render_cam1.cull_mask = render1_mask

	var render2_mask := 0
	render2_mask |= 1
	render2_mask |= (1 << MASK2_LAYER_BIT)
	render_cam2.cull_mask = render2_mask

	# 3. Mask cameras must see ONLY their own portal's mask quad — nothing
	#    else — so the rendered mask texture is a clean silhouette.
	mask_cam1.cull_mask = (1 << MASK1_LAYER_BIT)
	mask_cam2.cull_mask = (1 << MASK2_LAYER_BIT)


func _process(delta: float) -> void:
	
	#DebugDraw2D.set_text("Screen Size : ", screen_size)

	
	#####
	%Portal1.rotation = P1_rot
	%Portal2.rotation = P2_rot
	#####
	
	# 1. Update Portal Origins
	p1_pos = p1_mask.global_position
	p2_pos = p2_mask.global_position

	# 2. Calculate Half-Widths
	var p1_half: float = p1_mask.mesh.size.x / 2.0
	var p2_half: float = p2_mask.mesh.size.x / 2.0

	# 3. Get Portal Edges in World Space (Basis-aware)
	var p1_left: Vector3 = p1_pos - p1_mask.global_transform.basis.x * p1_half
	var p1_right: Vector3 = p1_pos + p1_mask.global_transform.basis.x * p1_half

	var p2_left: Vector3 = p2_pos - p2_mask.global_transform.basis.x * p2_half
	var p2_right: Vector3 = p2_pos + p2_mask.global_transform.basis.x * p2_half

	# 4. Get Primary Camera Position & Transform, and assign to $Portal1/CAM1
	var cam1_transform: Transform3D = cam3d.global_transform
	$Portal1/CAM1.global_transform = cam1_transform
	cam1_pos = cam1_transform.origin
	

	# 5. Exact Portal Camera Transform & Position Match (Flipping Local X & Z)
	var local_cam: Transform3D = p1_mask.global_transform.affine_inverse() * cam1_transform
	local_cam.origin.x = -local_cam.origin.x
	local_cam.origin.z = -local_cam.origin.z
	
	# Rotate basis 180 deg around local Y to match camera facing direction
	local_cam.basis = local_cam.basis.rotated(Vector3.UP, PI)

	# Apply to Portal 2 and update CAM2 node
	$Portal2/CAM2.global_transform = p2_mask.global_transform * local_cam
	cam2_pos = $Portal2/CAM2.global_position

	# Sync render cameras AFTER portal camera transforms are updated
	sync_render_cams()
	sync_mask_cam1()
	sync_mask_cam2()
	update_portal_view_materials()

	# 6. Debug Visualizations	
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_left), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_right), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_pos), Color.WHITE)

	DebugDraw3D.draw_position(Transform3D(Basis(), p2_left), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p2_right), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p2_pos), Color.WHITE)

	DebugDraw3D.draw_position(Transform3D(Basis(), cam1_pos), Color.GOLD)
	DebugDraw3D.draw_position(Transform3D(Basis(), cam2_pos), Color.GOLD)

	# 7. Draw Top-Down Directional Arrows for Cameras
	var cam1_dir: Vector3 = -cam1_transform.basis.z * 3.0
	var cam2_dir: Vector3 = -$Portal2/CAM2.global_transform.basis.z * 3.0

	#DebugDraw3D.draw_arrow(cam1_pos, cam1_pos + cam1_dir, Color.GOLD, 0.4)
	#DebugDraw3D.draw_arrow(cam2_pos, cam2_pos + cam2_dir, Color.GOLD, 0.4)

	#DebugDraw3D.draw_camera_frustum($Portal1/CAM1, Color.WHITE)
	#DebugDraw3D.draw_camera_frustum($Portal2/CAM2, Color.GOLD)
	
	# Run diagnostic print
	_verify_camera_positions()

	$CanvasLayer/DebugRender.texture = mask2_render


func sync_render_cams() -> void:
	# Sync RenderCam1 with Portal1/CAM1
	if is_instance_valid(render_cam1):
		render_cam1.global_transform = $Portal1/CAM1.global_transform
		render_cam1.fov = $Portal1/CAM1.fov
		render_cam1.near = $Portal1/CAM1.near
		render_cam1.far = $Portal1/CAM1.far

	# Sync RenderCam2 with Portal2/CAM2
	if is_instance_valid(render_cam2):
		render_cam2.global_transform = $Portal2/CAM2.global_transform
		render_cam2.fov = $Portal2/CAM2.fov
		render_cam2.near = $Portal2/CAM2.near
		render_cam2.far = $Portal2/CAM2.far

	# Get rendered textures
	if is_instance_valid(render_viewport1):
		cam1_render = render_viewport1.get_texture()
	
	if is_instance_valid(render_viewport2):
		cam2_render = render_viewport2.get_texture()
	
	
func resize_viewports() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	print(screen_size)

	render_viewport1.size = screen_size
	render_viewport2.size = screen_size
	
	mask_viewport1.size = screen_size
	mask_viewport2.size = screen_size
	
	
func sync_mask_cam1() -> void:
	mask_cam1.global_transform = $Portal1/CAM1.global_transform
	mask_cam1.fov = $Portal1/CAM1.fov
	mask_cam1.near = $Portal1/CAM1.near
	mask_cam1.far = $Portal1/CAM1.far

	mask1_render = mask_viewport1.get_texture()


func sync_mask_cam2() -> void:
	mask_cam2.global_transform = $Portal2/CAM2.global_transform
	mask_cam2.fov = $Portal2/CAM2.fov
	mask_cam2.near = $Portal2/CAM2.near
	mask_cam2.far = $Portal2/CAM2.far

	mask2_render = mask_viewport2.get_texture()


func update_portal_view_materials() -> void:
	# Portal1's surface shows what lies beyond Portal2 (RenderCam2's feed),
	# clipped to Portal1's own mask silhouette — and vice versa.
	if is_instance_valid(portal1_view_material) and is_instance_valid(cam2_render) and is_instance_valid(mask1_render):
		portal1_view_material.set_shader_parameter("cam_texture", cam2_render)
		portal1_view_material.set_shader_parameter("mask_texture", mask1_render)

	if is_instance_valid(portal2_view_material) and is_instance_valid(cam1_render) and is_instance_valid(mask2_render):
		portal2_view_material.set_shader_parameter("cam_texture", cam1_render)
		portal2_view_material.set_shader_parameter("mask_texture", mask2_render)
	
	
func _verify_camera_positions() -> void:
	return
	var dist_cam1_to_p1: float = cam1_pos.distance_to(p1_pos)
	var dist_cam2_to_p2: float = cam2_pos.distance_to(p2_pos)

	print_rich("[color=yellow]--- CAMERA DIAGNOSTICS ---[/color]")
	print("CAM1 Pos: ", cam1_pos, " | Distance to Portal 1: ", dist_cam1_to_p1)
	print("CAM2 Pos: ", cam2_pos, " | Distance to Portal 2: ", dist_cam2_to_p2)

	if is_equal_approx(dist_cam1_to_p1, dist_cam2_to_p2):
		print_rich("[color=green]STATUS: Working correctly (Distances match!)[/color]")
	else:
		print_rich("[color=red]STATUS: Distance mismatch detected![/color]")
