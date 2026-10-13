@tool
class_name DataLegendItem
extends Control

@export var name_label: Label
@export var color_rect: ColorRect

signal clicked(label: String)

var disabled: bool = false
var disabled_color: Color = Color.DIM_GRAY
var active_color: Color = Color.WHITE

func initialize(label: String, color: Color) -> void:
	name_label.text = label
	color_rect.color = color
	active_color = color

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if disabled:
			disabled = false
			color_rect.color = active_color
		else:
			disabled = true
			color_rect.color = disabled_color
		
		clicked.emit(name_label.text)
