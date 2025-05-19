extends GraphNode


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var titlebar = self.get_titlebar_hbox()
	var btn = Button.new()
	btn.text = "?"
	btn.connect("pressed", Callable(self, "_open_help").bind("help_pressed")) #pass key (process name) when button is pressed
	titlebar.add_child(btn)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _open_help(key: String):
	print(key)
