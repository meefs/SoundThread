extends PopupPanel

@onready var item_container: VBoxContainer = $VBoxContainer/ScrollContainer/ItemContainer
@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var search_bar = $VBoxContainer/SearchBar
var node_data = {} #stores node data for each node to display in help popup
signal make_node(command)


func _ready() -> void:
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")
				
	#honestly not sure what of these is actually doing things
	item_container.custom_minimum_size.x = scroll_container.size.x
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.set("theme_override_constants/maximum_height", 400)



func _on_about_to_popup() -> void:
	display_items("") #populate menu when needed
	search_bar.clear()
	search_bar.grab_focus()

func display_items(filter: String):
	# Remove all existing items from the VBoxContainer
	for child in item_container.get_children():
		child.queue_free()
	for key in node_data.keys():
		var item = node_data[key]
		var title = item.get("title", "")
		
		#filter out input and output nodes
		#if title == "Input File" or title == "Output File":
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
		
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL #make buttons wide
		btn.alignment = 0 #left align text
		btn.clip_text = true #clip off labels that are too long
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS #and replace with ...
		if category.to_lower() == "pvoc": #format node names correctly, only show the category for PVOC
			btn.text = "%s %s: %s - %s" % [category.to_upper(), subcategory.to_pascal_case(), title, short_desc]
		else:
			btn.text = "%s: %s - %s" % [subcategory.to_pascal_case(), title, short_desc]
		btn.connect("pressed", Callable(self, "_on_item_selected").bind(key)) #pass key (process name) when button is pressed
		item_container.add_child(btn)
	
	#resize menu within certain bounds #50
	await get_tree().process_frame
	if DisplayServer.screen_get_scale() > 1:
		self.size.y = min((item_container.size.y * DisplayServer.screen_get_scale()) + search_bar.size.y + 50, 410 * DisplayServer.screen_get_scale()) #i think this will scale for retina screens but might be wrong
	else:
		self.size.y = min(item_container.size.y + search_bar.size.y + 12, 410)
	
func _on_search_bar_text_changed(new_text: String) -> void:
	display_items(new_text)
	
func _on_item_selected(key: String):
	self.hide()
	make_node.emit(key) # send out signal to main patch
