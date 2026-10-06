extends Node3D
## Two-way portal using portal-aligned OFF-AXIS cameras.
## Each virtual camera:
##   - sits at the main camera position mapped through the portal pair
##   - looks straight through the source portal (basis = portal basis)
##   - uses a frustum built from the source portal's 4 corners
## => aperture clipping, source-plane (near plane) clipping, parallax and
##    perspective all come from one construction, no oblique-plane hack needed.

const PORTAL_LAYER: int = 1 << 19
const NEAR_BIAS: float = 0.002   # push near plane slightly past the portal plane (no z-fight with wall)
const MIN_NEAR: float = 0.02

@export var resolution: int = 1024   # square render target per portal

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
var spatial_portal_shader: Shader = preload("res://shaders/portal_spatial.gdshader")
var _ok: bool = false


func _ready() -> void:
	process_priority = 1000  # run after camera smoothing / player scripts
	_resolve_main_camera()

	if not p1_mask or not p2_mask:
		return
	if not mask1 and p1_mask is GeometryInstance3D:
		mask1 = p1_mask as GeometryInstance3D
	if not mask2 and p2_mask is GeometryInstance3D:
		mask2 = p2_mask as GeometryInstance3D
	if not mask1 or not mask2 or not renderer1 or not renderer2 or not cam1 or not cam2:
		return

	for m: GeometryInstance3D in [mask1, mask2]:
		m.layers = PORTAL_LAYER
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if cam3d:
		cam3d.cull_mask |= PORTAL_LAYER

	_configure_portal_camera(cam1)
	_configure_portal_camera(cam2)

	portal_material_1 = ShaderMaterial.new()
	portal_material_1.shader = spatial_portal_shader
	portal_material_2 = ShaderMaterial.new()
	portal_material_2.shader = spatial_portal_shader
	mask1.material_override = portal_material_1
	mask2.material_override = portal_material_2

	for r: SubViewport in [renderer1, renderer2]:
		r.world_3d = get_viewport().world_3d
		r.transparent_bg = true
		r.size = Vector2i(resolution, resolution)
		r.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_ok = true


func _configure_portal_camera(camera: Camera3D) -> void:
	camera.cull_mask &= ~PORTAL_LAYER   # portals never render themselves (recursion OFF)
	camera.current = true
	var env: Environment = camera.environment
	if not env:
		env = Environment.new()
		camera.environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)


func _resolve_main_camera() -> void:
	var active: Camera3D = get_viewport().get_camera_3d()
	if active:
		cam3d = active


func _process(_delta: float) -> void:
	_resolve_main_camera()
	if not _ok or not cam3d:
		return

	var main_pos: Vector3 = cam3d.global_transform.origin

	# P2 shows what CAM1 sees through P1;  P1 shows what CAM2 sees through P2.
	_update_portal(p2_mask, p1_mask, mask1, cam1, portal_material_2, renderer1, main_pos)
	_update_portal(p1_mask, p2_mask, mask2, cam2, portal_material_1, renderer2, main_pos)


func _update_portal(
	display_frame: Node3D,
	source_frame: Node3D,
	source_geo: GeometryInstance3D,
	cam: Camera3D,
	material: ShaderMaterial,
	renderer: SubViewport,
	main_pos: Vector3
) -> void:
	var d_xf: Transform3D = _rigid(display_frame)
	var s_xf: Transform3D = _rigid(source_frame)

	# 180 deg turn about the portal's local Y  (X -> -X, Z -> -Z). Built from portal basis only.
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)

	# world -> world map: display portal space -> source portal space
	var map_xf: Transform3D = s_xf * flip * d_xf.affine_inverse()

	var eye: Vector3 = map_xf * main_pos

	# Which side of the display portal is the player on? (both sides work)
	var front: bool = (d_xf.affine_inverse() * main_pos).z >= 0.0
	var cam_basis: Basis = s_xf.basis
	if front:
		cam_basis = s_xf.basis * Basis(Vector3.UP, PI)

	var cam_xf := Transform3D(cam_basis.orthonormalized(), eye)
	var inv: Transform3D = cam_xf.affine_inverse()

	# Source portal aperture corners (include mesh scale) -> virtual camera space
	var aabb: AABB = source_geo.get_aabb()
	var zc: float = aabb.position.z + aabb.size.z * 0.5
	var gx: Transform3D = source_geo.global_transform
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var depth: float = 0.0
	for cx in [aabb.position.x, aabb.end.x]:
		for cy in [aabb.position.y, aabb.end.y]:
			var p: Vector3 = inv * (gx * Vector3(cx, cy, zc))
			mn = mn.min(Vector2(p.x, p.y))
			mx = mx.max(Vector2(p.x, p.y))
			depth += -p.z * 0.25   # distance eye -> portal plane along view axis

	var far: float = cam3d.far
	var near: float = maxf(depth + NEAR_BIAS, MIN_NEAR)
	var k: float = near / maxf(depth, 0.001)   # scale rect from portal plane to near plane

	var center: Vector2 = (mn + mx) * 0.5 * k
	var size: float = maxf(mx.x - mn.x, mx.y - mn.y) * k   # square frustum covering the aperture
	var h: float = size * 0.5

	cam.global_transform = cam_xf
	cam.set_frustum(size, center, near, far)   # near plane == source portal plane

	var proj: Projection = Projection.create_frustum(
		center.x - h, center.x + h, center.y - h, center.y + h, near, far
	)

	material.set_shader_parameter("portal_map", Projection(map_xf))
	material.set_shader_parameter("portal_view_proj", proj * Projection(inv))
	material.set_shader_parameter("portal_texture", renderer.get_texture())


func _rigid(node: Node3D) -> Transform3D:
	return Transform3D(node.global_transform.basis.orthonormalized(), node.global_position)
