extends RigidBody3D

@export var MOV_MODE := true # 'true' for WASD and 'false' for DRAGnSHOOT.
@export var roll_torque: float = 2.0

var input_dir: Vector2
var torque_vector : Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$CameraRayCast.add_exception(self) # Add self as exception for the CameraRayCast


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
		DebugDraw3D.draw_arrow(%CollisionShape.global_position, %CollisionShape.global_position + %CollisionShape.get_parent().linear_velocity * 0.3, Color.BLUE, 0.01)



func _input(event: InputEvent) -> void:
	#Toggling MOV_MODE
	if event.is_action_pressed("change_mov_mode"):
		MOV_MODE = not MOV_MODE
		print("MOV_MODE changed to:" + str(MOV_MODE) + ".")
		
	#Exiting the scene [for development stage]
	if event.is_action_pressed("exit"):
		get_tree().quit()
		print("QUIT ( " + str(get_tree().current_scene.name) + " )SCENE!")
	

func _physics_process(delta: float) -> void:
	#MOVEMENT
	player_mov(MOV_MODE)

	
func player_mov(MOV_MODE):
	#Setting Movement Modes as per MOV_MODE
	if MOV_MODE == true:
		wasd_mov()
	else:
		dragnshoot_mov()
		

func wasd_mov():
	#print("WASD MOVEMENT MODE ACTIVATED")
	input_dir = input_dir.lerp(Input.get_vector("move_left", "move_right", "move_forward", "move_backward"), 16.0 * get_physics_process_delta_time())
	
	# Debugdraw3D
	DebugDraw2D.set_text("INPUT_DIR", input_dir)
	DebugDraw2D.set_text("TORQUE VECTOR :", torque_vector)
	DebugDraw3D.draw_arrow_ray(self.global_position, Vector3(input_dir.x, 0.0, input_dir.y), 1.0, Color.BLUE, 0.1)
	
	#Roll as per input_dir
	torque_vector = Vector3(input_dir.y, 0, -input_dir.x) * roll_torque
	torque_vector = torque_vector.lerp(Vector3(input_dir.y, 0, -input_dir.x) * roll_torque, 16.0 * get_tree().root.get_physics_process_delta_time())
	apply_torque(torque_vector)
	
func dragnshoot_mov():
	#print("DRAGnSHOOT MOVEMENT MODE ACTIVATED")
	pass
