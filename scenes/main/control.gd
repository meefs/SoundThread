extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var cdpprogs_location
var delete_intermediate_outputs
@onready var console_output: RichTextLabel = $Console/ConsoleOutput
var final_output_dir

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Nodes.hide()
	$mainmenu.hide()
	$NoLocationPopup.hide()
	$Console.hide()
	$NoInputPopup.hide()
	
	#Goes through all nodes in scene and checks for buttons in the make_node_buttons group
	#Associates all buttons with the _on_button_pressed fuction and passes the button as an argument
	for child in get_tree().get_nodes_in_group("make_node_buttons"):
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))
	
	#Generate input and output nodes
	var effect: GraphNode = Nodes.get_node(NodePath("inputfile")).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = Vector2(-500,-150)
	
	effect = Nodes.get_node(NodePath("outputfile")).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = Vector2(1000,-150)
	
	check_cdp_location_set()
	
	#link output file to input file to enable audio output file loopback
	$GraphEdit/outputfile/AudioPlayer.recycle_outfile_trigger.connect($GraphEdit/inputfile/AudioPlayer.recycle_outfile)
	
	#link run process button to the batch generation script
	$GraphEdit/outputfile/RunProcess.button_down.connect(_run_process)
	
	#link and set delete intermediat files toggle from outputfile
	$GraphEdit/outputfile/DeleteIntermediateFilesToggle.toggled.connect(_toggle_delete)
	$GraphEdit/outputfile/DeleteIntermediateFilesToggle.button_pressed = true
	
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


func _on_button_pressed(button: Button):
	#close menu
	$mainmenu.hide()
	mainmenu_visible = false
	
	#Find node with matching name to button and create a version of it in the graph edit
	#and position it close to the origin right click to open the menu
	var effect: GraphNode = Nodes.get_node(NodePath(button.name)).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	effect.position_offset = effect_position


#logic for connecting, disconnecting and deleteing nodes and connections in GraphEdit
#mostly taken from https://gdscript.com/solutions/godot-graphnode-and-graphedit-tutorial/
func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	get_node("GraphEdit").connect_node(from_node, from_port, to_node, to_port)

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	get_node("GraphEdit").disconnect_node(from_node, from_port, to_node, to_port)

func _on_graph_edit_node_selected(node: Node) -> void:
	selected_nodes[node] = true

func _on_graph_edit_node_deselected(node: Node) -> void:
	selected_nodes[node] = false

func _on_graph_edit_delete_nodes_request(nodes: Array[StringName]) -> void:
	for node in selected_nodes.keys():
		if selected_nodes[node]:
			if  node.name == "inputfile":
				print("can't delete input")
			elif  node.name == "outputfile":
				print("can't delete output")
			else:
				remove_connections_to_node(node)
				node.queue_free()
	selected_nodes = {}

func remove_connections_to_node(node):
	for con in get_node("GraphEdit").get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			get_node("GraphEdit").disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			

#Here be dragons
#Scans through all nodes and generates a batch file based on their order

func _run_process() -> void:
	if Global.infile == "no_file":
		$NoInputPopup.show()
	else:
		$FileDialog.show()

func _on_file_dialog_dir_selected(dir: String) -> void:
	console_output.clear()
	$Console.show()
	log_console("Generating processing queue", true)

	#get the current time in hh-mm-ss format as default : causes file name issues
	var time_dict = Time.get_time_dict_from_system()
	# Pad with zeros to ensure two digits for hour, minute, second
	var hour = str(time_dict.hour).pad_zeros(2)
	var minute = str(time_dict.minute).pad_zeros(2)
	var second = str(time_dict.second).pad_zeros(2)
	var time_str = hour + "-" + minute + "-" + second
	Global.outfile = dir + "/outfile_" + Time.get_date_string_from_system() + "_" + time_str
	log_console("Output directory and file name(s):" + Global.outfile, true)
	
	generate_batch_file_with_branches()
	
func generate_batch_file_with_branches():
	var connections = graph_edit.get_connection_list()
	var graph = {}
	var reverse_graph = {}
	var indegree = {}
	var all_nodes = {}

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
		log_console("Adding cleanup commands for intermediate files", true)
		for file_path in intermediate_files:
			batch_lines.append("del \"%s\"" % file_path.replace("/", "\\"))

	# Step 6: Write batch file
	var file = FileAccess.open("user://ordered_script.bat", FileAccess.WRITE)
	for line in batch_lines:
		file.store_line(line)
	file.close()

	log_console("Batch script with merging written.", true)
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
	else:
		console_output.append_text("[color=red][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code + "\n \n")
		console_output.append_text("[b]Error:[/b]\n" )
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		console_output.append_text(error_str + "/n")


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
