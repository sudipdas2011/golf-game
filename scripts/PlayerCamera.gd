class_name PlayerCamera
extends Node3D

# Mouse Config
@export var mouse_sensitivity := 0.003
@export var min_pitch := -80.0
@export var max_pitch := 80.0
@export var camera_look_smooth_speed := 15.0
@export var camera_smooth_speed := 10.0

# Camera Parameters
@export var camera_range := 1.0
@export var camera_offset: float = 4.0 
@export var fov_fac := 7.0

# Node References
@onready var SPRING_ARM: SpringArm3D = $SpringArm3D
@onready var CAMERA := %CameraTarget
@onready var CAMERA_ANCHOR := get_node("../PlayerMain/CameraAnchor")
@onready var PLAYER := get_node("../PlayerMain/Mesh")
@onready var PLAYERx := get_node("../PlayerMain")


# State Tracking Variables
var camera_anchor_offset: float = 0.0
var player_pos: Vector3 = Vector3.ZERO
var prev_pos: Vector3 = Vector3.ZERO
var camera_anchor_pos: Vector3 = Vector3.ZERO

# Look Rotations
var target_rot_x: float = 0.0
var target_rot_y: float = 0.0
var smoothed_rot_x: float = 0.0
var smoothed_rot_y: float = 0.0

func _ready() -> void:
	camera_anchor_pos = CAMERA_ANCHOR.global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SPRING_ARM.spring_length = camera_offset

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		
		# Disable camera rotation while swing_hotkey is held
		if not PLAYERx.mov_mode and Input.is_action_pressed("swing_hotkey"):
			return
		
		# Normal camera rotation
		target_rot_x -= event.relative.x * mouse_sensitivity
		target_rot_y -= event.relative.y * mouse_sensitivity
		target_rot_y = clamp( target_rot_y, deg_to_rad(min_pitch), deg_to_rad(max_pitch) )

func _process(delta: float) -> void:
	var proc_delta = get_process_delta_time()
	
	%Camera3D.global_position = %Camera3D.global_position.slerp( %CameraTarget.global_position, camera_smooth_speed * proc_delta )
	
	camera_anchor_offset = CAMERA_ANCHOR.global_position.distance_to(camera_anchor_pos)
	camera_anchor_pos = camera_anchor_pos.lerp( CAMERA_ANCHOR.global_position, 8.0 * proc_delta )
	
	global_position = camera_anchor_pos
	player_pos = PLAYER.global_position

	smoothed_rot_x = lerp( smoothed_rot_x, target_rot_x, camera_look_smooth_speed * proc_delta )
	smoothed_rot_y = lerp( smoothed_rot_y, target_rot_y, camera_look_smooth_speed * proc_delta )
	
	SPRING_ARM.rotation.x = smoothed_rot_y
	SPRING_ARM.rotation.y = smoothed_rot_x
	
	%Camera3D.look_at(camera_anchor_pos, Vector3.UP)

func _physics_process(delta: float) -> void:
	camera_ranging(camera_range)
	camera_fov(delta)

func camera_ranging(radius: float) -> void:
	DebugDraw2D.set_text("CAMERA_ANCHOR_POS : ", camera_anchor_pos)
	DebugDraw2D.set_text("CAMERA_ANCHOR_OFFSET : ", camera_anchor_offset)
	DebugDraw2D.set_text("CAMERA_FOV : ", %Camera3D.fov)
	DebugDraw2D.set_text("FOV_FAC : ", fov_fac)
	
	var is_colliding = SPRING_ARM.get_hit_length() < SPRING_ARM.spring_length
	DebugDraw2D.set_text("SpringArm Collision Active: ", is_colliding)

func camera_fov(delta: float) -> void:
	var current_speed = camera_anchor_pos.distance_to(prev_pos) / delta
	%Camera3D.fov = lerp( %Camera3D.fov, 75.0 + (current_speed * fov_fac), 0.1 )
	prev_pos = camera_anchor_pos
