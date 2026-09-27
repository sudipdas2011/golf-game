extends Node3D

var player_cam: Node3D = null
var cam3d: Camera3D = null

# Safe Node Fetching
@onready var p1_mask := $Portal1/Mask1 if has_node("Portal1/Mask1") else null
@onready var p2_mask := $Portal2/Mask2 if has_node("Portal2/Mask2") else null

var p1_pos: Vector3
var p2_pos: Vector3

# Dynamic Viewport Cameras
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
	# 1. Grab Player Camera
	var current_view = get_viewport().get_camera_3d()
	if current_view:
		cam3d = current_view
		player_cam = cam3d.get_parent()
	else:
		cam3d = get_tree().get_first_node_in_group("player_camera") as Camera3D
	
	# 2. Setup Layer 20 Isolation
	if mask1: 
		mask1.layers = 1 << 19 
		mask1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mask2: 
		mask2.layers = 1 << 19 
		mask2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	if cam3d:
		cam3d.cull_mask = cam3d.cull_mask | (1 << 19)
	
	# 3. Setup Portal Cameras (Hide Portal Frames)
	for camera_node in [cam1, cam2]:
		if camera_node:
			camera_node.cull_mask = camera_node.cull_mask & ~(1 << 19)
			var env = camera_node.environment
			if not env:
				env = Environment.new()
				camera_node.environment = env
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 0.0, 0.0, 0.0)

	# 4. Create Materials
	portal_material_1 = ShaderMaterial.new()
	portal_material_1.shader = spatial_portal_shader
	
	portal_material_2 = ShaderMaterial.new()
	portal_material_2.shader = spatial_portal_shader
	
	if mask1: mask1.material_override = portal_material_1
	if mask2: mask2.material_override = portal_material_2
	
	# 5. Disable Auto-Update for Manual Recursion Control
	if renderer1: renderer1.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if renderer2: renderer2.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if not cam3d or not p1_mask or not p2_mask:
		var current_view = get_viewport().get_camera_3d()
		if current_view: cam3d = current_view
		return
	
	# =================================================================
	# FIXED: HARDCODED SNAP-ROTATION LOCKS REMOVED ENTIRELY
	# =================================================================
	
	# --- Draw Portal 1 Orientation Vectors ---
	var p1_origin = p1_mask.global_position
	var p1_z_plus = p1_mask.global_transform.basis.z 
	var p1_z_minus = -p1_mask.global_transform.basis.z 
	var p1_up = p1_mask.global_transform.basis.y 
	
	DebugDraw3D.draw_arrow(p1_origin, p1_origin + p1_z_plus * 2.0, Color.BLUE, 0.1)
	DebugDraw3D.draw_arrow(p1_origin, p1_origin + p1_z_minus * 2.0, Color.RED, 0.1)
	DebugDraw3D.draw_arrow(p1_origin, p1_origin + p1_up * 1.5, Color.YELLOW, 0.1)

	# --- Draw Portal 2 Orientation Vectors ---
	var p2_origin = p2_mask.global_position
	var p2_z_plus = p2_mask.global_transform.basis.z
	var p2_z_minus = -p2_mask.global_transform.basis.z
	var p2_up = p2_mask.global_transform.basis.y
	
	DebugDraw3D.draw_arrow(p2_origin, p2_origin + p2_z_plus * 2.0, Color.BLUE, 0.1)
	DebugDraw3D.draw_arrow(p2_origin, p2_origin + p2_z_minus * 2.0, Color.RED, 0.1)
	DebugDraw3D.draw_arrow(p2_origin, p2_origin + p2_up * 1.5, Color.YELLOW, 0.1)

	projection()


func projection() -> void:
	if not cam3d or not cam1 or not cam2 or not renderer1 or not renderer2:
		return
		
	# Resolution Sync
	var window_size = get_viewport().get_visible_rect().size
	var target_res = Vector2i(window_size)
	if renderer1.size != target_res: renderer1.size = target_res
	if renderer2.size != target_res: renderer2.size = target_res

	portal_material_1.set_shader_parameter("portal_texture", renderer2.get_texture())
	portal_material_2.set_shader_parameter("portal_texture", renderer1.get_texture())

	var main_cam_transform: Transform3D = cam3d.global_transform

	# --- RECURSIVE BOUNCE 1 ---
	_update_portal_camera_transforms(main_cam_transform)
	renderer1.render_target_update_mode = SubViewport.UPDATE_ONCE
	renderer2.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	# --- RECURSIVE BOUNCE 1 ---
	_update_portal_camera_transforms(main_cam_transform)
	renderer1.render_target_update_mode = SubViewport.UPDATE_ONCE
	renderer2.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	# --- RECURSIVE BOUNCE 2 ---
	_update_portal_camera_transforms(main_cam_transform)
	renderer1.render_target_update_mode = SubViewport.UPDATE_ONCE
	renderer2.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	# --- RECURSIVE BOUNCE 3 ---
	_update_portal_camera_transforms(main_cam_transform)
	renderer1.render_target_update_mode = SubViewport.UPDATE_ONCE
	renderer2.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_portal_camera_transforms(main_cam_transform: Transform3D) -> void:
	if not p1_mask or not p2_mask: return
	
	# =================================================================
	# DYNAMIC DUAL-SURFACE REFLECTION LOGIC (Handles Any Rotation angle)
	# =================================================================
	# Construct our local mirroring flip operator matrix
	var flip_matrix = Transform3D.IDENTITY
	flip_matrix.basis.x = -flip_matrix.basis.x
	flip_matrix.basis.z = -flip_matrix.basis.z

	# --- Update CAM2 (Tracks Portal 1 Input -> Displays on Portal 2) ---
	var p1_local_cam = p1_mask.global_transform.affine_inverse() * main_cam_transform
	p1_local_cam = flip_matrix * p1_local_cam
	if cam2:
		cam2.global_transform = p2_mask.global_transform * p1_local_cam

	# --- Update CAM1 (Tracks Portal 2 Input -> Displays on Portal 1) ---
	var p2_local_cam = p2_mask.global_transform.affine_inverse() * main_cam_transform
	p2_local_cam = flip_matrix * p2_local_cam
	if cam1:
		cam1.global_transform = p1_mask.global_transform * p2_local_cam
