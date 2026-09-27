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
var collshape_thickness := 0.5




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	#scaling collshape and mask auto
	portal1_ref_scale = portal1_ref.scale
	portal2_ref_scale = portal2_ref.scale
	##collshape scaling
	collshape1_scale = Vector3(portal1_ref_scale.x, portal1_ref_scale.y, collshape_thickness)
	collshape2_scale = Vector3(portal2_ref_scale.x, portal2_ref_scale.y, collshape_thickness)
	collshape1.shape.size = collshape1_scale
	collshape2.shape.size = collshape2_scale
	#rotation
	collshape1.rotation = portal1_ref.rotation
	collshape2.rotation = portal2_ref.rotation
	#no 2
	collshape12_scale = Vector3(portal1_ref_scale.x, portal1_ref_scale.y, collshape_thickness)
	collshape22_scale = Vector3(portal2_ref_scale.x, portal2_ref_scale.y, collshape_thickness)
	collshape12.shape.size = collshape12_scale
	collshape22.shape.size = collshape22_scale
	#rotation
	collshape12.rotation = portal1_ref.rotation
	collshape22.rotation = portal2_ref.rotation



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#turn primary_portal into primary_portal_ref
	if primary_portal == true:
		primary_portal_ref = portal1_ref
	elif primary_portal == false:
		primary_portal_ref = portal2_ref
		
		

func _physics_process(delta: float) -> void:
	
	
	#detect collisions with Mask1 and Mask2
	#detect is nayy object collides with a meshinstance3d var "portal1_ref"
	area1.global_position = portal1_ref.global_position + Vector3(0.0, 0.0, (collshape_thickness/2))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area1.global_position))
	area2.global_position = portal2_ref.global_position + Vector3(0.0, 0.0, (collshape_thickness/2))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area2.global_position))
	#no 2
	area12.global_position = portal1_ref.global_position + Vector3(0.0, 0.0, (collshape_thickness/2))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area12.global_position))
	area22.global_position = portal2_ref.global_position + Vector3(0.0, 0.0, (collshape_thickness/2))
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), area22.global_position))
	
	#debug 1 
	DebugDraw3D.draw_box(
		collshape1.global_position,
		collshape1.global_basis.get_rotation_quaternion(),
		collshape1.shape.size,
		Color.BLUE,
		true
	)
	DebugDraw3D.draw_box(
		collshape2.global_position,
		collshape2.global_basis.get_rotation_quaternion(),
		collshape2.shape.size,
		Color.RED,
		true
	)
	#debug 2
	DebugDraw3D.draw_box(
		collshape12.global_position,
		collshape12.global_transform.basis.get_rotation_quaternion(),
		collshape12.shape.size,
		Color.GREEN,
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
	for body1 in area1.get_overlapping_bodies():
		var node : Node = body1
		while node != null:
			if node.is_in_group("SceneObject"):
				break
			node = node.get_parent()
		if node != null:
			continue
		print("AREA1 :", body1.get_path())
	
	for body2 in area2.get_overlapping_bodies():
		var node : Node = body2
		while node != null:
			if node.is_in_group("SceneObject"):
				break
			node = node.get_parent()
		if node != null:
			continue
		print("AREA2 :", body2.get_path())
