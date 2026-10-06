extends Node3D
## Two-way portal with finite recursion (infinity illusion for facing portals).
##
## Per display portal i there are N virtual cameras (levels 1..N):
##   level L eye = map^L(main camera),   map = display portal frame -> source portal frame
## and N display meshes ("copies"):
##   copy 0   = the real mask, seen by the MAIN camera, shows level-1 texture
##   copy j   = child mesh on the same transform, seen ONLY by level-j camera, shows level-(j+1) texture
## Level N camera sees no portal at all (end of the chain).
## Each camera is a portal-aligned off-axis camera (near plane == source portal plane).

const NEAR_BIAS: float = 0.002
const MIN_NEAR: float = 0.02

@export_range(1, 6) var recursion_levels: int = 3
@export_range(0.0, 1.0) var fade_per_level: float = 0.85   # darkening per bounce, helps sell depth
@export var resolution: int = 1024                          # level 1 size (square)
@export var min_resolution: int = 256                       # deeper levels halve until this

var cam3d: Camera3D = null

@onready var p1_mask: Node3D = get_node_or_null("Portal1/Mask1") as Node3D
@onready var p2_mask: Node3D = get_node_or_null("Portal2/Mask2") as Node3D
@onready var mask1: GeometryInstance3D = get_node_or_null("%Mask1") as GeometryInstance3D
@onready var mask2: GeometryInstance3D = get_node_or_null("%Mask2") as GeometryInstance3D
@onready var renderer1: SubViewport = get_node_or_null("%Renderer1") as SubViewport
@onready var renderer2: SubViewport = get_node_or_null("%Renderer2") as SubViewport
@onready var cam1: Camera3D = get_node_or_null("%CAM1") as Camera3D
@onready var cam2: Camera3D = get_node_or_null("%CAM2") as Camera3D

var spatial_portal_shader: Shader = preload("res://shaders/portal_spatial.gdshader")

# index i: 0 = display P1 (looks through P2),  1 = display P2 (looks through P1)
var _display_geo: Array = []
var _display_frame: Array = []
var _source_geo: Array = []
var _source_frame: Array = []

var _views: Array = [[], []]   # [i][L-1]  SubViewport
var _cams: Array = [[], []]    # [i][L-1]  Camera3D
var _mats: Array = [[], []]    # [i][j]    ShaderMaterial, j = 0..N-1

var _all_bits: int = 0
var _masked_cam: Camera3D = null
var _ok: bool = false
var _n: int = 3   # effective levels


func _bit(i: int, j: int) -> int:
	# 20 visual layers available (bits 0..19); count down from the top
	return 1 << (19 - (i * _n + j))


func _ready() -> void:
	process_priority = 1000
	_resolve_main_camera()

	if not p1_mask or not p2_mask:
		return
	if not mask1 and p1_mask is GeometryInstance3D:
		mask1 = p1_mask as GeometryInstance3D
	if not mask2 and p2_mask is GeometryInstance3D:
		mask2 = p2_mask as GeometryInstance3D
	if not mask1 or not mask2 or not renderer1 or not renderer2 or not cam1 or not cam2:
		return
	if not (mask1 is MeshInstance3D and mask2 is MeshInstance3D):
		push_error("Portal masks must be MeshInstance3D (needed to build recursion copies).")
		return

	_n = clampi(recursion_levels, 1, 6)
	var n: int = _n

	_display_geo = [mask1, mask2]
	_display_frame = [p1_mask, p2_mask]
	_source_geo = [mask2, mask1]
	_source_frame = [p2_mask, p1_mask]

	for i in 2:
		for j in n:
			_all_bits |= _bit(i, j)

	var base_views: Array = [renderer2, renderer1]
	var base_cams: Array = [cam2, cam1]

	for i in 2:
		# --- viewports + cameras, levels 1..N ---
		for l in range(1, n + 1):
			var v: SubViewport
			var c: Camera3D
			if l == 1:
				v = base_views[i]
				c = base_cams[i]
			else:
				v = SubViewport.new()
				v.name = "PortalView_%d_L%d" % [i, l]
				add_child(v)
				c = Camera3D.new()
				c.name = "PortalCam_%d_L%d" % [i, l]
				v.add_child(c)

			var s: int = maxi(min_resolution, resolution >> (l - 1))
			v.size = Vector2i(s, s)
			v.world_3d = get_viewport().world_3d
			v.transparent_bg = false
			v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			_configure_portal_camera(c)
			_views[i].append(v)
			_cams[i].append(c)

		# --- display meshes, copies 0..N-1 ---
		for j in n:
			var mat := ShaderMaterial.new()
			mat.shader = spatial_portal_shader
			var geo: GeometryInstance3D
			if j == 0:
				geo = _display_geo[i]
			else:
				var src_mesh := _display_geo[i] as MeshInstance3D
				var copy := MeshInstance3D.new()
				copy.name = "PortalCopy_L%d" % j
				copy.mesh = src_mesh.mesh
				src_mesh.add_child(copy)   # identity local transform -> same place & scale
				geo = copy
			geo.layers = _bit(i, j)
			geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geo.material_override = mat
			_mats[i].append(mat)

	_ok = true


