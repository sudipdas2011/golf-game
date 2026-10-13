extends Control
## TeleportManager - two-way portal teleport for a RigidBody3D player + seamless camera.
##
##  1. BALL    : when the ball's centre passes through a portal WINDOW (swept test) it is moved
##               to the other portal with rotated velocity / spin (physics server, Jolt-safe).
##               Pure rigid mapping - if the exit is higher/lower the ball simply falls/rises
##               naturally, nothing is snapped to the ground.
##  2. CAMERA  : the camera is the ball's eye - it never teleports on its own. A ballistic
##               prediction (gravity included, so it works in the air too) tells whether the
##               ball is COMMITTED to a portal window. Then:
##                 * ball first   -> camera keeps following the ball through the window and is
##                                   switched when it crosses the plane inside the window
##                 * camera first -> ONLY if the ball is committed to that same window: camera is
##                                   switched when it crosses, keeps looking at the ball (mapped
##                                   through the portal) until the ball crosses; if the ball
##                                   stops being committed the camera returns
##                 * not committed-> the camera just moves through (no teleport)
##               Unclean cases fall back to a soft re-attach to the ball (never behind a portal).
##  3. FIELDS  : small, soft, invisible fields around each portal mouth. A field only wakes up
##               while the ball is committed to that portal, and then steers the view so the
##               camera sits on the ball's own path (behind OR ahead of it, never a 180 spin) -
##               so it travels through the same window as the ball.
##  5. POLISH  : critically damped camera motion (no velocity jumps), a thin "portal volume" so the
##               screen never clips while the camera passes through (works because the portal
##               shader projects from WORLD position - any point on a view ray gives the same
##               pixel), a screen shader pulse (radial blur + chromatic split + vignette) and a
##               small FOV kick that peak exactly at the swap.
##  4. CONTROLS: Player.gd reads a proxy camera expressed in the BALL's space, so WASD / torque
##               stay consistent while camera and ball are on different sides of a portal.
##
## Only this script needs changing. Scene needs: Mask1/Mask2 (unique-name MeshInstance3D quads),
## optional Area1/12/2/22 + CollShape*, player in group "Player" with a "CameraAnchor" child and
## a sibling "PlayerCamera" node.

# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------
@onready var portal1_ref: MeshInstance3D = get_node_or_null("%Mask1") as MeshInstance3D
@onready var portal2_ref: MeshInstance3D = get_node_or_null("%Mask2") as MeshInstance3D

@onready var area1: Area3D = get_node_or_null("%Area1") as Area3D
@onready var area12: Area3D = get_node_or_null("%Area12") as Area3D
@onready var area2: Area3D = get_node_or_null("%Area2") as Area3D
@onready var area22: Area3D = get_node_or_null("%Area22") as Area3D
@onready var collshape1: CollisionShape3D = get_node_or_null("%CollShape1") as CollisionShape3D
@onready var collshape12: CollisionShape3D = get_node_or_null("%CollShape12") as CollisionShape3D
@onready var collshape2: CollisionShape3D = get_node_or_null("%CollShape2") as CollisionShape3D
@onready var collshape22: CollisionShape3D = get_node_or_null("%CollShape22") as CollisionShape3D

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
@export var collshape_thickness := 0.05
@export var scene_object_group := "SceneObject"
@export var draw_debug := false ## gizmos, field wireframes, speed trace and debug text
@export var require_area_overlap := false ## also require the player to be inside a portal Area3D

@export_group("Camera transit")
@export var camera_transit := true ## camera passes through portal windows instead of snapping
@export var camera_first_transit := true ## camera that reaches a window first goes through first
@export var transit_timeout := 4.0 ## ball-first: hard safety limit for a camera still on the entry side
@export var force_through := true ## camera left behind after the ball teleported is pulled through the window
@export var force_delay := 0.35 ## seconds the camera may lag naturally before it is pulled
@export var force_ramp := 0.5 ## seconds for the pull to reach full strength (smooth start)
@export var force_gain := 3.0 ## how hard the camera is drawn toward the window
@export var force_speed := 14.0 ## max speed (m/s) of that pull
@export var exit_guard := true ## brief settle after a teleport: camera stays in front of the exit portal while the ball rests there
@export var guard_margin := 0.35 ## how far in front of the exit plane the camera stops (m)
@export var guard_time := 2.5 ## the guard only lasts this long (s) after the camera has arrived - never a permanent wall
@export var soft_cut_fade := true ## quick fade-in that hides the rare hard cut (unclean fallbacks only)
@export var soft_cut_time := 0.3 ## length of that fade (s)
@export var camera_first_timeout := 12.0 ## camera-first: max seconds before re-attaching to the ball
@export var camera_near_during_transit := 0.02 ## smaller near plane near portals (less clipping flash); 0 = off
@export var exclude_frames_from_spring_arm := true ## camera spring arm ignores the portal frame bodies

@export_group("Commit prediction")
@export var commit_time := 1.2 ## look-ahead (s): will the ball reach a portal window within this time?
@export var commit_min_speed := 0.5 ## slower than this = not going anywhere
@export var commit_margin := 0.15 ## window tolerance (m) for the prediction
@export var commit_grace := 0.5 ## camera-first: seconds the ball may stop being committed before the camera returns
@export var ground_probe := 0.45 ## ray length below the ball: "rolling" (no gravity in the prediction) vs "airborne"
@export var ground_mask := 1 ## physics layers that count as floor for that ray

@export_group("Polish")
@export var smooth_motion := true ## critically damped camera motion during transits (continuous velocity)
@export var follow_smooth_time := 0.10 ## camera follow smoothing time during transits (s)
@export var crossing_fx := true ## subtle screen pulse ONLY at the moment the camera really swaps sides (hides the swap)
@export var fx_strength := 0.6 ## strength of that pulse
@export var fx_proximity := false ## also build an effect up when merely NEAR a window (off: not realistic - nothing happens without a swap)
@export var fx_range := 1.6 ## proximity effect: how close (m) the camera must be to a window
@export var fx_pulse_time := 0.45 ## length of the pulse at the swap (s)
@export var fov_kick_deg := 5.0 ## little FOV swell after passing through (0 = off)
@export var portal_slab := true ## thin invisible-to-the-eye portal volume so the screen never clips at the crossing
@export var slab_thickness := 0.12 ## thickness of that volume (m, total)
@export var slab_range := 0.7 ## volume is only shown when the camera is this close (m)

@export_group("Auto roll")
@export var auto_roll := true ## ball that passed through and stopped is rolled gently on, so the camera simply follows it through
@export var roll_delay := 0.25 ## seconds after the teleport before the roll starts
@export var roll_idle_speed := 1.0 ## only when the ball is slower than this (m/s) - never fights your input
@export var roll_speed := 3.0 ## the roll stops adding force once the ball moves this fast away from the portal
@export var roll_force := 14.0 ## push strength (N)

