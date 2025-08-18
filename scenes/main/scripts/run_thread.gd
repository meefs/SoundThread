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
var final_output_dir

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
		log_console("Threads must contain at least one processing node and a valid path from the Input File or Synthesis node to the Output File.", true)
		await get_tree().process_frame  # Let UI update
		if progress_window.visible:
			progress_window.hide()
		if !console_window.visible:
			console_window.popup_centered()
		return
	else:
		log_console("[color=#638382][b]Valid Thread found[/b][/color]", true)
		await get_tree().process_frame  # Let UI update
		
	# Step 1: Gather nodes from the GraphEdit
	var inputcount = 0 # used for tracking the number of input nodes and trims on input files for progress bar
	for child in graph_edit.get_children():
		if child is GraphNode:
			var includenode = true
			var name = str(child.name)
			all_nodes[name] = child
			if child.has_meta("utility"):
				includenode = false
			else:
				#check if node has inputs
				if child.get_input_port_count() > 0:
					#if it does scan through those inputs
					for i in range(child.get_input_port_count()):
						#check if it can find any valid connections
						var connected = false
						for conn in connections:
							if conn["to_node"] == name and conn["to_port"] == i:
								connected = true
								break
						#if no valid connections are found break the for loop to skip checking other inputs and set include to false
						if connected == false:
							log_console(name + " input is not connected, skipping node.", true)
							includenode = false
							break
				#check if node has outputs
				if child.get_output_port_count() > 0:
					#if it does scan through those outputs
					for i in range(child.get_output_port_count()):
						#check if it can find any valid connections
						var connected = false
						for conn in connections:
							if conn["from_node"] == name and conn["from_port"] == i:
								connected = true
								break
						#if no valid connections are found break the for loop to skip checking other inputs and set include to false
						if connected == false:
							log_console(name + " output is not connected, skipping node.", true)
							includenode = false
							break
								
			if includenode == true:
				graph[name] = []
				reverse_graph[name] = []
				indegree[name] = 0  # Start with zero incoming edges
				if child.get_meta("command") == "inputfile":
					inputcount -= 1
					if child.get_node("AudioPlayer").get_meta("trimfile"):
						inputcount += 1
	#do calculations for progress bar
	var progress_step
	progress_step = 100 / (graph.size() + 3 + inputcount)

	

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

	var current_infile

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
		# Build an array of all inlet connections
		var input_connections := []
		for conn in connections:
			if conn["to_node"] == node_name:
				input_connections.append(conn)
		input_connections.sort_custom(func(a, b): return a["to_port"] < b["to_port"])
		
		#build a dictionary with all inputs sorted by inlet number
		var inlet_inputs = {}

		for conn in input_connections:
			var inlet_idx = conn["to_port"]
			var upstream_node = conn["from_node"]
			if output_files.has(upstream_node):
				if not inlet_inputs.has(inlet_idx):
					inlet_inputs[inlet_idx] = []
				inlet_inputs[inlet_idx].append(output_files[upstream_node])

		# Merge inputs if inlet has more than one input and build infile dictionary
		var current_infiles = {} #dictionary to store input files by inlet number

		for inlet_idx in inlet_inputs.keys():
			var files = inlet_inputs[inlet_idx]
			if files.size() > 1: #if more than one file mix them together
				var runmerge = await merge_many_files(inlet_idx, process_count, files)
				var merge_output = runmerge[0] #mixed output file name
				var converted_files = runmerge[1] #intermediate files created from merge

				current_infiles[inlet_idx] = merge_output #input filename added to dictionary sorted by inlet number
				
				#add intermediate files to delete list if toggled
				if control_script.delete_intermediate_outputs:
					intermediate_files.append(merge_output)
					for f in converted_files:
						intermediate_files.append(f)
			elif files.size() == 1:
				current_infiles[inlet_idx] = files[0] #only one file, do not merge add to dictionary
		
		#if the dictionary has more than one entry there is more than one inlet and files need to be matched
		if current_infiles.size() > 1 and node.get_slot_type_left(0) == 0:
			#check all files in dictionary have the same sample rate and channel count and fix if not
			var all_files = current_infiles.values()
			
			var match_sample_rate = await match_file_sample_rates(0, process_count, all_files)
			var match_channels = await match_file_channels(0, process_count, match_sample_rate[0])
			var matched_files = match_channels[0]
			
			#add intermediate files
			if control_script.delete_intermediate_outputs:
				for f in match_sample_rate[1]:
					intermediate_files.append(f)
				for f in match_channels[1]:
					intermediate_files.append(f)
			
			#replace files in dictionary with matched files
			var idx = 0
			for key in current_infiles.keys():
				current_infiles[key] = matched_files[idx]
				idx += 1
		
		
		#check if node is some form of input node
		if node.get_input_port_count() == 0:
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
					await run_command(control_script.cdpprogs_location + "/sfedit", ["cut", "1", loadedfile, "%s_%d_input_trim.wav" % [Global.outfile, process_count], str(start), str(end)])
					
					output_files[node_name] =  "%s_%d_input_trim.wav" % [Global.outfile, process_count]
					
					# Mark trimmed file for cleanup if needed
					if control_script.delete_intermediate_outputs:
						intermediate_files.append("%s_%d_input_trim.wav" % [Global.outfile, process_count])
					progress_bar.value += progress_step
				else:
					#if trim not enabled pass the loaded file
					output_files[node_name] =  loadedfile
					
				process_count += 1
			else: #not an audio file must be synthesis
				var slider_data = _get_slider_values_ordered(node)
				var makeprocess = await make_process(node, process_count, [], slider_data)
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
					
				process_count += 1
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
							var dual_mono_file = current_infile.get_basename() + "_%s.%s" % [channel, current_infile.get_extension()]
							
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
				elif node.get_meta("command") == "preview":
					var preview_audioplayer = node.get_child(1)
					preview_audioplayer._on_file_selected(current_infile)
					if current_infile in intermediate_files:
						intermediate_files.erase(current_infile)
				else:
					#Detect if input file is mono or stereo
					var input_stereo = await is_stereo(current_infiles.values()[0])
					#var input_stereo = true #bypassing stereo check just for testing need to reimplement
					if input_stereo == true:
						if node.get_meta("stereo_input") == true: #audio file is stereo and process is stereo, run file through process
							#current_infile = current_infiles.values()
							var makeprocess = await make_process(node, process_count, current_infiles.values(), slider_data)
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
							var split_files = await stereo_split_and_process(current_infiles.values(), node, process_count, slider_data)
							var dual_mono_output = split_files[0]
								
							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								for file in split_files[1]:
									breakfiles.append(file)
								for file in dual_mono_output:
									intermediate_files.append(file)
							
							#Delete c1 and c2 because they can be in the wrong folder and if the same infile is used more than once
							#with this stereo process CDP will throw errors in the console even though its fine
							var files_to_delete = split_files[2] + split_files[3]
							for file in files_to_delete:
								if is_windows:
									file = file.replace("/", "\\")
								await run_command(delete_cmd, [file])
							
							#advance process count to match the advancement in the stereo_split_and_process function
							process_count += 1
							
							
							var output_file = Global.outfile.get_basename() + str(process_count) + "_interleaved.wav"
							await run_command(control_script.cdpprogs_location + "/submix", ["interleave", dual_mono_output[0], dual_mono_output[1], output_file])
							
							# Store output file path for this node
							output_files[node_name] = output_file

							# Mark file for cleanup if needed
							if control_script.delete_intermediate_outputs:
								intermediate_files.append(output_file)

					else: #audio file is mono, run through the process
						var makeprocess = await make_process(node, process_count, current_infiles.values(), slider_data)
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
		var runmerge = await merge_many_files(0, process_count, final_outputs)
		final_output_dir = runmerge[0]
		var converted_files = runmerge[1]
		
		if control_script.delete_intermediate_outputs:
			for f in converted_files:
				intermediate_files.append(f)


	# Only one output, no merge needed
	elif final_outputs.size() == 1:
		var single_output = final_outputs[0]
		final_output_dir = single_output
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
	var final_output_dir_fixed_path = final_output_dir
	if is_windows:
		final_output_dir_fixed_path = final_output_dir_fixed_path.replace("/", "\\")
		await run_command(rename_cmd, [final_output_dir_fixed_path, final_filename.get_file()])
	else:
		await run_command(rename_cmd, [final_output_dir_fixed_path, "%s.wav" % Global.outfile])
	final_output_dir = Global.outfile + ".wav"
	
	control_script.output_audio_player.play_outfile(final_output_dir)
	Global.cdpoutput = final_output_dir
	progress_bar.value = 100.0
	var interface_settings = ConfigHandler.load_interface_settings() #checks if close console is enabled and closes console on a success
	progress_window.hide()
	if interface_settings.auto_close_console and process_successful == true:
		console_window.hide()

