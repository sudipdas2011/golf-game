@tool
class_name _DebugGraphDock
extends Control

var debug_plugin: EditorDebuggerPlugin

@export var timeline: Panel
@export var memory_spin_box: SpinBox
@export var settings_menu: MenuButton
@export var data_legend: HBoxContainer

@export var windowed_button: Button
@export var unwindowed_button: Button
@export var popped_out_panel_below: Control

@onready var record_button: Button = $"HSplitContainer/VBoxContainer/Options ScrollContainer/Options HBox/Record Button"
@onready var pause_button: Button = $"HSplitContainer/VBoxContainer/Options ScrollContainer/Options HBox/Pause Button"
@onready var stop_button: Button = $"HSplitContainer/VBoxContainer/Options ScrollContainer/Options HBox/Stop Button"
const RECORD_ICON = preload("uid://dtyi33tjrhdks")
const RECORD_ARMED_ICON = preload("uid://cdf320y7yvitl")

var _in_play_mode: bool = false

var data: Array[_DebugGraphData] = []

var recording_armed: bool = false
var recording: bool = false

var window: Window
@export var window_scene: PackedScene
var last_window_size: Vector2 = Vector2.ZERO

const DATA_LEGEND_ITEM = preload("uid://c0yggf2m5x6jm")

var game_time_offset: float = 0  # difference between editor time and game time

# SETTINGS
var highlight_current_values: bool = false
var local_value_range: bool = false
var clear_graph_on_start: bool = true
var memory_ms: float = 10000
var manual_recording_control: bool = false


var highest_value: float = -INF
var lowest_value: float = INF

const COLORS: Array[Color] = [
	Color.RED,
	Color.GREEN,
	Color.CYAN,
	Color.YELLOW,
	Color.MAGENTA,
	Color.ORANGE,
	Color.PINK,
]

var _was_playing := false


# Lifetime

func _enter_tree() -> void:
	memory_ms = 10000
	timeline.update_viewport_ms(memory_ms)
	_on_global_peak_value_toggled(true)
	settings_menu.get_popup().id_pressed.connect(_on_settings_button_pressed)

func _ready() -> void:
	reevaluate_record_controls()

func _on_play_start(game_start_time: int) -> void:
	_in_play_mode = true
	if (not manual_recording_control) or recording_armed:
		start_recording(game_start_time)

func _on_manual_record(game_start_time: int) -> void:
	start_recording(game_start_time)

func start_recording(game_start_time: int) -> void:
	recording_armed = false
	game_time_offset = Time.get_ticks_msec() - game_start_time
	timeline.start()
	timeline.update_viewport_ms(memory_ms)
	if clear_graph_on_start:
		clear_data()
	recording = true
	
	reevaluate_record_controls()

func stop_recording() -> void:
	timeline.drawing = false
	recording = false
	reevaluate_record_controls()

func _process(delta: float) -> void:
	if recording:
		timeline.data = data
		timeline.highest_value = highest_value
		timeline.lowest_value = lowest_value
	
	# Check whether play mode is ending
	var is_playing = EditorInterface.is_playing_scene()
	if _was_playing and not is_playing:
		_in_play_mode = false
		stop_recording()
	_was_playing = is_playing

# Data management

func receive_point(point: Array) -> void:
	if recording:
		var label: StringName = point[0]
		var value: float = point[1]
		var game_timestamp: float = point[2]
		var editor_timestamp: float = game_timestamp + game_time_offset
		var debug_graph_data: _DebugGraphData = null
		
		for d in data:
			if d.label == label:
				debug_graph_data = d
				if debug_graph_data.values.size() > 2:
					if is_equal_approx(debug_graph_data.values[-1].y, value):
						return
				if value > debug_graph_data.peak_value:
					debug_graph_data.peak_value = value
				if value < debug_graph_data.lowest_value:
					debug_graph_data.lowest_value = value
		
		if debug_graph_data == null:
			var color = COLORS[data.size() % COLORS.size()]
			debug_graph_data = _DebugGraphData.new(label, color)
			debug_graph_data.lowest_value = value
			debug_graph_data.peak_value = value + 0.01
			if debug_graph_data.peak_value > highest_value:
				highest_value = debug_graph_data.peak_value
			data.append(debug_graph_data)
			var data_legend_item = DATA_LEGEND_ITEM.instantiate() as DataLegendItem
			data_legend_item.initialize(label, color)
			data_legend_item.clicked.connect(_on_legend_item_pressed)
			data_legend.add_child(data_legend_item)
		
		debug_graph_data.values.append(Vector2(editor_timestamp, value))
		
		if debug_graph_data.visible:
			if value > highest_value:
				highest_value = value
			if value < lowest_value:
				lowest_value = value

func recalculate_highest_value() -> float:
	var temp_highest_value: float = -INF
	for d in data:
		if not d.visible:
			continue
		for p in d.values:
			if p.y > temp_highest_value:
				temp_highest_value = p.y
	return temp_highest_value

func recalculate_lowest_value() -> float:
	var temp_lowest_value: float = INF
	for d in data:
		if not d.visible:
			continue
		for p in d.values:
			if p.y < temp_lowest_value:
				temp_lowest_value = p.y
	return temp_lowest_value

