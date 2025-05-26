extends Control

var node_data = {} #stores json file
@onready var parameter_container = $HBoxContainer/VBoxContainer2/ScrollContainer/parameter_container

func _ready() -> void:
	Nodes.hide()
		
	load_json()
	fill_search("")
	
func load_json():
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		node_data = JSON.parse_string(file.get_as_text())


func fill_search(filter: String):
	# Remove all existing items from the VBoxContainer
	var container = $HBoxContainer/VBoxContainer/search/MarginContainer/VBoxContainer/ScrollContainer/ItemContainer
	for child in container.get_children():
		child.queue_free()
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		var category = item.get("category", "")
		var subcategory = item.get("subcategory", "")
		var short_desc = item.get("short_description", "")
		
		# If filter is not empty, skip non-matches populate all other buttons
		if filter != "":
			var filter_lc = filter.to_lower()
			if not (filter_lc in title.to_lower() or filter_lc in short_desc.to_lower() or filter_lc in category.to_lower() or filter_lc in subcategory.to_lower()):
				continue
		
		
		var hbox = HBoxContainer.new()
		var label = RichTextLabel.new()
		var editbtn = Button.new()
		var margin = MarginContainer.new()
		
		hbox.size.x = container.size.x
		label.bbcode_enabled = true
		label.text = "[b]%s[/b]\n%s" % [title, short_desc]
		label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		label.fit_content = true
		
		
		editbtn.text = "Edit"
		editbtn.custom_minimum_size = Vector2(80, 40)
		editbtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		editbtn.connect("pressed", Callable(self, "edit_node").bind(key)) #pass key (process name) when button is pressed
		
		margin.add_theme_constant_override("margin_bottom", 3)
		container.add_child(hbox)
		hbox.add_child(label)
		hbox.add_child(editbtn)
		container.add_child(margin)


func _on_search_bar_text_changed(new_text: String) -> void:
	fill_search(new_text)
	
func edit_node(key: String):
	if node_data.has(key):
		#looks up the help data from the json and stores it in info
		var info = node_data[key]
		var parameters = info.get("parameters", {})
		
		$HBoxContainer/VBoxContainer2/HBoxContainer/key.text = key
		$HBoxContainer/VBoxContainer2/HBoxContainer2/category.text = info.get("category", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer3/subcategory.text = info.get("subcategory", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer4/title.text = info.get("title", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer5/shortdescription.text = info.get("short_description", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer7/longdescription.text = info.get("description", "")
		$HBoxContainer/VBoxContainer2/HBoxContainer6/stereo.button_pressed = bool(info.get("stereo"))
		
		for child in parameter_container.get_children():
			child.queue_free()
			
		var count = 1
		for param_key in parameters.keys():
			var param_box = VBoxContainer.new()
			param_box.set_h_size_flags(Control.SIZE_EXPAND_FILL)
			parameter_container.add_child(param_box)
			
			var label = Label.new()
			label.text = "Parameter " + str(count)
			param_box.add_child(label)
			
			var param_data = parameters[param_key]
			
			for field_key in param_data.keys():
				var field_value = param_data[field_key]
				
				var hbox = HBoxContainer.new()
				var namelabel = RichTextLabel.new()
				var namefield

				
				namelabel.text = field_key
				namelabel.custom_minimum_size.x = 250
				
				if field_value is bool:
					namefield = CheckBox.new()
					namefield.button_pressed = field_value
				else:
					namefield = LineEdit.new()
					namefield.text = str(field_value)
					namefield.set_h_size_flags(Control.SIZE_EXPAND_FILL)
				
				hbox.add_child(namelabel)
				hbox.add_child(namefield)
				param_box.add_child(hbox)
			
			var delete_button = Button.new()
			delete_button.text = "Delete " + param_data.get("paramname", "")
			delete_button.set_h_size_flags(Control.SIZE_EXPAND)
			delete_button.connect("pressed", Callable(self, "delete_param").bind(param_box))
			param_box.add_child(delete_button)
			
			
			var margin = MarginContainer.new()
			margin.add_theme_constant_override("margin_bottom", 5)
			param_box.add_child(margin)
			
			count += 1
			
func delete_param(container: VBoxContainer):
	container.queue_free()


func _on_button_button_down() -> void:
	var info = node_data["distort_replace"]
	var parameters = info.get("parameters", {})
	var parameter = parameters.get("param1", {})
	
	print(info)
	print(parameter)
	
	var param_box = VBoxContainer.new()
	param_box.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	parameter_container.add_child(param_box)
	
	var label = Label.new()
	label.text = "New Parameter"
	param_box.add_child(label)
	
	for field_key in parameter.keys():
		var field_value = parameter[field_key]
		
		var hbox = HBoxContainer.new()
		var namelabel = RichTextLabel.new()
		var namefield

		
		namelabel.text = field_key
		namelabel.custom_minimum_size.x = 250
		
		if field_value is bool:
			namefield = CheckBox.new()
		else:
			namefield = LineEdit.new()
			namefield.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		
		hbox.add_child(namelabel)
		hbox.add_child(namefield)
		param_box.add_child(hbox)
	
	var delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.set_h_size_flags(Control.SIZE_EXPAND)
	delete_button.connect("pressed", Callable(self, "delete_param").bind(param_box))
	param_box.add_child(delete_button)
	
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_bottom", 5)
	param_box.add_child(margin)
	
	
	
	
