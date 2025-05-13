extends VBoxContainer


#Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#$HSplitContainer/ValueLabel.text = str($HSplitContainer/HSlider.value) # initial value
	$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value) # initial value


func _on_h_slider_value_changed(value: float) -> void:
	#$HSplitContainer/ValueLabel.text = str(value)
	$HSplitContainer/LineEdit.text = str(value)
	
func _on_line_edit_text_submitted(new_text: String) -> void:
	#check if input from text box is a valid number for the slider if not choose and appropriate value and set that
	if new_text.is_valid_float():
		var new_val = new_text.to_float()
		if new_val > $HSplitContainer/HSlider.max_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.max_value
		elif new_val < $HSplitContainer/HSlider.min_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.min_value
		else:
			$HSplitContainer/HSlider.set_value_no_signal(new_val)
	else:
		$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value)

func _on_line_edit_focus_exited() -> void:
	#check if input from text box is a valid number for the slider if not choose and appropriate value and set that
	if $HSplitContainer/LineEdit.text.is_valid_float():
		var new_val = $HSplitContainer/LineEdit.text.to_float()
		if new_val > $HSplitContainer/HSlider.max_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.max_value
		elif new_val < $HSplitContainer/HSlider.min_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.min_value
		else:
			$HSplitContainer/HSlider.set_value_no_signal(new_val)
	else:
		$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value)
		



		


#func _on_h_slider_gui_input(event: InputEvent) -> void:
	#if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and $HSplitContainer/HSlider.has_meta("brk"):
		#var local_pos = to_local(get_global_mouse_position())
		## Show popup at global mouse position
		#$HSplitContainer/HSlider/PopupMenu.popup()
		#$HSplitContainer/HSlider/PopupMenu.set_position(get_viewport().get_mouse_position())
		## Prevent default context menu or input propagation if needed
		#accept_event()
