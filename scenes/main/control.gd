extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var cdpprogs_location
var delete_intermediate_outputs
@onready var console_output: RichTextLabel = $Console/ConsoleOutput
var final_output_dir
var copied_nodes_data = []
var copied_connections = []
var undo_redo := UndoRedo.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Nodes.hide()
	$mainmenu.hide()
	$NoLocationPopup.hide()
	$Console.hide()
	$NoInputPopup.hide()
	$MultipleConnectionsPopup.hide()
	
	$SaveDialog.access = FileDialog.ACCESS_FILESYSTEM
	$SaveDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	$SaveDialog.filters = ["*.thd"]
	
	$LoadDialog.access = FileDialog.ACCESS_FILESYSTEM
	$LoadDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	$LoadDialog.filters = ["*.thd"]
	
	#Goes through all nodes in scene and checks for buttons in the make_node_buttons group
	#Associates all buttons with the _on_button_pressed fuction and passes the button as an argument
	for child in get_tree().get_nodes_in_group("make_node_buttons"):
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))
	
	DisplayServer.screen_get_size().x
	#Generate input and output nodes
	var effect: GraphNode = Nodes.get_node(NodePath("inputfile")).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = Vector2(20,80)
	
	effect = Nodes.get_node(NodePath("outputfile")).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = Vector2((DisplayServer.screen_get_size().x - 480) ,80)
	
	check_cdp_location_set()
	check_user_preferences()
	
	
	#link output file to input file to enable audio output file loopback
	$GraphEdit/outputfile/AudioPlayer.recycle_outfile_trigger.connect($GraphEdit/inputfile/AudioPlayer.recycle_outfile)
	
	#link run process button to the batch generation script
	$GraphEdit/outputfile/RunProcess.button_down.connect(_run_process)
	
	#link and set delete intermediat files toggle from outputfile
	$GraphEdit/outputfile/DeleteIntermediateFilesToggle.toggled.connect(_toggle_delete)
	$GraphEdit/outputfile/DeleteIntermediateFilesToggle.button_pressed = true
	
func check_user_preferences():
	var interface_settings = ConfigHandler.load_interface_settings()
	$MenuBar/SettingsButton.set_item_checked(1, interface_settings.disable_pvoc_warning)
	$MenuBar/SettingsButton.set_item_checked(2, interface_settings.auto_close_console)

	
func check_cdp_location_set():
	#checks if the location has been set and prompts user to set it
	var cdpprogs_settings = ConfigHandler.load_cdpprogs_settings()
	if cdpprogs_settings.location == "no_location":
		$NoLocationPopup.show()
	else:
		#if location is set, stores it in a variable
		cdpprogs_location = str(cdpprogs_settings.location)
		print(cdpprogs_location)

func _on_ok_button_button_down() -> void:
	#after user has read dialog on where to find cdp progs this loads the file browser
	$NoLocationPopup.hide()
	$CdpLocationDialog.show()

func _on_cdp_location_dialog_dir_selected(dir: String) -> void:
	#saves default location for cdp programs in config file
	ConfigHandler.save_cdpprogs_settings(dir)

func _on_cdp_location_dialog_canceled() -> void:
	#cycles around the set location prompt if user cancels the file dialog
	check_cdp_location_set()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	showmenu()
	

func _input(event):
	if event.is_action_pressed("copy_node"):
		copy_selected_nodes()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("paste_node"):
		paste_copied_nodes()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("undo"):
		undo_redo.undo()
	elif event.is_action_pressed("redo"):
		undo_redo.redo()


#logic for making, connecting, disconnecting, copy pasting and deleteing nodes and connections in GraphEdit
#mostly taken from https://gdscript.com/solutions/godot-graphnode-and-graphedit-tutorial/
func showmenu():
	#check for mouse input and if menu is already open and then open or close the menu
	#stores mouse position at time of right click to later place a node in that location
	if Input.is_action_just_pressed("open_menu"):
		if mainmenu_visible == false:
			effect_position = get_viewport().get_mouse_position()
			$mainmenu.show()
			mainmenu_visible = true
		else:
			$mainmenu.hide()
			mainmenu_visible = false

