extends Control


var primary_portal : bool #true for 1 and false for 2
@onready var portal1_ref := %Mask1
@onready var portal2_ref := %Mask2
@onready var primary_portal_ref

@onready var area1 := %Area1
@onready var area12 := %Area12
@onready var collshape1 := %CollShape1
@onready var collshape12 := %CollShape12
@onready var area2 := %Area2
@onready var area22 := %Area22
@onready var collshape2 := %CollShape2
@onready var collshape22 := %CollShape22

var portal1_ref_scale : Vector3
var portal2_ref_scale : Vector3
var collshape1_scale : Vector3
var collshape2_scale : Vector3
var collshape12_scale : Vector3
var collshape22_scale : Vector3
@export var collshape_thickness := 0.05
@export var scene_object_group := "SceneObject"
@export var draw_debug := true
@export var require_area_overlap := false ## also require the player to be inside a portal Area3D
@export var camera_transit := true ## camera glides through the portal window before switching sides


func _ready() -> void:
	process_priority = 500 # after PlayerCamera (0), before PortalMaster0 (1000)
	# Scaling collshape and mask auto
	portal1_ref_scale = portal1_ref.scale
	portal2_ref_scale = portal2_ref.scale

	## Collshape scaling
	collshape1_scale = Vector3(portal1_ref_scale.x, portal1_ref_scale.y, collshape_thickness)
	collshape2_scale = Vector3(portal2_ref_scale.x, portal2_ref_scale.y, collshape_thickness)
	collshape1.shape.size = collshape1_scale
	collshape2.shape.size = collshape2_scale

	# Rotation setting initially
	collshape1.rotation = portal1_ref.rotation
	collshape2.rotation = portal2_ref.rotation

	# No 2 scaling
	collshape12_scale = Vector3(portal1_ref_scale.x, portal1_ref_scale.y, collshape_thickness)
	collshape22_scale = Vector3(portal2_ref_scale.x, portal2_ref_scale.y, collshape_thickness)
	collshape12.shape.size = collshape12_scale
	collshape22.shape.size = collshape22_scale

	# Rotation setting initially for No 2
	collshape12.rotation = portal1_ref.rotation
	collshape22.rotation = portal2_ref.rotation


func _process(delta: float) -> void:
	if primary_portal == true:
		primary_portal_ref = portal1_ref
	elif primary_portal == false:
		primary_portal_ref = portal2_ref

	_update_camera_transit(delta)


func _physics_process(delta: float) -> void:
	# 1. Sync rotations from the portals directly via their global bases
	area1.global_transform.basis = portal1_ref.global_transform.basis.orthonormalized()
	area12.global_transform.basis = portal1_ref.global_transform.basis.orthonormalized()
	area2.global_transform.basis = portal2_ref.global_transform.basis.orthonormalized()
	area22.global_transform.basis = portal2_ref.global_transform.basis.orthonormalized()

	# 2. Offsets along the local Z-axis (-basis.z is Forward, +basis.z is Backward)
	var offset_dist = collshape_thickness / 2.0

	var forward_offset1 = -portal1_ref.global_transform.basis.z * offset_dist
	var backward_offset1 = portal1_ref.global_transform.basis.z * offset_dist

	var forward_offset2 = -portal2_ref.global_transform.basis.z * offset_dist
	var backward_offset2 = portal2_ref.global_transform.basis.z * offset_dist

	# 3. Apply the oriented offsets
	area1.global_position = portal1_ref.global_position + forward_offset1
	area2.global_position = portal2_ref.global_position + forward_offset2
	area12.global_position = portal1_ref.global_position + backward_offset1
	area22.global_position = portal2_ref.global_position + backward_offset2

	if draw_debug:
		DebugDraw3D.draw_gizmo(Transform3D(Basis(), area1.global_position))
		DebugDraw3D.draw_gizmo(Transform3D(Basis(), area2.global_position))
		DebugDraw3D.draw_gizmo(Transform3D(Basis(), area12.global_position))
		DebugDraw3D.draw_gizmo(Transform3D(Basis(), area22.global_position))

		DebugDraw3D.draw_box(collshape1.global_position, collshape1.global_basis.get_rotation_quaternion(), collshape1.shape.size, Color.RED, true )
		DebugDraw3D.draw_box(collshape2.global_position, collshape2.global_basis.get_rotation_quaternion(), collshape2.shape.size, Color.RED, true )
		DebugDraw3D.draw_box(collshape12.global_position, collshape12.global_transform.basis.get_rotation_quaternion(), collshape12.shape.size, Color.BLUE, true )
		DebugDraw3D.draw_box(collshape22.global_position, collshape22.global_transform.basis.get_rotation_quaternion(), collshape22.shape.size, Color.BLUE, true )

	# Collision detection with areas
	var arcollobj1 = get_area_collision(area1, scene_object_group)
	var arcollobj12 = get_area_collision(area12, scene_object_group)
	var arcollobj2 = get_area_collision(area2, scene_object_group)
	var arcollobj22 = get_area_collision(area22, scene_object_group)

	teleport(arcollobj1, arcollobj12, arcollobj2, arcollobj22)


