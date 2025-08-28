extends Control

signal add_inlet
signal remove_inlet
var minimum_inlet_count
var maximum_inlet_count
var current_inlet_count

func _ready() -> void:
	minimum_inlet_count = get_meta("min")
	maximum_inlet_count = get_meta("max")
	current_inlet_count = get_meta("default")
	check_buttons()


func _on_add_inlet_button_button_down() -> void:
	add_inlet.emit()
	current_inlet_count += 1
	check_buttons()


func _on_remove_inlet_button_button_down() -> void:
	remove_inlet.emit()
	current_inlet_count -= 1
	check_buttons()

func check_buttons():
	if current_inlet_count == maximum_inlet_count:
		$VBoxContainer/HBoxContainer/AddInletButton.disabled = true
	else:
		$VBoxContainer/HBoxContainer/AddInletButton.disabled = false
		
	if current_inlet_count == minimum_inlet_count:
		$VBoxContainer/HBoxContainer/RemoveInletButton.disabled = true
	else:
		$VBoxContainer/HBoxContainer/RemoveInletButton.disabled = false
