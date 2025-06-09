extends GraphEdit

var control_script
var graph_edit
var open_help
var multiple_connections
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var copied_nodes_data = [] #stores node data on ctrl+c
var copied_connections = [] #stores all connections on ctrl+c
var node_data = {} #stores json with all nodes in it
var valueslider = preload("res://scenes/Nodes/valueslider.tscn") #slider scene for use in nodes
var node_logic = preload("res://scenes/Nodes/node_logic.gd") #load the script logic


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	snapping_enabled = false
	show_grid = false
	zoom = 0.9
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")

func init(main_node: Node, graphedit: GraphEdit, openhelp: Callable, multipleconnections: Window) -> void:
	control_script = main_node
	graph_edit = graphedit
	open_help = openhelp
	multiple_connections = multipleconnections

func _make_node(command: String, skip_undo_redo := false) -> GraphNode:
	if node_data.has(command):
		var node_info = node_data[command]
		
		if node_info.get("category", "") == "utility":
			#Find utility node with matching name and create a version of it in the graph edit
			#and position it close to the origin right click to open the menu
			var effect: GraphNode = Nodes.get_node(NodePath(command)).duplicate()
			effect.name = command
			add_child(effect, true)
			if command == "outputfile":
				effect.init() #initialise ui from user prefs
			effect.connect("open_help", open_help)
			effect.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom) #set node to current mouse position in graph edit
			_register_inputs_in_node(effect) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking

			control_script.changesmade = true

			if not skip_undo_redo:
				# Remove node with UndoRedo
				control_script.undo_redo.create_action("Add Node")
				control_script.undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(effect))
				control_script.undo_redo.add_undo_method(Callable(effect, "queue_free"))
				control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
				control_script.undo_redo.commit_action()
			
			return effect
		else: #auto generate node from json
			#get the title to display at the top of the node
			var title 
			if node_info.get("category", "") == "pvoc":
				title = "%s: %s" % [node_info.get("category", "").to_upper(), node_info.get("title", "")]
			else:
				title = "%s: %s" % [node_info.get("subcategory", "").to_pascal_case(), node_info.get("title", "")]
			var shortdescription = node_info.get("short_description", "") #for tooltip
			
			#get node properties
			var stereo = node_info.get("stereo", false)
			var inputs = JSON.parse_string(node_info.get("inputtype", ""))
			var outputs = JSON.parse_string(node_info.get("outputtype", ""))
			var portcount = max(inputs.size(), outputs.size())
			var parameters = node_info.get("parameters", {})
			
			var graphnode = GraphNode.new()
			for i in range(portcount):
				#add a number of control nodes equal to whatever is higher input or output ports
				var control = Control.new()
				graphnode.add_child(control)
				
				#check if input or output is enabled
				var enable_input = i < inputs.size()
				var enable_output = i < outputs.size()
				
				#get the colour of the port for time or pvoc ins/outs
				var input_colour = Color("#ffffff90")
				var output_colour = Color("#ffffff90")
				
				if enable_input:
					if inputs[i] == 1:
						input_colour = Color("#000000b0")
				if enable_output:
					if outputs[i] == 1:
						output_colour = Color("#000000b0")
				
				#enable and set ports
				if enable_input == true and enable_output == false:
					graphnode.set_slot(i, true, inputs[i], input_colour, false, 0, output_colour)
				elif enable_input == false and enable_output == true:
					graphnode.set_slot(i, false, 0, input_colour, true, outputs[i], output_colour)
				elif enable_input == true and enable_output == true:
					graphnode.set_slot(i, true, inputs[i], input_colour, true, outputs[i], output_colour)
				else:
					pass
			#set meta data for the process
			graphnode.set_meta("command", command)
			graphnode.set_meta("stereo_input", stereo)
			if inputs.size() == 0 and outputs.size() > 0:
				graphnode.set_meta("input", true)
			else:
				graphnode.set_meta("input", false)
			
			#adjust size, position and title of the node
			graphnode.title = title
			graphnode.tooltip_text = shortdescription
			graphnode.size.x = 306
			graphnode.custom_minimum_size.y = 80
			graphnode.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom)
			graphnode.name = command
			
			if parameters.is_empty():
				var noparams = Label.new()
				noparams.text = "No adjustable parameters"
				
				graphnode.add_child(noparams)
			else:
				for param_key in parameters.keys():
					var param_data = parameters[param_key]
					if param_data.get("uitype", "") == "hslider":
						#instance the slider scene
						var slider = valueslider.instantiate()
						
						#get slider text
						var slider_label = param_data.get("paramname", "")
						var slider_tooltip  = param_data.get("paramdescription", "")
						
						#get slider properties
						var brk = param_data.get("automatable", false)
						var time = param_data.get("time", false)
						var outputduration = param_data.get("outputduration", false)
						var min = param_data.get("min", false)
						var max = param_data.get("max", false)
						var flag = param_data.get("flag", "")
						var minrange = param_data.get("minrange", 0)
						var maxrange = param_data.get("maxrange", 10)
						var step = param_data.get("step", 0.01)
						var value = param_data.get("value", 1)
						var exponential = param_data.get("exponential", false)
						
						#set labels and tooltips
						slider.get_node("SliderLabel").text = slider_label
						if brk == true:
							slider.get_node("SliderLabel").text += "~"
						slider.tooltip_text = slider_tooltip
						slider.get_node("SliderLabel").tooltip_text = slider_tooltip
						
						#set meta data
						var hslider = slider.get_node("HSplitContainer/HSlider")
						hslider.set_meta("brk", brk)
						hslider.set_meta("time", time)
						hslider.set_meta("min", min)
						hslider.set_meta("max", max)
						hslider.set_meta("flag", flag)
						
						#set slider params
						hslider.min_value = minrange
						hslider.max_value = maxrange
						hslider.step = step
						hslider.value = value
						hslider.exp_edit = exponential
						
						#add output duration meta to main if true
						if outputduration:
							graphnode.set_meta("outputduration", value)
						
						graphnode.add_child(slider)
					
					elif param_data.get("uitype", "") == "checkbutton":
						#make a checkbutton
						var checkbutton = CheckButton.new()
						
						#get button text
						var checkbutton_label = param_data.get("paramname", "")
						var checkbutton_tooltip  = param_data.get("paramdescription", "")
						
						#get checkbutton properties
						var flag = param_data.get("flag", "")
						
						checkbutton.text = checkbutton_label
						checkbutton.tooltip_text = checkbutton_tooltip
						
						var checkbutton_pressed = param_data.get("value", "false")
						#get button state
						if str(checkbutton_pressed).to_lower() == "true":
							checkbutton.button_pressed = true
							
						#set checkbutton meta
						checkbutton.set_meta("flag", flag)
						
						graphnode.add_child(checkbutton)
					elif param_data.get("uitype", "") == "optionbutton":
						#make optionbutton and label
						var label = Label.new()
						var optionbutton = OptionButton.new()
						var margin = MarginContainer.new()
						
						#get button text
						var optionbutton_label = param_data.get("paramname", "")
						var optionbutton_tooltip  = param_data.get("paramdescription", "")
						
						#get optionbutton properties
						var options = JSON.parse_string(param_data.get("step", ""))
						var value = param_data.get("value", 1)
						var flag = param_data.get("flag", "")
						
						label.text = optionbutton_label
						optionbutton.tooltip_text = optionbutton_tooltip
						
						#fill option button
						for option in options:
							optionbutton.add_item(str(option))
						
						
						#select the given id
						optionbutton.select(int(value))
						
						#set flag meta
						optionbutton.set_meta("flag", flag)
						
						#add margin size for ertical spacing
						margin.add_theme_constant_override("margin_bottom", 4)
						
						graphnode.add_child(label)
						graphnode.add_child(optionbutton)
						graphnode.add_child(margin)
			
			
			graphnode.set_script(node_logic)
			
			add_child(graphnode, true)
			graphnode.connect("open_help", open_help)
			_register_inputs_in_node(graphnode) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking
			
			if not skip_undo_redo:
				# Remove node with UndoRedo
				control_script.undo_redo.create_action("Add Node")
				control_script.undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(graphnode))
				control_script.undo_redo.add_undo_method(Callable(graphnode, "queue_free"))
				control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
				control_script.undo_redo.commit_action()
			
			return graphnode
			
	return null
	

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var to_graph_node = get_node(NodePath(to_node))

	# Get the type of the input port using GraphNode's built-in method
	var port_type = to_graph_node.get_input_port_type(to_port)

	# If port type is 1 and already has a connection, reject the request
	if port_type == 1:
		var connections = get_connection_list()
		var existing_connections = 0

		for conn in connections:
			if conn.to_node == to_node and conn.to_port == to_port:
				existing_connections += 1
				if existing_connections >= 1:
					var interface_settings = ConfigHandler.load_interface_settings()
					if interface_settings.disable_pvoc_warning == false:
						multiple_connections.popup_centered()
					return

	# If no conflict, allow the connection
	connect_node(from_node, from_port, to_node, to_port)
	control_script.changesmade = true

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	control_script.changesmade = true

