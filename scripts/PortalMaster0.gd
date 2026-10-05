extends Node3D


# ============================================================
# MAIN CAMERA
# ============================================================

var cam3d: Camera3D = null


# ============================================================
# PORTAL GEOMETRY
# ============================================================

@onready var p1_mask = get_node_or_null("Portal1/Mask1")
@onready var p2_mask = get_node_or_null("Portal2/Mask2")

@onready var mask1 = get_node_or_null("%Mask1")
@onready var mask2 = get_node_or_null("%Mask2")


# ============================================================
# PORTAL CAMERAS
# ============================================================

@onready var cam1: Camera3D = get_node_or_null("%CAM1") as Camera3D
@onready var cam2: Camera3D = get_node_or_null("%CAM2") as Camera3D


# ============================================================
# PORTAL VIEWPORTS
# ============================================================

@onready var renderer1: SubViewport = get_node_or_null("%Renderer1") as SubViewport
@onready var renderer2: SubViewport = get_node_or_null("%Renderer2") as SubViewport


# ============================================================
# MATERIALS
# ============================================================

var portal_material_1: ShaderMaterial
var portal_material_2: ShaderMaterial

var spatial_portal_shader = preload(
	"res://shaders/portal_spatial.gdshader"
)


# ============================================================
# CONSTANTS
# ============================================================

const PORTAL_LAYER := 1 << 19


func _ready() -> void:

	# Run portal update AFTER the normal camera/player processing.
	#
	# Lower process priority executes first.
	# High priority here means we sample the camera after
	# its smoothing / FOV responsiveness has finished.
	process_priority = 1000


	# ========================================================
	# FIND ACTIVE CAMERA
	# ========================================================

	_resolve_main_camera()


	# ========================================================
	# PORTAL MASK LAYER
	# ========================================================

	if mask1:
		mask1.layers = PORTAL_LAYER
		mask1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if mask2:
		mask2.layers = PORTAL_LAYER
		mask2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


	# Main camera MUST be able to see the portal surfaces.

	if cam3d:
		cam3d.cull_mask |= PORTAL_LAYER


	# ========================================================
	# PORTAL CAMERAS
	# ========================================================

	_configure_portal_camera(cam1)
	_configure_portal_camera(cam2)


	# ========================================================
	# MATERIALS
	# ========================================================

	portal_material_1 = ShaderMaterial.new()
	portal_material_1.shader = spatial_portal_shader

	portal_material_2 = ShaderMaterial.new()
	portal_material_2.shader = spatial_portal_shader


	if mask1:
		mask1.material_override = portal_material_1

	if mask2:
		mask2.material_override = portal_material_2


	# ========================================================
	# MANUAL RENDERING
	# ========================================================

	if renderer1:
		renderer1.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if renderer2:
		renderer2.render_target_update_mode = SubViewport.UPDATE_DISABLED


	# Make both portal viewports render the same world.

	var main_viewport := get_viewport()

	if main_viewport.world_3d:
		if renderer1:
			renderer1.world_3d = main_viewport.world_3d

		if renderer2:
			renderer2.world_3d = main_viewport.world_3d


	_sync_viewport_size()


func _configure_portal_camera(camera: Camera3D) -> void:
	#var env: Environment = camera_node.environment

	if not camera:
		return

	# Portal cameras must NOT see the portal masks themselves.
	camera.cull_mask &= ~PORTAL_LAYER

	# Transparent background.
	var env: Environment = camera.environment

	if not env:
		env = Environment.new()
		camera.environment = env

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)


func _resolve_main_camera() -> void:

	var active_camera := get_viewport().get_camera_3d()

	if active_camera:
		cam3d = active_camera


func _process(_delta: float) -> void:

	# --------------------------------------------------------
	# Always re-check the active camera.
	# Useful if cameras are switched during gameplay.
	# --------------------------------------------------------

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


# ============================================================
# MAIN PORTAL PROJECTION
# ============================================================

func projection() -> void:

	if not cam3d:
		return

	# --------------------------------------------------------
	# Match viewport size.
	# --------------------------------------------------------

	_sync_viewport_size()


	# --------------------------------------------------------
	# IMPORTANT:
	#
	# Use the camera's FINAL camera transform.
	#
	# This is better for your smoothed camera than reading
	# the player's physics transform.
	#
	# get_camera_transform() includes camera offsets and
	# adjustments used by Camera3D.
	# --------------------------------------------------------

	var main_cam_transform: Transform3D = (
		cam3d.get_camera_transform()
	)


	# --------------------------------------------------------
	# Match the optical/projection parameters.
	#
	# We do NOT run the player's camera system again.
	# We only copy the values required to reproduce the view.
	# --------------------------------------------------------

	_sync_camera_projection(cam3d, cam1)
	_sync_camera_projection(cam3d, cam2)


	# --------------------------------------------------------
	# Calculate portal camera transforms.
	# --------------------------------------------------------

	var cam2_transform := _map_camera_through_portal(
		main_cam_transform,
		p1_mask,
		p2_mask
	)

	var cam1_transform := _map_camera_through_portal(
		main_cam_transform,
		p2_mask,
		p1_mask
	)


	# --------------------------------------------------------
	# Apply transforms.
	# --------------------------------------------------------

	cam1.global_transform = cam1_transform
	cam2.global_transform = cam2_transform


	# --------------------------------------------------------
	# Connect textures.
	#
	# Portal 1 shows Renderer2.
	# Portal 2 shows Renderer1.
	# --------------------------------------------------------

	portal_material_1.set_shader_parameter(
		"portal_texture",
		renderer2.get_texture()
	)

	portal_material_2.set_shader_parameter(
		"portal_texture",
		renderer1.get_texture()
	)


	# --------------------------------------------------------
	# Render ONE time this frame.
	# --------------------------------------------------------

	renderer1.render_target_update_mode = (
		SubViewport.UPDATE_ONCE
	)

	renderer2.render_target_update_mode = (
		SubViewport.UPDATE_ONCE
	)


