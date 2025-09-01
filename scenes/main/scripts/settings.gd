extends Window
signal open_cdp_location
signal console_on_top
var interface_settings
var main_theme = preload("res://theme/main_theme.tres")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


func _on_change_cdp_button_down() -> void:
	self.hide()
	open_cdp_location.emit()
	

func _on_close_requested() -> void:
	self.hide()


func _on_about_to_popup() -> void:
	interface_settings = ConfigHandler.load_interface_settings()
	$VBoxContainer/HBoxContainer5/ThemeList.select(interface_settings.theme, true)
	$VBoxContainer/HBoxContainer/CustomColourPicker.color = Color(interface_settings.theme_custom_colour)
	$VBoxContainer/invert_ui_container/InvertUI.button_pressed = interface_settings.invert_theme
	$VBoxContainer/HBoxContainer2/PvocWarning.button_pressed = interface_settings.disable_pvoc_warning
	$VBoxContainer/HBoxContainer6/ProgressBar.button_pressed = interface_settings.disable_progress_bar
	$VBoxContainer/HBoxContainer3/AutoCloseConsole.button_pressed = interface_settings.auto_close_console
	$VBoxContainer/HBoxContainer4/ConsoleAlwaysOnTop.button_pressed = interface_settings.console_on_top
	

func _on_pvoc_warning_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("disable_pvoc_warning", toggled_on)

func _on_progress_bar_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("disable_progress_bar", toggled_on)



func _on_auto_close_console_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("auto_close_console", toggled_on)
	

func _on_console_always_on_top_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("console_on_top", toggled_on)
	console_on_top.emit(toggled_on)


func _on_theme_list_item_selected(index: int) -> void:
	interface_settings = ConfigHandler.load_interface_settings()
	ConfigHandler.save_interface_settings("theme", index)
	match index:
		0:
			RenderingServer.set_default_clear_color(Color("#2f4f4e"))
		1:
			RenderingServer.set_default_clear_color(Color("#000807"))
		2:
			RenderingServer.set_default_clear_color(Color("#98d4d2"))
		3:
			RenderingServer.set_default_clear_color(Color(interface_settings.theme_custom_colour))


func _on_custom_colour_picker_color_changed(color: Color) -> void:
	ConfigHandler.save_interface_settings("theme_custom_colour", color.to_html(false))
	if $VBoxContainer/HBoxContainer5/ThemeList.is_selected(3):
		RenderingServer.set_default_clear_color(color)
		
func invert_theme(theme: Theme) -> Theme:
	var inverted_theme = theme.duplicate(true) # deep copy

	# Check all types and color names in the theme
	var types = inverted_theme.get_type_list()
	for type in types:
		var color_names = inverted_theme.get_color_list(type)
		for cname in color_names:
			var col = inverted_theme.get_color(cname, type)
			var inverted = Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, col.a)
			inverted_theme.set_color(cname, type, inverted)

		var style_names = inverted_theme.get_stylebox_list(type)
		for sname in style_names:
			if type == "GraphEdit" and sname == "panel":
				continue
			var sb = inverted_theme.get_stylebox(sname, type)
			var new_sb = sb.duplicate()
			if new_sb is StyleBoxFlat:
				var col = new_sb.bg_color
				new_sb.bg_color = Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, col.a)
			inverted_theme.set_stylebox(sname, type, new_sb)
	
	return inverted_theme
	

func _on_invert_ui_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("invert_theme", toggled_on)
	if toggled_on:
		print("invert toggled on")
		var inverted = invert_theme(main_theme)
		get_tree().root.theme = inverted # force refresh
	else:
		get_tree().root.theme = main_theme # force refresheme = main_theme
