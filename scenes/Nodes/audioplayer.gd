extends Control

@onready var audio_player = $AudioStreamPlayer
@onready var file_dialog = $FileDialog
@onready var waveform_display = $WaveformPreview
var outfile_path = "not_loaded"
#signal recycle_outfile_trigger

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


func _on_play_button_button_down() -> void:
	if audio_player.stream:
		audio_player.play()
		$Playhead.position.x = 0
	
func _on_stop_button_button_down() -> void:
	if audio_player.playing:
		audio_player.stop()
		$Playhead.position.x = 0
		
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
		
		

#func _on_recycle_button_button_down() -> void:
	#if outfile_path != "not_loaded":
		#recycle_outfile_trigger.emit(outfile_path)
	
