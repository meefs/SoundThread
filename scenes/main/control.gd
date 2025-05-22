extends Control

var mainmenu_visible : bool = false #used to test if mainmenu is open
var effect_position = Vector2(40,40) #tracks mouse position for node placement offset
@onready var graph_edit = $GraphEdit
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var cdpprogs_location #stores the cdp programs location from user prefs for easy access
var delete_intermediate_outputs # tracks state of delete intermediate outputs toggle
@onready var console_output: RichTextLabel = $Console/ConsoleOutput
var final_output_dir
var copied_nodes_data = [] #stores node data on ctrl+c
var copied_connections = [] #stores all connections on ctrl+c
var undo_redo := UndoRedo.new() 
var output_audio_player #tracks the node that is the current output player for linking
var input_audio_player #tracks node that is the current input player for linking
var outfile = "no file" #tracks dir of output file from cdp process
var currentfile = "none" #tracks dir of currently loaded file for saving
var changesmade = false #tracks if user has made changes to the currently loaded save file
var savestate # tracks what the user is trying to do when savechangespopup is called
var helpfile #tracks which help file the user was trying to load when savechangespopup is called
var outfilename #links to the user name for outputfile field
var foldertoggle #links to the reuse folder button
var lastoutputfolder = "none" #tracks last output folder, this can in future be used to replace global.outfile but i cba right now
var process_successful #tracks if the last run process was successful
var help_data := {} #stores help data for each node to display in help popup
var HelpWindowScene = preload("res://scenes/main/help_window.tscn")
var uiscale = 1.0 #tracks scaling for retina screens

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Nodes.hide()
	$mainmenu.hide()
	#$"mainmenu/select_effect/Time Domain".show()
	#$"mainmenu/select_effect/Time Domain/Distort".show()
	#$"mainmenu/select_effect/Frequency Domain/Convert".show()
	$NoLocationPopup.hide()
	$Console.hide()
	$NoInputPopup.hide()
	$MultipleConnectionsPopup.hide()
	$AudioSettings.hide()
	$AudioDevicePopup.hide()
	$SearchMenu.hide()
	
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
	
	get_node("SearchMenu").make_node.connect(_make_node_from_search_menu)
	get_node("mainmenu").make_node.connect(_make_node_from_search_menu)
	get_node("mainmenu").open_help.connect(show_help_for_node)
	
	check_cdp_location_set()
	check_user_preferences()
	get_tree().set_auto_accept_quit(false) #disable closing the app with the x and instead handle it internally
	
	#Check export config for version number and set about menu to current version
	#Assumes version of mac + linux builds is the same as windows
	#Requires manual update for alpha and beta builds but once the -beta is removed will be fully automatic so long as version is updated on export
	var export_config = ConfigFile.new()
	export_config.load("res://export_presets.cfg")
	$MenuBar/About.set_item_text(0, "SoundThread v" + export_config.get_value("preset.0.options", "application/product_version", "version unknown") + "-alpha") 
	
	#checks if display is hidpi and scales ui accordingly hidpi - 144
	if DisplayServer.screen_get_dpi(0) >= 144:
		uiscale = 2.0
		get_window().content_scale_factor = uiscale
		#goes through popup_windows group and scales all popups and resizes them
		for window in get_tree().get_nodes_in_group("popup_windows"):
			window.size = window.size * uiscale
			window.content_scale_factor = uiscale

	#checks if user has opened a file from the system file menu and loads it
	var args = OS.get_cmdline_args()
	for arg in args:
		var path = arg.strip_edges()
		if FileAccess.file_exists(path) and path.get_extension().to_lower() == "thd":
			load_graph_edit(path)
			break
	
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		help_data = JSON.parse_string(file.get_as_text())
	
	new_patch()
	
func new_patch():
	#clear old patch
	graph_edit.clear_connections()

	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()
	
	await get_tree().process_frame  # Wait for nodes to actually be removed
	
	graph_edit.scroll_offset = Vector2(0, 0)
	
		#Generate input and output nodes
	var effect: GraphNode = Nodes.get_node(NodePath("inputfile")).duplicate()
	effect.name = "inputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(self, "show_help_for_node"))
	effect.position_offset = Vector2(20,80)
	
	effect = Nodes.get_node(NodePath("outputfile")).duplicate()
	effect.name = "outputfile"
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(self, "show_help_for_node"))
	effect.position_offset = Vector2((DisplayServer.screen_get_size().x - 480) / uiscale, 80)
	_register_node_movement() #link nodes for tracking position changes for changes tracking
	
	changesmade = false #so it stops trying to save unchanged empty files
	Global.infile = "no_file" #resets input to stop processes running with old files
	get_window().title = "SoundThread"
	link_output()
	
	

func link_output():
	#links various buttons and function in the input nodes - this is called after they are created so that it still works on new and loading files
	for control in get_tree().get_nodes_in_group("outputnode"): #check all items in outputnode group
		if control.get_meta("outputfunction") == "deleteintermediate": #link delete intermediate files toggle to script
			control.toggled.connect(_toggle_delete)
			control.button_pressed = true
		elif control.get_meta("outputfunction") == "runprocess": #link runprocess button
			control.button_down.connect(_run_process)
		elif control.get_meta("outputfunction") == "recycle": #link recycle button
			control.button_down.connect(_recycle_outfile)
		elif control.get_meta("outputfunction") == "audioplayer": #link output audio player
			output_audio_player = control
		elif control.get_meta("outputfunction") == "filename":
			control.text = "outfile"
			outfilename = control
		elif control.get_meta("outputfunction") == "reusefolder":
			foldertoggle = control
			foldertoggle.button_pressed = true
		elif control.get_meta("outputfunction") == "openfolder":
			control.button_down.connect(_open_output_folder)

	for control in get_tree().get_nodes_in_group("inputnode"):
		if control.get_meta("inputfunction") == "audioplayer": #link input for recycle function
			print("input player found")
			input_audio_player = control

func check_user_preferences():
	var interface_settings = ConfigHandler.load_interface_settings()
	var audio_settings = ConfigHandler.load_audio_settings()
	var audio_devices = AudioServer.get_output_device_list()
	$MenuBar/SettingsButton.set_item_checked(1, interface_settings.disable_pvoc_warning)
	$MenuBar/SettingsButton.set_item_checked(2, interface_settings.auto_close_console)
	$MenuBar/SettingsButton.set_item_checked(3, interface_settings.console_on_top)
	$MenuBar/SettingsButton.set_item_checked(4, interface_settings.use_search)
	$Console.always_on_top = interface_settings.console_on_top
	if audio_devices.has(audio_settings.device):
		AudioServer.set_output_device(audio_settings.device)
	else:
		$AudioDevicePopup.popup()

	
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
	if OS.get_name() == "Windows":
		$CdpLocationDialog.current_dir = "C:/"
	else:
		$CdpLocationDialog.current_dir = "~/"
	$CdpLocationDialog.show()