# creates nodes from menu
func _on_button_pressed(button: Button):
	#close menu
	$mainmenu.hide()
	mainmenu_visible = false
	
	#Find node with matching name to button and create a version of it in the graph edit
	#and position it close to the origin right click to open the menu
	var effect: GraphNode = Nodes.get_node(NodePath(button.name)).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = effect_position


	# Remove node with UndoRedo
	undo_redo.create_action("Add Node")
	undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(effect))
	undo_redo.add_undo_method(Callable(effect, "queue_free"))
	undo_redo.commit_action()

func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#get_node("GraphEdit").connect_node(from_node, from_port, to_node, to_port)
	var graph_edit = get_node("GraphEdit")
	var to_graph_node = graph_edit.get_node(NodePath(to_node))

	# Get the type of the input port using GraphNode's built-in method
	var port_type = to_graph_node.get_input_port_type(to_port)

	# If port type is 1 and already has a connection, reject the request
	if port_type == 1:
		var connections = graph_edit.get_connection_list()
		var existing_connections = 0

		for conn in connections:
			if conn.to_node == to_node and conn.to_port == to_port:
				existing_connections += 1
				if existing_connections >= 1:
					var interface_settings = ConfigHandler.load_interface_settings()
					if interface_settings.disable_pvoc_warning == false:
						$MultipleConnectionsPopup.show()
					return

	# If no conflict, allow the connection
	graph_edit.connect_node(from_node, from_port, to_node, to_port)

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	get_node("GraphEdit").disconnect_node(from_node, from_port, to_node, to_port)

func _on_graph_edit_node_selected(node: Node) -> void:
	selected_nodes[node] = true

func _on_graph_edit_node_deselected(node: Node) -> void:
	selected_nodes[node] = false

func _on_graph_edit_delete_nodes_request(nodes: Array[StringName]) -> void:
	var graph_edit = get_node("GraphEdit")
	undo_redo.create_action("Delete Nodes (Undo only)")

	for node in selected_nodes.keys():
		if selected_nodes[node]:
			if node.name in ["inputfile", "outputfile"]:
				print("can't delete input or output")
			else:
				# Store duplicate and state for undo
				var node_data = node.duplicate()
				var position = node.position_offset

				# Store all connections for undo
				var conns = []
				for con in graph_edit.get_connection_list():
					if con["to_node"] == node.name or con["from_node"] == node.name:
						conns.append(con)

				# Delete
				remove_connections_to_node(node)
				node.queue_free()

				# Register undo restore
				undo_redo.add_undo_method(Callable(graph_edit, "add_child").bind(node_data, true))
				undo_redo.add_undo_method(Callable(node_data, "set_position_offset").bind(position))
				for con in conns:
					undo_redo.add_undo_method(Callable(graph_edit, "connect_node").bind(
						con["from_node"], con["from_port"],
						con["to_node"], con["to_port"]
					))
				undo_redo.add_undo_method(Callable(self, "set_node_selected").bind(node_data, true))

	# Clear selection
	selected_nodes = {}

	undo_redo.commit_action()

func set_node_selected(node: Node, selected: bool) -> void:
	selected_nodes[node] = selected
#
func remove_connections_to_node(node):
	for con in get_node("GraphEdit").get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			get_node("GraphEdit").disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			
