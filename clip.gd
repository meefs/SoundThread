extends GraphNode


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Label.text = "0.00" # initial value


func _on_h_slider_2_value_changed(value: float) -> void:
	$Label.text = str(value)