func _on_cdp_location_dialog_dir_selected(dir: String) -> void:
	#saves default location for cdp programs in config file
	ConfigHandler.save_cdpprogs_settings(dir)
	cdpprogs_location = dir

func _on_cdp_location_dialog_canceled() -> void:
	#cycles around the set location prompt if user cancels the file dialog
	check_cdp_location_set()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#showmenu()
	pass
	

func _input(event):
	if event.is_action_pressed("copy_node"):
		copy_selected_nodes()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("paste_node"):
		simulate_mouse_click() #hacky fix to stop tooltips getting stuck
		await get_tree().process_frame
		paste_copied_nodes()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("undo"):
		undo_redo.undo()
	elif event.is_action_pressed("redo"):
		undo_redo.redo()
	elif event.is_action_pressed("save"):
		if currentfile == "none":
			savestate = "saveas"
			$SaveDialog.popup_centered()
		else:
			save_graph_edit(currentfile)
	elif event.is_action_pressed("open_explore"):
		open_explore()
	

func show_help_for_node(node_name: String, node_title: String):
	#check if there is already a help window open for this node and pop it up instead of making a new one
	for child in get_tree().current_scene.get_children():
		if child is Window and child.title == "Help - " + node_title:
			# Found existing window, bring it to front
			if child.is_visible():
				child.hide()
				child.popup()
			else:
				child.popup()
			return
	
	if help_data.has(node_name):
		#looks up the help data from the json and stores it in info
		var info = help_data[node_name]
		#makes an instance of the help_window scene
		var help_window = HelpWindowScene.instantiate()
		help_window.title = "Help - " + node_title
		help_window.get_node("HelpTitle").text = node_title
		
		var output = ""
		output += info.get("short_description", "") + "\n\n"
		
		var parameters = info.get("parameters", {})
		#checks if there are parameters and if there are places them in a table
		if parameters.size() > 0:
			output += "[table=3]\n"
			output += "[cell][b]Parameter Name[/b][/cell][cell][b]Description[/b][/cell][cell][b]Automatable[/b][/cell]\n"
			for key in parameters.keys(): #scans through all parameters
				var param = parameters[key]
				var name = param.get("paramname", "")
				var desc = param.get("paramdescription", "")
				var automatable = param.get("automatable", false)
				var autom_text = "[center]✓[/center]" if automatable else "[center]𐄂[/center]" #replaces true and false with ticks and crosses
				output += "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]\n" % [name, desc, autom_text] #places each param detail into cells of the table
			output += "[/table]\n\n" #ends the table
		
		output += "[b]Functionality[/b]\n"
		var description_text = info.get("description", "")
		output += description_text.strip_edges()
		#check if this is a cdp process or a utility and display the cdp process if it is one
		var category = info.get("category", "")
		if category != "utility":
			output += "\n\n[b]CDP Process[/b]\nThis node runs the CDP Process: " + node_name.replace("_", " ")
		
		help_window.get_node("HelpText").bbcode_text = output
		help_window.get_node("HelpText").scroll_to_line(0) #scrolls to the first line of the help file just incase
		
		# Add to the current scene tree to show it
		get_tree().current_scene.add_child(help_window)
		if help_window.content_scale_factor < uiscale:
			help_window.size = help_window.size * uiscale
			help_window.content_scale_factor = uiscale
		
		help_window.popup() 
		
	else:
		# If no help available, even though there always should be, show a window saying no help found
		var help_window = HelpWindowScene.instance()
		help_window.title = "Help - " + node_title
		help_window.get_node("HelpTitle").text = node_title
		help_window.get_node("HelpText").bbcode_text = "No help found."
		get_tree().current_scene.add_child(help_window)
		help_window.popup()


func simulate_mouse_click():
	#simulates clicking the middle mouse button in order to hide any visible tooltips
	var click_pos = get_viewport().get_mouse_position()

	var down_event := InputEventMouseButton.new()
	down_event.button_index = MOUSE_BUTTON_MIDDLE
	down_event.pressed = true
	down_event.position = click_pos
	Input.parse_input_event(down_event)

	var up_event := InputEventMouseButton.new()
	up_event.button_index = MOUSE_BUTTON_MIDDLE
	up_event.pressed = false
	up_event.position = click_pos
	Input.parse_input_event(up_event)

func _make_node_from_search_menu(command: String):
	#close menu
	$SearchMenu.hide()
	
	#Find node with matching name to button and create a version of it in the graph edit
	#and position it close to the origin right click to open the menu
	var effect: GraphNode = Nodes.get_node(NodePath(command)).duplicate()
	effect.name = command
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(self, "show_help_for_node"))
	effect.set_position_offset((effect_position + graph_edit.scroll_offset) / graph_edit.zoom) #set node to current mouse position in graph edit
	_register_inputs_in_node(effect) #link sliders for changes tracking
	_register_node_movement() #link nodes for tracking position changes for changes tracking

	changesmade = true

	# Remove node with UndoRedo
	undo_redo.create_action("Add Node")
	undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(effect))
	undo_redo.add_undo_method(Callable(effect, "queue_free"))
	undo_redo.add_undo_method(Callable(self, "_track_changes"))
	undo_redo.commit_action()
	

func _on_button_pressed(button: Button):
	#close menu
	$mainmenu.hide()
	mainmenu_visible = false
	
	#Find node with matching name to button and create a version of it in the graph edit
	#and position it close to the origin right click to open the menu
	var effect: GraphNode = Nodes.get_node(NodePath(button.name)).duplicate()
	effect.name = button.name
	get_node("GraphEdit").add_child(effect, true)
	effect.connect("open_help", Callable(self, "show_help_for_node"))
	effect.set_position_offset((effect_position + graph_edit.scroll_offset) / graph_edit.zoom) #set node to current mouse position in graph edit
	_register_inputs_in_node(effect) #link sliders for changes tracking
	_register_node_movement() #link nodes for tracking position changes for changes tracking

	changesmade = true


	# Remove node with UndoRedo
	undo_redo.create_action("Add Node")
	undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(effect))
	undo_redo.add_undo_method(Callable(effect, "queue_free"))
	undo_redo.add_undo_method(Callable(self, "_track_changes"))
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
	changesmade = true

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	get_node("GraphEdit").disconnect_node(from_node, from_port, to_node, to_port)
	changesmade = true

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
	var graph_edit = get_node("GraphEdit")
	undo_redo.create_action("Delete Nodes (Undo only)")

	for node in selected_nodes.keys():
		if selected_nodes[node]:
			if node.get_meta("command") == "inputfile" or node.get_meta("command") == "outputfile":
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
				changesmade = true

				# Register undo restore
				undo_redo.add_undo_method(Callable(graph_edit, "add_child").bind(node_data, true))
				undo_redo.add_undo_method(Callable(node_data, "set_position_offset").bind(position))
				for con in conns:
					undo_redo.add_undo_method(Callable(graph_edit, "connect_node").bind(
						con["from_node"], con["from_port"],
						con["to_node"], con["to_port"]
					))
				undo_redo.add_undo_method(Callable(self, "set_node_selected").bind(node_data, true))
				undo_redo.add_undo_method(Callable(self, "_track_changes"))
				undo_redo.add_undo_method(Callable(self, "_register_inputs_in_node").bind(node_data)) #link sliders for changes tracking
				undo_redo.add_undo_method(Callable(self, "_register_node_movement")) # link nodes for changes tracking

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
			changesmade = true
			
