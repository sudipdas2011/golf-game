extends Node3D

# Mouse Config [look]
@export var mouse_sensitivity := 0.003
@export var min_pitch := -80.0 # Don't look straight up
@export var max_pitch := 80.0  # Don't look straight down

@onready var CAMERA := %Camera3D
@onready var CAMERA_ANCHOR := get_node("../PlayerMain/CameraAnchor")
@onready var CAMERA_RAYCAST := get_node("../PlayerMain/CameraRayCast")
@onready var PLAYER := get_node("../PlayerMain/Mesh")

@export var camera_range := 1.0
@export var fov_fac := 12.0

@onready var camera_anchor_offset
@export var camera_offset : float = 4.0 # Acts as your sphere's radius
#@export var camera_offset : Vector3 = Vector3(0.0, 3.0, 3.0)
@onready var player_pos : Vector3 = PLAYER.global_position

var prev_pos : Vector3 = Vector3.ZERO
var camera_anchor_pos : Vector3 = Vector3.ZERO

#looking cam rotations
var rot_x : float = 0.0 # Left/Right rotation (Yaw)
var rot_y : float = 0.0 # Up/Down rotation (Pitch)



#var space_state := get_world_3d().direct_space_state

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	camera_anchor_pos = CAMERA_ANCHOR.global_position
	#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED #for now...
	
	
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rot_x -= event.relative.x * mouse_sensitivity
		rot_y -= event.relative.y * mouse_sensitivity
		
		#clamp it
		rot_y = clamp(rot_y, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		
	
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#Camera Anchor Offset Distance
	camera_anchor_offset = CAMERA_ANCHOR.global_position.distance_to(camera_anchor_pos)
	# Smooth Camera Anchor Position
	camera_anchor_pos = camera_anchor_pos.lerp( CAMERA_ANCHOR.global_position , 8.0 * get_physics_process_delta_time())
	# Update Player Position
	player_pos = PLAYER.global_position
	
	#project camera onto sphere
	var direction := Vector3.ZERO
	direction.x = sin(rot_x) * cos(rot_y)
	direction.y = sin(rot_y)
	direction.z = cos(rot_x) * cos(rot_y)
	
	CAMERA.global_position = camera_anchor_pos + (direction * camera_offset)

	CAMERA.look_at(camera_anchor_pos, Vector3.UP)

func _physics_process(delta: float) -> void:
	
	
	# Placing the camera inside a range
	camera_ranging(camera_range)
	# Look at the player
	#CAMERA.look_at(player_pos, Vector3.UP)
	# Camera FOV effect
	camera_fov(delta)
	#print(camera_anchor_pos)


func camera_ranging(radius):
	# DebugDraw3D
	DebugDraw3D.draw_gizmo(Transform3D(Basis(), player_pos), Color.BLUE, true)
	DebugDraw2D.set_text("CAMERA_ANCHOR_POS : ", camera_anchor_pos)
	DebugDraw2D.set_text("CAMERA_ANCHOR_OFFSET : ", camera_anchor_offset)
	DebugDraw2D.set_text("CAMERA_FOV : ", CAMERA.fov)
	DebugDraw2D.set_text("FOV_FAC : ", fov_fac)
	DebugDraw3D.draw_position(Transform3D(Basis(), camera_anchor_pos), Color.GREEN)
	DebugDraw3D.draw_arrow(camera_anchor_pos, CAMERA_RAYCAST.get_collision_point(), Color.RED, 0.05)
	
	#Simpler Method
	#CAMERA.global_position = camera_anchor_pos + camera_offset
	
	# Set CameraRaycast Position to CameraAnchor
	CAMERA_RAYCAST.global_position = camera_anchor_pos
	
	if CAMERA_RAYCAST.is_colliding():
		DebugDraw2D.set_text("Raycast Hit At", CAMERA_RAYCAST.get_collision_point())
		DebugDraw3D.draw_position(Transform3D(Basis(), CAMERA_RAYCAST.get_collision_point()), Color.RED)
	else:
		DebugDraw2D.set_text("Raycast not hit.")


func camera_fov(delta):
	CAMERA.fov = lerp(CAMERA.fov, 75.0 + ( (camera_anchor_pos.distance_to(prev_pos) / delta) * fov_fac ), 0.1)
	prev_pos = camera_anchor_pos
