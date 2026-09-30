extends Node

const SAVE_PATH = "user://settings.cfg"

var config := ConfigFile.new()

# settings
var mods_location: String = ""
## A copy of pyramid-mods the player chose themselves. Empty means the app's own
## managed copy, which is what most people use.
var repo_location: String = ""


func _ready() -> void:
	config.load(SAVE_PATH)

	_load_config()

	_save_config()


func set_mods_location(location: String) -> void:
	mods_location = location
	_save_config()


func set_repo_location(location: String) -> void:
	repo_location = location
	_save_config()


func _load_config() -> void:
	if config.has_section("settings"):
		mods_location = config.get_value("settings", "mods_location", "")
		repo_location = config.get_value("settings", "repo_location", "")


func _save_config() -> void:
	config.set_value("settings", "mods_location", mods_location)
	config.set_value("settings", "repo_location", repo_location)

	config.save(SAVE_PATH)