func filter_array_dups(array: Array) -> Array:
	var output := {}
	for element in array:
		output[element] = true
	return output.keys()


func get_area_collision(area: Area3D, group: StringName) -> Array[int]:
	var result: Array[int] = []

	for body in area.get_overlapping_bodies():
		if body == null:
			continue

		var node: Node = body

		while node != null:
			if node.is_in_group(group):
				result.append(body.get_instance_id())
				break

			node = node.get_parent()

	return result


func get_active_portal(arr1, arr12, arr2, arr22) -> Array[String]:
	var active_areas: Array[String] = []

	var arrays := {
		"arr1": arr1,
		"arr12": arr12,
		"arr2": arr2,
		"arr22": arr22
	}

	for array_name in arrays:
		var arr = arrays[array_name]
		if arr == null:
			continue

		for instance_id in arr:
			var obj = instance_from_id(instance_id)

			if is_instance_valid(obj) and obj.is_in_group("Player"):
				active_areas.append(array_name)
				break

	return active_areas


func get_exit_portal(entry_portal: String) -> String:
	match entry_portal:
		"arr1":
			return "arr2"
		"arr2":
			return "arr1"
		"arr12":
			return "arr22"
		"arr22":
			return "arr12"
		_:
			return ""


var previous_distances: Dictionary = {}
func get_plane_collision(plane: MeshInstance3D, point: Vector3) -> int:
	var id := plane.get_instance_id()
	var local_point := plane.to_local(point)
	var bounds := plane.get_aabb()

	# Check if the point is within the finite X/Y bounds.
	if (
		local_point.x < bounds.position.x or
		local_point.x > bounds.position.x + bounds.size.x or
		local_point.y < bounds.position.y or
		local_point.y > bounds.position.y + bounds.size.y
	):
		previous_distances.erase(id)
		return 0

	# Check which side of the plane the point is on.
	var normal := plane.global_transform.basis.z.normalized()
	var d := (point - plane.global_position).dot(normal)

	if not previous_distances.has(id):
		previous_distances[id] = d
		return 0

	var previous_d: float = previous_distances[id]
	previous_distances[id] = d

	if previous_d > 0.0 and d <= 0.0:
		return 1 # Front -> Back
	elif previous_d < 0.0 and d >= 0.0:
		return -1 # Back -> Front

	return 0


## Moves the player (a RigidBody3D) from the portal it crossed to the other portal.
func teleport(arr1, arr12, arr2, arr22) -> void:
	var player := get_tree().get_first_node_in_group("Player") as RigidBody3D
	if player == null:
		return

	# Track plane crossings EVERY frame so the stored side never goes stale.
	var player_pos := player.global_position
	var crossing1 := get_plane_collision(portal1_ref, player_pos)
	var crossing2 := get_plane_collision(portal2_ref, player_pos)

	# Optional: also require the player to be inside one of the portal areas.
	if require_area_overlap and get_active_portal(arr1, arr12, arr2, arr22).is_empty():
		return

	# Entry / exit come from whichever plane was crossed.
	var entry_portal: MeshInstance3D
	var exit_portal: MeshInstance3D
	var crossing_direction := 0

	if crossing1 != 0:
		entry_portal = portal1_ref
		exit_portal = portal2_ref
		crossing_direction = crossing1
	elif crossing2 != 0:
		entry_portal = portal2_ref
		exit_portal = portal1_ref
		crossing_direction = crossing2
	else:
		return

	# Portal transform: entry space -> 180 deg flip -> exit space.
	var entry_basis := entry_portal.global_transform.basis.orthonormalized()
	var exit_basis := exit_portal.global_transform.basis.orthonormalized()
	var portal_basis: Basis = exit_basis * Basis(Vector3.UP, PI) * entry_basis.inverse()

	var old_xform := player.global_transform
	var new_origin: Vector3 = exit_portal.global_position \
		+ portal_basis * (old_xform.origin - entry_portal.global_position)
	var new_basis: Basis = (portal_basis * old_xform.basis.orthonormalized()).orthonormalized()
	var new_xform := Transform3D(new_basis, new_origin)

	if draw_debug:
		DebugDraw3D.draw_sphere(old_xform.origin, 0.5, Color.DARK_GREEN)
		DebugDraw3D.draw_sphere(new_origin, 0.5, Color.WEB_MAROON)

	# --- Move the RigidBody3D. Writing global_transform alone is overridden by
	# the physics engine, so push the state straight into the physics server. ---
	var new_lin_vel: Vector3 = portal_basis * player.linear_velocity
	var new_ang_vel: Vector3 = portal_basis * player.angular_velocity
	var body_rid := player.get_rid()
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, new_xform)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, new_lin_vel)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, new_ang_vel)
	player.global_transform = new_xform # keeps the node in sync this frame

	# --- Camera stays on the entry side and glides through the window ---
	if camera_transit:
		_begin_camera_transit(player, entry_portal, exit_portal, crossing_direction)

	# Reset plane tracking so we don't instantly re-trigger on the exit portal.
	previous_distances.erase(entry_portal.get_instance_id())
	previous_distances.erase(exit_portal.get_instance_id())
	get_plane_collision(exit_portal, new_origin) # prime with the new side

	var direction := "FRONT -> BACK" if crossing_direction == 1 else "BACK -> FRONT"
	print("[", entry_portal.name, "] ======>> [", exit_portal.name, "] | Direction: ", direction)


