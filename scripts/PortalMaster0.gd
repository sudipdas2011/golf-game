extends Node3D

#####
@export var P1_rot : Vector3
@export var P2_rot : Vector3
#####

var player_cam: Node3D = null
var cam3d: Camera3D = null

# Safe Node Fetching
@onready var p1_mask := $Portal1/Mask1 if has_node("Portal1/Mask1") else null
@onready var p2_mask := $Portal2/Mask2 if has_node("Portal2/Mask2") else null

var p1_pos: Vector3
var p2_pos: Vector3

# Dynamic Viewport Cameras (These will move to Front OR Back automatically)
@onready var renderer1: SubViewport = %Renderer1 if has_node("%Renderer1") else null
@onready var renderer2: SubViewport = %Renderer2 if has_node("%Renderer2") else null

@onready var cam1 := %CAM1 if has_node("%CAM1") else null
@onready var cam2 := %CAM2 if has_node("%CAM2") else null

@onready var mask1 := %Mask1 if has_node("%Mask1") else ($Portal1/Mask1 if has_node("Portal1/Mask1") else null)
@onready var mask2 := %Mask2 if has_node("%Mask2") else ($Portal2/Mask2 if has_node("Portal2/Mask2") else null)

var portal_material_1 : ShaderMaterial
var portal_material_2 : ShaderMaterial
var spatial_portal_shader = preload("res://shaders/portal_spatial.gdshader")

func _ready() -> void:
	# Set rotations if nodes exist
	if has_node("%Portal1"): %Portal1.rotation = P1_rot
	if has_node("%Portal2"): %Portal2.rotation = P2_rot
	
	# 1. Grab Player Camera
	var current_view = get_viewport().get_camera_3d()
	if current_view:
		cam3d = current_view
		player_cam = cam3d.get_parent()
	else:
		cam3d = get_tree().get_first_node_in_group("player_camera") as Camera3D
	
	# 2. Setup Layer 20 Isolation (The "Invisible" Layer)
	# This hides the white portal sheets from the main camera so they don't block the view
	# BUT we keep them visible to the shader logic.
	
	# Actually, for Spatial Shaders, we usually WANT the main camera to see Layer 20
	# so it can render the shader surface.
	if mask1: 
		mask1.layers = 1 << 19 # Layer 20
		# Disable shadows on the portal mesh to prevent weird self-shadowing on the back
		mask1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
	if mask2: 
		mask2.layers = 1 << 19 # Layer 20
		mask2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Main Camera MUST see Layer 20 to render the portal surface
	if cam3d:
		cam3d.cull_mask = cam3d.cull_mask | (1 << 19)
	
	# 3. Setup Portal Cameras (The "Eyes")
	# These cameras must NOT see Layer 20 (The Portal Frames) to prevent "Hall of Mirrors"
	for camera_node in [cam1, cam2]:
		if camera_node:
			camera_node.cull_mask = camera_node.cull_mask & ~(1 << 19)
			
			var env = camera_node.environment
			if not env:
				env = Environment.new()
				camera_node.environment = env
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color.BLACK

	# 4. Create & Assign Materials
	portal_material_1 = ShaderMaterial.new()
	portal_material_1.shader = spatial_portal_shader
	
	portal_material_2 = ShaderMaterial.new()
	portal_material_2.shader = spatial_portal_shader
	
	if mask1: mask1.material_override = portal_material_1
	if mask2: mask2.material_override = portal_material_2
	
	# 5. Force Always Update
	if renderer1: renderer1.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if renderer2: renderer2.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(delta: float) -> void:
	if not cam3d or not p1_mask or not p2_mask:
		var current_view = get_viewport().get_camera_3d()
		if current_view: cam3d = current_view
		return
		
	if has_node("%Portal1"): %Portal1.rotation = P1_rot
	if has_node("%Portal2"): %Portal2.rotation = P2_rot
	
	var main_cam_transform: Transform3D = cam3d.global_transform

	# =================================================================
	# DOUBLE-SIDED MATRIX TRACKING SYSTEM
	# =================================================================
	# This math calculates the relative position of the player to Portal 1.
	# If the player is BEHIND Portal 1, 'local_cam1' naturally reflects that (negative Z).
	# When applied to Portal 2, the camera ('cam2') automatically moves BEHIND Portal 2.
	# This allows you to look through the "back" of the portal without extra cameras!
	
	# --- Update CAM2 (The eye for Portal 1) ---
	var local_cam1: Transform3D = p1_mask.global_transform.affine_inverse() * main_cam_transform
	
	# Standard Portal Flip Logic (Rotate 180 degrees)
	local_cam1.origin.x = -local_cam1.origin.x
	local_cam1.origin.z = -local_cam1.origin.z
	local_cam1.basis = local_cam1.basis.rotated(Vector3.UP, PI)
	
	if cam2:
		# Apply this relative offset to Portal 2
		cam2.global_transform = p2_mask.global_transform * local_cam1
		
		# NEAR CLIP PLANE FIX:
		# If the camera gets too close to the portal surface, it might clip.
		# A small offset or oblique plane helps, but for now we rely on the shader depth.

	# --- Update CAM1 (The eye for Portal 2) ---
	var local_cam2: Transform3D = p2_mask.global_transform.affine_inverse() * main_cam_transform
	
	local_cam2.origin.x = -local_cam2.origin.x
	local_cam2.origin.z = -local_cam2.origin.z
	local_cam2.basis = local_cam2.basis.rotated(Vector3.UP, PI)
	
	if cam1:
		cam1.global_transform = p1_mask.global_transform * local_cam2
		
	projection()
	
	
func projection() -> void:
	# Resolution Sync
	var window_size = get_viewport().get_visible_rect().size
	var target_res = Vector2i(window_size)
	
	if renderer1 and renderer1.size != target_res: renderer1.size = target_res
	if renderer2 and renderer2.size != target_res: renderer2.size = target_res

	# Texture Linking
	if portal_material_1 and renderer2:
		portal_material_1.set_shader_parameter("portal_texture", renderer2.get_texture())
		
	if portal_material_2 and renderer1:
		portal_material_2.set_shader_parameter("portal_texture", renderer1.get_texture())
