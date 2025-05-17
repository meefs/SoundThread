extends Control

@onready var item_list = $VBoxContainer/ItemList
@onready var device_timer = $DevicePollTimer

func _ready():
	for item in AudioServer.get_output_device_list():
		item_list.add_item(item)

	var device = AudioServer.get_output_device()
	for i in range(item_list.get_item_count()):
		if device == item_list.get_item_text(i):
			item_list.select(i)
			break
	
	$VBoxContainer/DeviceInfo.text = "Current Device: " + AudioServer.get_output_device()


func _process(_delta):
	#var speaker_mode_text = "Stereo"
	#var speaker_mode = AudioServer.get_speaker_mode()
#
	#if speaker_mode == AudioServer.SPEAKER_SURROUND_31:
		#speaker_mode_text = "Surround 3.1"
	#elif speaker_mode == AudioServer.SPEAKER_SURROUND_51:
		#speaker_mode_text = "Surround 5.1"
	#elif speaker_mode == AudioServer.SPEAKER_SURROUND_71:
		#speaker_mode_text = "Surround 7.1"
	#$VBoxContainer/DeviceInfo.text += "Speaker Mode: " + speaker_mode_text
	#$VBoxContainer/DeviceInfo.text = "Current Device: " + AudioServer.get_output_device()
	pass


func _on_item_list_item_selected(index: int) -> void:
	var device = item_list.get_item_text(index)
	AudioServer.set_output_device(device)
	$VBoxContainer/DeviceInfo.text = "Current Device: " + device
