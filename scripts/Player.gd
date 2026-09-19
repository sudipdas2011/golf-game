extends RigidBody3D

@export var mov_mode := true # 'true' for WASD, 'false' for DRAGnSHOOT
@export var roll_torque: float = 2.0
@export var smooth_speed: float = 16.0

@onready var camera_node: Camera3D = get_viewport().get_camera_3d()

var input_dir: Vector2 = Vector2.ZERO
var torque_vector: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Ignore self so the camera's raycast doesn't hit the player mesh
	$CameraRayCast.add_exception(self)

func _process(_delta: float) -> void:
	# Draw velocity helper arrow
	var arrow_start = %CollisionShape.global_position
	var arrow_end = arrow_start + linear_velocity * 0.3
	DebugDraw3D.draw_arrow(arrow_start, arrow_end, Color.BLUE, 0.01)

func _input(event: InputEvent) -> void:
	# Toggle Movement Mode
	if event.is_action_pressed("change_mov_mode"):
		mov_mode = not mov_mode
		print("MOV_MODE changed to: ", mov_mode)
		
	# Developer shortcut to close the active testing instance
	if event.is_action_pressed("exit"):
		print("QUIT ( ", get_tree().current_scene.name, " ) SCENE!")
		get_tree().quit()

func _physics_process(delta: float) -> void:
	# Divert control pipelines based on current toggle state
	if mov_mode:
		wasd_mov(delta)
	else:
		dragnshoot_mov()

func wasd_mov(delta: float) -> void:
	# 1. Gather smoothly interpolated input axis vectors
	var raw_input = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	input_dir = input_dir.lerp(raw_input, smooth_speed * delta)
	
	# 2. Extract camera basis directions flattened onto the floor horizontal ground plane
	var cam_forward = -camera_node.global_transform.basis.z
	var cam_right = camera_node.global_transform.basis.x
	
	cam_forward.y = 0.0
	cam_right.y = 0.0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()
	
	# 3. Translate 2D input space directly into the camera-facing 3D movement path
	var move_direction = (cam_right * input_dir.x) + (cam_forward * input_dir.y)
	
	# 4. Convert structural move direction vector into true rolling physics forces (Perpendicular Torque)
	# Moving "forward" means spinning around the horizontal axis perpendicular to forward direction
	var target_torque = Vector3(move_direction.z, 0.0, -move_direction.x) * roll_torque
	torque_vector = torque_vector.lerp(target_torque, smooth_speed * delta)
	
	# Apply final physics rotational force impulse
	apply_torque(torque_vector)
	
	# Debug Telemetry Outputs
	DebugDraw2D.set_text("INPUT_DIR", input_dir)
	DebugDraw2D.set_text("TORQUE VECTOR :", torque_vector)
	DebugDraw3D.draw_arrow_ray(global_position, move_direction, 1.0, Color.BLUE, 0.1)

func dragnshoot_mov() -> void:
	pass
