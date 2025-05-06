extends GraphNode


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$VBoxContainer3/HSplitContainer/ValueLabel.text = str($"VBoxContainer3/HSplitContainer/-d".value) # initial value
	$VBoxContainer4/HSplitContainer/ValueLabel.text = str($"VBoxContainer4/HSplitContainer/-g".value) # initial value


func _on_g_value_changed(value: float) -> void:
	$VBoxContainer4/HSplitContainer/ValueLabel.text = str(value)


func _on_d_value_changed(value: float) -> void:
	$VBoxContainer3/HSplitContainer/ValueLabel.text = str(value)