func _on_graph_edit_node_selected(node: Node) -> void:
	selected_nodes[node] = true

func _on_graph_edit_node_deselected(node: Node) -> void:
	selected_nodes[node] = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			_on_graph_edit_delete_nodes_request(PackedStringArray(selected_nodes.keys().filter(func(k): return selected_nodes[k])))
			pass

func _on_graph_edit_delete_nodes_request(nodes: Array[StringName]) -> void:
	control_script.undo_redo.create_action("Delete Nodes (Undo only)")
	
	#get the number of inputs in the patch
	#var number_of_inputs = 0
	#for allnodes in get_children():
		#if allnodes.get_meta("command") == "inputfile":
			#number_of_inputs += 1
			
	for node in selected_nodes.keys():
		if selected_nodes[node]:
			#check if node is the output or the last input node and do nothing
			if node.get_meta("command") == "outputfile":
				pass
			else:
				# Store duplicate and state for undo
				var node_data = node.duplicate()
				var position = node.position_offset

				# Store all connections for undo
				var conns = []
				for con in get_connection_list():
					if con["to_node"] == node.name or con["from_node"] == node.name:
						conns.append(con)

				# Delete
				remove_connections_to_node(node)
				node.queue_free()
				control_script.changesmade = true

				# Register undo restore
				control_script.undo_redo.add_undo_method(Callable(self, "add_child").bind(node_data, true))
				control_script.undo_redo.add_undo_method(Callable(node_data, "set_position_offset").bind(position))
				for con in conns:
					control_script.undo_redo.add_undo_method(Callable(self, "connect_node").bind(
						con["from_node"], con["from_port"],
						con["to_node"], con["to_port"]
					))
				control_script.undo_redo.add_undo_method(Callable(self, "set_node_selected").bind(node_data, true))
				control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
				control_script.undo_redo.add_undo_method(Callable(self, "_register_inputs_in_node").bind(node_data)) #link sliders for changes tracking
				control_script.undo_redo.add_undo_method(Callable(self, "_register_node_movement")) # link nodes for changes tracking

	# Clear selection
	selected_nodes = {}

	control_script.undo_redo.commit_action()