@export_group("Camera settle")
@export var orbit_settle := true ## after a transit the camera swings AROUND the ball to its follow spot (curved path, never through the ball)
@export var orbit_speed := 5.0 ## how quickly it settles
@export var orbit_max_deg := 150.0 ## max swing speed (deg/s)
@export var orbit_max_time := 3.0 ## safety limit (s)

@export_group("Portal fields")
@export var camera_fields := true ## small soft fields steer the view toward the ball's own path
@export var field_length := 5.0 ## field reach along the portal axis (each side)
@export var field_width := 2.5 ## field reach sideways / up-down
@export var field_turn_speed := 3.0 ## strength of the view steering
@export var field_max_turn_deg := 70.0 ## never rotate the view faster than this (deg/s)
@export var field_attack := 4.0 ## how fast a field fades in
@export var field_hold := 0.8 ## seconds a field takes to fade out
@export var field_mouse_pause := 0.25 ## steering yields this long after you move the mouse


# ---------------------------------------------------------------------------
# Critically damped springs ("SmoothDamp"). Unlike a plain lerp they keep a VELOCITY, so
# motion starts, stops and re-targets without sudden accelerations.
# ---------------------------------------------------------------------------
class DampedVec3:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO

	func reset(v: Vector3, vel: Vector3 = Vector3.ZERO) -> void:
		value = v
		velocity = vel

	func step(target: Vector3, smooth_time: float, delta: float, max_speed: float = INF) -> Vector3:
		if delta <= 0.0:
			return value
		var st := maxf(smooth_time, 0.0001)
		var omega := 2.0 / st
		var x := omega * delta
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := (value - target).limit_length(max_speed * st)
		var adj := value - change
		var temp := (velocity + omega * change) * delta
		velocity = (velocity - omega * temp) * e
		var out := adj + (change + temp) * e
		if (target - value).dot(out - target) > 0.0: # never overshoot the target
			out = target
			velocity = Vector3.ZERO
		value = out
		return out


class DampedFloat:
	var value := 0.0
	var velocity := 0.0

	func reset(v: float, vel: float = 0.0) -> void:
		value = v
		velocity = vel

	func step(target: float, smooth_time: float, delta: float, max_speed: float = INF) -> float:
		if delta <= 0.0:
			return value
		var st := maxf(smooth_time, 0.0001)
		var omega := 2.0 / st
		var x := omega * delta
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var max_change := max_speed * st
		var change := clampf(value - target, -max_change, max_change)
		var adj := value - change
		var temp := (velocity + omega * change) * delta
		velocity = (velocity - omega * temp) * e
		var out := adj + (change + temp) * e
		if (target - value > 0.0) == (out > target):
			out = target
			velocity = 0.0
		value = out
		return out


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# After PlayerCamera (0), before PortalMaster0 (1000): the final camera pose is what renders.
	process_priority = 500

	if portal1_ref == null or portal2_ref == null:
		push_error("TeleportManager: Mask1 / Mask2 not found - disabled.")
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return

	_setup_area_shapes()


func _setup_area_shapes() -> void:
	var s1 := portal1_ref.scale
	var s2 := portal2_ref.scale
	var pairs := [
		[collshape1, s1, portal1_ref], [collshape12, s1, portal1_ref],
		[collshape2, s2, portal2_ref], [collshape22, s2, portal2_ref],
	]
	for p in pairs:
		var cs := p[0] as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sc: Vector3 = p[1]
		(cs.shape as BoxShape3D).size = Vector3(sc.x, sc.y, collshape_thickness)
		cs.rotation = (p[2] as Node3D).rotation


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_fx(delta)


func _physics_process(_delta: float) -> void:
	if draw_debug:
		_speed_trace()
	_auto_roll()
	_sync_areas()
	_try_teleport(_area_hits(area1), _area_hits(area12), _area_hits(area2), _area_hits(area22))


func _input(event: InputEvent) -> void:
	# Remember when the player last moved the mouse so view steering can yield.
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0:
		_last_mouse_t = Time.get_ticks_msec() * 0.001


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
var _player: RigidBody3D = null


func _get_player() -> RigidBody3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("Player") as RigidBody3D
	return _player


func _portal_frame(plane: Node3D) -> Transform3D:
	return Transform3D(plane.global_transform.basis.orthonormalized(), plane.global_position)


func _plane_normal(plane: Node3D) -> Vector3:
	return plane.global_transform.basis.z.normalized()


## Signed distance of a point from a portal plane (+ = on the +Z / "front" side).
func _side_of(plane: Node3D, p: Vector3) -> float:
	return (p - plane.global_position).dot(_plane_normal(plane))


## Rotation that carries entry-portal space into exit-portal space (with the 180 deg flip).
func _portal_rotation(entry: Node3D, exit: Node3D) -> Basis:
	return exit.global_transform.basis.orthonormalized() \
		* Basis(Vector3.UP, PI) \
		* entry.global_transform.basis.orthonormalized().inverse()


func _yaw_of(rot: Basis) -> float:
	var f := rot * Vector3.BACK
	return atan2(f.x, f.z)


func _window_half(plane: MeshInstance3D) -> Vector2:
	var b := plane.get_aabb()
	var sc := plane.global_transform.basis.get_scale().abs()
	return Vector2(b.size.x * sc.x, b.size.y * sc.y) * 0.5


# ---------------------------------------------------------------------------
# Optional Area3D gate (kept from the original setup)
# ---------------------------------------------------------------------------
func _sync_areas() -> void:
	if area1 == null or area12 == null or area2 == null or area22 == null:
		return
	var b1 := portal1_ref.global_transform.basis.orthonormalized()
	var b2 := portal2_ref.global_transform.basis.orthonormalized()
	area1.global_transform.basis = b1
	area12.global_transform.basis = b1
	area2.global_transform.basis = b2
	area22.global_transform.basis = b2

	var off := collshape_thickness * 0.5
	area1.global_position = portal1_ref.global_position - b1.z * off
	area12.global_position = portal1_ref.global_position + b1.z * off
	area2.global_position = portal2_ref.global_position - b2.z * off
	area22.global_position = portal2_ref.global_position + b2.z * off

	if draw_debug:
		for a in [area1, area12, area2, area22]:
			DebugDraw3D.draw_gizmo(Transform3D(Basis(), (a as Node3D).global_position))