#copy and paste nodes with vertical offset on paste
func copy_selected_nodes():
	copied_nodes_data.clear()
	copied_connections.clear()

	var graph_edit = get_node("GraphEdit")

	# Store selected nodes and their slider values
	for node in graph_edit.get_children():
		# Check if the node is selected and not an 'inputfile' or 'outputfile'
		if node is GraphNode and selected_nodes.get(node, false):
			if node.name == "inputfile" or node.name == "outputfile":
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
	for conn in graph_edit.get_connection_list():
		var from_ref = graph_edit.get_node_or_null(NodePath(conn["from_node"]))
		var to_ref = graph_edit.get_node_or_null(NodePath(conn["to_node"]))

		var is_from_selected = from_ref != null and selected_nodes.get(from_ref, false)
		var is_to_selected = to_ref != null and selected_nodes.get(to_ref, false)

		# Skip if any of the connected nodes are 'inputfile' or 'outputfile'
		if (from_ref != null and (from_ref.name == "inputfile" or from_ref.name == "outputfile")) or (to_ref != null and (to_ref.name == "inputfile" or to_ref.name == "outputfile")):
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

	var graph_edit = get_node("GraphEdit")
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
		var original_node = graph_edit.get_node_or_null(NodePath(node_data["name"]))
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

		graph_edit.add_child(new_node, true)
		name_map[node_data["name"]] = new_node.name
		pasted_nodes.append(new_node)


	# Step 4: Reconnect new nodes
	for conn_data in copied_connections:
		var new_from = name_map.get(conn_data["from_node"], null)
		var new_to = name_map.get(conn_data["to_node"], null)

		if new_from and new_to:
			graph_edit.connect_node(new_from, conn_data["from_port"], new_to, conn_data["to_port"])

	# Step 5: Select pasted nodes
	for pasted_node in pasted_nodes:
		graph_edit.set_selected(pasted_node)
		selected_nodes[pasted_node] = true

	# Remove node with UndoRedo
	undo_redo.create_action("Paste Nodes")
	for pasted_node in pasted_nodes:
		undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(pasted_node))
		undo_redo.add_undo_method(Callable(pasted_node, "queue_free"))
		undo_redo.add_undo_method(Callable(self, "remove_connections_to_node").bind(pasted_node))
	undo_redo.commit_action()

######## Here be dragons #########
##################################

#Scans through all nodes and generates a batch file based on their order

func _run_process() -> void:
	if Global.infile == "no_file":
		$NoInputPopup.show()
	else:
		$FileDialog.show()

func _on_file_dialog_dir_selected(dir: String) -> void:
	console_output.clear()
	$Console.show()
	await get_tree().process_frame
	log_console("Generating processing queue", true)
	await get_tree().process_frame

	#get the current time in hh-mm-ss format as default : causes file name issues
	var time_dict = Time.get_time_dict_from_system()
	# Pad with zeros to ensure two digits for hour, minute, second
	var hour = str(time_dict.hour).pad_zeros(2)
	var minute = str(time_dict.minute).pad_zeros(2)
	var second = str(time_dict.second).pad_zeros(2)
	var time_str = hour + "-" + minute + "-" + second
	Global.outfile = dir + "/outfile_" + Time.get_date_string_from_system() + "_" + time_str
	log_console("Output directory and file name(s):" + Global.outfile, true)
	await get_tree().process_frame
	
	generate_batch_file_with_branches()
	