#copy and paste nodes with vertical offset on paste
func copy_selected_nodes():
	copied_nodes_data.clear()
	copied_connections.clear()

	var graph_edit = get_node("GraphEdit")

	# Store selected nodes and their slider values
	for node in graph_edit.get_children():
		# Check if the node is selected and not an 'inputfile' or 'outputfile'
		if node is GraphNode and selected_nodes.get(node, false):
			if node.get_meta("command") == "inputfile" or node.get_meta("command") == "outputfile":
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
		_register_inputs_in_node(new_node) #link sliders for changes tracking
		_register_node_movement() # link nodes for changes tracking
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
	
	changesmade = true
	
	# Remove node with UndoRedo
	undo_redo.create_action("Paste Nodes")
	for pasted_node in pasted_nodes:
		undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(pasted_node))
		undo_redo.add_undo_method(Callable(pasted_node, "queue_free"))
		undo_redo.add_undo_method(Callable(self, "remove_connections_to_node").bind(pasted_node))
		undo_redo.add_undo_method(Callable(self, "_track_changes"))
	undo_redo.commit_action()
	

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
	changesmade = true
	print("Meta changed in slider")
	
func _register_node_movement():
	for graphnode in graph_edit.get_children():
		if graphnode is GraphNode:
			var callable = Callable(self, "_on_graphnode_moved")
			if not graphnode.is_connected("position_offset_changed", callable):
				graphnode.connect("position_offset_changed", callable)

func _on_graphnode_moved():
	changesmade = true
	
func _on_any_slider_changed(value: float) -> void:
	changesmade = true
	
func _on_any_input_changed():
	changesmade = true

func _track_changes():
	changesmade = true
	


func _run_process() -> void:
	if Global.infile == "no_file":
		$NoInputPopup.show()
	else:
		if foldertoggle.button_pressed == true and lastoutputfolder != "none":
			_on_file_dialog_dir_selected(lastoutputfolder)
		else:
			$FileDialog.show()
			

func _on_file_dialog_dir_selected(dir: String) -> void:
	lastoutputfolder = dir
	console_output.clear()
	if $Console.is_visible():
		$Console.hide()
		await get_tree().process_frame  # Wait a frame to allow hide to complete
		$Console.popup()
	else:
		$Console.popup()
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
	Global.outfile = dir + "/" + outfilename.text.get_basename() + "_" + Time.get_date_string_from_system() + "_" + time_str
	log_console("Output directory and file name(s):" + Global.outfile, true)
	await get_tree().process_frame
	
	run_thread_with_branches()
	