func clear_data() -> void:
	timeline.clear_graph()
	highest_value = -INF
	lowest_value = INF
	data = []
	timeline.data = []
	for child in data_legend.get_children():
		if child is DataLegendItem:
			child.queue_free()


# Windowed mode

func pop_out() -> void:
	window = window_scene.instantiate()
	window.title = "Debug Graph"
	window.size = last_window_size if last_window_size != Vector2.ZERO else Vector2(800, 400)
	window.always_on_top = true
	window.minimize_disabled = true
	window.maximize_disabled = true
	window.min_size = Vector2(188,135)
	#window.transient = false
	#window.sharp_corners = true
	
	# reparent the dock content into the window
	var content = $HSplitContainer  # your main content node
	remove_child(content)
	window.get_child(0).add_child(content)
	
	# add window to editor
	EditorInterface.get_base_control().add_child(window)
	window.position = get_viewport_rect().size / 2 - Vector2(window.size/2)
	window.show()
	
	# restore on close
	window.close_requested.connect(pop_back_in)
	
	unwindowed_button.visible = true
	windowed_button.visible = false
	popped_out_panel_below.visible = true

func pop_back_in() -> void:
	var content = window.get_child(0).get_child(0)
	window.get_child(0).remove_child(content)
	add_child(content)
	window.queue_free()
	last_window_size = window.size
	windowed_button.visible = true
	unwindowed_button.visible = false
	popped_out_panel_below.visible = false


# Controls / Settings

func reevaluate_record_controls() -> void:
	if manual_recording_control:
		stop_button.tooltip_text = "Stop"
		if recording:
			stop_button.disabled = false
			pause_button.disabled = false
			record_button.disabled = true
			record_button.tooltip_text = ""
			record_button.icon = RECORD_ICON
		else:
			stop_button.disabled = true
			pause_button.disabled = true
			record_button.disabled = false
			if _in_play_mode:
				record_button.tooltip_text = "Record"
			elif recording_armed:
				record_button.icon = RECORD_ARMED_ICON
				record_button.tooltip_text = "Record (armed)"
			elif not recording_armed:
				record_button.icon = RECORD_ICON
				record_button.tooltip_text = "Record"
	else:
		stop_button.disabled = true
		stop_button.tooltip_text = "Stop \n('Manual recording control' is disabled, recording will start automatically on run)"
		pause_button.disabled = true
		record_button.disabled = true
		record_button.tooltip_text = "Record \n('Manual recording control' is disabled, recording will start automatically on run)"

func _on_settings_button_pressed(id: int) -> void:
	var popup: PopupMenu = settings_menu.get_popup()
	var index: int = popup.get_item_index(id)
	match id:
		1:
			highlight_current_values = !popup.is_item_checked(index)
			timeline.highlight_current_values = highlight_current_values
		2:
			local_value_range = !popup.is_item_checked(index)
			timeline.global_peak_value = !local_value_range
		3:
			timeline.display_cursor_value = !popup.is_item_checked(index)
		7:
			timeline.fit_to_viewport = !popup.is_item_checked(index)
		#4:
			#clear_graph_on_start = !popup.is_item_checked(id)
			#timeline.clear_on_start = clear_graph_on_start
		6:
			manual_recording_control = !popup.is_item_checked(index)
			reevaluate_record_controls()
	popup.set_item_checked(index, !popup.is_item_checked(index))

func _on_highlight_current_values_toggled(toggled_on: bool) -> void:
	highlight_current_values = toggled_on
	timeline.highlight_current_values = highlight_current_values

func _on_global_peak_value_toggled(toggled_on: bool) -> void:
	local_value_range = !toggled_on
	timeline.global_peak_value = !local_value_range

func _on_memory_spin_box_value_changed(value: float) -> void:
	memory_ms = value * 1000
	timeline.update_viewport_ms(value * 1000)

func set_memory_ms(value: float) -> void:
	memory_ms = value
	memory_spin_box.value = value / 1000

func _on_clear_button_pressed() -> void:
	clear_data()

func _on_legend_item_pressed(label: String) -> void:
	for d in data:
		if d.label == label:
			d.visible = !d.visible
	highest_value = recalculate_highest_value()
	timeline.highest_value = highest_value
	lowest_value = recalculate_lowest_value()
	timeline.lowest_value = lowest_value
	#for d in data:
		#if d.label == label:
			#if d.disabled:
				#highest_value = recalculate_highest_value()
				#timeline.highest_value = highest_value
				#lowest_value = recalculate_lowest_value()
				#timeline.lowest_value = lowest_value
			#else:
				#d.visible = true
			


func _on_windowed_pressed() -> void:
	pop_out()

func _on_return_window_pressed() -> void:
	pop_back_in()

func _on_unwindowed_button_pressed() -> void:
	pop_back_in()

func _on_record_button_pressed() -> void:
	if _in_play_mode:
		debug_plugin.request_start()
	elif recording_armed:
		recording_armed = false
	elif not recording_armed:
		recording_armed = true
		
	reevaluate_record_controls()

func _on_stop_button_pressed() -> void:
	stop_recording()
