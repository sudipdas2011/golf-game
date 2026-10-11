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

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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


# Called every frame. 'delta' is the elapsed time does not change.
func _process(delta: float) -> void:
	# Turn primary_portal into primary_portal_ref
	if primary_portal == true:
		primary_portal_ref = portal1_ref
	elif primary_portal == false:
		primary_portal_ref = portal2_ref


func _physics_process(delta: float) -> void:
	# 1. Sync rotations from the portals directly via their global bases
	# .orthonormalized() forces the matrix scale back to exactly 1x1x1 (Vector3.ONE)
	area1.global_transform.basis = portal1_ref.global_transform.basis.orthonormalized()
	area12.global_transform.basis = portal1_ref.global_transform.basis.orthonormalized()
	area2.global_transform.basis = portal2_ref.global_transform.basis.orthonormalized()
	area22.global_transform.basis = portal2_ref.global_transform.basis.orthonormalized()

	# 2. Calculate offsets along the local Z-axis (basis.z)
	var offset_dist = collshape_thickness / 2.0
	
	# In Godot, -basis.z is Forward, +basis.z is Backward
	var forward_offset1 = -portal1_ref.global_transform.basis.z * offset_dist
	var backward_offset1 = portal1_ref.global_transform.basis.z * offset_dist
	
	var forward_offset2 = -portal2_ref.global_transform.basis.z * offset_dist
	var backward_offset2 = portal2_ref.global_transform.basis.z * offset_dist
	
	# 3. Apply the oriented offsets to the global positions
	# Area1 and Area2 go to the FRONT side (-Z)
	area1.global_position = portal1_ref.global_position + forward_offset1
	area2.global_position = portal2_ref.global_position + forward_offset2
	
	# Area12 and Area22 go to the BACK side (+Z)
	area12.global_position = portal1_ref.global_position + backward_offset1
	area22.global_position = portal2_ref.global_position + backward_offset2
	
	# Draw Gizmos
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area1.global_position))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area2.global_position))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area12.global_position))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area22.global_position))
	
	# Debug 1 (Front Side Shapes)
	DebugDraw3D.draw_box(collshape1.global_position, collshape1.global_basis.get_rotation_quaternion(), collshape1.shape.size, Color.RED, true )
	DebugDraw3D.draw_box(collshape2.global_position, collshape2.global_basis.get_rotation_quaternion(), collshape2.shape.size, Color.RED, true )
	
	# Debug 2 (Back Side Shapes)
	DebugDraw3D.draw_box(collshape12.global_position, collshape12.global_transform.basis.get_rotation_quaternion(), collshape12.shape.size, Color.BLUE, true )
	DebugDraw3D.draw_box(collshape22.global_position, collshape22.global_basis.get_rotation_quaternion(), collshape22.shape.size, Color.BLUE, true )

	# Collision detection with areas
	var arcollobj1 = get_area_collision(area1, scene_object_group)
	var arcollobj12 = get_area_collision(area12, scene_object_group)
	var arcollobj2 = get_area_collision(area2, scene_object_group)
	var arcollobj22 = get_area_collision(area22, scene_object_group)
	var arcollobjs = (arcollobj1 + arcollobj2 + arcollobj12 + arcollobj22)
	var arcollobjArray = filter_array_dups(arcollobjs)
	
	teleport(arcollobj1, arcollobj12, arcollobj2, arcollobj22)
	
	
	
func filter_array_dups(array: Array) -> Array:
	var output := {}
	for element in array:
		output[element] = true  # Directly overwrite, don't check 'if not element in output'
	return output.keys()
	
	
