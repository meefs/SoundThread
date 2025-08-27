extends Control

signal add_inlet
signal remove_inlet



func _on_add_inlet_button_button_down() -> void:
	add_inlet.emit()


func _on_remove_inlet_button_button_down() -> void:
	remove_inlet.emit()
