extends GraphNode

var calulated = false
var expression = ""
signal open_help

func _ready() -> void:
	#add button to title bar
	var titlebar = self.get_titlebar_hbox()
	var btn = Button.new()
	btn.text = "?"
	btn.tooltip_text = "Open help for " + self.title
	btn.connect("pressed", Callable(self, "_open_help")) #pass key (process name) when button is pressed
	titlebar.add_child(btn)
	
	#this links the buttons, it is stupid but for some reason doing this automatically just would not work reliably
	$HBoxContainer/Button.pressed.connect(calculate.bind($HBoxContainer/Button))
	$HBoxContainer/Button2.pressed.connect(calculate.bind($HBoxContainer/Button2))
	$HBoxContainer/Button3.pressed.connect(calculate.bind($HBoxContainer/Button3))
	$HBoxContainer/Button4.pressed.connect(calculate.bind($HBoxContainer/Button4))
	$HBoxContainer5/Button.pressed.connect(calculate.bind($HBoxContainer5/Button))
	$HBoxContainer5/Button2.pressed.connect(calculate.bind($HBoxContainer5/Button2))
	$HBoxContainer5/Button3.pressed.connect(calculate.bind($HBoxContainer5/Button3))
	$HBoxContainer5/Button4.pressed.connect(calculate.bind($HBoxContainer5/Button4))
	$HBoxContainer2/Button.pressed.connect(calculate.bind($HBoxContainer2/Button))
	$HBoxContainer2/Button2.pressed.connect(calculate.bind($HBoxContainer2/Button2))
	$HBoxContainer2/Button3.pressed.connect(calculate.bind($HBoxContainer2/Button3))
	$HBoxContainer2/Button4.pressed.connect(calculate.bind($HBoxContainer2/Button4))
	$HBoxContainer3/Button.pressed.connect(calculate.bind($HBoxContainer3/Button))
	$HBoxContainer3/Button2.pressed.connect(calculate.bind($HBoxContainer3/Button2))
	$HBoxContainer3/Button3.pressed.connect(calculate.bind($HBoxContainer3/Button3))
	$HBoxContainer3/Button4.pressed.connect(calculate.bind($HBoxContainer3/Button4))
	$HBoxContainer4/Button.pressed.connect(calculate.bind($HBoxContainer4/Button))
	$HBoxContainer4/Button2.pressed.connect(calculate.bind($HBoxContainer4/Button2))
	$HBoxContainer4/Button3.pressed.connect(calculate.bind($HBoxContainer4/Button3))
	$HBoxContainer4/Button4.pressed.connect(calculate.bind($HBoxContainer4/Button4))
	
func _open_help():
	open_help.emit(self.get_meta("command"), self.title)
	
func calculate(button: Button):
	print("button pressed")
	var label = button.text
	var value = button.get_meta("calc")
	print(label)
	print(value)
	
	if value == "clear":
		$Screen.text = ""
	elif value == "del":
		$Screen.text = $Screen.text.substr(0, $Screen.text.length() - 1)
	elif value == "=":
		pass
	else:
		$Screen.text += label
