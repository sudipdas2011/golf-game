@tool
extends Panel

@export var timeline_scrollbar: HScrollBar
var scrollbar_value: float = 1
@export var current_time_label: Label
@export var debug_graph_dock: _DebugGraphDock
@export var decimals_spinbox: SpinBox

var mouse_pos: Vector2i = Vector2i.ZERO
var mouse_visible: bool = false

const DEFAULT_DECIMALS: int = 3
var decimal_step: float

var data: Array = []
var highest_value: float = -INF
var lowest_value: float = INF
var viewport_ms: float = 0

var highlight_current_values: bool = false
var display_cursor_value: bool = false
var global_peak_value: bool = false
var fit_to_viewport: bool = false
var clear_on_start: bool = true

var drawing: bool = false

var start_time: float = 0
var last_recorded_time: float = 0
var elapsed_time: float = 0

var text_margin: int = 5

var font = get_theme_default_font()

func _enter_tree() -> void:
	decimal_step = calculate_decimal_step(decimals_spinbox.value)

func start() -> void:
	drawing = true
	timeline_scrollbar.value = 1
	start_time = Time.get_ticks_msec()

func clear_graph() -> void:
	highest_value = -INF
	lowest_value = INF
	start_time = Time.get_ticks_msec()
	timeline_scrollbar.value = 1

func calculate_decimal_step(decimals: int) -> float:
	return 1 / pow(10,decimals)

func _process(delta: float) -> void:
	mouse_pos = get_local_mouse_position()
	mouse_visible = not (mouse_pos.x > size.x or mouse_pos.x <= 0 or mouse_pos.y > size.y or mouse_pos.y <= 0)

	queue_redraw()
	
	if drawing:
		last_recorded_time = Time.get_ticks_msec()
		elapsed_time = last_recorded_time - start_time
		current_time_label.text = "🔴 " + str(roundf(elapsed_time / 10) / 100) + "s"
		current_time_label.tooltip_text = "Program recording..."
	elif not clear_on_start:
		current_time_label.text = "❚❚ " + str(roundf(elapsed_time / 10) / 100) + "s"
		current_time_label.tooltip_text = "Program paused..."
	else:
		current_time_label.text = "💀 " + str(roundf(elapsed_time / 10) / 100) + "s"
		current_time_label.tooltip_text = "Program terminated"

