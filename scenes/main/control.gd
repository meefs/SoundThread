extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var cdpprogs_location
var delete_intermediate_outputs
@onready var console_output: RichTextLabel = $Console/ConsoleOutput

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Distortions.hide()
	Nodes.hide()
	$mainmenu.hide()
	$NoLocationPopup.hide()
	$DeleteIntermediateFilesToggle.button_pressed = true
	$Console.hide()
	
	#Goes through all nodes in scene and checks for buttons in the make_node_buttons group
	#Associates all buttons with the _on_button_pressed fuction and passes the button as an argument
	for child in get_tree().get_nodes_in_group("make_node_buttons"):
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))
	
	var effect: GraphNode = Nodes.get_node(NodePath("inputfile")).duplicate()
	get_node("GraphEdit").add_child(effect, true)
	
	check_cdp_location_set()
	
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
		if selected_nodes[node] and node.name != "inputfile":
			remove_connections_to_node(node)
			node.queue_free()
	selected_nodes = {}

func remove_connections_to_node(node):
	for con in get_node("GraphEdit").get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			get_node("GraphEdit").disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			

#Here be dragons
#Scans through all nodes and generates a batch file based on their order
func _on_generate_batch_file_button_down() -> void:
	$FileDialog.show()

func _on_file_dialog_dir_selected(dir: String) -> void:
	$Console.show()
	console_output.append_text("Generating processing queue\n")
	await get_tree().process_frame
	#get the current time in hh-mm-ss format as default : causes file name issues
	var time_dict = Time.get_time_dict_from_system()
	# Pad with zeros to ensure two digits for hour, minute, second
	var hour = str(time_dict.hour).pad_zeros(2)
	var minute = str(time_dict.minute).pad_zeros(2)
	var second = str(time_dict.second).pad_zeros(2)
	var time_str = hour + "-" + minute + "-" + second
	Global.outfile = dir + "/outfile_" + Time.get_date_string_from_system() + "_" + time_str
	console_output.append_text("Output directory and file name(s):" + Global.outfile + "\n")
	await get_tree().process_frame
	
	generate_batch_file_ordered_with_multiple_sliders()