func generate_batch_file_with_branches():
	var connections = graph_edit.get_connection_list()
	var graph = {}
	var reverse_graph = {}
	var indegree = {}
	var all_nodes = {}
	
	log_console("Generating batch file.", true)
	await get_tree().process_frame
	
	# Step 1: Collect nodes
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			all_nodes[name] = child
			if name != "inputfile" and name != "outputfile":
				graph[name] = []
				reverse_graph[name] = []
				indegree[name] = 0

	# Step 2: Build the graph
	for conn in connections:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from) and graph.has(to):
			graph[from].append(to)
			reverse_graph[to].append(from)
			indegree[to] += 1

	# Step 3: Topological sort
	var sorted = []
	var queue = []
	for node in graph.keys():
		if indegree[node] == 0:
			queue.append(node)
	while not queue.is_empty():
		var current = queue.pop_front()
		sorted.append(current)
		for neighbor in graph[current]:
			indegree[neighbor] -= 1
			if indegree[neighbor] == 0:
				queue.append(neighbor)
	if sorted.size() != graph.size():
		log_console("Cycle detected or disconnected nodes", true)
		return

	# Step 4: Batch file generation
	var batch_lines = []
	var intermediate_files = []
	var stereo_outputs = {}

	if Global.infile_stereo:
		log_console("Input file is stereo, note this may cause left/right decorrelation with some processes.", true)
		await get_tree().process_frame
		
		# Step 4.1: Split stereo to c1/c2
		batch_lines.append("%s/housekeep chans 2 \"%s\"" % [cdpprogs_location, Global.infile])

		# Process for each channel
		for channel in ["c1", "c2"]:
			var current_infile = Global.infile.get_basename() + "_%s.wav" % channel
			var output_files = {}
			var process_count = 0

			for node_name in sorted:
				var node = all_nodes[node_name]
				var inputs = reverse_graph[node_name]
				var input_files = []
				for input_node in inputs:
					if output_files.has(input_node):
						input_files.append(output_files[input_node])

				if input_files.size() > 1:
					var merge_output = "%s_%s_merge_%d.wav" % [Global.outfile.get_basename(), channel, process_count]
					var quoted_inputs = []
					for f in input_files:
						quoted_inputs.append("\"%s\"" % f)
					var merge_cmd = cdpprogs_location + "/submix mergemany " + " ".join(quoted_inputs) + " \"%s\"" % merge_output
					batch_lines.append(merge_cmd)
					intermediate_files.append(merge_output)
					current_infile = merge_output
				elif input_files.size() == 1:
					current_infile = input_files[0]
				else:
					current_infile = Global.infile.get_basename() + "_%s.wav" % channel

				var slider_data = _get_slider_values_ordered(node)
				var extension = ".wav" if node.get_slot_type_right(0) == 0 else ".ana"
				var output_file = "%s_%s_%d%s" % [Global.outfile.get_basename(), channel, process_count, extension]
				var command_name = str(node.get_meta("command")) if node.has_meta("command") else node_name
				command_name = command_name.replace("_", " ")
				var line = "%s/%s \"%s\" \"%s\" " % [cdpprogs_location, command_name, current_infile, output_file]
				for entry in slider_data:
					line += ("%s%.2f " % [entry[0], entry[1]]) if entry[0].begins_with("-") else ("%.2f " % entry[1])
				batch_lines.append(line.strip_edges())
				output_files[node_name] = output_file
				if delete_intermediate_outputs:
					intermediate_files.append(output_file)
				process_count += 1

			# Handle output node
			var output_inputs = []
			for conn in connections:
				if conn["to_node"] == "outputfile":
					output_inputs.append(str(conn["from_node"]))
			var final_output = ""
			if output_inputs.size() > 1:
				var quoted_inputs = []
				for fnode in output_inputs:
					if output_files.has(fnode):
						quoted_inputs.append("\"%s\"" % output_files[fnode])
						#intermediate_files.append(output_files[fnode])
				final_output = "%s_%s_final.wav" % [Global.outfile.get_basename(), channel]
				batch_lines.append("%s/submix mergemany %s \"%s\"" % [cdpprogs_location, " ".join(quoted_inputs), final_output])
			elif output_inputs.size() == 1:
				final_output = output_files[output_inputs[0]]
				intermediate_files.erase(final_output)
			stereo_outputs[channel] = final_output

		# Interleave final
		if stereo_outputs.has("c1") and stereo_outputs.has("c2"):
			if stereo_outputs["c1"].ends_with(".wav") and stereo_outputs["c2"].ends_with(".wav"):
				var final_stereo = Global.outfile.get_basename() + "_stereo.wav"
				batch_lines.append("%s/submix interleave \"%s\" \"%s\" \"%s\"" % [cdpprogs_location, stereo_outputs["c1"], stereo_outputs["c2"], final_stereo])
				final_output_dir = final_stereo
				if delete_intermediate_outputs:
					intermediate_files.append(stereo_outputs["c1"])
					intermediate_files.append(stereo_outputs["c2"])
				
		#add del command for not needed files
		#always delete mono split as they are in a weird location
		intermediate_files.append(Global.infile.get_basename() + "_c1.wav")
		intermediate_files.append(Global.infile.get_basename() + "_c2.wav")
		
		for file_path in intermediate_files:
			batch_lines.append("del \"%s\"" % file_path.replace("/", "\\"))
			
	else:
		# Use mono logic as before
			# Step 4: Process chain
		var output_files = {}  # node -> output file
		var process_count = 0
		var current_infile = Global.infile

		for node_name in sorted:
			var node = all_nodes[node_name]
			var inputs = reverse_graph[node_name]
			var input_files = []
			for input_node in inputs:
				input_files.append(output_files[input_node])

			# If multiple inputs, merge with submix mergemany
			if input_files.size() > 1:
				var merge_output = "%s_merge_%d.wav" % [Global.outfile.get_basename(), process_count]
				var quoted_inputs := []
				for f in input_files:
					quoted_inputs.append("\"%s\"" % f)
				var merge_cmd = cdpprogs_location + "/submix mergemany " + " ".join(quoted_inputs) + " \"%s\"" % merge_output
				batch_lines.append(merge_cmd)
				intermediate_files.append(merge_output)
				current_infile = merge_output
			elif input_files.size() == 1:
				current_infile = input_files[0]
			else:
				current_infile = Global.infile

			# Build node command
			var slider_data = _get_slider_values_ordered(node)
			var extension = ".wav" if node.get_slot_type_right(0) == 0 else ".ana"
			var output_file = "%s_%d%s" % [Global.outfile.get_basename(), process_count, extension]
			var command_name = str(node.get_meta("command")) if node.has_meta("command") else node_name
			command_name = command_name.replace("_", " ")
			var line = "%s/%s \"%s\" \"%s\" " % [cdpprogs_location, command_name, current_infile, output_file]
			for entry in slider_data:
				line += ("%s%.2f " % [entry[0], entry[1]]) if entry[0].begins_with("-") else ("%.2f " % entry[1])
			batch_lines.append(line.strip_edges())
			output_files[node_name] = output_file
			if delete_intermediate_outputs:
				intermediate_files.append(output_file)
			process_count += 1

		# Step 4.5: Handle nodes connected to outputfile
		var output_inputs := []
		for conn in connections:
			if conn["to_node"] == "outputfile":
				output_inputs.append(str(conn["from_node"]))

		var final_outputs := []
		for node_name in output_inputs:
			if output_files.has(node_name):
				final_outputs.append(output_files[node_name])

		if final_outputs.size() > 1:
			var quoted_inputs := []
			for f in final_outputs:
				quoted_inputs.append("\"%s\"" % f)
				intermediate_files.append(f)
			var merge_cmd = cdpprogs_location + "/submix mergemany " + " ".join(quoted_inputs) + " \"%s\"" % Global.outfile + ".wav"
			final_output_dir = Global.outfile + ".wav"
			batch_lines.append(merge_cmd)
			for f in final_outputs:
				intermediate_files.erase(f)
		elif final_outputs.size() == 1:
			var single_output = final_outputs[0]
			final_output_dir = single_output
			intermediate_files.erase(single_output)

		# Step 5: Cleanup commands
		log_console("Adding cleanup commands for intermediate files.", true)
		for file_path in intermediate_files:
			batch_lines.append("del \"%s\"" % file_path.replace("/", "\\"))

	# Step 6: Write batch file
	var file = FileAccess.open("user://ordered_script.bat", FileAccess.WRITE)
	for line in batch_lines:
		file.store_line(line)
	file.close()

	log_console("Batch file complete.", true)
	log_console("Processing audio, please wait.", true)
	await get_tree().process_frame
	run_batch_file()