func stereo_split_and_process(files: Array, node: Node, process_count: int, slider_data: Array) -> Array:
	var dual_mono_output:= []
	var left:= []
	var right:= []
	var intermediate_files:= []
	
	for file in files:
		await run_command(control_script.cdpprogs_location + "/housekeep",["chans", "2", file])
		left.append(file.get_basename() + "_%s.%s" % ["c1", file.get_extension()])
		right.append(file.get_basename() + "_%s.%s" % ["c2", file.get_extension()])
	
	#loop through the left and right arrays and make and run the process for each of them
	for channel in [left, right]:
		var makeprocess = await make_process(node, process_count, channel, slider_data)
		# run the command
		await run_command(makeprocess[0], makeprocess[3])
		await get_tree().process_frame
		var output_file = makeprocess[1]
		dual_mono_output.append(output_file)
		for file in makeprocess[2]:
			intermediate_files.append(file)
		
		#advance process count to maintain unique file names
		process_count += 1
		
	#return the two output files, any breakfiles generated and the split files for deletion
	return [dual_mono_output, intermediate_files, left, right]
	
func is_stereo(file: String) -> bool:
	if file != "none":
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
	return true
		
func get_samplerate(file: String) -> int:
	var output = await run_command(control_script.cdpprogs_location + "/sfprops", ["-r", file])
	output = int(output.strip_edges())
	return output

