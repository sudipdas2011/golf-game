@tool
extends EditorPlugin

const VERSION: String = "0.1"

var _debugger := preload("res://addons/debug_graph/debugger_plugin.gd").new()

var dock

func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree():
	print("\nYou are using alpha build "+VERSION+" of 'Debug Graph' created by Jeditor. Leave your feedback and suggestions on jeditor.itch.io/debug-graph, and consider supporting the developer.
	")
	add_autoload_singleton("DebugGraph", "res://addons/debug_graph/debug_graph.gd")
	dock = load("res://addons/debug_graph/Dock/debug_plot_dock.tscn").instantiate() as _DebugGraphDock
	add_control_to_bottom_panel(dock, "Debug Graph")
	_debugger.debug_graph_dock = dock
	add_debugger_plugin(_debugger)
	dock.debug_plugin = _debugger

func _exit_tree():
	remove_debugger_plugin(_debugger)
	remove_autoload_singleton("DebugGraph")
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
