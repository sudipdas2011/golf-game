extends EditorDebuggerPlugin
var debug_graph_dock: _DebugGraphDock
var active_session_id: int = -1

func _has_capture(prefix: String) -> bool:
	return prefix == "debug_graph"

func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "debug_graph:start":
		debug_graph_dock._on_play_start(data[0])
		active_session_id = session_id
		return true
	if message == "debug_graph:point":
		debug_graph_dock.receive_point(data)
		return true
	if message == "debug_graph:start_manual":
		debug_graph_dock._on_manual_record(data[0])
		return true
	return false

func request_start() -> void:
	if active_session_id != -1:
		print(active_session_id)
		get_session(active_session_id).send_message("debug_graph:request_start", [])