func _area_hits(area: Area3D) -> Array[int]:
	var result: Array[int] = []
	if area == null:
		return result
	for body in area.get_overlapping_bodies():
		var node: Node = body
		while node != null:
			if node.is_in_group(scene_object_group):
				result.append(body.get_instance_id())
				break
			node = node.get_parent()
	return result


func _player_in_any_area(arrays: Array) -> bool:
	for arr in arrays:
		for id in arr:
			var obj := instance_from_id(id)
			if is_instance_valid(obj) and obj.is_in_group("Player"):
				return true
	return false


# ---------------------------------------------------------------------------
# Swept window crossing (shared by ball and camera)
# ---------------------------------------------------------------------------
## 1 = crossed front->back, -1 = back->front, 0 = nothing. The segment from the previous
## position to the current one must pierce the finite window, so fast movers can't skip the
## plane and anything passing beside the window never counts.
func _plane_cross(plane: MeshInstance3D, point: Vector3, store: Dictionary) -> int:
	var id := plane.get_instance_id()
	var had: bool = store.has(id)
	var prev: Vector3 = store.get(id, point)
	store[id] = point
	if not had:
		return 0

	var d0 := _side_of(plane, prev)
	var d1 := _side_of(plane, point)
	var dir := 0
	if d0 > 0.0 and d1 <= 0.0:
		dir = 1
	elif d0 < 0.0 and d1 >= 0.0:
		dir = -1
	else:
		return 0

	var hit := prev.lerp(point, d0 / (d0 - d1))
	var l := plane.to_local(hit)
	var b := plane.get_aabb()
	if l.x < b.position.x or l.x > b.end.x or l.y < b.position.y or l.y > b.end.y:
		return 0
	return dir


# ---------------------------------------------------------------------------
# Commit prediction: will the ball go through this portal's window soon?
# Ballistic: p(t) = p + v t + 1/2 g t^2. A rolling ball (floor right below) feels no gravity
# in the prediction, an airborne one does - so jumps / bounces / falls are handled.
# Returns the crossing direction (1 = front->back, -1 = back->front) or 0.
# ---------------------------------------------------------------------------
var _grounded := true


func _is_grounded(player: RigidBody3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		player.global_position, player.global_position + Vector3.DOWN * ground_probe,
		ground_mask, [player.get_rid()])
	return not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _gravity_vec(player: RigidBody3D) -> Vector3:
	var mag := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var dirv: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	return dirv * mag * player.gravity_scale


func _predict_crossing(player: RigidBody3D, plane: MeshInstance3D) -> int:
	var v := player.linear_velocity
	if v.length() < commit_min_speed:
		return 0
	var g := Vector3.ZERO
	if _grounded:
		v.y = 0.0
	else:
		g = _gravity_vec(player)

	var n := _plane_normal(plane)
	var p0 := player.global_position
	var d0 := _side_of(plane, p0)
	if absf(d0) < 0.0001:
		return 0
	# side(t) = d0 + (v.n) t + 1/2 (g.n) t^2  -> first positive root
	var a := 0.5 * g.dot(n)
	var b := v.dot(n)
	var t := -1.0
	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			t = -d0 / b
	else:
		var disc := b * b - 4.0 * a * d0
		if disc >= 0.0:
			var sq := sqrt(disc)
			for r in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				if r > 0.0 and (t < 0.0 or r < t):
					t = r
	if t <= 0.0 or t > commit_time:
		return 0

	var hit := p0 + v * t + 0.5 * g * t * t
	var l := _portal_frame(plane).affine_inverse() * hit
	var half := _window_half(plane)
	if absf(l.x) > half.x + commit_margin or absf(l.y) > half.y + commit_margin:
		return 0
	return 1 if d0 > 0.0 else -1


# ---------------------------------------------------------------------------
# 1) BALL TELEPORT
# ---------------------------------------------------------------------------
var _ball_prev: Dictionary = {} # plane instance id -> last ball position

# debug trace: speed right before the teleport and over the next physics ticks
var _trace_ticks := 0
var _trace_before := 0.0
var _trace_label := ""


func _speed_trace() -> void:
	if _trace_ticks <= 0:
		return
	var player := _get_player()
	if player == null:
		_trace_ticks = 0
		return
	_trace_ticks -= 1
	var v := player.linear_velocity
	var msg := "%s | before %.3f | tick+%d total %.3f horiz %.3f vert %.3f" % [
		_trace_label, _trace_before, 3 - _trace_ticks, v.length(), Vector2(v.x, v.z).length(), v.y]
	print(msg)
	DebugDraw2D.set_text("TP SPEED", msg)


func _try_teleport(a1: Array, a12: Array, a2: Array, a22: Array) -> void:
	var player := _get_player()
	if player == null:
		return

	# Track crossings EVERY frame so the stored position never goes stale.
	var pos := player.global_position
	var c1 := _plane_cross(portal1_ref, pos, _ball_prev)
	var c2 := _plane_cross(portal2_ref, pos, _ball_prev)

	if require_area_overlap and not _player_in_any_area([a1, a12, a2, a22]):
		return

	var entry: MeshInstance3D
	var exit: MeshInstance3D
	var dir := 0
	if c1 != 0:
		entry = portal1_ref
		exit = portal2_ref
		dir = c1
	elif c2 != 0:
		entry = portal2_ref
		exit = portal1_ref
		dir = c2
	else:
		return

	# --- Move the RigidBody3D (writing global_transform alone is overridden by physics) ---
	var rot := _portal_rotation(entry, exit)
	var old_xf := player.global_transform
	var speed_before := player.linear_velocity.length()
	var new_origin := exit.global_position + rot * (old_xf.origin - entry.global_position)
	var new_xf := Transform3D((rot * old_xf.basis.orthonormalized()).orthonormalized(), new_origin)

	var rid := player.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, new_xf)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, rot * player.linear_velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, rot * player.angular_velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	player.global_transform = new_xf
	if player.has_method("reset_physics_interpolation"):
		player.call("reset_physics_interpolation")

	# Player.gd keeps a smoothed roll torque: rotate it with the ball so it can't kick.
	var tq = player.get("torque_vector")
	if tq is Vector3:
		player.set("torque_vector", rot * (tq as Vector3))

	# --- Camera ---
	if camera_transit and _ensure_camera():
		if _pend and _cam_first and entry == _p_entry and dir == _p_dir:
			# The camera already went through this very portal first: it is on the exit side
			# and the ball has just caught up. Nothing to remap - just swing the camera
			# around the ball to its follow spot.
			_pend = false
			_start_orbit()
		elif _pend and not _cam_first and entry == _p_exit and exit == _p_entry:
			# The ball came straight back: the camera never left its original space.
			_pend = false
		else:
			_resolve_pending()
			_begin_camera_transit(entry, exit, dir)
		_cam_prev.clear()
		_sync_proxy() # controls follow the ball's space before the next physics step

	_guard_plane = exit
	_guard_t = guard_time

	# Reset tracking so we don't instantly re-trigger on the exit portal.
	_ball_prev.erase(entry.get_instance_id())
	_ball_prev[exit.get_instance_id()] = new_origin

	if draw_debug:
		DebugDraw3D.draw_sphere(old_xf.origin, 0.5, Color.DARK_GREEN)
		DebugDraw3D.draw_sphere(new_origin, 0.5, Color.WEB_MAROON)
		_trace_before = speed_before
		_trace_ticks = 3
		_trace_label = "%s -> %s" % [entry.name, exit.name]
		print("[", entry.name, "] ==> [", exit.name, "] ", "FRONT->BACK" if dir == 1 else "BACK->FRONT",
			" | speed %.3f" % speed_before)


