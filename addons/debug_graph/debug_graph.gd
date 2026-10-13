extends Node

func _ready() -> void:
	EngineDebugger.register_message_capture("debug_graph", _on_editor_message)
	EngineDebugger.send_message("debug_graph:start", [Time.get_ticks_msec()])

func plot(label: StringName, value: float) -> void:
	EngineDebugger.send_message("debug_graph:point", [label, value, Time.get_ticks_msec()])

func _on_editor_message(message: String, data: Array) -> bool:
	print("received")
	if message == "request_start":
		EngineDebugger.send_message("debug_graph:start_manual", [Time.get_ticks_msec()])
		return true
	return false
