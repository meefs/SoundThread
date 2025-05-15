extends GraphNode

@export var min_gap: float = 0.5  # editable value in inspector for the minimum gap between min and max

func _ready() -> void:
	var sliders := _get_all_hsliders(self) #finds all sliders
	#links sliders to this script
	for slider in sliders:
		slider.value_changed.connect(_on_slider_value_changed.bind(slider))

func _get_all_hsliders(node: Node) -> Array:
	#moves through all children recusively to find nested sliders
	var result: Array = []
	for child in node.get_children():
		if child is HSlider:
			result.append(child)
		elif child.has_method("get_children"):
			result += _get_all_hsliders(child)
	return result

func _on_slider_value_changed(value: float, changed_slider: HSlider) -> void:
	#checks if the slider moved has min or max meta data
	var is_min := changed_slider.has_meta("min")
	var is_max := changed_slider.has_meta("max")
	
	#if not exits function
	if not is_min and not is_max:
		return

	var sliders := _get_all_hsliders(self)

	for other_slider in sliders:
		if other_slider == changed_slider:
			continue
		
		if is_min and other_slider.has_meta("max"):
			var max_value: float = other_slider.value
			if changed_slider.value > max_value - min_gap:
				changed_slider.value = max_value - min_gap
		
		elif is_max and other_slider.has_meta("min"):
			var min_value: float = other_slider.value
			if changed_slider.value < min_value + min_gap:
				changed_slider.value = min_value + min_gap
