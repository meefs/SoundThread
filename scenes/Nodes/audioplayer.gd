extends Control

@onready var audio_player = $AudioStreamPlayer
@onready var file_dialog = $FileDialog
@onready var waveform_display = $WaveformPreview
var outfile_path = "not_loaded"
#signal recycle_outfile_trigger
var rect_focus = false
var mouse_pos_x

#Used for waveform preview
var voice_preview_generator : Node = null
var stream : AudioStreamWAV = null

func _ready():
	#Setup file dialogue to access system files and only accept wav files
	#get_window().files_dropped.connect(_on_files_dropped)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = ["*.wav ; WAV audio files"]
	file_dialog.connect("file_selected", Callable(self, "_on_file_selected"))
	audio_player.connect("finished", Callable(self, "_on_audio_finished"))
	
	if get_meta("loadenable") == true:
		$RecycleButton.hide()
		$LoadButton.show()
	else:
		$LoadButton.hide()
		$RecycleButton.show()
	
	$WavError.hide()
	
	# Load the voice preview generator for waveform visualization
	voice_preview_generator = preload("res://addons/audio_preview/voice_preview_generator.tscn").instantiate()
	add_child(voice_preview_generator)
	voice_preview_generator.texture_ready.connect(_on_texture_ready)

#func _on_files_dropped(files):
	#if files[0].get_extension() == "wav" or files[0].get_extension() == "WAV":
		#audio_player.stream = AudioStreamWAV.load_from_file(files[0])
		#if audio_player.stream.stereo == true: #checks if stream is stereo, not sure what this will do with a surround sound file
			#audio_player.stream = null #empties audio stream so stereo audio cant be played back
			#$WavError.show()
		#else:
			#voice_preview_generator.generate_preview(audio_player.stream) #this generates the waveform graphic
			#Global.infile = files[0] #this sets the global infile variable to the audio file path
			#print(Global.infile)
	#else:
		#$WavError.show()

func _on_close_button_button_down() -> void:
	$WavError.hide()

func _on_load_button_button_down() -> void:
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	audio_player.stream = AudioStreamWAV.load_from_file(path)
	Global.infile_stereo = audio_player.stream.stereo
	#if audio_player.stream.stereo == true:
		##audio_player.stream = null
		##$WavError.show()
	voice_preview_generator.generate_preview(audio_player.stream)
	Global.infile = path
	print("Infile set: " + Global.infile)
	$LoopRegion.size.x = 0
	$Playhead.position.x = 0
	
func play_outfile(path: String):
	outfile_path = path
	audio_player.stream = AudioStreamWAV.load_from_file(path)
	voice_preview_generator.generate_preview(audio_player.stream)

	
func recycle_outfile(path: String):
	audio_player.stream = AudioStreamWAV.load_from_file(path)
	Global.infile_stereo = audio_player.stream.stereo
	#if audio_player.stream.stereo == true:
		##audio_player.stream = null
		##$WavError.show()
	voice_preview_generator.generate_preview(audio_player.stream)
	Global.infile = path
	print("Infile set: " + Global.infile)
	$LoopRegion.size.x = 0
	$Playhead.position.x = 0


func _on_play_button_button_down() -> void:
	var playhead_position
	#check if trim markers are set and set playhead position to correct location
	if $LoopRegion.size.x == 0:
		playhead_position = 0
	else:
		playhead_position = $LoopRegion.position.x
	
	$Playhead.position.x = playhead_position
	
	#check if audio is playing, to decide if this is a play or stop button
	if audio_player.stream:
		if audio_player.playing:
			audio_player.stop()
			$Timer.stop()
			$PlayButton.text = "Play"
		else:
			$PlayButton.text = "Stop"
			if $LoopRegion.size.x == 0: #loop position is not set, play from start of file
				audio_player.play()
			else:
				var length = $AudioStreamPlayer.stream.get_length()
				var pixel_to_time = length / 399
				audio_player.play(pixel_to_time * $LoopRegion.position.x)
				if $LoopRegion.position.x + $LoopRegion.size.x < 399:
					$Timer.start(pixel_to_time * $LoopRegion.size.x)
				

#timer for ending playback at end of loop
func _on_timer_timeout() -> void:
	_on_play_button_button_down() #"press" stop button

func _on_audio_finished():
	$PlayButton.text = "Play"


# This function will be called when the waveform texture is ready
func _on_texture_ready(image_texture: ImageTexture):
	# Set the generated texture to the TextureRect (waveform display node)
	waveform_display.texture = image_texture
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if $AudioStreamPlayer.playing:
		var length = $AudioStreamPlayer.stream.get_length()
		var total_distance = 399.0
		var speed = total_distance / length
		$Playhead.position.x += speed * delta
		if $Playhead.position.x >= 399:
			$Playhead.position.x = 0
	
	if rect_focus == true:
		if get_local_mouse_position().x > mouse_pos_x:
			$LoopRegion.size.x = clamp(get_local_mouse_position().x - mouse_pos_x, 0, $Panel.size.x - (mouse_pos_x - $Panel.position.x))
		else:
			$LoopRegion.size.x = clamp(mouse_pos_x - get_local_mouse_position().x, 0, (mouse_pos_x - $Panel.position.x))
			$LoopRegion.position.x = clamp(get_local_mouse_position().x, $Panel.position.x, $Panel.position.x + $Panel.size.x)

#func _on_recycle_button_button_down() -> void:
	#if outfile_path != "not_loaded":
		#recycle_outfile_trigger.emit(outfile_path)
	



	

func _on_button_button_down() -> void:
	if audio_player.playing: #if audio is playing allow user to skip around the sound file
		$Timer.stop()
		var length = $AudioStreamPlayer.stream.get_length()
		var pixel_to_time = length / 399
		$Playhead.position.x = get_local_mouse_position().x
		if $LoopRegion.size.x == 0 or get_local_mouse_position().x > $LoopRegion.position.x + $LoopRegion.size.x: #loop position is not set or click is after loop position, play to end of file
			audio_player.seek(pixel_to_time * get_local_mouse_position().x)
		else: #if click position is before the loop position play from there and stop at the end of the loop position
			audio_player.seek(pixel_to_time * get_local_mouse_position().x)
			if $LoopRegion.position.x + $LoopRegion.size.x < 399:
				$Timer.start(pixel_to_time * ($LoopRegion.position.x + $LoopRegion.size.x - get_local_mouse_position().x))
	else:
		mouse_pos_x = get_local_mouse_position().x
		$LoopRegion.position.x = mouse_pos_x
		rect_focus = true


func _on_button_button_up() -> void:
	rect_focus = false
	if get_meta("loadenable") == true:
		print("got meta")
		if $LoopRegion.size.x > 0:
			Global.trim_infile = true
			var length = $AudioStreamPlayer.stream.get_length()
			var pixel_to_time = length / 399
			Global.infile_start = pixel_to_time * $LoopRegion.position.x
			Global.infile_stop = Global.infile_start + (pixel_to_time * $LoopRegion.size.x)
			print(Global.trim_infile)
			print(Global.infile_start)
			print(Global.infile_stop)
		else:
			Global.trim_infile = false
			print(Global.trim_infile)
	
