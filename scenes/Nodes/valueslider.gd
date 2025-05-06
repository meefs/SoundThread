extends VBoxContainer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HSplitContainer/ValueLabel.text = str($HSplitContainer/HSlider.value) # initial value
	pass


func _on_h_slider_value_changed(value: float) -> void:
	$HSplitContainer/ValueLabel.text = str(value)
