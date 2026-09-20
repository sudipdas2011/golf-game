#class_name GlobalCursorX
extends Control

# REMOVED: Player.new() clone setup

var player_horizon: float = 0.0
var twod_cursor_pos : Vector2 
var pos_of_player : Vector3
var hit_position : Vector3
var mov_mode: bool = true # Defaults to true (WASD)

func _ready() -> void:
	print(". . . . . GLOBAL CURSOR AUTO-LOADED . . . . .")
	twod_cursor_pos = get_viewport_rect().size / 2

func _process(_delta: float) -> void:
	# 1. Fetch the live player root node from your scene hierarchy
	# (Assuming PlayerMain contains your active Player.gd script)
	var player_node = get_node_or_null("/root/ActiveScene/PlayerMain")
	if player_node == null:
		player_node = get_tree().root.find_child("PlayerMain", true, false)
		
	# 2. Update your movement mode in real time from the live player script
	if player_node and "mov_mode" in player_node:
		mov_mode = player_node.mov_mode
	
	# 3. Directly fetch your Mesh node for the horizon calculations
	var mesh_node = get_node_or_null("/root/ActiveScene/PlayerMain/Mesh")
	if mesh_node == null:
		mesh_node = get_tree().root.find_child("Mesh", true, false)

	if mesh_node and mesh_node is Node3D:
		pos_of_player = mesh_node.global_position
		player_horizon = pos_of_player.y
		
		# Telemetry Debug lines
		DebugDraw3D.draw_position(Transform3D(Basis(), pos_of_player), Color.MAGENTA)
		DebugDraw3D.draw_position(Transform3D(Basis(), Vector3(0, player_horizon, 0)), Color.AQUA)
	
	# 4. Handle 3D vector calculations safely inside process loop
	if mov_mode == false:
		three3d_cursor(pos_of_player)
	
	# 5. Tell the system to run the _draw() process
	queue_redraw()
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		twod_cursor_pos += event.relative
		var screen_size = get_viewport_rect().size
		twod_cursor_pos.x = clamp(twod_cursor_pos.x, 0, screen_size.x)
		twod_cursor_pos.y = clamp(twod_cursor_pos.y, 0, screen_size.y)
		
func _draw() -> void:
	# Cleanly draws the 2D cursor only when in WASD mode
	if mov_mode == true:
		twod_cursor()
	
func twod_cursor():
	draw_arc(twod_cursor_pos, 5.0, 0, TAU, 32, Color.WHITE, 2.0)

func three3d_cursor(target_position: Vector3):
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
		
	var mouse_pos = twod_cursor_pos
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	var ground_plane = Plane(Vector3.UP, target_position)
	hit_position = ground_plane.intersects_ray(ray_origin, ray_normal)
	
	if hit_position != null:
		
		DebugDraw3D.draw_gizmo(Transform3D(Basis(), hit_position), Color.AQUA, true)