# Ordered slider collection
func _get_slider_values_ordered(node: Node) -> Array:
	var results := []
	for child in node.get_children():
		if child is Range:
			results.append([child.name, child.value])
		elif child.get_child_count() > 0:
			var nested := _get_slider_values_ordered(child)
			results.append_array(nested)
	return results

func build_graph_from_connections(graph_edit: GraphEdit) -> Dictionary:
	var connections = graph_edit.get_connection_list()
	var graph := {}
	var reverse_graph := {}
	var all_nodes := {}

	# Collect all GraphNode names
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			all_nodes[name] = true
			graph[name] = []
			reverse_graph[name] = []

	# Build forward and reverse graphs
	for conn in connections:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from) and graph.has(to):
			graph[from].append(to)
			reverse_graph[to].append(from)

	# Perform BFS from "inputfile"
	var reachable := {}
	var queue := ["inputfile"]
	while not queue.is_empty():
		var current = queue.pop_front()
		if reachable.has(current):
			continue
		reachable[current] = true
		for neighbor in graph.get(current, []):
			queue.append(neighbor)

	# Reverse BFS from "outputfile"
	var required := {}
	queue = ["outputfile"]
	while not queue.is_empty():
		var current = queue.pop_front()
		if required.has(current):
			continue
		required[current] = true
		for parent in reverse_graph.get(current, []):
			queue.append(parent)

	# Keep only nodes that are reachable both ways
	var used_nodes := []
	for node in reachable.keys():
		if required.has(node):
			used_nodes.append(node)

	var pruned_graph := {}
	for node in used_nodes:
		var filtered_neighbors := []
		for neighbor in graph.get(node, []):
			if used_nodes.has(neighbor):
				filtered_neighbors.append(neighbor)
		pruned_graph[node] = filtered_neighbors

	return {
		"graph": pruned_graph,
		"nodes": used_nodes
	}

