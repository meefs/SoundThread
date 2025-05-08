extends VBoxContainer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HSplitContainer/ValueLabel.text = str($"HSplitContainer/-s".value) # initial value
	pass


func _on_s_value_changed(value: float) -> void:
	$HSplitContainer/ValueLabel.text = str(value)
