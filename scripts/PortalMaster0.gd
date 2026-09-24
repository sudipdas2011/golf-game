extends Node3D

#####
@export var P1_rot : Vector3
@export var P2_rot : Vector3
#####

@onready var player_cam: PlayerCamera = $PlayerCamera
@onready var cam3d: Camera3D = %PlayerCamera/Camera3D

@onready var p1_mask := $Portal1/Mask
@onready var p2_mask := $Portal2/Mask

var p1_pos: Vector3
var p2_pos: Vector3

var cam1_pos: Vector3
var cam2_pos: Vector3


func _ready() -> void:
	#####
	P1_rot = %Portal1.rotation
	P2_rot = %Portal2.rotation
	#####


func _process(delta: float) -> void:
	#####
	%Portal1.rotation = P1_rot
	%Portal2.rotation = P2_rot
	#####
	
	# 1. Update Portal Origins
	p1_pos = p1_mask.global_position
	p2_pos = p2_mask.global_position

	# 2. Calculate Half-Widths
	var p1_half: float = p1_mask.mesh.size.x / 2.0
	var p2_half: float = p2_mask.mesh.size.x / 2.0

	# 3. Get Portal Edges in World Space (Basis-aware)
	var p1_left: Vector3 = p1_pos - p1_mask.global_transform.basis.x * p1_half
	var p1_right: Vector3 = p1_pos + p1_mask.global_transform.basis.x * p1_half

	var p2_left: Vector3 = p2_pos - p2_mask.global_transform.basis.x * p2_half
	var p2_right: Vector3 = p2_pos + p2_mask.global_transform.basis.x * p2_half

	# 4. Get Primary Camera Position & Transform, and assign to $Portal1/CAM1
	var cam1_transform: Transform3D = cam3d.global_transform
	$Portal1/CAM1.global_transform = cam1_transform
	cam1_pos = cam1_transform.origin
	

	# 5. Exact Portal Camera Transform & Position Match (Flipping Local X & Z)
	var local_cam: Transform3D = p1_mask.global_transform.affine_inverse() * cam1_transform
	local_cam.origin.x = -local_cam.origin.x
	local_cam.origin.z = -local_cam.origin.z
	
	# Rotate basis 180 deg around local Y to match camera facing direction
	local_cam.basis = local_cam.basis.rotated(Vector3.UP, PI)

	# Apply to Portal 2 and update CAM2 node
	$Portal2/CAM2.global_transform = p2_mask.global_transform * local_cam
	cam2_pos = $Portal2/CAM2.global_position

	# 6. Debug Visualizations
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_left), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_right), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p1_pos), Color.WHITE)

	DebugDraw3D.draw_position(Transform3D(Basis(), p2_left), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p2_right), Color.PURPLE)
	DebugDraw3D.draw_position(Transform3D(Basis(), p2_pos), Color.WHITE)

	DebugDraw3D.draw_position(Transform3D(Basis(), cam1_pos), Color.GOLD)
	DebugDraw3D.draw_position(Transform3D(Basis(), cam2_pos), Color.GOLD)

	# 7. Draw Top-Down Directional Arrows for Cameras
	var cam1_dir: Vector3 = -cam1_transform.basis.z * 3.0
	var cam2_dir: Vector3 = -$Portal2/CAM2.global_transform.basis.z * 3.0

	#DebugDraw3D.draw_arrow(cam1_pos, cam1_pos + cam1_dir, Color.GOLD, 0.4)
	#DebugDraw3D.draw_arrow(cam2_pos, cam2_pos + cam2_dir, Color.GOLD, 0.4)

	#DebugDraw3D.draw_camera_frustum($Portal1/CAM1, Color.WHITE)
	#DebugDraw3D.draw_camera_frustum($Portal2/CAM2, Color.GOLD)
	
	# Run diagnostic print
	_verify_camera_positions()


func _verify_camera_positions() -> void:
	var dist_cam1_to_p1: float = cam1_pos.distance_to(p1_pos)
	var dist_cam2_to_p2: float = cam2_pos.distance_to(p2_pos)

	print_rich("[color=yellow]--- CAMERA DIAGNOSTICS ---[/color]")
	print("CAM1 Pos: ", cam1_pos, " | Distance to Portal 1: ", dist_cam1_to_p1)
	print("CAM2 Pos: ", cam2_pos, " | Distance to Portal 2: ", dist_cam2_to_p2)

	if is_equal_approx(dist_cam1_to_p1, dist_cam2_to_p2):
		print_rich("[color=green]STATUS: Working correctly (Distances match!)[/color]")
	else:
		print_rich("[color=red]STATUS: Distance mismatch detected![/color]")