func merge_many_files(inlet_id: int, process_count: int, input_files: Array) -> Array:
	var merge_output = "%s_merge_%d_%d.wav" % [Global.outfile.get_basename(), inlet_id, process_count]
	var converted_files := []  # Track any mono->stereo converted files or upsampled files

	
	#check if sample rates of files to be mixed differ and upsample as required
	var match_sample_rates = await match_file_sample_rates(inlet_id, process_count, input_files)
	input_files = match_sample_rates[0]
	converted_files = match_sample_rates[1]
	
	#check if there are a mix of mono and stereo files and interleave mono files if required
	var match_channels = await match_file_channels(inlet_id, process_count, input_files)
	input_files = match_channels[0]
	converted_files += match_channels[1]

	# Merge all input files (converted or original)
	log_console("Mixing files to combined input.", true)
	var command := ["mergemany"]
	command += input_files
	command.append(merge_output)
	await run_command(control_script.cdpprogs_location + "/submix", command)
	
	if process_successful == false:
		log_console("Failed to to merge files to" + merge_output, true)
	
	return [merge_output, converted_files]

func match_file_sample_rates(inlet_id: int, process_count: int, input_files: Array) -> Array:
	var sample_rates := []
	var converted_files := []
	
	#Get all sample rates
	for f in input_files:
		var samplerate = await get_samplerate(f)
		sample_rates.append(samplerate)
	
	#Check if all sample rates are the same
	if sample_rates.all(func(v): return v == sample_rates[0]):
		pass
	else:
		log_console("Different sample rates found, upsampling files to match highest current sample rate before processing.", true)
		#if not find the highest sample rate
		var highest_sample_rate = sample_rates.max()
		var index = 0
		#move through all input files and compare match their index to the sample_rate array
		for f in input_files:
			#check if sample rate of current file is less than the highest sample rate
			if sample_rates[index] < highest_sample_rate:
				#up sample it to the highest sample rate if so
				var upsample_output = Global.outfile + "_" + str(inlet_id) + "_" + str(process_count) + f.get_file().get_slice(".wav", 0) + "_" + str(highest_sample_rate) + ".wav"
				await run_command(control_script.cdpprogs_location + "/housekeep", ["respec", "1", f, upsample_output, str(highest_sample_rate)])
				#replace the file in the input_file index with the new upsampled file
				input_files[index] = upsample_output
				converted_files.append(upsample_output)
				
			index += 1
	return [input_files, converted_files]
	
