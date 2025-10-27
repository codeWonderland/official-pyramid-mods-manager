extends Node

const SAVE_PATH = "user://settings.cfg"

var config := ConfigFile.new()

# settings
var mods_location: String = ""


func _ready() -> void:
	config.load(SAVE_PATH)

	_load_config()

	_save_config()


func set_mods_location(location: String) -> void:
	mods_location = location
	_save_config()


func _load_config() -> void:
	if config.has_section("settings"):
		mods_location = config.get_value("settings", "mods_location", "")


func _save_config() -> void:
	config.set_value("settings", "mods_location", mods_location)

	config.save(SAVE_PATH)