func run_thread_with_branches():
	# Detect platform: Determine if the OS is Windows
	var is_windows := OS.get_name() == "Windows"
	
	# Choose appropriate commands based on OS
	var delete_cmd = "del" if is_windows else "rm"
	var rename_cmd = "ren" if is_windows else "mv"
	var path_sep := "/"  # Always use forward slash for paths

	# Get all node connections in the GraphEdit
	var connections = graph_edit.get_connection_list()

	# Prepare data structures for graph traversal
	var graph = {}          # forward adjacency list
	var reverse_graph = {}  # reverse adjacency list (for input lookup)
	var indegree = {}       # used for topological sort
	var all_nodes = {}      # map of node name -> GraphNode reference

	log_console("Mapping thread.", true)
	await get_tree().process_frame  # Let UI update

	#Step 0: check thread is valid
	var is_valid = path_exists_through_all_nodes()
	if is_valid == false:
		log_console("[color=#9c2828][b]Error: Valid Thread not found[/b][/color]", true)
		log_console("Threads must contain at least one processing node and a valid path from the Input File to the Output File.", true)
		await get_tree().process_frame  # Let UI update
		return
	else:
		log_console("[color=#638382][b]Valid Thread found[/b][/color]", true)
		await get_tree().process_frame  # Let UI update
		
	# Step 1: Gather nodes from the GraphEdit
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			all_nodes[name] = child
			if not child.has_meta("utility"):
				graph[name] = []
				reverse_graph[name] = []
				indegree[name] = 0  # Start with zero incoming edges

	# Step 2: Build graph relationships from connections
	for conn in connections:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from) and graph.has(to):
			graph[from].append(to)
			reverse_graph[to].append(from)
			indegree[to] += 1  # Count incoming edges

	# Step 3: Topological sort to get execution order
	var sorted = []  # Sorted list of node names
	var queue = []   # Queue of nodes with 0 indegree

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

	# If not all nodes were processed, there's a cycle
	if sorted.size() != graph.size():
		log_console("[color=#9c2828][b]Error: Thread not valid[/b][/color]", true)
		log_console("Threads cannot contain loops.", true)
		return

	# Step 4: Start processing audio
	var batch_lines = []        # Holds all batch file commands
	var intermediate_files = [] # Files to delete later
	var breakfiles = [] #breakfiles to delete later

	# Dictionary to keep track of each node's output file
	var output_files = {}
	var process_count = 0

	# Start with the original input file
	var starting_infile = Global.infile
	
	#If trim is enabled trim input audio
	if Global.trim_infile == true:
		run_command(cdpprogs_location + "/sfedit", ["cut", "1", starting_infile, "%s_trimmed.wav" % Global.outfile, str(Global.infile_start), str(Global.infile_stop)])
		starting_infile = Global.outfile + "_trimmed.wav"
		# Mark trimmed file for cleanup if needed
		if delete_intermediate_outputs:
			intermediate_files.append(Global.outfile + "_trimmed.wav")
			
	var current_infile = starting_infile

	# Iterate over the processing nodes in topological order
	for node_name in sorted:
		var node = all_nodes[node_name]
		
		# Find upstream nodes connected to the current node
		var inputs = reverse_graph[node_name]
		var input_files = []
		for input_node in inputs:
			input_files.append(output_files[input_node])

		# Merge inputs if this node has more than one input
		if input_files.size() > 1:
			# Prepare final merge output file name
			var runmerge = merge_many_files(process_count, input_files)
			var merge_output = runmerge[0]
			var converted_files = runmerge[1]

			# Track the output and intermediate files
			current_infile = merge_output
			
			if delete_intermediate_outputs:
				intermediate_files.append(merge_output)
				for f in converted_files:
					intermediate_files.append(f)

		# If only one input, use that
		elif input_files.size() == 1:
			current_infile = input_files[0]

		## If no input, use the original input file
		else:
			current_infile = starting_infile

		# Build the command for the current node's audio processing
		var slider_data = _get_slider_values_ordered(node)
		
		if node.get_slot_type_right(0) == 1: #detect if process outputs pvoc data
			if typeof(current_infile) == TYPE_ARRAY:
				#check if infile is an array meaning that the last pvoc process was run in dual mono mode
				# Process left and right seperately
				var pvoc_stereo_files = []
				
				for infile in current_infile:
					var makeprocess = make_process(node, process_count, infile, slider_data)
					# run the command
					run_command(makeprocess[0], makeprocess[3])
					await get_tree().process_frame
					var output_file = makeprocess[1]
					pvoc_stereo_files.append(output_file)
					
					# Mark file for cleanup if needed
					if delete_intermediate_outputs:
						for file in makeprocess[2]:
							breakfiles.append(file)
						intermediate_files.append(output_file)

					process_count += 1
					
				output_files[node_name] = pvoc_stereo_files
			else:
				var input_stereo = is_stereo(current_infile)
				if input_stereo == true: 
					#audio file is stereo and needs to be split for pvoc processing
					var pvoc_stereo_files = []
					##Split stereo to c1/c2
					run_command(cdpprogs_location + "/housekeep",["chans", "2", current_infile])
			
					# Process left and right seperately
					for channel in ["c1", "c2"]:
						var dual_mono_file = current_infile.get_basename() + "_%s.wav" % channel
						
						var makeprocess = make_process(node, process_count, dual_mono_file, slider_data)
						# run the command
						run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						pvoc_stereo_files.append(output_file)
						
						# Mark file for cleanup if needed
						if delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)
						
						#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
						#with this stereo process CDP will throw errors in the console even though its fine
						if is_windows:
							dual_mono_file = dual_mono_file.replace("/", "\\")
						run_command(delete_cmd, [dual_mono_file])
						process_count += 1
						
						# Store output file path for this node
					output_files[node_name] = pvoc_stereo_files
				else: 
					#input file is mono run through process
					var makeprocess = make_process(node, process_count, current_infile, slider_data)
					# run the command
					run_command(makeprocess[0], makeprocess[3])
					await get_tree().process_frame
					var output_file = makeprocess[1]

					# Store output file path for this node
					output_files[node_name] = output_file

					# Mark file for cleanup if needed
					if delete_intermediate_outputs:
						for file in makeprocess[2]:
							breakfiles.append(file)
						intermediate_files.append(output_file)

		# Increase the process step count
			process_count += 1
			
		else: 
			#Process outputs audio
			#check if this is the last pvoc process in a stereo processing chain
			if node.get_meta("command") == "pvoc_synth" and typeof(current_infile) == TYPE_ARRAY:
			
				#check if infile is an array meaning that the last pvoc process was run in dual mono mode
				# Process left and right seperately
				var pvoc_stereo_files = []
				
				for infile in current_infile:
					var makeprocess = make_process(node, process_count, infile, slider_data)
					# run the command
					run_command(makeprocess[0], makeprocess[3])
					await get_tree().process_frame
					var output_file = makeprocess[1]
					pvoc_stereo_files.append(output_file)
					
					# Mark file for cleanup if needed
					if delete_intermediate_outputs:
						for file in makeprocess[2]:
							breakfiles.append(file)
						intermediate_files.append(output_file)

					process_count += 1
					
					
				#interleave left and right
				var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
				run_command(cdpprogs_location + "/submix", ["interleave", pvoc_stereo_files[0], pvoc_stereo_files[1], output_file])
				# Store output file path for this node
				output_files[node_name] = output_file
				
				# Mark file for cleanup if needed
				if delete_intermediate_outputs:
					intermediate_files.append(output_file)

			else:
				#Detect if input file is mono or stereo
				var input_stereo = is_stereo(current_infile)
				if input_stereo == true:
					if node.get_meta("stereo_input") == true: #audio file is stereo and process is stereo, run file through process
						var makeprocess = make_process(node, process_count, current_infile, slider_data)
						# run the command
						run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						
						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

					else: #audio file is stereo and process is mono, split stereo, process and recombine
						##Split stereo to c1/c2
						run_command(cdpprogs_location + "/housekeep",["chans", "2", current_infile])
				
						# Process left and right seperately
						var dual_mono_output = []
						for channel in ["c1", "c2"]:
							var dual_mono_file = current_infile.get_basename() + "_%s.wav" % channel
							
							var makeprocess = make_process(node, process_count, dual_mono_file, slider_data)
							# run the command
							run_command(makeprocess[0], makeprocess[3])
							await get_tree().process_frame
							var output_file = makeprocess[1]
							dual_mono_output.append(output_file)
							
							# Mark file for cleanup if needed
							if delete_intermediate_outputs:
								for file in makeprocess[2]:
									breakfiles.append(file)
								intermediate_files.append(output_file)
							
							#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
							#with this stereo process CDP will throw errors in the console even though its fine
							if is_windows:
								dual_mono_file = dual_mono_file.replace("/", "\\")
							run_command(delete_cmd, [dual_mono_file])
							process_count += 1
						
						
						var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
						run_command(cdpprogs_location + "/submix", ["interleave", dual_mono_output[0], dual_mono_output[1], output_file])
						
						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if delete_intermediate_outputs:
							intermediate_files.append(output_file)

				else: #audio file is mono, run through the process
					var makeprocess = make_process(node, process_count, current_infile, slider_data)
					# run the command
					run_command(makeprocess[0], makeprocess[3])
					await get_tree().process_frame
					var output_file = makeprocess[1]
					

					# Store output file path for this node
					output_files[node_name] = output_file

					# Mark file for cleanup if needed
					if delete_intermediate_outputs:
						for file in makeprocess[2]:
							breakfiles.append(file)
						intermediate_files.append(output_file)

			# Increase the process step count
			process_count += 1

	# FINAL OUTPUT STAGE

	# Collect all nodes that are connected to the outputfile node
	var output_inputs := []
	for conn in connections:
		var to_node = str(conn["to_node"])
		if all_nodes.has(to_node) and all_nodes[to_node].get_meta("command") == "outputfile":
			output_inputs.append(str(conn["from_node"]))

	# List to hold the final output files to be merged (if needed)
	var final_outputs := []
	for node_name in output_inputs:
		if output_files.has(node_name):
			final_outputs.append(output_files[node_name])

	# If multiple outputs go to the outputfile node, merge them
	if final_outputs.size() > 1:
		var runmerge = merge_many_files(process_count, final_outputs)
		final_output_dir = runmerge[0]
		var converted_files = runmerge[1]
		
		if delete_intermediate_outputs:
			for f in converted_files:
				intermediate_files.append(f)


	# Only one output, no merge needed
	elif final_outputs.size() == 1:
		var single_output = final_outputs[0]
		final_output_dir = single_output
		intermediate_files.erase(single_output)

	# CLEANUP: Delete intermediate files after processing and rename final output
	log_console("Cleaning up intermediate files.", true)
	for file_path in intermediate_files:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
	#delete break files 
	for file_path in breakfiles:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
		
	var final_filename = "%s.wav" % Global.outfile
	var final_output_dir_fixed_path = final_output_dir
	if is_windows:
		final_output_dir_fixed_path = final_output_dir_fixed_path.replace("/", "\\")
		run_command(rename_cmd, [final_output_dir_fixed_path, final_filename.get_file()])
	else:
		run_command(rename_cmd, [final_output_dir_fixed_path, "%s.wav" % Global.outfile])
	final_output_dir = Global.outfile + ".wav"
	
	output_audio_player.play_outfile(final_output_dir)
	outfile = final_output_dir
			
	var interface_settings = ConfigHandler.load_interface_settings() #checks if close console is enabled and closes console on a success
	if interface_settings.auto_close_console and process_successful == true:
		$Console.hide()