func match_file_channels(inlet_id: int, process_count: int, input_files: Array) -> Array:
	var converted_files := []
	var channel_counts := []
	
	# Check each file's channel count and build channel count array
	for f in input_files:
		var stereo = await is_stereo(f)
		channel_counts.append(stereo)

	# Check if there is a mix of mono and stereo files
	if channel_counts.has(true) and channel_counts.has(false):
		log_console("Mix of mono and stereo files found, interleaving mono files to stereo before mixing.", true)
		var index = 0
		for f in input_files:
			if channel_counts[index] == false: #file is mono
				var stereo_file = Global.outfile + "_" + str(inlet_id) + "_" + str(process_count) + f.get_file().get_slice(".wav", 0) + "_stereo.wav"
				await run_command(control_script.cdpprogs_location + "/submix", ["interleave", f, f, stereo_file])
				if process_successful == false:
					log_console("Failed to interleave mono file: %s" % f, true)
				else:
					converted_files.append(stereo_file)
					input_files[index] = stereo_file
			index += 1

	return [input_files, converted_files]
	

func _get_slider_values_ordered(node: Node) -> Array:
	var results := []
	for child in node.get_children():
		if child is Range:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			var time = child.get_meta("time")
			var brk_data = []
			var min_slider = child.min_value
			var max_slider = child.max_value
			var exp = child.exp_edit
			if child.has_meta("brk_data"):
				brk_data = child.get_meta("brk_data")
			results.append(["slider", flag, child.value, time, brk_data, min_slider, max_slider, exp])
		elif child is CheckButton:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			results.append(["checkbutton", flag, child.button_pressed])
		elif child is OptionButton:
			var flag = child.get_meta("flag") if child.has_meta("flag") else ""
			var value = child.get_item_text(child.selected)
			results.append(["optionbutton", flag, value])
		#call this function recursively to find any nested sliders in scenes
		if child.get_child_count() > 0:
			var nested := _get_slider_values_ordered(child)
			results.append_array(nested)
	return results



