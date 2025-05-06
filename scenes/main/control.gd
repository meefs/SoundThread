extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var cdpprogs_location

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Distortions.hide()
	Nodes.hide()
	$mainmenu.hide()
	$NoLocationPopup.hide()
	
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
		if selected_nodes[node]:
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
	#get the current time in hh-mm-ss format as default : causes file name issues
	var time_dict = Time.get_time_dict_from_system()
	# Pad with zeros to ensure two digits for hour, minute, second
	var hour = str(time_dict.hour).pad_zeros(2)
	var minute = str(time_dict.minute).pad_zeros(2)
	var second = str(time_dict.second).pad_zeros(2)
	var time_str = hour + "-" + minute + "-" + second
	Global.outfile = dir + "/outfile_" + Time.get_date_string_from_system() + "_" + time_str
	
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
		push_error("Cycle detected in graph or disconnected nodes.")
		return

	# Step 4: Generate batch lines
	var batch_lines: Array[String] = []
	var current_infile: String = Global.infile

	for i in sorted.size():
		var node_name = sorted[i]
		var node = graph_edit.get_node(NodePath(node_name))
		var slider_data = _get_slider_values_ordered(node)

		# Get slot type to determine file extension
		var output_slot_type: int = node.get_slot_type_right(0)
		var extension := ".wav"
		if output_slot_type == 1:
			extension = ".ana"

		var node_name_spaced: String = node_name.replace("_", " ")
		var outfile_numbered: String = Global.outfile.get_basename() + "_%d%s" % [i, extension]

		# Build the batch line
		var line: String = cdpprogs_location + "/" + node_name_spaced + " \"" + current_infile + "\" \"" + outfile_numbered + "\" "

		for entry in slider_data:
			var slider_name = entry[0]
			var value = entry[1]
			if slider_name.begins_with("-"):
				line += "%s%.2f " % [slider_name, float(value)]
			else:
				line += "%.2f " % float(value)

		batch_lines.append(line.strip_edges())
		current_infile = outfile_numbered  # Pass this as next step's input

	# Step 5: Write file
	var file = FileAccess.open("user://ordered_script.bat", FileAccess.WRITE)
	for line in batch_lines:
		file.store_line(line)
	file.close()

	print("Batch file written to user://ordered_script.bat")
	run_batch_file()
#func generate_batch_file_ordered_with_multiple_sliders():
	#var connections = graph_edit.get_connection_list()
	#var graph := {}
	#var indegree := {}
	#var nodes := []
#
	## Step 1: Collect relevant nodes
	#for child in graph_edit.get_children():
		#if child is GraphNode:
			#var name = str(child.name)
			#if name == "inputfile" or name == "outputfile":
				#continue
			#graph[name] = []
			#indegree[name] = 0
			#nodes.append(name)
#
	## Step 2: Build graph
	#for conn in connections:
		#var from = str(conn["from_node"])
		#var to = str(conn["to_node"])
		#if graph.has(from) and graph.has(to):
			#graph[from].append(to)
			#indegree[to] += 1
#
	## Step 3: Topological sort
	#var sorted := []
	#var queue := []
	#for node in nodes:
		#if indegree[node] == 0:
			#queue.append(node)
#
	#while not queue.is_empty():
		#var current = queue.pop_front()
		#sorted.append(current)
		#for neighbor in graph[current]:
			#indegree[neighbor] -= 1
			#if indegree[neighbor] == 0:
				#queue.append(neighbor)
#
	#if sorted.size() != nodes.size():
		#push_error("Cycle detected in graph or disconnected nodes.")
		#return
#
	## Step 4: Generate batch lines
	#var batch_lines: Array[String] = []
	#var current_infile: String = Global.infile
#
	#for i in sorted.size():
		#var node_name = sorted[i]
		#var node = graph_edit.get_node(NodePath(node_name))
		#var slider_data = _get_slider_values_ordered(node)
#
		#var node_name_spaced: String = node_name.replace("_", " ")
		#var outfile_numbered: String = Global.outfile.get_basename() + "_%d.wav" % i
#
		#var line: String = cdpprogs_location + "/" + node_name_spaced + " \"" + current_infile + "\" \"" + outfile_numbered + "\" "
#
		#for entry in slider_data:
			#var slider_name = entry[0]
			#var value = entry[1]
			#if slider_name.begins_with("-"):
				#line += "%s %.2f " % [slider_name, float(value)]
			#else:
				#line += "%.2f " % float(value)
#
		#batch_lines.append(line.strip_edges())
		#current_infile = outfile_numbered  # Use this as next step's inputes())
#
	## Step 5: Write file
	#var file = FileAccess.open("user://ordered_script.bat", FileAccess.WRITE)
	#for line in batch_lines:
		#file.store_line(line)
	#file.close()
#
	#print("Batch file written to user://ordered_script.bat")
	#run_batch_file()


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

	# Create empty arrays to capture the output and error
	var output : Array = []
	var error : Array = []

	# Execute the batch file and capture output and error
	var exit_code = OS.execute("cmd.exe", ["/c", bat_path], output, true, true)

	# Manually join the array elements into a single string
	var output_str = ""
	for item in output:
		output_str += item + "\n"  # Append each element with a newline

	var error_str = ""
	for item in error:
		error_str += item + "\n"  # Append each element with a newline

	# Output handling based on exit code
	if exit_code == 0:
		print("Batch file ran successfully.")
		print("Output: ", output_str)
	else:
		print("Batch file failed with exit code:", exit_code)
		print("Error: ", error_str)