func set_node_selected(node: Node, selected: bool) -> void:
	selected_nodes[node] = selected
#
func remove_connections_to_node(node):
	for con in get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			control_script.changesmade = true
			
#copy and paste nodes with vertical offset on paste
func copy_selected_nodes():
	copied_nodes_data.clear()
	copied_connections.clear()

	# Store selected nodes and their slider values
	for node in get_children():
		# Check if the node is selected and not an 'inputfile' or 'outputfile'
		if node is GraphNode and selected_nodes.get(node, false):
			if node.get_meta("command") == "outputfile":
				continue  # Skip these nodes

			var node_data = {
				"name": node.name,
				"type": node.get_class(),
				"offset": node.position_offset,
				"slider_values": {}
			}

			for child in node.get_children():
				if child is HSlider or child is VSlider:
					node_data["slider_values"][child.name] = child.value

			copied_nodes_data.append(node_data)

	# Store connections between selected nodes
	for conn in get_connection_list():
		var from_ref = get_node_or_null(NodePath(conn["from_node"]))
		var to_ref = get_node_or_null(NodePath(conn["to_node"]))

		var is_from_selected = from_ref != null and selected_nodes.get(from_ref, false)
		var is_to_selected = to_ref != null and selected_nodes.get(to_ref, false)

		# Skip if any of the connected nodes are 'inputfile' or 'outputfile'
		if (from_ref != null and (from_ref.get_meta("command") == "inputfile" or from_ref.get_meta("command") == "outputfile")) or (to_ref != null and (to_ref.get_meta("command") == "inputfile" or to_ref.get_meta("command") == "outputfile")):
			continue

		if is_from_selected and is_to_selected:
			# Store connection as dictionary
			var conn_data = {
				"from_node": conn["from_node"],
				"from_port": conn["from_port"],
				"to_node": conn["to_node"],
				"to_port": conn["to_port"]
			}
			copied_connections.append(conn_data)

