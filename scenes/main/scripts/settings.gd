extends Window
signal open_cdp_location
signal console_on_top
signal invert_ui
signal swap_zoom_and_move

var interface_settings
var main_theme = preload("res://theme/main_theme.tres")
var cdpprogs_location



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
	$VBoxContainer/high_contrast_cables_container/HighContrastCablesToggle.button_pressed = interface_settings.high_contrast_selected_cables
	$VBoxContainer/HBoxContainer8/SwapZoomAndMoveToggle.button_pressed = interface_settings.swap_zoom_and_move
	$VBoxContainer/HBoxContainer2/PvocWarning.button_pressed = interface_settings.disable_pvoc_warning
	$VBoxContainer/HBoxContainer6/ProgressBar.button_pressed = interface_settings.disable_progress_bar
	$VBoxContainer/HBoxContainer3/AutoCloseConsole.button_pressed = interface_settings.auto_close_console
	$VBoxContainer/HBoxContainer4/ConsoleAlwaysOnTop.button_pressed = interface_settings.console_on_top
	$VBoxContainer/HBoxContainer7/cdprogsLocationLabel.text = cdpprogs_location
	$VBoxContainer/HBoxContainer7.tooltip_text = cdpprogs_location
	

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
		

func _on_invert_ui_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("invert_theme", toggled_on)
	invert_ui.emit(toggled_on)


func _on_swap_zoom_and_move_toggle_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("swap_zoom_and_move", toggled_on)
	swap_zoom_and_move.emit(toggled_on)


func _on_high_contrast_cables_toggle_toggled(toggled_on: bool) -> void:
	ConfigHandler.save_interface_settings("high_contrast_selected_cables", toggled_on)
