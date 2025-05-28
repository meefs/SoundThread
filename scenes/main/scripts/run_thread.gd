extends Node
var control_script

var progress_label
var progress_bar
var graph_edit
var console_output
var progress_window
var console_window
var process_successful #tracks if the last run process was successful
var process_info = {} #tracks the data of the currently running process
var process_running := false #tracks if a process is currently running
var process_cancelled = false #checks if the currently running process has been cancelled

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


func init(main_node: Node, progresswindow: Window, progresslabel: Label, progressbar: ProgressBar, graphedit: GraphEdit, consolewindow: Window, consoleoutput: RichTextLabel) -> void:
	control_script = main_node
	progress_window = progresswindow
	progress_label = progresslabel
	progress_bar = progressbar
	graph_edit = graphedit
	console_window = consolewindow
	console_output = consoleoutput


	
func run_thread_with_branches():
	process_cancelled = false
	process_successful = true
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
	#do calculations for progress bar
	var progress_step
	if Global.trim_infile == true:
		progress_step = 100 / (graph.size() + 4)
	else:
		progress_step = 100 / (graph.size() + 3)
	

	# Step 2: Build graph relationships from connections
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		progress_label.text = "Building Thread"
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
	progress_bar.value = progress_step
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
	
	var current_infile = starting_infile

	# Iterate over the processing nodes in topological order
	for node_name in sorted:
		var node = all_nodes[node_name]
		if process_cancelled:
			progress_label.text = "Thread Stopped"
			log_console("[b]Thread Stopped[/b]", true)
			break
		else:
			progress_label.text = "Running process: " + node.get_title()
		# Find upstream nodes connected to the current node
		var inputs = reverse_graph[node_name]
		var input_files = []
		for input_node in inputs:
			input_files.append(output_files[input_node])

		# Merge inputs if this node has more than one input
		if input_files.size() > 1:
			# Prepare final merge output file name
			var runmerge = await merge_many_files(process_count, input_files)
			var merge_output = runmerge[0]
			var converted_files = runmerge[1]

			# Track the output and intermediate files
			current_infile = merge_output
			
			if control_script.delete_intermediate_outputs:
				intermediate_files.append(merge_output)
				for f in converted_files:
					intermediate_files.append(f)

		# If only one input, use that
		elif input_files.size() == 1:
			current_infile = input_files[0]

		## If no input, use the original input file
		else:
			current_infile = starting_infile
		
		if node.get_meta("command") == "inputfile":
			#get the inputfile from the nodes meta
			var loadedfile = node.get_node("AudioPlayer").get_meta("inputfile")
			#get wether trim has been enabled
			var trimfile = node.get_node("AudioPlayer").get_meta("trimfile")
			
			#if trim is enabled trim the file
			if trimfile == true:
				#get the start and end points
				var start = node.get_node("AudioPlayer").get_meta("trimpoints")[0]
				var end = node.get_node("AudioPlayer").get_meta("trimpoints")[1]
				
				if process_cancelled:
					#exit out of process if cancelled
					progress_label.text = "Thread Stopped"
					log_console("[b]Thread Stopped[/b]", true)
					return
				else:
					progress_label.text = "Trimming input audio"
				await run_command(control_script.cdpprogs_location + "/sfedit", ["cut", "1", loadedfile, "%s_trimmed.wav" % Global.outfile, str(start), str(end)])
				
				output_files[node_name] =  Global.outfile + "_trimmed.wav"
				
				# Mark trimmed file for cleanup if needed
				if control_script.delete_intermediate_outputs:
					intermediate_files.append(Global.outfile + "_trimmed.wav")
				progress_bar.value += progress_step
			else:
				#if trim not enabled pass the loaded file
				output_files[node_name] =  loadedfile
			
		else:
			# Build the command for the current node's audio processing
			var slider_data = _get_slider_values_ordered(node)
			
			if node.get_slot_type_right(0) == 1: #detect if process outputs pvoc data
				if typeof(current_infile) == TYPE_ARRAY:
					#check if infile is an array meaning that the last pvoc process was run in dual mono mode
					# Process left and right seperately
					var pvoc_stereo_files = []
					
					for infile in current_infile:
						var makeprocess = await make_process(node, process_count, infile, slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						pvoc_stereo_files.append(output_file)
						
						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

						process_count += 1
						
					output_files[node_name] = pvoc_stereo_files
				else:
					var input_stereo = await is_stereo(current_infile)
					if input_stereo == true: 
						#audio file is stereo and needs to be split for pvoc processing
						var pvoc_stereo_files = []
						##Split stereo to c1/c2
						await run_command(control_script.cdpprogs_location + "/housekeep",["chans", "2", current_infile])
				
						# Process left and right seperately
						for channel in ["c1", "c2"]:
							var dual_mono_file = current_infile.get_basename() + "_%s.wav" % channel
							
							var makeprocess = await make_process(node, process_count, dual_mono_file, slider_data)
							# run the command
							await run_command(makeprocess[0], makeprocess[3])
							await get_tree().process_frame
							var output_file = makeprocess[1]
							pvoc_stereo_files.append(output_file)
							
							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								for file in makeprocess[2]:
									breakfiles.append(file)
								intermediate_files.append(output_file)
							
							#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
							#with this stereo process CDP will throw errors in the console even though its fine
							if is_windows:
								dual_mono_file = dual_mono_file.replace("/", "\\")
							await run_command(delete_cmd, [dual_mono_file])
							process_count += 1
							
							# Store output file path for this node
						output_files[node_name] = pvoc_stereo_files
					else: 
						#input file is mono run through process
						var makeprocess = await make_process(node, process_count, current_infile, slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]

						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
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
						var makeprocess = await make_process(node, process_count, infile, slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						pvoc_stereo_files.append(output_file)
						
						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

						process_count += 1
						
						
					#interleave left and right
					var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
					await run_command(control_script.cdpprogs_location + "/submix", ["interleave", pvoc_stereo_files[0], pvoc_stereo_files[1], output_file])
					# Store output file path for this node
					output_files[node_name] = output_file
					
					# Mark file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						intermediate_files.append(output_file)

				else:
					#Detect if input file is mono or stereo
					var input_stereo = await is_stereo(current_infile)
					if input_stereo == true:
						if node.get_meta("stereo_input") == true: #audio file is stereo and process is stereo, run file through process
							var makeprocess = await make_process(node, process_count, current_infile, slider_data)
							# run the command
							await run_command(makeprocess[0], makeprocess[3])
							await get_tree().process_frame
							var output_file = makeprocess[1]
							
							# Store output file path for this node
							output_files[node_name] = output_file

							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								for file in makeprocess[2]:
									breakfiles.append(file)
								intermediate_files.append(output_file)

						else: #audio file is stereo and process is mono, split stereo, process and recombine
							##Split stereo to c1/c2
							await run_command(control_script.cdpprogs_location + "/housekeep",["chans", "2", current_infile])
					
							# Process left and right seperately
							var dual_mono_output = []
							for channel in ["c1", "c2"]:
								var dual_mono_file = current_infile.get_basename() + "_%s.wav" % channel
								
								var makeprocess = await make_process(node, process_count, dual_mono_file, slider_data)
								# run the command
								await run_command(makeprocess[0], makeprocess[3])
								await get_tree().process_frame
								var output_file = makeprocess[1]
								dual_mono_output.append(output_file)
								
								# Mark file for cleanup if needed
								if control_script.delete_intermediate_outputs:
									for file in makeprocess[2]:
										breakfiles.append(file)
									intermediate_files.append(output_file)
								
								#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
								#with this stereo process CDP will throw errors in the console even though its fine
								if is_windows:
									dual_mono_file = dual_mono_file.replace("/", "\\")
								await run_command(delete_cmd, [dual_mono_file])
								process_count += 1
							
							
							var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
							await run_command(control_script.cdpprogs_location + "/submix", ["interleave", dual_mono_output[0], dual_mono_output[1], output_file])
							
							# Store output file path for this node
							output_files[node_name] = output_file

							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								intermediate_files.append(output_file)

					else: #audio file is mono, run through the process
						var makeprocess = await make_process(node, process_count, current_infile, slider_data)
						# run the command
						await run_command(makeprocess[0], makeprocess[3])
						await get_tree().process_frame
						var output_file = makeprocess[1]
						

						# Store output file path for this node
						output_files[node_name] = output_file

						# Mark file for cleanup if needed
						if control_script.delete_intermediate_outputs:
							for file in makeprocess[2]:
								breakfiles.append(file)
							intermediate_files.append(output_file)

				# Increase the process step count
				process_count += 1
			progress_bar.value += progress_step
	# FINAL OUTPUT STAGE

	# Collect all nodes that are connected to the outputfile node
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		progress_label.text = "Finalising output"
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
		var runmerge = await merge_many_files(process_count, final_outputs)
		control_script.final_output_dir = runmerge[0]
		var converted_files = runmerge[1]
		
		if control_script.delete_intermediate_outputs:
			for f in converted_files:
				intermediate_files.append(f)


	# Only one output, no merge needed
	elif final_outputs.size() == 1:
		var single_output = final_outputs[0]
		control_script.final_output_dir = single_output
		intermediate_files.erase(single_output)
	progress_bar.value += progress_step
	# CLEANUP: Delete intermediate files after processing and rename final output
	if process_cancelled:
		progress_label.text = "Thread Stopped"
		log_console("[b]Thread Stopped[/b]", true)
		return
	else:
		log_console("Cleaning up intermediate files.", true)
		progress_label.text = "Cleaning up"
	for file_path in intermediate_files:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		await run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
	#delete break files 
	for file_path in breakfiles:
		# Adjust file path format for Windows if needed
		var fixed_path = file_path
		if is_windows:
			fixed_path = fixed_path.replace("/", "\\")
		await run_command(delete_cmd, [fixed_path])
		await get_tree().process_frame
		
	var final_filename = "%s.wav" % Global.outfile
	var final_output_dir_fixed_path = control_script.final_output_dir
	if is_windows:
		final_output_dir_fixed_path = final_output_dir_fixed_path.replace("/", "\\")
		await run_command(rename_cmd, [final_output_dir_fixed_path, final_filename.get_file()])
	else:
		await run_command(rename_cmd, [final_output_dir_fixed_path, "%s.wav" % Global.outfile])
	control_script.final_output_dir = Global.outfile + ".wav"
	
	control_script.output_audio_player.play_outfile(control_script.final_output_dir)
	control_script.outfile = control_script.final_output_dir
	progress_bar.value = 100.0
	var interface_settings = ConfigHandler.load_interface_settings() #checks if close console is enabled and closes console on a success
	progress_window.hide()
	if interface_settings.auto_close_console and process_successful == true:
		console_window.hide()


func is_stereo(file: String) -> bool:
	var output = await run_command(control_script.cdpprogs_location + "/sfprops", ["-c", file])
	output = int(output.strip_edges()) #convert output from cmd to clean int
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
		var stereo = await is_stereo(f)
		if stereo == false:
			mono_files.append(f)
		elif stereo == true:
			stereo_files.append(f)


	# STEP 2: Convert mono to stereo if there is a mix
	if mono_files.size() > 0 and stereo_files.size() > 0:
		for mono_file in mono_files:
			var stereo_file = "%s_stereo.wav" % mono_file.get_basename()
			await run_command(control_script.cdpprogs_location + "/submix", ["interleave", mono_file, mono_file, stereo_file])
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
	await run_command(control_script.cdpprogs_location + "/submix", quoted_inputs)

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
	command_name = command_name.split("_", true, 1)
	var command = "%s/%s" %[control_script.cdpprogs_location, command_name[0]]
	var args = command_name[1].split("_", true, 1)
	args.append(current_infile)
	args.append(output_file)

	# Start building the command line windows
	var line = "%s/%s \"%s\" \"%s\" " % [control_script.cdpprogs_location, command_name, current_infile, output_file]
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
			var infile_length = await run_command(control_script.cdpprogs_location + "/sfprops", ["-d", current_infile])
			infile_length = float(infile_length.strip_edges())
			
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
				var infile_length = await run_command(control_script.cdpprogs_location + "/sfprops", ["-d", current_infile])
				infile_length = float(infile_length.strip_edges())
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

func _on_kill_process_button_down() -> void:
	if process_running and process_info.has("pid"):
		progress_window.hide()
		# Terminate the process by PID
		OS.kill(process_info["pid"])
		process_running = false
		print("Process cancelled.")
		process_cancelled = true

	
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
	
func log_console(text: String, update: bool) -> void:
	console_output.append_text(text + "\n \n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	if update == true:
		await get_tree().process_frame  # Optional: ensure UI updates

func run_command(command: String, args: Array) -> String:
	var is_windows = OS.get_name() == "Windows"

	console_output.append_text(command + " " + " ".join(args) + "\n")
	console_output.scroll_to_line(console_output.get_line_count() - 1)
	await get_tree().process_frame
	
	if is_windows and (command == "del" or command == "ren"): #checks if the command is a windows system command and runs it through cmd.exe
		args.insert(0, command)
		args.insert(0, "/C")
		process_info = OS.execute_with_pipe("cmd.exe", args, false)
	else:
		process_info = OS.execute_with_pipe(command, args, false)
	# Check if the process was successfully started
	if !process_info.has("pid"):
		print("Failed to start process.")
		return ""
	
	process_running = true
	
	# Start monitoring the process output and status
	return await monitor_process(process_info["pid"], process_info["stdio"], process_info["stderr"])

func monitor_process(pid: int, stdout: FileAccess, stderr: FileAccess) -> String:
	var output := ""
	
	while OS.is_process_running(pid):
		await get_tree().process_frame
		
		while stdout.get_position() < stdout.get_length():
			var line = stdout.get_line()
			output += line
			console_output.append_text(line + "\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
		while stderr.get_position() < stderr.get_length():
			var line = stderr.get_line()
			output += line
			console_output.append_text(line + "\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
	
	var exit_code = OS.get_process_exit_code(pid)
	if exit_code == 0:
		if output.contains("ERROR:"): #checks if CDP reported an error but passed exit code 0 anyway
			console_output.append_text("[color=#9c2828][b]Processes failed[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			process_successful = false
			if process_cancelled == false:
				progress_window.hide()
				if !console_window.visible:
					console_window.popup_centered()
		else:
			console_output.append_text("[color=#638382]Processes ran successfully[/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
	else:
		console_output.append_text("[color=#9c2828][b]Processes failed with exit code: %d[/b][/color]\n" % exit_code + "\n")
		console_output.scroll_to_line(console_output.get_line_count() - 1)
		process_successful = false
		if process_cancelled == false:
			progress_window.hide()
			if !console_window.visible:
				console_window.popup_centered()
		if output.contains("as an internal or external command"): #check for cdprogs location error on windows
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is C:\\CDPR8\\_cdp\\_cdprogs[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
		if output.contains("command not found"): #check for cdprogs location error on unix systems
			console_output.append_text("[color=#9c2828][b]Please make sure your cdprogs folder is set to the correct location in the Settings menu. The default location is ~/cdpr8/_cdp/_cdprogs[/b][/color]\n\n")
			console_output.scroll_to_line(console_output.get_line_count() - 1)
			
	process_running = false
	return output