func _draw() -> void:
	var time_start: float = start_time
	var time_end: float = max(last_recorded_time, time_start + 1.0)
	var time_range: float = time_end - time_start
	
	if viewport_ms != 0:
		time_end = lerp(start_time, last_recorded_time, scrollbar_value)
		time_start = time_end - viewport_ms
		time_range = viewport_ms
	
	var effective_highest: float = highest_value
	var effective_lowest: float = lowest_value
	
	if fit_to_viewport:
		effective_highest = -INF
		effective_lowest = INF
		for d in data:
			if not d.visible: continue
			for v in d.values:
				if v.x < time_start or v.x > time_end:
					continue
				if v.y > effective_highest:
					effective_highest = v.y
				if v.y < effective_lowest:
					effective_lowest = v.y
		if effective_highest == -INF:
			effective_highest = highest_value
			effective_lowest = lowest_value
	
	var mouse_normalized_x := mouse_pos.x / size.x
	var mouse_time : float = lerp(time_start, time_end, mouse_normalized_x)
	
	# Value ticks/lines
	if global_peak_value:
		var display_highest_value: String = str(snapped(effective_highest, decimal_step))
		var display_lowest_value: String = str(snapped(effective_lowest, decimal_step))
		draw_string(font, Vector2(size.x + text_margin, 0 - text_margin), display_highest_value + " (max)", 0, 100, 14, Color.GRAY)
		draw_string(font, Vector2(size.x + text_margin, size.y + text_margin + 10), display_lowest_value + " (min)", 0, 100, 14, Color.GRAY)
		
		var value_range: float = effective_highest - effective_lowest
		var step: float = nice_step(value_range, ceili(size.y * 0.015))
		if is_zero_approx(step): step = 1
		
		var i: float = roundi(effective_lowest / step) * step
		while i < (effective_highest - step):
			i += step
			var normalized_y = (i - effective_lowest) / value_range if value_range > 0.0 else 0.5
			var y_pos: float = size.y - (normalized_y * size.y)
			draw_line(Vector2(0, y_pos), Vector2(size.x, y_pos), Color(1, 1, 1, 0.15))
			draw_string(font, Vector2(0, y_pos), str(i), 0, -1, 14, Color.GRAY)
	
	# Start line
	var x_pos: float = (start_time - time_start) / time_range * size.x
	if x_pos > 0:
		draw_line(Vector2(x_pos, size.y), Vector2(x_pos, 0), Color.WHITE, 2)
	
	# Time markers/lines
	var interval: float = nice_step(viewport_ms, ceili(size.x * 0.004))
	
	var aligned_start_index := int(ceil((time_start - start_time) / interval))
	var aligned_end_index   := int(floor((time_end - start_time)  / interval))

	for i in range(aligned_start_index, aligned_end_index + 1):
		var marker_time: float = start_time + i * interval
		if marker_time < time_start or marker_time < start_time:
			continue
		x_pos = (marker_time - time_start) / time_range * size.x
		if x_pos < 0 or x_pos > size.x:
			continue
		draw_line(Vector2(x_pos, 0), Vector2(x_pos, size.y), Color(1, 1, 1, 0.15), 1.0)
		var elapsed_seconds: float = (marker_time - start_time) / 1000.0
		draw_string(font, Vector2(x_pos + text_margin, size.y - text_margin), str(elapsed_seconds) + "s", 0, -1, 14, Color.GRAY)
	
	var mouse_values_data: Array[Dictionary] = []
	var right_edge_labels_data: Array[Dictionary] = []
	
	# DATASET LOOP
	if data.size() > 0:
		for d in data:
			if not d.visible: continue
			var peak_value: float = 0
			var graph_line_array: Array[Vector2] = []
			
			var last_value_before_end: float = 0.0
			var has_value_before_end: bool = false
			
			var value_at_mouse: float = 0.0
			var has_value_before_mouse: bool = false
			
			if d.values.size() > 1:
				peak_value = effective_highest if global_peak_value else d.peak_value
				var low = effective_lowest if global_peak_value else d.lowest_value
				
				if fit_to_viewport and not global_peak_value:
					peak_value = -INF
					low = INF
					var last_before_viewport: float = INF  # track last point before viewport
					var has_before: bool = false
					for v in d.values:
						if v.x < time_start:
							last_before_viewport = v.y
							has_before = true
							continue
						if v.x > time_end:
							continue
						if v.y > peak_value:
							peak_value = v.y
						if v.y < low:
							low = v.y
					# include the value that extends into the viewport from the left
					if has_before:
						if last_before_viewport > peak_value:
							peak_value = last_before_viewport
						if last_before_viewport < low:
							low = last_before_viewport
					if peak_value == -INF:
						peak_value = d.peak_value
						low = d.lowest_value
				
				var range_y = peak_value - low
				
				for v in d.values:
					if v.y > peak_value:
						peak_value = v.y
					
					if v.x <= time_end:
						last_value_before_end = v.y
						has_value_before_end = true
					
					var normalized_x = (v.x - time_start) / time_range
					var normalized_y = (v.y - low) / range_y if range_y > 0.0 else 0.5
					var screen_pos = Vector2i(
						normalized_x * size.x,
						size.y - (normalized_y * size.y)
					)
					
					graph_line_array.append(screen_pos)
				
					if v.x <= mouse_time:
						value_at_mouse = v.y
						has_value_before_mouse = true
				
				# Draw graph lines
				for i in range(graph_line_array.size() - 1):
					var cur: Vector2 = graph_line_array[i]
					var nxt: Vector2 = graph_line_array[i + 1]
					if cur.x <= 0:
						if nxt.x <= 0:
							continue
						else:
							cur.x = 0
					
					if cur.x >= size.x:
						continue
					draw_line(cur, Vector2(min(nxt.x, size.x), cur.y), d.color, 1.0)
					
					if nxt.x > size.x:
						continue
					draw_line(Vector2(nxt.x, cur.y), nxt, d.color, 1.0)
					
				# Extend line to right edge
				if graph_line_array.size() > 0:
					var last_x: float = max(graph_line_array[-1].x, 0)
					if last_x <= size.x:
						draw_line(
							Vector2(last_x, graph_line_array[-1].y),
							Vector2(size.x, graph_line_array[-1].y),
							d.color
						)
				
				# Collect right-edge label
				if has_value_before_end:
					var normalized_y = (last_value_before_end - low) / range_y if range_y > 0.0 else 0.5
					var y_pos = size.y - (normalized_y * size.y)
					right_edge_labels_data.append({
						"y_pos": y_pos,
						"text": str(snapped(last_value_before_end, decimal_step)),
						"color": d.color
					})
				
				# Draw line highlighting current value
				if highlight_current_values and graph_line_array.size() > 0:
					draw_line(
						Vector2(0, graph_line_array[-1].y),
						Vector2(size.x, graph_line_array[-1].y),
						Color(d.color, 0.5)
					)
				
				# Collect mouse hover label
				if has_value_before_mouse and mouse_visible:
					var mouse_value_normalized_y = (value_at_mouse - low) / range_y if range_y > 0.0 else 0.5
					var mouse_value_y_pos = size.y - (mouse_value_normalized_y * size.y)
					mouse_values_data.append({
						"y_pos": mouse_value_y_pos,
						"x_pos": mouse_pos.x,
						"text": str(snapped(value_at_mouse, decimal_step)),
						"color": d.color
					})
	
	# Highlight mouse position with fancy lines
	if mouse_visible:
		draw_line(Vector2(mouse_pos.x, 0), Vector2(mouse_pos.x, size.y), Color(1, 1, 1, 0.35))
		if global_peak_value:
			if display_cursor_value:
				draw_line(Vector2(0, mouse_pos.y), Vector2(size.x, mouse_pos.y), Color(1, 1, 1, 0.15))
				var normalized_y: float = 1.0 - (mouse_pos.y / size.y)
				var value_at_mouse: float = lowest_value + normalized_y * (effective_highest - effective_lowest)
				draw_string(font, mouse_pos + Vector2i(text_margin, -text_margin), str(snapped(value_at_mouse, decimal_step)), 0, -1, 14, Color.GRAY)
	
	_place_labels(mouse_values_data)
	_place_labels(right_edge_labels_data, size.x + text_margin)
	