# ---------------------------------------------------------------------------
# 2) CAMERA TRANSIT
#    _p_entry / _p_exit: the portal that was crossed FIRST (by ball or camera) and its partner.
#    _p_R maps entry space -> exit space.
#    Ball first   : ball in exit space, camera still in entry space (virtual anchor = ball mapped back)
#    Camera first : camera in exit space, ball still in entry space (virtual anchor = ball mapped forward)
# ---------------------------------------------------------------------------
var _pend := false
var _cam_first := false
var _pend_time := 0.0
var _p_entry: MeshInstance3D
var _p_exit: MeshInstance3D
var _p_dir := 0
var _p_side := 1.0 # +1 if the crossing was front->back (dir == 1), else -1
var _p_R := Basis.IDENTITY
var _v_anchor := Vector3.ZERO
var _v_cam := Vector3.ZERO
var _cam_prev: Dictionary = {} # plane instance id -> last camera position
var _d_cam := DampedVec3.new() # damped follower for the camera during a transit
var _d_anchor := DampedVec3.new() # ... and for the virtual anchor
var _cam_vel_est := Vector3.ZERO # measured camera / anchor velocity (hand-over into the damped followers)
var _anchor_vel_est := Vector3.ZERO
var _last_cam := Vector3.ZERO
var _last_anchor := Vector3.ZERO
var _have_last := false
var _lost_t := 0.0 # camera-first: how long the ball has not been committed to the window

var _pc = null # PlayerCamera (untyped on purpose)
var _real_cam: Node3D = null
var _ctrl_cam: Camera3D = null # what Player.gd reads for WASD directions
var _frames_excluded := false
var _arm_default := 9.0
var _guard_plane: MeshInstance3D = null # exit portal the ball just came out of
var _guard_t := 0.0 # remaining settle time
var _near_default := 0.05
var _last_mouse_t := -100.0


func _to_exit(p: Vector3) -> Vector3:
	return _p_exit.global_position + _p_R * (p - _p_entry.global_position)


func _to_entry(p: Vector3) -> Vector3:
	return _p_entry.global_position + _p_R.inverse() * (p - _p_exit.global_position)


func _ensure_camera() -> bool:
	if is_instance_valid(_pc) and is_instance_valid(_real_cam):
		return true
	var player := _get_player()
	if player == null or player.get_parent() == null:
		return false
	var pc = player.get_parent().get_node_or_null("PlayerCamera")
	if pc == null:
		return false
	var rc := pc.get_node_or_null("%Camera3D") as Camera3D
	if rc == null:
		return false
	_pc = pc
	_real_cam = rc
	_near_default = rc.near
	_fov_base = rc.fov
	_arm_default = float(pc.SPRING_ARM.spring_length)

	# Player.gd builds its roll torque from this camera's basis. Give it a proxy that is
	# always expressed in the ball's space (see _sync_proxy).
	if _ctrl_cam == null:
		_ctrl_cam = Camera3D.new()
		_ctrl_cam.name = "ControlCam"
		_ctrl_cam.current = false
		add_child(_ctrl_cam)
	player.set("camera_node", _ctrl_cam)
	_sync_proxy()

	if exclude_frames_from_spring_arm and not _frames_excluded:
		for m in [portal1_ref, portal2_ref]:
			var body := (m as Node).get_parent() as CollisionObject3D
			if body:
				_pc.SPRING_ARM.add_excluded_object(body.get_rid())
		_frames_excluded = true
	return true


## Is a camera position a sane place to end a transit? It must be on the expected side of the
## plane (the open side). Where exactly on that side does not matter: in front of a portal
## there is only open air, even if the camera arrived from behind a wall.
func _valid_pos(plane: MeshInstance3D, world_pos: Vector3, side: float) -> bool:
	return _side_of(plane, world_pos) * side > -0.001


## Move the camera state through the portal (forward = entry->exit, else exit->entry).
func _remap_camera(forward: bool) -> void:
	var R: Basis = _p_R if forward else _p_R.inverse()
	_v_anchor = _to_exit(_v_anchor) if forward else _to_entry(_v_anchor)
	_v_cam = _to_exit(_v_cam) if forward else _to_entry(_v_cam)
	_pc.camera_anchor_pos = _v_anchor
	_pc.global_position = _v_anchor
	_real_cam.global_transform = Transform3D(
		(R * _real_cam.global_transform.basis).orthonormalized(), _v_cam)
	# Keep "forward" forward: rotate the mouse-look yaw by the portal's yaw.
	var yaw := _yaw_of(R)
	_pc.target_rot_x += yaw
	_pc.smoothed_rot_x += yaw
	_fx_trigger(1.0) # the pulse peaks exactly at the swap
	_fov_start()


## Fallback: start the camera at the ball (in the destination space); PlayerCamera's own
## smoothing and spring arm then pull it out to a normal, collision-aware follow position.
func _soft_attach(forward: bool) -> void:
	var R: Basis = _p_R if forward else _p_R.inverse()
	var anchor := _to_exit(_v_anchor) if forward else _to_entry(_v_anchor)
	var yaw := _yaw_of(R)
	_pc.target_rot_x += yaw
	_pc.smoothed_rot_x += yaw
	_pc.camera_anchor_pos = anchor
	_pc.global_position = anchor
	var off: Vector3 = R * (_pc.SPRING_ARM.global_transform.basis * Vector3(0.0, 0.0, 1.0))
	_real_cam.global_position = anchor + off
	_real_cam.look_at(anchor, Vector3.UP)
	_soft_cut()