func _configure_portal_camera(camera: Camera3D) -> void:
	camera.current = true
	# Render with the SAME environment / sky / exposure as the main view.
	# (null -> falls back to the WorldEnvironment of the shared world)
	camera.environment = cam3d.environment if cam3d else null
	camera.attributes = cam3d.attributes if cam3d else null


func _resolve_main_camera() -> void:
	var active: Camera3D = get_viewport().get_camera_3d()
	if active:
		cam3d = active


func _apply_cull_masks() -> void:
	var base: int = cam3d.cull_mask & ~_all_bits
	# main camera sees only the real masks (copy 0)
	cam3d.cull_mask = base | _bit(0, 0) | _bit(1, 0)
	var world_mask: int = base
	for i in 2:
		for l in range(1, _n + 1):
			var cam: Camera3D = _cams[i][l - 1]
			# level-l camera sees copy l of its own portal (none for the last level)
			var extra: int = _bit(i, l) if l < _n else 0
			cam.cull_mask = world_mask | extra
	_masked_cam = cam3d


func _process(_delta: float) -> void:
	_resolve_main_camera()
	if not _ok or not cam3d:
		return
	if _masked_cam != cam3d:
		_apply_cull_masks()

	var main_pos: Vector3 = cam3d.global_transform.origin
	for i in 2:
		_update_chain(i, main_pos)


func _update_chain(i: int, main_pos: Vector3) -> void:
	var d_xf: Transform3D = _rigid(_display_frame[i])
	var s_xf: Transform3D = _rigid(_source_frame[i])
	var d_inv: Transform3D = d_xf.affine_inverse()
	var source_geo: GeometryInstance3D = _source_geo[i]

	# 180 deg about portal-local Y: X -> -X, Z -> -Z (no world-axis assumptions)
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var map_xf: Transform3D = s_xf * flip * d_inv
	var map_proj := Projection(map_xf)

	var view_projs: Array = []
	var prev_eye: Vector3 = main_pos
	for l in _n:
		var cam: Camera3D = _cams[i][l]
		var eye: Vector3 = map_xf * prev_eye
		var front: bool = (d_inv * prev_eye).z >= 0.0
		view_projs.append(_aim_camera(cam, eye, front, s_xf, source_geo))
		prev_eye = eye

	for j in _n:
		var mat: ShaderMaterial = _mats[i][j]
		var view: SubViewport = _views[i][j]   # copy j shows level j+1
		mat.set_shader_parameter("portal_map", map_proj)
		mat.set_shader_parameter("portal_view_proj", view_projs[j])
		mat.set_shader_parameter("portal_texture", view.get_texture())
		mat.set_shader_parameter("brightness", 1.0 if j == 0 else fade_per_level)


## Portal-aligned off-axis camera through the source portal. Returns projection * view.
func _aim_camera(
	cam: Camera3D,
	eye: Vector3,
	front: bool,
	s_xf: Transform3D,
	source_geo: GeometryInstance3D
) -> Projection:
	var cam_basis: Basis = s_xf.basis
	if front:
		cam_basis = s_xf.basis * Basis(Vector3.UP, PI)

	var cam_xf := Transform3D(cam_basis.orthonormalized(), eye)
	var inv: Transform3D = cam_xf.affine_inverse()

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
			depth += -p.z * 0.25

	var far: float = cam3d.far
	var near: float = maxf(depth + NEAR_BIAS, MIN_NEAR)
	var k: float = near / maxf(depth, 0.001)

	var center: Vector2 = (mn + mx) * 0.5 * k
	var size: float = maxf(mx.x - mn.x, mx.y - mn.y) * k
	var h: float = size * 0.5

	cam.global_transform = cam_xf
	cam.set_frustum(size, center, near, far)

	var proj: Projection = Projection.create_frustum(
		center.x - h, center.x + h, center.y - h, center.y + h, near, far
	)
	return proj * Projection(inv)


func _rigid(node: Node3D) -> Transform3D:
	return Transform3D(node.global_transform.basis.orthonormalized(), node.global_position)
