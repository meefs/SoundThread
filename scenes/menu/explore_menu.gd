extends Window

var node_data = {} #stores node data for each node to display in help popup
signal make_node(command)
signal open_help(command)


func _ready() -> void:
	
	$"Control/select_effect/Time Domain".show()
	$"Control/select_effect/Time Domain/Distort".show()
	$"Control/select_effect/Frequency Domain/Convert".show()
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")
				
	fill_menu()
	
func fill_menu():
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		#filter out output nodes
		if title == "Output File":
			continue
		
		var category = item.get("category", "")
		var subcategory = item.get("subcategory", "")
		var short_desc = item.get("short_description", "")
		
		var container
		if category == "time":
			if subcategory == "distort":
				container = $"Control/select_effect/Time Domain/Distort/MarginContainer/ScrollContainer/DistortContainer"
			elif subcategory == "extend":
				container = $"Control/select_effect/Time Domain/Extend/MarginContainer/ScrollContainer/ExtendContainer"
			elif subcategory == "filter":
				container = $"Control/select_effect/Time Domain/Filter/MarginContainer/ScrollContainer/FilterContainer"
			elif subcategory == "granulate":
				container = $"Control/select_effect/Time Domain/Granulate/MarginContainer/ScrollContainer/GranulateContainer"
			elif subcategory == "misc":
				container = $"Control/select_effect/Time Domain/Misc/MarginContainer/ScrollContainer/MiscContainer"
			elif subcategory == "reverb":
				container = $"Control/select_effect/Time Domain/Reverb and Delay/MarginContainer/ScrollContainer/ReverbContainer"
			else:
				continue
		elif category == "pvoc":
			if subcategory == "convert":
				container = $"Control/select_effect/Frequency Domain/Convert/MarginContainer/ScrollContainer/PVOCConvertContainer"
			elif subcategory == "amppitch":
				container = $"Control/select_effect/Frequency Domain/Amplitude and Pitch/MarginContainer/ScrollContainer/PVOCAmplitudePitchContainer"
			elif subcategory == "formants":
				container = $"Control/select_effect/Frequency Domain/Formants/MarginContainer/ScrollContainer/PVOCFormantsContainer"
			elif subcategory == "time":
				container = $"Control/select_effect/Frequency Domain/Time/MarginContainer/ScrollContainer/PVOCTimeContainer"
			elif subcategory == "spectrum":
				container = $"Control/select_effect/Frequency Domain/Spectrum/MarginContainer/ScrollContainer/PVOCSpectrumContainer"
			else:
				continue
		elif category == "utility":
			container = $Control/select_effect/Utilities/SoundThread/MarginContainer/ScrollContainer/UtilityContainer
		else:
			continue
		
		
		var hbox = HBoxContainer.new()
		var label = RichTextLabel.new()
		var helpbtn = Button.new()
		var makebtn = Button.new()
		var margin = MarginContainer.new()
		
		hbox.size.x = container.size.x
		label.bbcode_enabled = true
		label.text = "[b]%s[/b]\n%s" % [title, short_desc]
		label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		label.fit_content = true
		
		helpbtn.text = "?"
		helpbtn.tooltip_text = "Open help for " + title
		helpbtn.custom_minimum_size = Vector2(40, 40)
		helpbtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		helpbtn.connect("pressed", Callable(self, "_open_help").bind(key, title)) #pass key (process name) when button is pressed
		
		makebtn.text = "+"
		makebtn.tooltip_text = "Add " + title + " to thread"
		makebtn.custom_minimum_size = Vector2(40, 40)
		makebtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		makebtn.connect("pressed", Callable(self, "_make_node").bind(key)) #pass key (process name) when button is pressed
		
		margin.add_theme_constant_override("margin_bottom", 3)
		
		container.add_child(hbox)
		hbox.add_child(label)
		hbox.add_child(helpbtn)
		hbox.add_child(makebtn)
		container.add_child(margin)



func _on_about_to_popup() -> void:
	fill_search("")
	$"Control/select_effect/Search/Search for a process in SoundThread/MarginContainer/VBoxContainer/SearchBar".clear()
	if $Control/select_effect.current_tab == 3:
		$"Control/select_effect/Search/Search for a process in SoundThread/MarginContainer/VBoxContainer/SearchBar".grab_focus()
	



func fill_search(filter: String):
	# Remove all existing items from the VBoxContainer
	var container = $"Control/select_effect/Search/Search for a process in SoundThread/MarginContainer/VBoxContainer/ScrollContainer/ItemContainer"
	for child in container.get_children():
		child.queue_free()
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		#filter out output node
		if title == "Output File":
			continue
		
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
		var helpbtn = Button.new()
		var makebtn = Button.new()
		var margin = MarginContainer.new()
		
		hbox.size.x = container.size.x
		label.bbcode_enabled = true
		label.text = "[b]%s[/b]\n%s" % [title, short_desc]
		label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		label.fit_content = true
		
		helpbtn.text = "?"
		helpbtn.tooltip_text = "Open help for " + title
		helpbtn.custom_minimum_size = Vector2(40, 40)
		helpbtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		helpbtn.connect("pressed", Callable(self, "_open_help").bind(key, title)) #pass key (process name) when button is pressed
		
		makebtn.text = "+"
		makebtn.tooltip_text = "Add " + title + " to thread"
		makebtn.custom_minimum_size = Vector2(40, 40)
		makebtn.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		makebtn.connect("pressed", Callable(self, "_make_node").bind(key)) #pass key (process name) when button is pressed
		
		margin.add_theme_constant_override("margin_bottom", 3)
		
		container.add_child(hbox)
		hbox.add_child(label)
		hbox.add_child(helpbtn)
		hbox.add_child(makebtn)
		container.add_child(margin)

	

	
func _on_search_bar_text_changed(new_text: String) -> void:
	fill_search(new_text)
	pass
	
func _make_node(key: String):
	make_node.emit(key) # send out signal to main patch
	self.hide()

func _open_help(key: String, title: String):
	open_help.emit(key, title) # send out signal to main patch
	self.hide()


func _on_select_effect_tab_changed(tab: int) -> void:
	if tab == 3:
		$"Control/select_effect/Search/Search for a process in SoundThread/MarginContainer/VBoxContainer/SearchBar".grab_focus()