# ---- ball went first ----
func _begin_camera_transit(entry: MeshInstance3D, exit: MeshInstance3D, direction: int) -> void:
	_p_entry = entry
	_p_exit = exit
	_p_dir = direction
	_p_R = _portal_rotation(entry, exit)
	_p_side = 1.0 if direction == 1 else -1.0
	_v_anchor = _pc.camera_anchor_pos
	_v_cam = _real_cam.global_position
	_d_anchor.reset(_v_anchor, _anchor_vel_est)
	_d_cam.reset(_v_cam, _cam_vel_est)
	_cam_first = false
	_pend = true
	_pend_time = 0.0
	_orbit_on = false

	# Camera already past the entry plane? Switch right away.
	if _side_of(_p_entry, _v_cam) * _p_side <= 0.0:
		_finish_ball_first()


# ---- camera went first ----
func _begin_camera_first(entry: MeshInstance3D, exit: MeshInstance3D, direction: int) -> void:
	_p_entry = entry
	_p_exit = exit
	_p_dir = direction
	_p_R = _portal_rotation(entry, exit)
	_p_side = 1.0 if direction == 1 else -1.0
	_v_anchor = _pc.camera_anchor_pos
	_v_cam = _real_cam.global_position
	var cv := _cam_vel_est
	var av := _anchor_vel_est
	_remap_camera(true) # the camera is now on the exit side, looking at the ball through the portal
	_d_anchor.reset(_v_anchor, _p_R * av) # velocities travel through the portal too
	_d_cam.reset(_v_cam, _p_R * cv)
	_cam_first = true
	_pend = true
	_pend_time = 0.0
	_orbit_on = false
	_lost_t = 0.0
	_cam_prev.clear()


func _finish_ball_first() -> void:
	_pend = false
	_p_R = _portal_rotation(_p_entry, _p_exit)
	if _valid_pos(_p_exit, _to_exit(_v_cam), _p_side):
		_remap_camera(true)
	else:
		_soft_attach(true)
	_cam_prev.clear()
	_start_orbit()


func _undo_camera_first() -> void:
	_pend = false
	_p_R = _portal_rotation(_p_entry, _p_exit)
	if _valid_pos(_p_entry, _to_entry(_v_cam), _p_side):
		_remap_camera(false)
	else:
		_soft_attach(false)
	_cam_prev.clear()
	_start_orbit()


func _resolve_pending() -> void:
	if not _pend:
		return
	if not is_instance_valid(_pc) or not is_instance_valid(_real_cam):
		_pend = false
		return
	if _cam_first:
		_undo_camera_first()
	else:
		_finish_ball_first()


func _follow_vec(state: DampedVec3, target: Vector3, smooth_time: float, delta: float, vmax: float = INF) -> Vector3:
	if smooth_motion:
		return state.step(target, smooth_time, delta, vmax)
	state.value = state.value.lerp(target, 1.0 - exp(-delta / maxf(smooth_time, 0.0001)))
	state.velocity = Vector3.ZERO
	return state.value


## Measure camera / anchor velocity (ignoring teleport jumps) so the damped followers can
## start with the velocity the camera really had.
func _track_motion(delta: float) -> void:
	var cp := _real_cam.global_position
	var ap: Vector3 = _pc.camera_anchor_pos
	if _have_last and delta > 0.0:
		var cv := (cp - _last_cam) / delta
		var av := (ap - _last_anchor) / delta
		if cv.length() < 80.0 and av.length() < 80.0:
			_cam_vel_est = _cam_vel_est.lerp(cv, 0.35)
			_anchor_vel_est = _anchor_vel_est.lerp(av, 0.35)
	_last_cam = cp
	_last_anchor = ap
	_have_last = true


func _run_pending(delta: float) -> void:
	var player := _get_player()
	if player == null:
		_pend = false
		return
	_p_R = _portal_rotation(_p_entry, _p_exit)

	# Stuck guard: resolve cleanly instead of hanging forever.
	_pend_time += delta
	if _pend_time > (camera_first_timeout if _cam_first else transit_timeout):
		_resolve_pending()
		return

	# Camera went first but the ball is no longer heading for that window -> bring the camera back.
	if _cam_first:
		if _predict_crossing(player, _p_entry) == _p_dir:
			_lost_t = 0.0
		else:
			_lost_t += delta
			if _lost_t > commit_grace:
				_resolve_pending()
				return

	# Virtual anchor = ball expressed in the camera's space, smoothed like PlayerCamera.
	var anchor_node := player.get_node_or_null("CameraAnchor") as Node3D
	var real_anchor: Vector3 = anchor_node.global_position if anchor_node else player.global_position
	var target_anchor: Vector3 = _to_exit(real_anchor) if _cam_first else _to_entry(real_anchor)
	_v_anchor = _follow_vec(_d_anchor, target_anchor, follow_smooth_time, delta)
	_pc.camera_anchor_pos = _v_anchor
	_pc.global_position = _v_anchor

	var arm := _pc.SPRING_ARM as Node3D
	var cam_target: Vector3 = _v_anchor + arm.global_transform.basis \
		* Vector3(0.0, 0.0, float(_pc.SPRING_ARM.spring_length))

	# Camera still left behind on the entry side (ball stopped / slow)? After a short grace period
	# the follower's TARGET slides from the normal trailing spot toward a point on the window axis
	# that gets closer and closer to the plane (so the camera crosses INSIDE the window). It is a
	# single critically damped follower, so the camera simply accelerates - no force fighting a lerp.
	var pull := 0.0
	if force_through and not _cam_first:
		pull = smoothstep(0.0, force_ramp, _pend_time - force_delay)
	var target: Vector3 = cam_target
	var vmax := INF
	var st := follow_smooth_time
	if pull > 0.0:
		var z := _side_of(_p_entry, _v_cam) * _p_side
		var aim := _p_entry.global_position + _plane_normal(_p_entry) * _p_side * (z * 0.55 - 0.25)
		target = cam_target.lerp(aim, pull)
		vmax = force_speed
		st = lerpf(follow_smooth_time, follow_smooth_time * 0.6, pull)
	_v_cam = _follow_vec(_d_cam, target, st, delta, vmax)

	_real_cam.global_position = _v_cam
	_real_cam.look_at(_v_anchor, Vector3.UP)

	if _cam_first:
		# Camera backed out through the exit window again -> undo.
		if _side_of(_p_exit, _v_cam) * _p_side < -0.001:
			_undo_camera_first()
	else:
		# Camera reached the entry window -> switch sides.
		if _side_of(_p_entry, _v_cam) * _p_side <= 0.0:
			_finish_ball_first()