func generate_batch_file_ordered_with_multiple_sliders():
	var connections = graph_edit.get_connection_list()
	var graph := {}
	var indegree := {}
	var nodes := []

	# Step 1: Collect relevant nodes
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			if name == "inputfile" or name == "outputfile":
				continue
			graph[name] = []
			indegree[name] = 0
			nodes.append(name)

	# Step 2: Build graph
	for conn in connections:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from) and graph.has(to):
			graph[from].append(to)
			indegree[to] += 1

	# Step 3: Topological sort
	var sorted := []
	var queue := []
	for node in nodes:
		if indegree[node] == 0:
			queue.append(node)

	while not queue.is_empty():
		var current = queue.pop_front()
		sorted.append(current)
		for neighbor in graph[current]:
			indegree[neighbor] -= 1
			if indegree[neighbor] == 0:
				queue.append(neighbor)

	if sorted.size() != nodes.size():
		console_output.append_text("Cycle detected in graph or disconnected nodes\n")
		await get_tree().process_frame
		push_error("Cycle detected in graph or disconnected nodes.")
		return

	# Step 4: Generate batch lines
	console_output.append_text("Generating process queue from " + str(sorted.size()) + " nodes\n" )
	await get_tree().process_frame
	var batch_lines: Array[String] = []
	var intermediate_files: Array[String] = []

	var process_count = 0
	
	if Global.infile_stereo:
		# Stereo processing
		var stereo_base := Global.infile.get_basename()
		var infile_c1 := stereo_base + "_c1.wav"
		var infile_c2 := stereo_base + "_c2.wav"
		var outfile_c1 := ""
		var outfile_c2 := ""

		console_output.append_text("Input file is stereo, adding split to dual mono to process queue, this may cause stereo decorrolation with some processess\n")
		await get_tree().process_frame
		# Add stereo split processing command
		batch_lines.append(cdpprogs_location + "/housekeep chans 2 \"" + Global.infile + "\"")

		# Process both channels (c1 and c2)
		for channel in ["c1", "c2"]:
			var current_infile := stereo_base + "_%s.wav" % channel
			for i in sorted.size():
				var node_name = sorted[i]
				var node = graph_edit.get_node(NodePath(node_name))
				var slider_data = _get_slider_values_ordered(node)

				# Get output type and file extension
				var output_slot_type: int = node.get_slot_type_right(0)
				var extension := ".wav"
				if output_slot_type == 1:
					extension = ".ana"

				# Generate command
				var command_name: String = str(node.get_meta("command")) if node.has_meta("command") else node_name
				command_name = command_name.replace("_", " ")

				var outfile_numbered := Global.outfile.get_basename() + "_%s_%d%s" % [channel, i, extension]
				var line: String = cdpprogs_location + "/" + command_name + " \"" + current_infile + "\" \"" + outfile_numbered + "\" "

				# Add slider values to the command
				for entry in slider_data:
					var slider_name = entry[0]
					var value = entry[1]
					if slider_name.begins_with("-"):
						line += "%s%.2f " % [slider_name, float(value)]
					else:
						line += "%.2f " % float(value)

				batch_lines.append(line.strip_edges())
				console_output.append_text("Added process to queue:" + line.strip_edges() + "\n")
				
				
				# Add output file to delete list
				if process_count < sorted.size() - 1 and delete_intermediate_outputs:
					intermediate_files.append(outfile_numbered)
				process_count += 1
				current_infile = outfile_numbered
			
			#reset count for right channel
			process_count = 0
			
			# Keep track of the last output for each channel
			if channel == "c1":
				outfile_c1 = current_infile
			else:
				outfile_c2 = current_infile
				
		await get_tree().process_frame
		# Final interleave if both branches ended in .wav
		if outfile_c1.ends_with(".wav") and outfile_c2.ends_with(".wav"):
			batch_lines.append(cdpprogs_location + "/submix interleave \"" + outfile_c1 + "\" \"" + outfile_c2 + "\" \"" + Global.outfile + "_stereo.wav\"")
			# Conditionally add output files from stereo processing
			if delete_intermediate_outputs:
				intermediate_files.append(outfile_c1)
				intermediate_files.append(outfile_c2)
			console_output.append_text("Added process to queue to recombine dual mono output to stereo. Stereo output file is:" + Global.outfile +"_stereo.wav\n")
			await get_tree().process_frame
		# Always add stereo split files (_c1 and _c2) for cleanup
		intermediate_files.append(infile_c1)
		intermediate_files.append(infile_c2)

	else:
		# Mono processing
		var current_infile: String = Global.infile
		console_output.append_text("Input file is mono\n")
		await get_tree().process_frame
		
		for i in sorted.size():
			var node_name = sorted[i]
			var node = graph_edit.get_node(NodePath(node_name))
			var slider_data = _get_slider_values_ordered(node)

			# Get output type and file extension
			var output_slot_type: int = node.get_slot_type_right(0)
			var extension := ".wav"
			if output_slot_type == 1:
				extension = ".ana"

			# Generate command
			var command_name: String = str(node.get_meta("command")) if node.has_meta("command") else node_name
			command_name = command_name.replace("_", " ")
			var outfile_numbered: String = Global.outfile.get_basename() + "_%d%s" % [i, extension]

			var line: String = cdpprogs_location + "/" + command_name + " \"" + current_infile + "\" \"" + outfile_numbered + "\" "
			
			
			# Add slider values to the command
			for entry in slider_data:
				var slider_name = entry[0]
				var value = entry[1]
				if slider_name.begins_with("-"):
					line += "%s%.2f " % [slider_name, float(value)]
				else:
					line += "%.2f " % float(value)

			batch_lines.append(line.strip_edges())
			console_output.append_text("Added process to queue:" + line.strip_edges() + "\n")
			
			# Add output file to delete list if needed
			if process_count < sorted.size() - 1 and delete_intermediate_outputs:
				intermediate_files.append(outfile_numbered)
			process_count += 1
			current_infile = outfile_numbered
	
	await get_tree().process_frame
	
	# Step 5: Clean up intermediate files (skip the last one)
	if intermediate_files.size() >= 1:
		console_output.append_text("Adding processes to clean up intermediate files leaving only the final output file\n")
		await get_tree().process_frame
		var last_drive_letter := ""
		for i in intermediate_files.size(): 
			var file_path := intermediate_files[i].replace("/", "\\")
			var drive_letter := file_path.substr(0, 2)
			if drive_letter != last_drive_letter:
				batch_lines.append(drive_letter)
				last_drive_letter = drive_letter
			batch_lines.append("del \"%s\"" % file_path)
	
	
	# Step 6: Write file
	var file = FileAccess.open("user://ordered_script.bat", FileAccess.WRITE)
	for line in batch_lines:
		file.store_line(line)
	file.close()

	print("Batch file written to user://ordered_script.bat")
	console_output.append_text("[color=green]Building process queue is complete[/color]\n")
	console_output.append_text("Running process, please wait...\n")
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
		console_output.append_text("[color=green]Processes ran successfully[/color]\n")
		console_output.append_text("[b]Output:[/b]\n" + output_str)
	else:
		console_output.append_text("[color=red][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code)
		console_output.append_text("[b]Error:[/b]\n" + error_str)
#func run_batch_file():
	#var bat_path = ProjectSettings.globalize_path("user://ordered_script.bat")
#
	## Create empty arrays to capture the output and error
	#var output : Array = []
	#var error : Array = []
#
	## Execute the batch file and capture output and error
	#var exit_code = OS.execute("cmd.exe", ["/c", bat_path], output, true, true)
#
	## Manually join the array elements into a single string
	#var output_str = ""
	#for item in output:
		#output_str += item + "\n"  # Append each element with a newline
#
	#var error_str = ""
	#for item in error:
		#error_str += item + "\n"  # Append each element with a newline
#
	## Output handling based on exit code
	#if exit_code == 0:
		#print("Processes ran successfully.")
		#print("Output: ", output_str)
	#else:
		#print("Processes failed with exit code:", exit_code)
		#print("Error: ", error_str)



func _on_delete_intermediate_files_toggle_toggled(toggled_on: bool) -> void:
	delete_intermediate_outputs = toggled_on


func _on_console_close_requested() -> void:
	$Console.hide()
