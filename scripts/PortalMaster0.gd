extends Node3D


var cam3d: Camera3D = null

@onready var p1_mask: Node3D = get_node_or_null("Portal1/Mask1") as Node3D
@onready var p2_mask: Node3D = get_node_or_null("Portal2/Mask2") as Node3D

@onready var mask1: GeometryInstance3D = get_node_or_null("%Mask1") as GeometryInstance3D
@onready var mask2: GeometryInstance3D = get_node_or_null("%Mask2") as GeometryInstance3D

@onready var renderer1: SubViewport = get_node_or_null("%Renderer1") as SubViewport
@onready var renderer2: SubViewport = get_node_or_null("%Renderer2") as SubViewport

@onready var cam1: Camera3D = get_node_or_null("%CAM1") as Camera3D
@onready var cam2: Camera3D = get_node_or_null("%CAM2") as Camera3D

var portal_material_1: ShaderMaterial
var portal_material_2: ShaderMaterial

var spatial_portal_shader: Shader = preload(
	"res://shaders/portal_spatial.gdshader"
)

const PORTAL_LAYER: int = 1 << 19


func _ready() -> void:
	process_priority = 1000

	_resolve_main_camera()

	if mask1:
		mask1.layers = PORTAL_LAYER
		mask1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if mask2:
		mask2.layers = PORTAL_LAYER
		mask2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if cam3d:
		cam3d.cull_mask |= PORTAL_LAYER

	_configure_portal_camera(cam1)
	_configure_portal_camera(cam2)

	portal_material_1 = ShaderMaterial.new()
	portal_material_1.shader = spatial_portal_shader

	portal_material_2 = ShaderMaterial.new()
	portal_material_2.shader = spatial_portal_shader

	if mask1:
		mask1.material_override = portal_material_1

	if mask2:
		mask2.material_override = portal_material_2

	if renderer1:
		renderer1.render_target_update_mode = SubViewport.UPDATE_DISABLED
		renderer1.world_3d = get_viewport().world_3d

	if renderer2:
		renderer2.render_target_update_mode = SubViewport.UPDATE_DISABLED
		renderer2.world_3d = get_viewport().world_3d

	_sync_viewport_size()


func _configure_portal_camera(camera: Camera3D) -> void:
	if not camera:
		return

	camera.cull_mask &= ~PORTAL_LAYER

	var env: Environment = camera.environment

	if not env:
		env = Environment.new()
		camera.environment = env

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)


func _resolve_main_camera() -> void:
	var active_camera: Camera3D = get_viewport().get_camera_3d()

	if active_camera:
		cam3d = active_camera


func _process(_delta: float) -> void:
	_resolve_main_camera()

	if not cam3d:
		return

	if not p1_mask or not p2_mask:
		return

	if not cam1 or not cam2:
		return

	if not renderer1 or not renderer2:
		return

	var p1_origin: Vector3 = p1_mask.global_position
	var p1_basis: Basis = p1_mask.global_transform.basis
	var p2_origin: Vector3 = p2_mask.global_position
	var p2_basis: Basis = p2_mask.global_transform.basis

	DebugDraw3D.draw_arrow(p1_origin, p1_origin + p1_basis.z * 2.0, Color.DEEP_SKY_BLUE, 0.1)
	DebugDraw3D.draw_arrow(p1_origin, p1_origin - p1_basis.z * 2.0, Color.ORANGE_RED, 0.1)
	DebugDraw3D.draw_arrow(p1_origin, p1_origin + p1_basis.y * 1.5, Color.YELLOW, 0.1)

	DebugDraw3D.draw_arrow(p2_origin, p2_origin + p2_basis.z * 2.0, Color.DEEP_SKY_BLUE, 0.1)
	DebugDraw3D.draw_arrow(p2_origin, p2_origin - p2_basis.z * 2.0, Color.ORANGE_RED, 0.1)
	DebugDraw3D.draw_arrow(p2_origin, p2_origin + p2_basis.y * 1.5, Color.YELLOW, 0.1)

	projection()


func projection() -> void:
	if not cam3d or not cam1 or not cam2:
		return

	_sync_viewport_size()

	var main_cam_transform: Transform3D = cam3d.get_camera_transform()

	_sync_camera_projection(cam3d, cam1)
	_sync_camera_projection(cam3d, cam2)

	cam1.global_transform = _map_camera_through_portal(
		main_cam_transform,
		p2_mask,
		p1_mask
	)

	cam2.global_transform = _map_camera_through_portal(
		main_cam_transform,
		p1_mask,
		p2_mask
	)

	cam1.force_update_transform()
	cam2.force_update_transform()

	portal_material_1.set_shader_parameter(
		"portal_texture",
		renderer2.get_texture()
	)

	portal_material_2.set_shader_parameter(
		"portal_texture",
		renderer1.get_texture()
	)

	renderer1.render_target_update_mode = SubViewport.UPDATE_ONCE
	renderer2.render_target_update_mode = SubViewport.UPDATE_ONCE


func _map_camera_through_portal(
	camera_transform: Transform3D,
	source_portal: Node3D,
	destination_portal: Node3D
) -> Transform3D:

	var source_transform: Transform3D = _rigid_transform(source_portal)
	var destination_transform: Transform3D = _rigid_transform(destination_portal)

	var local_camera: Transform3D = (
		source_transform.affine_inverse() *
		camera_transform
	)

	var flip: Transform3D = Transform3D.IDENTITY
	flip.basis.x = -flip.basis.x
	flip.basis.z = -flip.basis.z

	local_camera = flip * local_camera

	return destination_transform * local_camera


func _rigid_transform(node: Node3D) -> Transform3D:
	var basis: Basis = node.global_transform.basis.orthonormalized()

	return Transform3D(
		basis,
		node.global_position
	)


func _sync_camera_projection(
	main_camera: Camera3D,
	portal_camera: Camera3D
) -> void:

	if not main_camera or not portal_camera:
		return

	portal_camera.projection = main_camera.projection
	portal_camera.near = main_camera.near
	portal_camera.far = main_camera.far
	portal_camera.keep_aspect = main_camera.keep_aspect

	if main_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		portal_camera.fov = main_camera.fov
	else:
		portal_camera.size = main_camera.size
		portal_camera.frustum_offset = main_camera.frustum_offset


func _sync_viewport_size() -> void:
	if not renderer1 or not renderer2:
		return

	var window_size: Vector2 = get_viewport().get_visible_rect().size
	var target_size: Vector2i = Vector2i(
		maxi(2, int(window_size.x)),
		maxi(2, int(window_size.y))
	)

	if renderer1.size != target_size:
		renderer1.size = target_size

	if renderer2.size != target_size:
		renderer2.size = target_size