func _place_labels(labels: Array[Dictionary], x_override: float = -1.0) -> void:
	if labels.is_empty():
		return
	
	labels.sort_custom(func(a, b):
		if is_equal_approx(a.y_pos, b.y_pos):
			return false
		return a.y_pos > b.y_pos
	)
	
	var previous_y_values: Array[float] = [-INF]
	
	for entry in labels:
		var text_size: Vector2i = font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var padding := Vector2i(1, 1)
		var x : int = x_override if x_override >= 0.0 else entry.x_pos
		var rect_pos := Vector2i(int(x), int(entry.y_pos) - text_size.y)
		var rect_size := text_size + padding * 2
		
		var adjusted_y := rect_pos.y
		var needs_adjustment := true
		var attempts := 0
		while needs_adjustment and attempts < 10:
			needs_adjustment = false
			for y_value in previous_y_values:
				if adjusted_y + rect_size.y > y_value and adjusted_y < y_value + text_size.y:
					adjusted_y -= rect_size.y
					needs_adjustment = true
					break
			attempts += 1
		
		rect_pos.y = adjusted_y
		previous_y_values.append(rect_pos.y)
		
		draw_rect(Rect2(rect_pos, rect_size), Color(Color.BLACK, 1))
		draw_string(
			font,
			rect_pos + Vector2i(padding.x, text_size.y + int(padding.y * 0.5)),
			entry.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			entry.color
		)







func _on_timeline_scrollbar_value_changed(value: float) -> void:
	scrollbar_value = value

func update_viewport_ms(value) -> void:
	viewport_ms = value
	if viewport_ms == 0:
		timeline_scrollbar.visible = false
	else:
		timeline_scrollbar.visible = true


var _dragging: bool = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var time_end: float = lerp(start_time, last_recorded_time, scrollbar_value)
			var time_start: float = time_end - viewport_ms
			var mouse_normalized: float = event.position.x / size.x
			var time_at_mouse: float = lerp(time_start, time_end, mouse_normalized)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				viewport_ms = max(50, viewport_ms * 0.95)
			else:
				viewport_ms = min(500000, viewport_ms * 1.05)
			debug_graph_dock.set_memory_ms(viewport_ms)
			var new_time_end: float = time_at_mouse + (1.0 - mouse_normalized) * viewport_ms
			var total_range: float = last_recorded_time - start_time
			scrollbar_value = clamp((new_time_end - start_time) / total_range, 0.0, 1.0)
			timeline_scrollbar.value = scrollbar_value
		if event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			timeline_scrollbar.value = max(0, timeline_scrollbar.value - viewport_ms/1000 * 0.0005)
		if event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			timeline_scrollbar.value = min(1, timeline_scrollbar.value + viewport_ms/1000 * 0.0005)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	
	if event is InputEventMouseMotion and _dragging:
		var ms_per_pixel: float = viewport_ms / size.x
		var time_delta: float = event.relative.x * ms_per_pixel
		var total_range: float = last_recorded_time - start_time
		scrollbar_value = clamp(scrollbar_value - time_delta / total_range, 0.0, 1.0)
		timeline_scrollbar.value = scrollbar_value


func nice_step(value_range: float, target_ticks: int = 5) -> float:
	var rough_step = value_range / target_ticks
	var exponent = floor(log(rough_step) / log(10))
	var fraction = rough_step / pow(10, exponent)

	var nice_fraction: float
	if fraction < 1.5:
		nice_fraction = 1.0
	elif fraction < 3.0:
		nice_fraction = 2.0
	elif fraction < 7.0:
		nice_fraction = 5.0
	else:
		nice_fraction = 10.0

	return nice_fraction * pow(10, exponent)

func _on_decimals_spin_box_value_changed(value: float) -> void:
	decimal_step = calculate_decimal_step(value)