func topological_sort(graph: Dictionary, nodes: Array) -> Array:
	var indegree := {}
	for node in nodes:
		indegree[node] = 0
	for node in nodes:
		for neighbor in graph[node]:
			indegree[neighbor] += 1

	var queue := []
	for node in nodes:
		if indegree[node] == 0:
			queue.append(node)

	var sorted := []
	while not queue.is_empty():
		var current = queue.pop_front()
		sorted.append(current)
		for neighbor in graph[current]:
			indegree[neighbor] -= 1
			if indegree[neighbor] == 0:
				queue.append(neighbor)

	if sorted.size() != nodes.size():
		push_error("Cycle detected or disconnected graph.")
		return []
	
	return sorted


	
func run_batch_file():
	var bat_path = ProjectSettings.globalize_path("user://ordered_script.bat")
	var output : Array = []
	var error : Array = []

	var exit_code = OS.execute("cmd.exe", ["/c", bat_path], output, true, true)

	var output_str = ""
	for item in output:
		output_str += item + "\n"

	var error_str = ""
	for item in error:
		error_str += item + "\n"

	if exit_code == 0:
		console_output.append_text("[color=green]Processes ran successfully[/color]\n \n")
		console_output.append_text("[b]Output:[/b]\n")
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		console_output.append_text(output_str + "/n")
		if final_output_dir.ends_with(".wav"):
			$GraphEdit/outputfile/AudioPlayer.play_outfile(final_output_dir)
		var interface_settings = ConfigHandler.load_interface_settings()
		if interface_settings.auto_close_console == true:
			$Console.hide()
	else:
		console_output.append_text("[color=red][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code + "\n \n")
		console_output.append_text("[b]Error:[/b]\n" )
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		console_output.append_text(error_str + "/n")

######## Realtively free from dragons from here

func _toggle_delete(toggled_on: bool):
	delete_intermediate_outputs = toggled_on

func _on_console_close_requested() -> void:
	$Console.hide()

func log_console(text: String, update: bool) -> void:
	console_output.append_text(text + "\n \n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	if update == true:
		await get_tree().process_frame  # Optional: ensure UI updates


func _on_console_open_folder_button_down() -> void:
	$Console.hide()
	OS.shell_open(Global.outfile.get_base_dir())


func _on_ok_button_2_button_down() -> void:
	$NoInputPopup.hide()


func _on_ok_button_3_button_down() -> void:
	$MultipleConnectionsPopup.hide()



func _on_settings_button_index_pressed(index: int) -> void:
	var interface_settings = ConfigHandler.load_interface_settings()
	
	match index:
		0:
			$CdpLocationDialog.show()
		1:
			if interface_settings.disable_pvoc_warning == false:
				$MenuBar/SettingsButton.set_item_checked(index, true)
				ConfigHandler.save_interface_settings("disable_pvoc_warning", true)
			else:
				$MenuBar/SettingsButton.set_item_checked(index, false)
				ConfigHandler.save_interface_settings("disable_pvoc_warning", false)
		2:
			if interface_settings.auto_close_console == false:
				$MenuBar/SettingsButton.set_item_checked(index, true)
				ConfigHandler.save_interface_settings("auto_close_console", true)
			else:
				$MenuBar/SettingsButton.set_item_checked(index, false)
				ConfigHandler.save_interface_settings("auto_close_console", false)


func _on_file_button_index_pressed(index: int) -> void:
	match index:
		0:
			$SaveDialog.popup_centered()
		1:
			$LoadDialog.popup_centered()


func save_graph_edit(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("Failed to open file for saving")
		return

	var node_data_list = []
	var connection_data_list = []

	for node in graph_edit.get_children():
		if node is GraphNode:
			var offset = node.position_offset
			var node_data = {
				"name": node.name,
				"command": node.get_meta("command"),
				"offset": { "x": offset.x, "y": offset.y },
				"slider_values": {},
				"notes":{}
			}

			for child in node.find_children("*", "Slider", true, false):
				var relative_path = node.get_path_to(child)
				node_data["slider_values"][str(relative_path)] = child.value
				
			for child in node.find_children("*", "CodeEdit", true, false):
				node_data["notes"][child.name] = child.text

			node_data_list.append(node_data)

	for conn in graph_edit.get_connection_list():
		connection_data_list.append({
			"from_node": conn["from_node"],
			"from_port": conn["from_port"],
			"to_node": conn["to_node"],
			"to_port": conn["to_port"]
		})

	var graph_data = {
		"nodes": node_data_list,
		"connections": connection_data_list
	}

	var json = JSON.new()
	var json_string = json.stringify(graph_data, "\t")
	file.store_string(json_string)
	file.close()
	print("Graph saved.")


func load_graph_edit(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Failed to open file for loading")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("Error parsing JSON")
		return

	var graph_data = json.get_data()
	graph_edit.clear_connections()

	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()

	await get_tree().process_frame  # Ensure nodes are cleared

	for node_data in graph_data["nodes"]:
		var command_name = node_data.get("command", "")
		var template = Nodes.get_node_or_null(command_name)
		if not template:
			print("Template not found for command:", command_name)
			continue

		var new_node: GraphNode = template.duplicate()
		new_node.name = node_data["name"]
		new_node.position_offset = Vector2(node_data["offset"]["x"], node_data["offset"]["y"])
		new_node.set_meta("command", command_name)
		graph_edit.add_child(new_node)

		# Restore sliders
		for slider_path_str in node_data["slider_values"]:
			var slider = new_node.get_node_or_null(slider_path_str)
			if slider and (slider is HSlider or slider is VSlider):
				slider.value = node_data["slider_values"][slider_path_str]

				
		# Restore notes
		for codeedit_name in node_data["notes"]:
			var codeedit = new_node.find_child(codeedit_name, true, false)
			if codeedit and (codeedit is CodeEdit):
				codeedit.text = node_data["notes"][codeedit_name]
			
	# Restore connections
	for conn in graph_data["connections"]:
		graph_edit.connect_node(
			conn["from_node"], conn["from_port"],
			conn["to_node"], conn["to_port"]
		)

	print("Graph loaded.")


func _on_save_dialog_file_selected(path: String) -> void:
	save_graph_edit(path)



func _on_load_dialog_file_selected(path: String) -> void:
	load_graph_edit(path)


func _on_help_button_index_pressed(index: int) -> void:
	match index:
		0:
			pass
		1:
			pass
		2:
			load_graph_edit("res://examples/frequency_domain.thd")
		3:
			pass
		4:
			OS.shell_open("https://www.composersdesktop.com/docs/html/cdphome.htm")