# ---------------------------------------------------------------------------
# Camera transit: after the ball teleports, the camera is NOT moved. It keeps
# orbiting a "virtual anchor" (the ball mapped back to the entry side), so you
# watch the ball through the portal window. When the camera itself crosses the
# entry plane, it is remapped to the exit side exactly where PortalMaster0's
# virtual camera was, so the swap is invisible.
# ---------------------------------------------------------------------------
var _pend := false
var _p_entry: Node3D
var _p_exit: Node3D
var _p_side := 1.0
var _p_R := Basis.IDENTITY
var _v_anchor := Vector3.ZERO
var _v_cam := Vector3.ZERO
var _pc = null # PlayerCamera (untyped on purpose)
var _real_cam: Node3D = null


func _update_R() -> void:
	_p_R = _p_exit.global_transform.basis.orthonormalized() \
		* Basis(Vector3.UP, PI) \
		* _p_entry.global_transform.basis.orthonormalized().inverse()


func _to_exit(p: Vector3) -> Vector3:
	return _p_exit.global_position + _p_R * (p - _p_entry.global_position)


func _to_entry(p: Vector3) -> Vector3:
	return _p_entry.global_position + _p_R.inverse() * (p - _p_exit.global_position)


func _begin_camera_transit(player: Node3D, entry_portal: Node3D, exit_portal: Node3D, direction: int) -> void:
	var pc = player.get_parent().get_node_or_null("PlayerCamera")
	if pc == null:
		return
	var rc := pc.get_node_or_null("%Camera3D") as Node3D
	if rc == null:
		return

	if _pend:
		_finalize_camera() # a previous transit is still running: finish it first

	_pc = pc
	_real_cam = rc
	_p_entry = entry_portal
	_p_exit = exit_portal
	_update_R()
	_v_anchor = _pc.camera_anchor_pos
	_v_cam = _real_cam.global_position
	_p_side = 1.0 if direction == 1 else -1.0 # side of the entry plane the camera is expected on
	_pend = true

	# Camera already past the plane? Then switch right away.
	var d := (_v_cam - _p_entry.global_position).dot(_p_entry.global_transform.basis.z.normalized())
	if d * _p_side <= 0.0:
		_finalize_camera()


func _update_camera_transit(delta: float) -> void:
	if not _pend:
		return
	var player := get_tree().get_first_node_in_group("Player") as Node3D
	if player == null or not is_instance_valid(_pc) or not is_instance_valid(_real_cam):
		_pend = false
		return
	_update_R()

	# Virtual anchor = ball mapped back to the entry side (smoothed like PlayerCamera).
	var anchor_node := player.get_node_or_null("CameraAnchor") as Node3D
	var real_anchor: Vector3 = anchor_node.global_position if anchor_node else player.global_position
	_v_anchor = _v_anchor.lerp(_to_entry(real_anchor), clampf(8.0 * delta, 0.0, 1.0))

	_pc.camera_anchor_pos = _v_anchor
	_pc.global_position = _v_anchor

	var arm := _pc.SPRING_ARM as Node3D
	var cam_target: Vector3 = _v_anchor + arm.global_transform.basis * Vector3(0.0, 0.0, float(_pc.SPRING_ARM.spring_length))
	_v_cam = _v_cam.lerp(cam_target, clampf(float(_pc.camera_smooth_speed) * delta, 0.0, 1.0))

	_real_cam.global_position = _v_cam
	_real_cam.look_at(_v_anchor, Vector3.UP)

	# Did the camera itself pass through the entry plane? -> switch sides.
	var d := (_v_cam - _p_entry.global_position).dot(_p_entry.global_transform.basis.z.normalized())
	if d * _p_side <= 0.0:
		_finalize_camera()


func _finalize_camera() -> void:
	if not _pend or not is_instance_valid(_pc) or not is_instance_valid(_real_cam):
		_pend = false
		return
	_update_R()
	var old_basis := _real_cam.global_transform.basis

	_pc.camera_anchor_pos = _to_exit(_v_anchor)
	_pc.global_position = _pc.camera_anchor_pos
	_real_cam.global_transform = Transform3D((_p_R * old_basis).orthonormalized(), _to_exit(_v_cam))

	# Rotate the mouse-look yaw by the portal's yaw so "forward" stays forward.
	var f := _p_R * Vector3.BACK
	var yaw_delta := atan2(f.x, f.z)
	_pc.target_rot_x += yaw_delta
	_pc.smoothed_rot_x += yaw_delta
	_pend = false