func is_stereo(file: String) -> bool:
	var output = run_command(cdpprogs_location + "/sfprops", ["-c", file])
	output = int(output[0].strip_edges()) #convert output from cmd to clean int
	if output == 1:
		return false
	elif output == 2:
		return true
	elif output == 1026: #ignore pvoc .ana files
		return false
	else:
		log_console("[color=#9c2828]Error: Only mono and stereo files are supported[/color]", true)
		return false

func merge_many_files(process_count: int, input_files: Array) -> Array:
	var merge_output = "%s_merge_%d.wav" % [Global.outfile.get_basename(), process_count]
	var converted_files := []  # Track any mono->stereo converted files
	var inputs_to_merge := []  # Files to be used in the final merge

	var mono_files := []
	var stereo_files := []

	# STEP 1: Check each file's channel count
	for f in input_files:
		var stereo = is_stereo(f)
		if stereo == false:
			mono_files.append(f)
		elif stereo == true:
			stereo_files.append(f)


	# STEP 2: Convert mono to stereo if there is a mix
	if mono_files.size() > 0 and stereo_files.size() > 0:
		for mono_file in mono_files:
			var stereo_file = "%s_stereo.wav" % mono_file.get_basename()
			run_command(cdpprogs_location + "/submix", ["interleave", mono_file, mono_file, stereo_file])
			if process_successful == false:
				log_console("Failed to interleave mono file: %s" % mono_file, true)
			else:
				converted_files.append(stereo_file)
				inputs_to_merge.append(stereo_file)
		# Add existing stereo files
		inputs_to_merge += stereo_files
	else:
		# All mono or all stereo — use input_files directly
		inputs_to_merge = input_files.duplicate()

	# STEP 3: Merge all input files (converted or original)
	var quoted_inputs := []
	for f in inputs_to_merge:
		quoted_inputs.append(f)
	quoted_inputs.insert(0, "mergemany")
	quoted_inputs.append(merge_output)
	run_command(cdpprogs_location + "/submix", quoted_inputs)

	if process_successful == false:
		log_console("Failed to to merge files to" + merge_output, true)
	
	return [merge_output, converted_files]

func _get_slider_values_ordered(node: Node) -> Array:
	var results := []
	for child in node.get_children():
		if child is Range:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			var time
			var brk_data = []
			var min_slider = child.min_value
			var max_slider = child.max_value
			if child.has_meta("time"):
				time = child.get_meta("time")
			else:
				time = false
			if child.has_meta("brk_data"):
				brk_data = child.get_meta("brk_data")
			results.append([flag, child.value, time, brk_data, min_slider, max_slider])
		elif child.get_child_count() > 0:
			var nested := _get_slider_values_ordered(child)
			results.append_array(nested)
	return results



func make_process(node: Node, process_count: int, current_infile: String, slider_data: Array) -> Array:
	# Determine output extension: .wav or .ana based on the node's slot type
	var extension = ".wav" if node.get_slot_type_right(0) == 0 else ".ana"

	# Construct output filename for this step
	var output_file = "%s_%d%s" % [Global.outfile.get_basename(), process_count, extension]

	# Get the command name from metadata or default to node name
	var command_name = str(node.get_meta("command"))
	#command_name = command_name.replace("_", " ")
	command_name = command_name.split("_", true, 1)
	print(command_name)
	var command = "%s/%s" %[cdpprogs_location, command_name[0]]
	print(command)
	var args = command_name[1].split("_", true, 1)
	print(args)
	args.append(current_infile)
	args.append(output_file)
	print(args)
	# Start building the command line windows
	var line = "%s/%s \"%s\" \"%s\" " % [cdpprogs_location, command_name, current_infile, output_file]
	#mac

	
	var cleanup = []

	# Append parameter values from the sliders, include flags if present
	var slider_count = 0
	for entry in slider_data:
		var flag = entry[0]
		var value = entry[1]
		var time = entry[2] #checks if slider is a time percentage slider
		var brk_data = entry[3]
		var min_slider = entry[4]
		var max_slider = entry[5]
		if brk_data.size() > 0: #if breakpoint data is present on slider
			#Sort all points by time
			var sorted_brk_data = []
			sorted_brk_data = brk_data.duplicate()
			sorted_brk_data.sort_custom(sort_points)
			
			var calculated_brk = []
			
			#get length of input file in seconds
			var infile_length = run_command(cdpprogs_location + "/sfprops", ["-d", current_infile])
			infile_length = float(infile_length[0].strip_edges())
			
			#scale values from automation window to the right length for file and correct slider values
			#need to check how time is handled in all files that accept it, zigzag is x = outfile position, y = infile position
			#if time == true:
				#for point in sorted_brk_data:
					#var new_x = infile_length * (point.x / 700) #time
					#var new_y = infile_length * (remap(point.y, 255, 0, min_slider, max_slider) / 100) #slider value scaled as a percentage of infile time
					#calculated_brk.append(Vector2(new_x, new_y))
			#else:
			for i in range(sorted_brk_data.size()):
				var point = sorted_brk_data[i]
				var new_x = infile_length * (point.x / 700) #time
				if i == sorted_brk_data.size() - 1: #check if this is last automation point
					new_x = infile_length + 0.1  # force last point's x to infile_length + 100ms to make sure the file is defo over
				var new_y = remap(point.y, 255, 0, min_slider, max_slider) #slider value
				calculated_brk.append(Vector2(new_x, new_y))
				
			#make text file
			var brk_file_path = output_file.get_basename() + "_" + str(slider_count) + ".txt"
			write_breakfile(calculated_brk, brk_file_path)
			
			#append text file in place of value
			line += ("\"%s\" " % brk_file_path)
			args.append(brk_file_path)
			
			cleanup.append(brk_file_path)
		else:
			if time == true:
				var infile_length = run_command(cdpprogs_location + "/sfprops", ["-d", current_infile])
				infile_length = float(infile_length[0].strip_edges())
				value = infile_length * (value / 100) #calculate percentage time of the input file
			line += ("%s%.2f " % [flag, value]) if flag.begins_with("-") else ("%.2f " % value)
			args.append(("%s%.2f " % [flag, value]) if flag.begins_with("-") else ("%.2f " % value))
			
		slider_count += 1
	return [command, output_file, cleanup, args]
	#return [line.strip_edges(), output_file, cleanup]

func sort_points(a, b):
	return a.x < b.x
	