func _update_camera(delta: float) -> void:
	if not camera_transit or not _ensure_camera():
		return

	var gp := _get_player()
	if gp != null:
		_grounded = _is_grounded(gp)

	if _pend:
		_run_pending(delta)
	else:
		_track_motion(delta)
		_update_orbit(delta)
		if camera_fields:
			_field_update(delta)
		if camera_first_transit:
			_detect_camera_cross()

	_update_arm_guard(delta)
	_sync_proxy()
	_update_near(delta)
	_update_fov(delta)
	_build_slabs()
	_update_slabs()

	if draw_debug:
		if camera_fields:
			_draw_fields()
		DebugDraw2D.set_text("PORTAL CAM", "pend=%s camfirst=%s field=%.2f" % [_pend, _cam_first, _fld_w])


## The camera is the ball's eye: it only goes through a window first if the ball is on course
## to go through that same window right after it. Otherwise it simply moves through (no teleport).
func _detect_camera_cross() -> void:
	var player := _get_player()
	if player == null:
		return
	var pos := _real_cam.global_position
	var c1 := _plane_cross(portal1_ref, pos, _cam_prev)
	var c2 := _plane_cross(portal2_ref, pos, _cam_prev)
	if c1 != 0 and _predict_crossing(player, portal1_ref) == c1:
		_begin_camera_first(portal1_ref, portal2_ref, c1)
	elif c2 != 0 and _predict_crossing(player, portal2_ref) == c2:
		_begin_camera_first(portal2_ref, portal1_ref, c2)


## Control camera = real camera expressed in the BALL's space.
func _sync_proxy() -> void:
	if _ctrl_cam == null or not is_instance_valid(_real_cam):
		return
	var b := _real_cam.global_transform.basis
	if _pend and is_instance_valid(_p_entry) and is_instance_valid(_p_exit):
		var rot := _portal_rotation(_p_entry, _p_exit)
		b = (rot.inverse() * b) if _cam_first else (rot * b)
	_ctrl_cam.global_transform = Transform3D(b.orthonormalized(), _real_cam.global_position)


