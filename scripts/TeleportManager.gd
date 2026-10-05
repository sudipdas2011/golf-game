@tool
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
	DebugDraw3D.draw_box(
		collshape1.global_position,
		collshape1.global_basis.get_rotation_quaternion(),
		collshape1.shape.size,
		Color.RED,
		true
	)
	DebugDraw3D.draw_box(
		collshape2.global_position,
		collshape2.global_basis.get_rotation_quaternion(),
		collshape2.shape.size,
		Color.RED,
		true
	)
	
	# Debug 2 (Back Side Shapes)
	DebugDraw3D.draw_box(
		collshape12.global_position,
		collshape12.global_transform.basis.get_rotation_quaternion(),
		collshape12.shape.size,
		Color.BLUE,
		true
	)
	DebugDraw3D.draw_box(
		collshape22.global_position,
		collshape22.global_basis.get_rotation_quaternion(),
		collshape22.shape.size,
		Color.BLUE,
		true
	)

	# Collision detection with areas
	get_area_collision(area1, scene_object_group)
	get_area_collision(area12, scene_object_group)
	get_area_collision(area2, scene_object_group)
	get_area_collision(area22, scene_object_group)

func get_area_collision(area, group):
	for body in area.get_overlapping_bodies():
		var node : Node = body
		while node != null:
			if node.is_in_group("SceneObject"):
				break
			node = node.get_parent()
		if node != null:
			continue
		print(str(area), body.get_path())

###