func write_breakfile(points: Array, path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		for point in points:
			var line = str(point.x) + " " + str(point.y) + "\n"
			file.store_string(line)
		file.close()
	else:
		print("Failed to open file for writing.")

func run_command(command: String, args: Array) -> Array:
	var is_windows = OS.get_name() == "Windows"

	var output: Array = []
	var error: Array = []

	var exit_code := 0
	if is_windows:
		#exit_code = OS.execute("cmd.exe", ["/C", command], output, true, false)
		args.insert(0, command)
		args.insert(0, "/C")
		exit_code = OS.execute("cmd.exe", args, output, true, false)
	else:
		exit_code = OS.execute(command, args, output, true, false)

	var output_str := ""
	for item in output:
		output_str += item + "\n"

	var error_str := ""
	for item in error:
		error_str += item + "\n"
	
	if is_windows:
		args.remove_at(0)
		console_output.append_text(" ".join(args) + "\n")
	else:
		console_output.append_text(command + " " + " ".join(args) + "\n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	
	if exit_code == 0:
		if output_str.contains("ERROR:"): #checks if CDP reported an error but passed exit code 0 anyway
			console_output.append_text("[color=#9c2828][b]Processes failed[/b][/color]\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			console_output.append_text(output_str + "\n")
			process_successful = false
		else:
			console_output.append_text("[color=#638382]Processes ran successfully[/color]\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			console_output.append_text(output_str + "\n")
			process_successful = true
			
	else:
		console_output.append_text("[color=#9c2828][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code)
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		console_output.append_text(output_str + "\n")
		console_output.append_text(error_str + "\n")
		if output_str.contains("as an internal or external command"): #check for cdprogs location error on windows
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is C:\\CDPR8\\_cdp\\_cdprogs[/b][/color]\n")
		if output_str.contains("command not found"): #check for cdprogs location error on unix systems
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is ~/cdpr8/_cdp/_cdprogs[/b][/color]\n")
		process_successful = false
	
	return output


	
func path_exists_through_all_nodes() -> bool:
	var all_nodes = {}
	var graph = {}

	var input_node_name = ""
	var output_node_name = ""

	# Gather all relevant nodes
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			all_nodes[name] = child

			var command = child.get_meta("command")
			if command == "inputfile":
				input_node_name = name
			elif command == "outputfile":
				output_node_name = name

			# Skip utility nodes, include others
			if command in ["inputfile", "outputfile"] or not child.has_meta("utility"):
				graph[name] = []

	# Ensure both input and output were found
	if input_node_name == "" or output_node_name == "":
		print("Input or output node not found!")
		return false

	# Add edges to graph from the connection list
	var connection_list = graph_edit.get_connection_list()
	for conn in connection_list:
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from):
			graph[from].append(to)

	# BFS traversal to check path and depth
	var visited = {}
	var queue = [ { "node": input_node_name, "depth": 0 } ]
	var has_intermediate = false

	while queue.size() > 0:
		var current = queue.pop_front()
		var current_node = current["node"]
		var depth = current["depth"]

		if current_node in visited:
			continue
		visited[current_node] = true

		if current_node == output_node_name and depth >= 2:
			has_intermediate = true

		if graph.has(current_node):
			for neighbor in graph[current_node]:
				queue.append({ "node": neighbor, "depth": depth + 1 })

	return has_intermediate


func _toggle_delete(toggled_on: bool):
	delete_intermediate_outputs = toggled_on
	print(toggled_on)

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
		3:
			if interface_settings.console_on_top == false:
				$MenuBar/SettingsButton.set_item_checked(index, true)
				ConfigHandler.save_interface_settings("console_on_top", true)
				$Console.always_on_top = true
			else:
				$MenuBar/SettingsButton.set_item_checked(index, false)
				ConfigHandler.save_interface_settings("console_on_top", false)
				$Console.always_on_top = false
		4:
			if interface_settings.use_search == false:
				$MenuBar/SettingsButton.set_item_checked(index, true)
				ConfigHandler.save_interface_settings("use_search", true)
			else:
				$MenuBar/SettingsButton.set_item_checked(index, false)
				ConfigHandler.save_interface_settings("use_search", false)
		5:
			$AudioSettings.popup()
		6:
			if $Console.is_visible():
				$Console.hide()
				await get_tree().process_frame  # Wait a frame to allow hide to complete
				$Console.popup()
			else:
				$Console.popup()

func _on_file_button_index_pressed(index: int) -> void:
	match index:
		0:
			if changesmade == true:
				savestate = "newfile"
				$SaveChangesPopup.show()
			else:
				new_patch()
				currentfile = "none" #reset current file to none for save tracking
		1:
			if currentfile == "none":
				savestate = "saveas"
				$SaveDialog.popup_centered()
			else:
				save_graph_edit(currentfile)
		2:
			savestate = "saveas"
			$SaveDialog.popup_centered()
		3:
			if changesmade == true:
				savestate = "load"
				$SaveChangesPopup.show()
			else:
				$LoadDialog.popup_centered()

func save_graph_edit(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("Failed to open file for saving")
		return

	var node_data_list = []
	var connection_data_list = []
	var node_id_map = {}  # Map node name to numeric ID

	var node_id = 1
	# Assign each node a unique numeric ID and gather node data
	for node in graph_edit.get_children():
		if node is GraphNode:
			node_id_map[node.name] = node_id

			var offset = node.position_offset
			var node_data = {
				"id": node_id,
				"name": node.name,
				"command": node.get_meta("command"),
				"offset": { "x": offset.x, "y": offset.y },
				"slider_values": {},
				"notes": {}
			}

			# Save slider values and metadata
			for child in node.find_children("*", "Slider", true, false):
				var relative_path = node.get_path_to(child)
				var path_str = str(relative_path)

				node_data["slider_values"][path_str] = {
					"value": child.value,
					"editable": child.editable,
					"meta": {}
				}
				for key in child.get_meta_list():
					node_data["slider_values"][path_str]["meta"][str(key)] = child.get_meta(key)
				
			# Save notes from CodeEdit children
			for child in node.find_children("*", "CodeEdit", true, false):
				node_data["notes"][child.name] = child.text

			node_data_list.append(node_data)
			node_id += 1

	# Save connections using node IDs instead of names
	for conn in graph_edit.get_connection_list():
		# Map from_node and to_node names to IDs
		var from_id = node_id_map.get(conn["from_node"], null)
		var to_id = node_id_map.get(conn["to_node"], null)

		if from_id != null and to_id != null:
			connection_data_list.append({
				"from_node_id": from_id,
				"from_port": conn["from_port"],
				"to_node_id": to_id,
				"to_port": conn["to_port"]
			})
		else:
			print("Warning: Connection references unknown node(s). Skipping connection.")

	var graph_data = {
		"nodes": node_data_list,
		"connections": connection_data_list
	}

	var json = JSON.new()
	var json_string = json.stringify(graph_data, "\t")
	file.store_string(json_string)
	file.close()
	print("Graph saved.")
	changesmade = false
	get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")


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

	# Remove all existing GraphNodes from graph_edit
	for node in graph_edit.get_children():
		if node is GraphNode:
			node.queue_free()

	await get_tree().process_frame  # Ensure nodes are freed before adding new ones

	var id_to_node = {}  # Map node IDs to new node instances

	# Recreate nodes and store them by ID
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
		_register_node_movement()  # Track node movement changes

		id_to_node[node_data["id"]] = new_node

		# Restore sliders
		for slider_path_str in node_data["slider_values"]:
			var slider = new_node.get_node_or_null(slider_path_str)
			if slider and (slider is HSlider or slider is VSlider):
				var slider_info = node_data["slider_values"][slider_path_str]
				if typeof(slider_info) == TYPE_DICTIONARY:
					slider.value = slider_info.get("value", slider.value)
					if slider_info.has("editable"):
						slider.editable = slider_info["editable"]
					if slider_info.has("meta"):
						for key in slider_info["meta"]:
							var value = slider_info["meta"][key]
							if key == "brk_data" and typeof(value) == TYPE_ARRAY:
								var new_array: Array = []
								for item in value:
									if typeof(item) == TYPE_STRING:
										var numbers: PackedStringArray = item.strip_edges().trim_prefix("(").trim_suffix(")").split(",")
										if numbers.size() == 2:
											var x = float(numbers[0])
											var y = float(numbers[1])
											new_array.append(Vector2(x, y))
								value = new_array
							slider.set_meta(key, value)
				else:
					slider.value = slider_info

		# Restore notes
		for codeedit_name in node_data["notes"]:
			var codeedit = new_node.find_child(codeedit_name, true, false)
			if codeedit and (codeedit is CodeEdit):
				codeedit.text = node_data["notes"][codeedit_name]

		_register_inputs_in_node(new_node)  # Track slider changes

	# Recreate connections by looking up nodes by ID
	for conn in graph_data["connections"]:
		var from_node = id_to_node.get(conn["from_node_id"], null)
		var to_node = id_to_node.get(conn["to_node_id"], null)

		if from_node != null and to_node != null:
			graph_edit.connect_node(
				from_node.name, conn["from_port"],
				to_node.name, conn["to_port"]
			)
		else:
			print("Warning: Connection references unknown node ID(s). Skipping connection.")

	link_output()
	print("Graph loaded.")
	get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")

#func save_graph_edit(path: String):
	#var file = FileAccess.open(path, FileAccess.WRITE)
	#if file == null:
		#print("Failed to open file for saving")
		#return
#
	#var node_data_list = []
	#var connection_data_list = []
#
	#for node in graph_edit.get_children():
		#if node is GraphNode:
			#var offset = node.position_offset
			#var node_data = {
				#"name": node.name,
				#"command": node.get_meta("command"),
				#"offset": { "x": offset.x, "y": offset.y },
				#"slider_values": {},
				#"notes":{}
			#}
#
			#for child in node.find_children("*", "Slider", true, false):
				#var relative_path = node.get_path_to(child)
				#var path_str = str(relative_path)
#
				## Save slider value
				#node_data["slider_values"][path_str] = {
					#"value": child.value,
					#"editable": child.editable,
					#"meta": {}
				#}
#
				## Save all metadata
				#for key in child.get_meta_list():
					#node_data["slider_values"][path_str]["meta"][str(key)] = child.get_meta(key)
				#
			#for child in node.find_children("*", "CodeEdit", true, false):
				#node_data["notes"][child.name] = child.text
#
			#node_data_list.append(node_data)
#
	#for conn in graph_edit.get_connection_list():
		#connection_data_list.append({
			#"from_node": conn["from_node"],
			#"from_port": conn["from_port"],
			#"to_node": conn["to_node"],
			#"to_port": conn["to_port"]
		#})
#
	#var graph_data = {
		#"nodes": node_data_list,
		#"connections": connection_data_list
	#}
#
	#var json = JSON.new()
	#var json_string = json.stringify(graph_data, "\t")
	#file.store_string(json_string)
	#file.close()
	#print("Graph saved.")
	#changesmade = false
	#get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")
#
#
#func load_graph_edit(path: String):
	#var file = FileAccess.open(path, FileAccess.READ)
	#if file == null:
		#print("Failed to open file for loading")
		#return
#
	#var json_text = file.get_as_text()
	#file.close()
#
	#var json = JSON.new()
	#if json.parse(json_text) != OK:
		#print("Error parsing JSON")
		#return
#
	#var graph_data = json.get_data()
	#graph_edit.clear_connections()
#
	#for node in graph_edit.get_children():
		#if node is GraphNode:
			#node.queue_free()
#
	#await get_tree().process_frame  # Ensure nodes are cleared
#
	#for node_data in graph_data["nodes"]:
		#var command_name = node_data.get("command", "")
		#var template = Nodes.get_node_or_null(command_name)
		#if not template:
			#print("Template not found for command:", command_name)
			#continue
#
		#var new_node: GraphNode = template.duplicate()
		#new_node.name = node_data["name"]
		#new_node.position_offset = Vector2(node_data["offset"]["x"], node_data["offset"]["y"])
		#new_node.set_meta("command", command_name)
		#graph_edit.add_child(new_node)
		#_register_node_movement() #link nodes for tracking position changes for changes tracking
#
		## Restore sliders
		#for slider_path_str in node_data["slider_values"]:
			#var slider = new_node.get_node_or_null(slider_path_str)
			#if slider and (slider is HSlider or slider is VSlider):
				#var slider_info = node_data["slider_values"][slider_path_str]
				#
				#if typeof(slider_info) == TYPE_DICTIONARY:
					#slider.value = slider_info.get("value", slider.value)
					#
					## Restore enabled/disabled
					#if slider_info.has("editable"):
						#slider.editable = slider_info["editable"]
					#
					## Restore metadata
					#if slider_info.has("meta"):
						#for key in slider_info["meta"]:
							#var value = slider_info["meta"][key]
#
							## Convert arrays of stringified Vector2s back to real Vector2s
							#if key == "brk_data" and typeof(value) == TYPE_ARRAY:
								#var new_array: Array = []
								#for item in value:
									#if typeof(item) == TYPE_STRING:
										## Extract values from "(x, y)"
										#var numbers: PackedStringArray = item.strip_edges().trim_prefix("(").trim_suffix(")").split(",")
										#if numbers.size() == 2:
											#var x = float(numbers[0])
											#var y = float(numbers[1])
											#new_array.append(Vector2(x, y))
								#value = new_array
#
							#slider.set_meta(key, value)
				#else:
					## Legacy support: just value
					#slider.value = slider_info
			#
	#
				#
		## Restore notes
		#for codeedit_name in node_data["notes"]:
			#var codeedit = new_node.find_child(codeedit_name, true, false)
			#if codeedit and (codeedit is CodeEdit):
				#codeedit.text = node_data["notes"][codeedit_name]
		#_register_inputs_in_node(new_node) #link sliders for changes tracking
	## Restore connections
	#for conn in graph_data["connections"]:
		#graph_edit.connect_node(
			#conn["from_node"], conn["from_port"],
			#conn["to_node"], conn["to_port"]
		#)
	#link_output()
	#print("Graph loaded.")
	#get_window().title = "SoundThread - " + path.get_file().trim_suffix(".thd")


func _on_save_dialog_file_selected(path: String) -> void:
	save_graph_edit(path) #save file
	#check what the user was trying to do before save and do that action
	if savestate == "newfile":
		new_patch()
		currentfile = "none" #reset current file to none for save tracking
	elif savestate == "load":
		$LoadDialog.popup_centered()
	elif savestate == "helpfile":
		currentfile = "none" #reset current file to none for save tracking so user cant save over help file
		load_graph_edit(helpfile)
	elif savestate == "quit":
		await get_tree().create_timer(0.25).timeout #little pause so that it feels like it actually saved even though it did
		get_tree().quit()
		
	savestate = "none" #reset save state, not really needed but feels good


func _on_load_dialog_file_selected(path: String) -> void:
	currentfile = path #tracking path here only means "save" only saves patches the user has loaded rather than overwriting help files
	load_graph_edit(path)

func _on_help_button_index_pressed(index: int) -> void:
	match index:
		0:
			pass
		1:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/getting_started.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/getting_started.thd")
		2:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/navigating.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/navigating.thd")
		3:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/building_a_thread.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/building_a_thread.thd")
		4:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/frequency_domain.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/frequency_domain.thd")
		5:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/automation.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/automation.thd")
		6:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/trimming.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/trimming.thd")
		7:
			pass
		8:
			if changesmade == true:
				savestate = "helpfile"
				helpfile = "res://examples/wetdry.thd"
				$SaveChangesPopup.show()
			else:
				currentfile = "none" #reset current file to none for save tracking so user cant save over help file
				load_graph_edit("res://examples/wetdry.thd")
		9:
			pass
		10:
			OS.shell_open("https://www.composersdesktop.com/docs/html/ccdpndex.htm")
		11:
			OS.shell_open("https://github.com/j-p-higgins/SoundThread/issues")

func _recycle_outfile():
	if outfile != "no file":
		input_audio_player.recycle_outfile(outfile)



func _on_save_changes_button_down() -> void:
	$SaveChangesPopup.hide()
	if currentfile == "none":
		$SaveDialog.show()
	else:
		save_graph_edit(currentfile)
		if savestate == "newfile":
			new_patch()
			currentfile = "none" #reset current file to none for save tracking
		elif savestate == "load":
			$LoadDialog.popup_centered()
		elif savestate == "helpfile":
			currentfile = "none" #reset current file to none for save tracking so user cant save over help file
			load_graph_edit(helpfile)
		elif savestate == "quit":
			await get_tree().create_timer(0.25).timeout #little pause so that it feels like it actually saved even though it did
			get_tree().quit()
			
		savestate = "none"


func _on_dont_save_changes_button_down() -> void:
	$SaveChangesPopup.hide()
	if savestate == "newfile":
		new_patch()
		currentfile = "none" #reset current file to none for save tracking
	elif savestate == "load":
		$LoadDialog.popup_centered()
	elif savestate == "helpfile":
		currentfile = "none" #reset current file to none for save tracking so user cant save over help file
		load_graph_edit(helpfile)
	elif savestate == "quit":
		get_tree().quit()
	
	savestate = "none"
	
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		$Console.hide()
		if changesmade == true:
			savestate = "quit"
			$SaveChangesPopup.show()
			#$HelpWindow.hide()
		else:
			get_tree().quit() # default behavior
			
func _open_output_folder():
	if lastoutputfolder != "none":
		OS.shell_open(lastoutputfolder)
		

func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	print(str(meta))
	OS.shell_open(str(meta))


func _on_graph_edit_popup_request(at_position: Vector2) -> void:
	var interface_settings = ConfigHandler.load_interface_settings()
	
	effect_position = graph_edit.get_local_mouse_position()
	
	if interface_settings.use_search == false:
		#get the mouse position in screen coordinates
		var mouse_screen_pos = DisplayServer.mouse_get_position()  
		#get the window position in screen coordinates
		var window_screen_pos = get_window().position
		#get the window size relative to its scaling for retina displays
		var window_size = get_window().size * DisplayServer.screen_get_scale()
		#get the size of the popup menu
		var popup_size = $mainmenu.size

		#calculate the xy position of the mouse clamped to the size of the window and menu so it doesn't go off the screen
		var clamped_x = clamp(mouse_screen_pos.x, window_screen_pos.x, window_screen_pos.x + window_size.x - popup_size.x)
		var clamped_y = clamp(mouse_screen_pos.y, window_screen_pos.y, window_screen_pos.y + window_size.y - popup_size.y)
		
		#position and show the menu
		$mainmenu.position = Vector2(clamped_x, clamped_y)
		$mainmenu.popup()
	else:
		#get the mouse position in screen coordinates
		var mouse_screen_pos = DisplayServer.mouse_get_position()  
		#get the window position in screen coordinates
		var window_screen_pos = get_window().position
		#get the window size relative to its scaling for retina displays
		var window_size = get_window().size * DisplayServer.screen_get_scale()

		#calculate the xy position of the mouse clamped to the size of the window and menu so it doesn't go off the screen
		var clamped_x = clamp(mouse_screen_pos.x, window_screen_pos.x, window_screen_pos.x + window_size.x - $SearchMenu.size.x)
		var clamped_y = clamp(mouse_screen_pos.y, window_screen_pos.y, window_screen_pos.y + window_size.y - (420 * DisplayServer.screen_get_scale()))
		
		#position and show the menu
		$SearchMenu.position = Vector2(clamped_x, clamped_y)
		$SearchMenu.popup()

func _on_audio_settings_close_requested() -> void:
	$AudioSettings.hide()


func _on_open_audio_settings_button_down() -> void:
	$AudioDevicePopup.hide()
	$AudioSettings.popup()


func _on_audio_device_popup_close_requested() -> void:
	$AudioDevicePopup.hide()

func _on_mainmenu_close_requested() -> void:
	#closes menu if click is anywhere other than the menu as it is a window with popup set to true
	$mainmenu.hide()

func open_explore():
	effect_position = graph_edit.get_local_mouse_position()
	
	#get the mouse position in screen coordinates
	var mouse_screen_pos = DisplayServer.mouse_get_position()  
	#get the window position in screen coordinates
	var window_screen_pos = get_window().position
	#get the window size relative to its scaling for retina displays
	var window_size = get_window().size * DisplayServer.screen_get_scale()
	#get the size of the popup menu
	var popup_size = $mainmenu.size

	#calculate the xy position of the mouse clamped to the size of the window and menu so it doesn't go off the screen
	var clamped_x = clamp(mouse_screen_pos.x, window_screen_pos.x, window_screen_pos.x + window_size.x - popup_size.x)
	var clamped_y = clamp(mouse_screen_pos.y, window_screen_pos.y, window_screen_pos.y + window_size.y - popup_size.y)
	
	#position and show the menu
	$mainmenu.position = Vector2(clamped_x, clamped_y)
	$mainmenu.popup()