func get_area_collisionx(area, group):
	for body in area.get_overlapping_bodies():
		var node : Node = body
		while node != null:
			if node.is_in_group("SceneObject"):
				break
			node = node.get_parent()
		if node != null:
			continue
		#print(str(area), body.get_instance_id())
		return body.name
		#return body.get_instance_id()
	
	
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
	
	
func get_active_portalx(arr1, arr12, arr2, arr22):
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
				#print("Player found in: ", array_name)
				return array_name
	
	
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
	
	
var previous_distancesx: Dictionary = {}
func get_plane_collisionx(plane: Node3D, com: Vector3):
	var P: Vector3 = plane.global_position
	var n: Vector3 = plane.global_transform.basis.z.normalized()
	var d: float = (com - P).dot(n)

	var id: int = plane.get_instance_id()

	if previous_distances.has(id):
		var prvd: float = previous_distances[id]

		if prvd * d < 0.0:
			print("Center of mass crossed plane: ", plane.name)
			return true
	previous_distances[id] = d
	
	
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
	
	
func teleport(arr1, arr12, arr2, arr22):
	var active_areas := get_active_portal(arr1, arr12, arr2, arr22)
	var exit_areas: Array[String] = []

	for portal in active_areas:
		var exit_portal := get_exit_portal(portal)
		if exit_portal != "":
			exit_areas.append(exit_portal)
	#print("ACTIVEa:", active_areas)
	#print("EXITa:", exit_areas)
	
	var active_portal_pos := Vector3.ZERO
	var exit_portal_pos := Vector3.ZERO
	var active_portal_rot : Quaternion
	var exit_portal_rot : Quaternion
	var active_portal_name : String
	var exit_portal_name : String

	if "arr1" in active_areas or "arr12" in active_areas:
		active_portal_pos = portal1_ref.global_position
		exit_portal_pos = portal2_ref.global_position
		active_portal_rot = portal1_ref.quaternion
		exit_portal_rot = portal2_ref.quaternion
		active_portal_name = portal1_ref.name
		exit_portal_name = portal2_ref.name
	elif "arr2" in active_areas or "arr22" in active_areas:
		active_portal_pos = portal2_ref.global_position
		exit_portal_pos = portal1_ref.global_position
		active_portal_rot = portal2_ref.quaternion
		exit_portal_rot = portal1_ref.quaternion
		active_portal_name = portal2_ref.name
		exit_portal_name = portal1_ref.name
	#print("ACTIVEpos:", active_portal_pos)
	#print("EXITpos:", exit_portal_pos)
	DebugDraw3D.draw_gizmo(Transform3D(Basis(),active_portal_pos), Color.DARK_GREEN, true)
	DebugDraw3D.draw_gizmo(Transform3D(Basis(),exit_portal_pos), Color.WEB_MAROON, true)
	
	############################################
	
	var pointApos: Vector3 = $"../../PlayerMain".global_position

	var pointArot: Quaternion = $"../../PlayerMain".global_transform.basis.get_rotation_quaternion()

	# Convert portal rotations to GLOBAL rotations
	active_portal_rot = portal1_ref.global_transform.basis.get_rotation_quaternion() if ("arr1" in active_areas or "arr12" in active_areas) else portal2_ref.global_transform.basis.get_rotation_quaternion()
	exit_portal_rot = portal2_ref.global_transform.basis.get_rotation_quaternion() if ("arr1" in active_areas or "arr12" in active_areas) else portal1_ref.global_transform.basis.get_rotation_quaternion()
	# 180-degree turn through the portal
	var portal_flip := Quaternion(Vector3.UP, PI)
	# Transform from entrance space to exit space
	var portal_transform: Quaternion = exit_portal_rot * portal_flip * active_portal_rot.inverse()
	# Calculate destination position and rotation
	var pointBpos: Vector3 = exit_portal_pos + portal_transform * (pointApos - active_portal_pos)
	var pointBrot: Quaternion = portal_transform * pointArot
	# Visualize both points
	DebugDraw3D.draw_sphere(pointApos, 0.5, Color.DARK_GREEN)
	DebugDraw3D.draw_sphere(pointBpos, 0.5, Color.WEB_MAROON)

	#############################################
	
	var crossed_portal := ""
	var crossing_direction := 0

	var crossing1 = get_plane_collision(portal1_ref, pointApos)
	var crossing2 = get_plane_collision(portal2_ref, pointApos)

	if crossing1 != 0:
		crossed_portal = "Mask1"
		crossing_direction = crossing1
	elif crossing2 != 0:
		crossed_portal = "Mask2"
		crossing_direction = crossing2

	if crossed_portal != "":
		var direction := "FRONT -> BACK" if crossing_direction == 1 else "BACK -> FRONT"
		var exit_portal := "Mask2" if crossed_portal == "Mask1" else "Mask1"

		print("[", crossed_portal, "] ======>> [", exit_portal, "] | Direction: ", direction)
