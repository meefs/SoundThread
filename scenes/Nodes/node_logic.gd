extends GraphNode

@export var min_gap: float = 0.5  # editable value in inspector for the minimum gap between min and max
signal open_help

func _ready() -> void:
	var sliders := _get_all_hsliders(self) #finds all sliders
	#links sliders to this script
	for slider in sliders:
		slider.value_changed.connect(_on_slider_value_changed.bind(slider))
		
	#add button to title bar
	var titlebar = self.get_titlebar_hbox()
	var btn = Button.new()
	btn.text = "?"
	btn.tooltip_text = "Open help for " + self.title
	btn.connect("pressed", Callable(self, "_open_help")) #pass key (process name) when button is pressed
	titlebar.add_child(btn)
	
	if self.has_node("addremoveinlets"):
		var addremove = self.get_node("addremoveinlets")
		addremove.add_inlet.connect(add_inlet_to_node)
		addremove.remove_inlet.connect(remove_inlet_from_node)
	

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
	var is_min = changed_slider.get_meta("min")
	var is_max = changed_slider.get_meta("max")
	var is_outputduration = changed_slider.get_meta("outputduration")
	
	#if not exits function
	if not is_min and not is_max:
		return

	var sliders := _get_all_hsliders(self)

	for other_slider in sliders:
		if other_slider == changed_slider:
			continue
		
		if is_min and other_slider.get_meta("max"):
			var max_value: float = other_slider.value
			if changed_slider.value > max_value - min_gap:
				changed_slider.value = max_value - min_gap
		
		elif is_max and other_slider.get_meta("min"):
			var min_value: float = other_slider.value
			if changed_slider.value < min_value + min_gap:
				changed_slider.value = min_value + min_gap
				
	#set output duration meta if this is the output duration slider
	if is_outputduration:
		set_meta("outputduration", value)

func _open_help():
	open_help.emit(self.get_meta("command"), self.title)

func add_inlet_to_node():
	var inlet_count = self.get_input_port_count()
	var child_count = self.get_child_count()
	
	if child_count < inlet_count + 1:
		var control = Control.new()
		control.custom_minimum_size.y = 57
		control.set_meta("dummynode", true)
		add_child(control)
		move_child(get_node("addremoveinlets"), get_child_count() - 1)
	
	set_slot(inlet_count, true, get_input_port_type(0), get_input_port_color(0), false, 0, get_input_port_color(0))
	
func remove_inlet_from_node():
	var inlet_count = self.get_input_port_count()
	var child_count = self.get_child_count()
	
	set_slot(inlet_count - 1, false, get_input_port_type(0), get_input_port_color(0), false, 0, get_input_port_color(0))
	
	if get_child(child_count - 2).has_meta("dummynode"):
		get_child(child_count - 2).queue_free()
		await get_tree().process_frame
		update_minimum_size()
		size.y = get_combined_minimum_size().y
