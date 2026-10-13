class_name _DebugGraphData

var label: StringName
var color: Color
## Values is an array of time (x) and value (y)
var values: Array[Vector2]
var peak_value: float = 0
var lowest_value: float = 0

var visible = true

func _init(l: StringName, c: Color, v: Array[Vector2] = []) -> void:
	label = l
	color = c
	values = v