func paste_copied_nodes():
	if copied_nodes_data.is_empty():
		return

	var name_map = {}
	var pasted_nodes = []

	# Step 1: Find topmost and bottommost Y of copied nodes
	var min_y = INF
	var max_y = -INF
	for node_data in copied_nodes_data:
		var y = node_data["offset"].y
		min_y = min(min_y, y)
		max_y = max(max_y, y)

	# Step 2: Decide where to paste the group
	var base_y_offset = max_y + 350  # Pasting below the lowest node

	# Step 3: Paste nodes, preserving vertical layout
	for node_data in copied_nodes_data:
		var original_node = get_node_or_null(NodePath(node_data["name"]))
		if not original_node:
			continue

		var new_node = original_node.duplicate()
		new_node.name = node_data["name"] + "_copy_" + str(randi() % 10000)

		var relative_y = node_data["offset"].y - min_y
		new_node.position_offset = Vector2(
			node_data["offset"].x,
			base_y_offset + relative_y
		)
		

		# Restore sliders
		for child in new_node.get_children():
			if child.name in node_data["slider_values"]:
				child.value = node_data["slider_values"][child.name]

		add_child(new_node, true)
		new_node.connect("open_help", open_help)
		_register_inputs_in_node(new_node) #link sliders for changes tracking
		_register_node_movement() # link nodes for changes tracking
		name_map[node_data["name"]] = new_node.name
		pasted_nodes.append(new_node)


	# Step 4: Reconnect new nodes
	for conn_data in copied_connections:
		var new_from = name_map.get(conn_data["from_node"], null)
		var new_to = name_map.get(conn_data["to_node"], null)

		if new_from and new_to:
			connect_node(new_from, conn_data["from_port"], new_to, conn_data["to_port"])

	# Step 5: Select pasted nodes
	for pasted_node in pasted_nodes:
		set_selected(pasted_node)
		selected_nodes[pasted_node] = true
	
	control_script.changesmade = true
	
	# Remove node with UndoRedo
	control_script.undo_redo.create_action("Paste Nodes")
	for pasted_node in pasted_nodes:
		control_script.undo_redo.add_undo_method(Callable(self, "remove_child").bind(pasted_node))
		control_script.undo_redo.add_undo_method(Callable(pasted_node, "queue_free"))
		control_script.undo_redo.add_undo_method(Callable(self, "remove_connections_to_node").bind(pasted_node))
		control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
	control_script.undo_redo.commit_action()
	

#functions for tracking changes for save state detection
func _register_inputs_in_node(node: Node):
	#tracks input to nodes sliders and codeedit to track if patch is saved
	# Track Sliders
	for slider in node.find_children("*", "HSlider", true, false):
		# Create a Callable to the correct method
		var callable = Callable(self, "_on_any_slider_changed")
		# Check if it's already connected, and connect if not
		if not slider.is_connected("value_changed", callable):
			slider.connect("value_changed", callable)
	
	for slider in node.find_children("*", "VBoxContainer", true, false):
		# Also connect to meta_changed if the slider has that signal
		if slider.has_signal("meta_changed"):
			var meta_callable = Callable(self, "_on_any_slider_meta_changed")
			if not slider.is_connected("meta_changed", meta_callable):
				slider.connect("meta_changed", meta_callable)
		
	# Track CodeEdits
	for editor in node.find_children("*", "CodeEdit", true, false):
		var callable = Callable(self, "_on_any_input_changed")
		if not editor.is_connected("text_changed", callable):
			editor.connect("text_changed", callable)
			
func _on_any_slider_meta_changed():
	control_script.changesmade = true
	print("Meta changed in slider")
	
func _register_node_movement():
	for graphnode in get_children():
		if graphnode is GraphNode:
			var callable = Callable(self, "_on_graphnode_moved")
			if not graphnode.is_connected("position_offset_changed", callable):
				graphnode.connect("position_offset_changed", callable)

func _on_graphnode_moved():
	control_script.changesmade = true
	
func _on_any_slider_changed(value: float) -> void:
	control_script.changesmade = true
	
func _on_any_input_changed():
	control_script.changesmade = true

func _track_changes():
	control_script.changesmade = true


func _on_copy_nodes_request() -> void:
	graph_edit.copy_selected_nodes()
	#get_viewport().set_input_as_handled()


func _on_paste_nodes_request() -> void:
	control_script.simulate_mouse_click() #hacky fix to stop tooltips getting stuck
	await get_tree().process_frame
	graph_edit.paste_copied_nodes()