## Smaller near plane around portals so the screen quad doesn't visibly clip.
func _update_near(delta: float) -> void:
	var cam := _real_cam as Camera3D
	if cam == null or camera_near_during_transit <= 0.0:
		return
	var target := camera_near_during_transit if (_pend or _fld_w > 0.01) else _near_default
	cam.near = lerpf(cam.near, target, clampf(12.0 * delta, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Auto roll: if the ball only just passed through a portal and then rests (so the camera is
# still being brought through), give it a gentle push away from the exit portal. The camera
# then simply follows the moving ball through the window - no special camera work needed.
# It only acts while the ball is nearly still, so it never fights the player's own input.
# ---------------------------------------------------------------------------
func _auto_roll() -> void:
	if not auto_roll or not _pend or _cam_first or _pend_time < roll_delay:
		return
	if not is_instance_valid(_p_exit):
		return
	var player := _get_player()
	if player == null:
		return
	var n := _plane_normal(_p_exit)
	var out := Vector3(n.x, 0.0, n.z) * _p_side # away from the exit portal, on the side the ball came out
	if out.length() < 0.01:
		return
	out = out.normalized()
	var v := player.linear_velocity
	if Vector2(v.x, v.z).length() > roll_idle_speed:
		return # already moving (player is steering): leave it alone
	var along := v.dot(out)
	if along >= roll_speed:
		return
	player.sleeping = false
	player.apply_central_force(out * roll_force * clampf(1.0 - along / roll_speed, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Camera settle: PlayerCamera moves the camera toward its follow spot in a straight line. After
# a transit the camera can be on the OPPOSITE side of the ball from that spot (e.g. you reversed
# into the portal and the camera went first) - a straight line would cut right through the portal
# and the ball. So for a moment the camera is moved in polar coordinates AROUND the ball instead:
# angle, height and distance are eased separately, which gives a curved path to the right side.
# ---------------------------------------------------------------------------
var _orbit_on := false
var _orbit_t := 0.0
var _o_yaw := DampedFloat.new()
var _o_pitch := DampedFloat.new()
var _o_r := DampedFloat.new()


func _start_orbit() -> void:
	if not orbit_settle or not is_instance_valid(_pc) or not is_instance_valid(_real_cam):
		return
	var v: Vector3 = _real_cam.global_position - _pc.camera_anchor_pos
	var d := v.normalized() if v.length() > 0.001 else Vector3.BACK
	_o_r.reset(maxf(v.length(), 0.25))
	_o_yaw.reset(atan2(d.x, d.z))
	_o_pitch.reset(asin(clampf(d.y, -1.0, 1.0)))
	_orbit_on = true
	_orbit_t = 0.0


func _update_orbit(delta: float) -> void:
	if not _orbit_on:
		return
	_orbit_t += delta
	var arm := _pc.SPRING_ARM as Node3D
	var dir: Vector3 = arm.global_transform.basis * Vector3(0.0, 0.0, 1.0)
	var yaw_t := atan2(dir.x, dir.z)
	var pitch_t := asin(clampf(dir.y, -1.0, 1.0))
	var r_t: float = (_pc.CAMERA.global_position - arm.global_position).length() # collision-aware distance

	# Angle, height and distance are damped separately -> a smooth curved path AROUND the ball.
	var st := 1.0 / maxf(orbit_speed, 0.1)
	var dyaw := wrapf(yaw_t - _o_yaw.value, -PI, PI) # shortest way around
	var yaw := _o_yaw.step(_o_yaw.value + dyaw, st, delta, deg_to_rad(orbit_max_deg))
	var pitch := _o_pitch.step(pitch_t, st, delta)
	var rad := _o_r.step(r_t, st, delta)

	var anchor: Vector3 = _pc.camera_anchor_pos
	var cp := cos(pitch)
	_real_cam.global_position = anchor + Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp) * rad
	_real_cam.look_at(anchor, Vector3.UP)

	if _orbit_t > orbit_max_time or (absf(dyaw) < deg_to_rad(4.0) \
			and absf(r_t - rad) < 0.35 and absf(pitch_t - pitch) < deg_to_rad(5.0)):
		_orbit_on = false # arrived: hand the camera back to PlayerCamera


# ---------------------------------------------------------------------------
# Exit guard (short settle only): right after the camera has come through, the ball may rest
# only a short way in front of the exit portal. A full-length arm would then put the camera
# BEHIND that portal. For `guard_time` seconds the arm is shortened just enough to keep the
# camera in front of the exit plane. It is NOT a permanent wall: it is cancelled the moment you
# touch the mouse or the ball heads for any portal window, and it only shortens quickly and
# releases slowly (no pop).
# ---------------------------------------------------------------------------
func _update_arm_guard(delta: float) -> void:
	var arm = _pc.SPRING_ARM
	var want := _arm_default
	if exit_guard and _guard_t > 0.0 and not _pend and is_instance_valid(_guard_plane):
		_guard_t -= delta
		var player := _get_player()
		var mouse_used := Time.get_ticks_msec() * 0.001 - _last_mouse_t < 0.3
		var committed := player != null and (
			_predict_crossing(player, portal1_ref) != 0 or _predict_crossing(player, portal2_ref) != 0)
		if mouse_used or committed:
			_guard_t = 0.0
		else:
			var a: Vector3 = _pc.camera_anchor_pos
			var raw := _side_of(_guard_plane, a)
			var s := signf(raw)
			if s != 0.0:
				var d := raw * s # ball's distance in front of the plane (its own side)
				var dir: Vector3 = arm.global_transform.basis * Vector3(0.0, 0.0, 1.0)
				var dn := dir.dot(_plane_normal(_guard_plane)) * s
				if dn < -0.01: # camera would sit toward the portal
					var t_hit := d / -dn
					if t_hit < _arm_default:
						want = maxf(t_hit - guard_margin, 0.8)
				if d > _arm_default + 1.0:
					_guard_t = 0.0 # far enough away, guard no longer needed
	var cur := float(arm.spring_length)
	if absf(cur - want) > 0.001:
		var rate := 10.0 if want < cur else 3.0 # shorten fast, release slowly
		arm.spring_length = lerpf(cur, want, 1.0 - exp(-rate * delta))


# ---------------------------------------------------------------------------
# 5) POLISH
# ---------------------------------------------------------------------------

# --- 5a) Screen shader pulse -------------------------------------------------
# One full-screen canvas shader (built in code, no extra files): radial zoom blur toward the
# portal, a tiny chromatic split and a vignette, strongest at the edges. It builds up as the
# camera nears a window, peaks at the swap (hiding it) and fades out. Hidden when idle, so it
# costs nothing. The rare hard cut (soft attach) also dips to dark through the same shader.
const FX_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float dip : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	float r = length(d * vec2(1.0, 0.75));
	float edge = smoothstep(0.05, 0.9, r);
	float amount = intensity * (0.03 + 0.08 * edge);
	vec3 acc = vec3(0.0);
	const int TAPS = 8;
	for (int i = 0; i < TAPS; i++) {
		float t = float(i) / float(TAPS - 1);
		vec2 o = d * amount * t;
		float ca = intensity * 0.012 * edge * (0.5 + t);
		acc.r += texture(screen_tex, uv - o - d * ca).r;
		acc.g += texture(screen_tex, uv - o).g;
		acc.b += texture(screen_tex, uv - o + d * ca).b;
	}
	acc /= float(TAPS);
	acc += vec3(intensity * 0.05 * (1.0 - edge));
	float vig = 1.0 - intensity * 0.4 * smoothstep(0.35, 1.0, r * 1.4);
	acc = mix(acc * vig, vec3(0.0), dip);
	COLOR = vec4(acc, 1.0);
}
"""

var _fx_rect: ColorRect = null
var _fx_mat: ShaderMaterial = null
var _fx_pulse := 0.0
var _fx_dip := 0.0
var _fx_prox := 0.0


func _ensure_fx() -> void:
	if _fx_rect != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 99
	add_child(layer)
	var shader := Shader.new()
	shader.code = FX_SHADER
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = shader
	_fx_rect = ColorRect.new()
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.material = _fx_mat
	_fx_rect.visible = false
	layer.add_child(_fx_rect)


func _fx_trigger(strength: float) -> void:
	if crossing_fx:
		_fx_pulse = maxf(_fx_pulse, strength)


## The rare hard cut: dip to dark and pulse, then fade back in.
func _soft_cut() -> void:
	if soft_cut_fade:
		_fx_dip = 1.0
	_fx_trigger(1.0)


func _update_fx(delta: float) -> void:
	_fx_pulse = maxf(_fx_pulse - delta / maxf(fx_pulse_time, 0.05), 0.0)
	_fx_dip = maxf(_fx_dip - delta / maxf(soft_cut_time, 0.05), 0.0)

	# Proximity: how close the camera is to a window it could pass through.
	var best := 0.0
	var focus := Vector2(0.5, 0.5)
	var cam: Camera3D = _real_cam as Camera3D if is_instance_valid(_real_cam) else null
	if crossing_fx and fx_proximity and cam != null:
		for plane in [portal1_ref, portal2_ref]:
			var l: Vector3 = _portal_frame(plane).affine_inverse() * cam.global_position
			var half := _window_half(plane)
			var az := absf(l.z)
			if az < fx_range and absf(l.x) < half.x + 0.3 and absf(l.y) < half.y + 0.3:
				var w := 1.0 - smoothstep(0.0, fx_range, az)
				if w > best:
					best = w
					var pos: Vector3 = plane.global_position
					if not cam.is_position_behind(pos):
						focus = cam.unproject_position(pos) / get_viewport().get_visible_rect().size
	_fx_prox = move_toward(_fx_prox, best, 6.0 * delta)

	var player := _get_player()
	var spd := 0.0
	if player != null:
		spd = clampf(player.linear_velocity.length() / 8.0, 0.0, 1.0) # faster = stronger
	var intensity := clampf(maxf(_fx_prox * 0.55 * (0.4 + 0.6 * spd), _fx_pulse) * fx_strength, 0.0, 1.0)
	var dip := _fx_dip * _fx_dip * 0.9

	if intensity <= 0.002 and dip <= 0.002:
		if _fx_rect != null:
			_fx_rect.visible = false # idle: no screen-texture copy at all
		return
	_ensure_fx()
	_fx_rect.visible = true
	_fx_mat.set_shader_parameter("intensity", intensity)
	_fx_mat.set_shader_parameter("dip", dip)
	_fx_mat.set_shader_parameter("center", focus)


# --- 5b) FOV kick --------------------------------------------------------------
var _fov_base := 75.0
var _fov_t := 1.0
var _fov_dirty := false


func _fov_start() -> void:
	if fov_kick_deg > 0.0:
		_fov_t = 0.0


## A small swell that starts at zero, so it can never pop.
func _update_fov(delta: float) -> void:
	var cam: Camera3D = _real_cam as Camera3D if is_instance_valid(_real_cam) else null
	if cam == null:
		return
	if _fov_t < 1.0:
		_fov_t = minf(_fov_t + delta / 0.6, 1.0)
		cam.fov = _fov_base + fov_kick_deg * sin(_fov_t * PI)
		_fov_dirty = true
	elif _fov_dirty:
		cam.fov = _fov_base
		_fov_dirty = false


# --- 5c) Portal volume ("slab") ------------------------------------------------
# While the camera is within a few cm of a portal plane, the near plane clips the flat quad and
# the real scene behind it flashes through. A thin box around the quad (same material, same render
# layer) swallows the camera instead and draws the portal view on its inner faces. The portal
# shader projects from WORLD position, and every point on a view ray maps to the same pixel,
# so the volume shows exactly the same image as the quad: no seam, no shimmer. It is only
# visible when the camera is close, so its sides are never seen.
var _slabs: Array[MeshInstance3D] = []
var _slabs_state := 0 # 0 = not built yet, 1 = built, -1 = gave up (no PortalMaster material)
var _slab_wait := 0


func _build_slabs() -> void:
	if not portal_slab or _slabs_state != 0:
		return
	_slab_wait += 1
	var masks := [portal1_ref, portal2_ref]
	for m in masks:
		var mi := m as MeshInstance3D
		if mi.material_override == null or mi.mesh == null:
			if _slab_wait > 120:
				_slabs_state = -1 # nothing to share: stay quietly disabled
			return
	for m in masks:
		var mask := m as MeshInstance3D
		var box_aabb := mask.mesh.get_aabb()
		var box := BoxMesh.new()
		box.size = Vector3(box_aabb.size.x, box_aabb.size.y,
			slab_thickness / maxf(mask.global_transform.basis.get_scale().z, 0.001))
		var slab := MeshInstance3D.new()
		slab.name = "PortalSlab"
		slab.mesh = box
		slab.position = box_aabb.get_center()
		slab.material_override = mask.material_override # same portal material, same uniforms
		slab.layers = mask.layers # seen by exactly the cameras that see the mask
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slab.visible = false
		mask.add_child(slab)
		_slabs.append(slab)
	_slabs_state = 1


func _update_slabs() -> void:
	if _slabs_state != 1 or not is_instance_valid(_real_cam):
		return
	var masks := [portal1_ref, portal2_ref]
	for i in 2:
		var plane: MeshInstance3D = masks[i]
		var l: Vector3 = _portal_frame(plane).affine_inverse() * _real_cam.global_position
		var half := _window_half(plane)
		_slabs[i].visible = absf(l.z) < slab_range \
			and absf(l.x) < half.x + 0.25 and absf(l.y) < half.y + 0.25


# ---------------------------------------------------------------------------
# 3) PORTAL FIELDS - small, soft, invisible. Each portal mouth owns a little ellipsoid whose
#    strength fades smoothly to 0 at its edge. A field only wakes up while the ball is
#    COMMITTED to that portal's window; it then steers the view so the camera sits on the
#    ball's own path, which carries the camera through the same window as the ball.
# ---------------------------------------------------------------------------
var _fw: Array[float] = [0.0, 0.0] # smoothed strength of field 1 / field 2
var _fld_w := 0.0 # combined strength


## 0..1 smooth falloff of a portal's field at a world point.
func _field_at(plane: MeshInstance3D, p: Vector3) -> float:
	var l: Vector3 = _portal_frame(plane).affine_inverse() * p
	var q := sqrt((l.x * l.x + l.y * l.y) / (field_width * field_width) \
		+ (l.z * l.z) / (field_length * field_length))
	return 1.0 - smoothstep(0.0, 1.0, q)


func _field_update(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	var planes := [portal1_ref, portal2_ref]
	for i in 2:
		var pl: MeshInstance3D = planes[i]
		var target := 0.0
		if _predict_crossing(player, pl) != 0:
			target = _field_at(pl, player.global_position)
		var rate := field_attack if target > _fw[i] else 1.0 / maxf(field_hold, 0.05)
		_fw[i] = move_toward(_fw[i], target, rate * delta)
	_fld_w = 1.0 - (1.0 - _fw[0]) * (1.0 - _fw[1])
	if _fld_w > 0.001:
		_field_steer(player, delta, planes)


func _field_steer(player: RigidBody3D, delta: float, planes: Array) -> void:
	if Input.is_action_pressed("swing_hotkey"):
		return
	if Time.get_ticks_msec() * 0.001 - _last_mouse_t < field_mouse_pause:
		return

	var vh := Vector3(player.linear_velocity.x, 0.0, player.linear_velocity.z)
	var cam_h: Vector3 = _real_cam.global_position - _pc.camera_anchor_pos
	cam_h.y = 0.0
	if vh.length() < 0.3 or cam_h.length() < 0.1:
		return
	vh = vh.normalized()
	cam_h = cam_h.normalized()
	# The camera sits on the ball's path: behind it, or ahead of it (whichever is nearer to
	# where it is now) - never a 180 degree spin.
	var cand := -vh if cam_h.dot(-vh) >= 0.0 else vh

	var arm_len := maxf(float(_pc.SPRING_ARM.spring_length), 0.1)
	var psum := 0.0
	var wsum := 0.0
	for i in 2:
		if _fw[i] > 0.001:
			var pl: MeshInstance3D = planes[i]
			psum += asin(clampf((player.global_position.y - pl.global_position.y) / arm_len, -0.9, 0.9)) * _fw[i]
			wsum += _fw[i]
	if wsum <= 0.001:
		return

	var k := clampf(field_turn_speed * _fld_w * delta, 0.0, 1.0)
	var diff := wrapf(atan2(cand.x, cand.z) - float(_pc.target_rot_x), -PI, PI)
	if absf(diff) > deg_to_rad(2.0):
		var max_step := deg_to_rad(field_max_turn_deg) * delta
		_pc.target_rot_x += clampf(diff * k, -max_step, max_step)

	# Camera height = window-centre height, so it passes through the middle of the window.
	var pitch_t := clampf(psum / wsum, deg_to_rad(float(_pc.min_pitch)), deg_to_rad(float(_pc.max_pitch)))
	_pc.target_rot_y = lerpf(float(_pc.target_rot_y), pitch_t, k)


func _draw_fields() -> void:
	const SEG := 24
	var planes := [portal1_ref, portal2_ref]
	for i in 2:
		var pl: MeshInstance3D = planes[i]
		var xf := _portal_frame(pl)
		var col := Color(0.2, 0.6, 0.6, 1.0).lerp(Color.CYAN, clampf(_fw[i], 0.0, 1.0))
		var prev := [Vector3.ZERO, Vector3.ZERO]
		for k in range(SEG + 1):
			var th := TAU * float(k) / float(SEG)
			var cur := [
				xf * Vector3(cos(th) * field_width, sin(th) * field_width, 0.0), # ring in the portal plane
				xf * Vector3(cos(th) * field_width, 0.0, sin(th) * field_length), # profile along the axis
			]
			if k > 0:
				for j in 2:
					DebugDraw3D.draw_line(prev[j], cur[j], col)
			prev = cur