# ============================================================
# PORTAL CAMERA MAPPING
#
# Mathematical form:
#
# C_out = T_out * F * inverse(T_in) * C_main
#
# T_in   = source portal transform
# T_out  = destination portal transform
# C_main = main camera transform
# F      = 180° rotation in portal-local space
#
# This is the standard rigid-body coordinate-space mapping
# used by planar portal systems.
# ============================================================

func _map_camera_through_portal(
	camera_transform: Transform3D,
	source_portal: Node3D,
	destination_portal: Node3D
) -> Transform3D:

	# --------------------------------------------------------
	# Use rigid portal transforms.
	#
	# Portal meshes may have scale applied for visual size.
	# We do not want that scale to distort the virtual camera.
	# --------------------------------------------------------

	var source_transform := _rigid_transform(source_portal)
	var destination_transform := _rigid_transform(
		destination_portal
	)


	# --------------------------------------------------------
	# Convert camera from world space into source-portal space.
	#
	# p_local = inverse(T_source) * p_world
	# --------------------------------------------------------

	var local_camera := (
		source_transform.affine_inverse()
		* camera_transform
	)


	# --------------------------------------------------------
	# 180° rotation around the portal's local Y axis.
	#
	# Matrix:
	#
	# [-1  0  0]
	# [ 0  1  0]
	# [ 0  0 -1]
	#
	# This reverses the forward/backward and left/right
	# directions while preserving portal up.
	# --------------------------------------------------------

	var flip := Transform3D.IDENTITY

	flip.basis.x = -flip.basis.x
	flip.basis.z = -flip.basis.z


	local_camera = flip * local_camera


	# --------------------------------------------------------
	# Convert back into world space at destination portal.
	# --------------------------------------------------------

	var destination_camera := (
		destination_transform
		* local_camera
	)


	return destination_camera


# ============================================================
# RIGID PORTAL TRANSFORM
# ============================================================

func _rigid_transform(node: Node3D) -> Transform3D:

	var basis := node.global_transform.basis.orthonormalized()

	return Transform3D(
		basis,
		node.global_position
	)


# ============================================================
# CAMERA OPTICS SYNCHRONIZATION
# ============================================================

func _sync_camera_projection(
	main_camera: Camera3D,
	portal_camera: Camera3D
) -> void:

	if not main_camera or not portal_camera:
		return


	# --------------------------------------------------------
	# Projection mode
	# --------------------------------------------------------

	portal_camera.projection = main_camera.projection


	# --------------------------------------------------------
	# Perspective camera
	# --------------------------------------------------------

	if main_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:

		# Your responsive FOV gets copied every frame.
		portal_camera.fov = main_camera.fov


	# --------------------------------------------------------
	# Orthographic / frustum camera
	# --------------------------------------------------------

	else:

		portal_camera.size = main_camera.size

		portal_camera.frustum_offset = (
			main_camera.frustum_offset
		)


	# --------------------------------------------------------
	# Needed clipping parameters
	# --------------------------------------------------------

	portal_camera.near = main_camera.near
	portal_camera.far = main_camera.far


	# --------------------------------------------------------
	# Aspect behavior
	# --------------------------------------------------------

	portal_camera.keep_aspect = main_camera.keep_aspect


	# --------------------------------------------------------
	# Camera offsets are NOT copied.
	#
	# get_camera_transform() above already contains the
	# effective camera transform including these adjustments.
	# --------------------------------------------------------


	# --------------------------------------------------------
	# Optional camera attributes.
	#
	# Keeps exposure/visual camera attributes consistent
	# without recreating the player's camera logic.
	# --------------------------------------------------------

	portal_camera.attributes = main_camera.attributes


# ============================================================
# VIEWPORT SIZE
# ============================================================

func _sync_viewport_size() -> void:

	if not renderer1 or not renderer2:
		return

	var window_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	var target_size := Vector2i(
		maxi(1, int(window_size.x)),
		maxi(1, int(window_size.y))
	)


	if renderer1.size != target_size:
		renderer1.size = target_size

	if renderer2.size != target_size:
		renderer2.size = target_size
