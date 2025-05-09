extends Node

var config = ConfigFile.new()
const SETTINGS_FILE_PATH = "user://settings.ini"

func _ready():
	if !FileAccess.file_exists(SETTINGS_FILE_PATH):
		config.set_value("cdpprogs", "location", "no_location")
		config.set_value("interface_settings", "disable_pvoc_warning", false)
		config.set_value("interface_settings", "auto_close_console", false)
		config.save(SETTINGS_FILE_PATH)
	else:
		config.load(SETTINGS_FILE_PATH)
	

func save_cdpprogs_settings(location: String):
	config.set_value("cdpprogs", "location", location)
	config.save(SETTINGS_FILE_PATH)
	
func load_cdpprogs_settings():
	var cdpprogs_settings = {}
	for key in config.get_section_keys("cdpprogs"):
		cdpprogs_settings[key] = config.get_value("cdpprogs", key)
	return cdpprogs_settings

func save_interface_settings(key: String, value):
	config.set_value("interface_settings", key, value)
	config.save(SETTINGS_FILE_PATH)

func load_interface_settings():
	var interface_settings = {}
	for key in config.get_section_keys("interface_settings"):
		interface_settings[key] = config.get_value("interface_settings", key)
	return interface_settings