func make_process(node: Node, process_count: int, current_infile: Array, slider_data: Array) -> Array:
	# Determine output extension: .wav or .ana based on the node's slot type
	var extension = ".wav" if node.get_slot_type_right(0) == 0 else ".ana"

	# Construct output filename for this step
	var output_file = "%s_%d%s" % [Global.outfile.get_basename(), process_count, extension]

	# Get the command name from metadata or default to node name
	var command_name = str(node.get_meta("command"))
	command_name = command_name.split("_", true, 1)
	var command = "%s/%s" %[control_script.cdpprogs_location, command_name[0]]
	var args = command_name[1].split("_", true, 1)
	if current_infile.size() > 0:
		#check if input is empty, e.g. synthesis nodes, otherwise append input file to arguments
		for file in current_infile:
			args.append(file)
	args.append(output_file)

	# Start building the command line windows i dont think this is used anymore
	#var line = "%s/%s \"%s\" \"%s\" " % [control_script.cdpprogs_location, command_name, current_infile, output_file]
	#mac

	
	var cleanup = []

	# Append parameter values from the sliders, include flags if present
	var slider_count = 0
	for entry in slider_data:
		if entry[0] == "slider":
			var flag = entry[1]
			var value = entry[2]
			#if value == int(value):
				#value = int(value)
			var time = entry[3] #checks if slider is a time percentage slider
			var brk_data = entry[4]
			var min_slider = entry[5]
			var max_slider = entry[6]
			var exp = entry[7]
			if brk_data.size() > 0: #if breakpoint data is present on slider
				#Sort all points by time
				var sorted_brk_data = []
				sorted_brk_data = brk_data.duplicate()
				sorted_brk_data.sort_custom(sort_points)
				
				var calculated_brk = []
				
				#get length of input file in seconds
				var infile_length = 1 #set infile length to dummy value just incase it does get used where it shouldn't to avoid crashes
				if current_infile.size() > 0:
					infile_length = await run_command(control_script.cdpprogs_location + "/sfprops", ["-d", current_infile])
					infile_length = float(infile_length.strip_edges())
				
				#scale values from automation window to the right length for file and correct slider values
				#if node has an output duration then breakpoint files should be x = outputduration y= slider value else x=input duration, y=value
				if node.has_meta("outputduration"):
					for i in range(sorted_brk_data.size()):
						var point = sorted_brk_data[i]
						var new_x = float(node.get_meta("outputduration")) * (point.x / 700) #output time
						if i == sorted_brk_data.size() - 1: #check if this is last automation point
							new_x = float(node.get_meta("outputduration")) + 0.1  # force last point's x to infile_length + 100ms to make sure the file is defo over
						var new_y
						#check if slider is exponential and scale automation
						if exp:
							new_y = remap_y_to_log_scale(point.y, 0.0, 255.0, min_slider, max_slider)
						else:
							new_y = remap(point.y, 255, 0, min_slider, max_slider) #slider value
						if time: #check if this is a time slider and convert to percentage of input file
							new_y = infile_length * (new_y / 100)
						calculated_brk.append(Vector2(new_x, new_y))
				else:
					for i in range(sorted_brk_data.size()):
						var point = sorted_brk_data[i]
						var new_x = infile_length * (point.x / 700) #time
						if i == sorted_brk_data.size() - 1: #check if this is last automation point
							new_x = infile_length + 0.1  # force last point's x to infile_length + 100ms to make sure the file is defo over
						var new_y
						#check if slider is exponential and scale automation
						if exp:
							new_y = remap_y_to_log_scale(point.y, 0.0, 255.0, min_slider, max_slider)
						else:
							new_y = remap(point.y, 255, 0, min_slider, max_slider) #slider value
						calculated_brk.append(Vector2(new_x, new_y))
					
				#make text file
				var brk_file_path = output_file.get_basename() + "_" + str(slider_count) + ".txt"
				write_breakfile(calculated_brk, brk_file_path)
				
				#add breakfile to cleanup before adding flag
				cleanup.append(brk_file_path)
				
				#append text file in place of value
				#include flag if this param has a flag
				if flag.begins_with("-"):
					brk_file_path = flag + brk_file_path
				args.append(brk_file_path)
				
				
			else: #no break file append slider value
				if time == true:
					var infile_length = await run_command(control_script.cdpprogs_location + "/sfprops", ["-d", current_infile])
					infile_length = float(infile_length.strip_edges())
					if value == 100:
						#if slider is set to 100% default to a millisecond before the end of the file to stop cdp moaning about rounding errors
						value = infile_length - 0.01
					else:
						value = infile_length * (value / 100) #calculate percentage time of the input file
				#line += ("%s%.2f " % [flag, value]) if flag.begins_with("-") else ("%.2f " % value)
				args.append(("%s%.2f " % [flag, value]) if flag.begins_with("-") else str(value))
				
		elif entry[0] == "checkbutton":
			var flag = entry[1]
			var value = entry[2]
			#if button is pressed add the flag to the arguments list
			if value == true:
				args.append(flag)
				
		elif entry[0] == "optionbutton":
			var flag = entry[1]
			var value = entry[2]
			args.append(("%s%.2f " % [flag, value]) if flag.begins_with("-") else str(value))
			
		slider_count += 1
	return [command, output_file, cleanup, args]
	#return [line.strip_edges(), output_file, cleanup]

func remap_y_to_log_scale(y: float, min_y: float, max_y: float, min_val: float, max_val: float) -> float:
	var t = clamp((y - min_y) / (max_y - min_y), 0.0, 1.0)
	# Since y goes top-down (0 = top, 255 = bottom), we invert t
	t = 1.0 - t
	var log_min = log(min_val) / log(10)
	var log_max = log(max_val) / log(10)
	var log_val = lerp(log_min, log_max, t)
	return pow(10.0, log_val)


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
	var graph = {}
	var input_node_names = []
	var output_node_name = ""

	# Gather nodes and build empty graph
	for child in graph_edit.get_children():
		if child is GraphNode:
			var name = str(child.name)
			var command = child.get_meta("command")
			var input = child.get_meta("input")

			if input:
				input_node_names.append(name)
			elif command == "outputfile":
				output_node_name = name

			graph[name] = []  # Initialize adjacency list

	# Add connections (edges)
	for conn in graph_edit.get_connection_list():
		var from = str(conn["from_node"])
		var to = str(conn["to_node"])
		if graph.has(from):
			graph[from].append(to)

	# BFS to check if any input node reaches the output
	for input_node in input_node_names:
		var visited = {}
		var queue = [input_node]

		while queue.size() > 0:
			var current = queue.pop_front()

			if current == output_node_name:
				return true  # Path found

			if current in visited:
				continue
			visited[current] = true

			for neighbor in graph.get(current, []):
				queue.append(neighbor)

	# No path from any input node to output
	return false
	
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
