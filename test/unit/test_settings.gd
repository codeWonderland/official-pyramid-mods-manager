extends GutTest

# Smoke tests for the app's own settings and the wrapper that hosts the shared
# mod manager.

const WRAPPER: PackedScene = preload("res://source/menus/mod_manager_wrapper.tscn")

var _saved_location: String


func before_each() -> void:
	_saved_location = UserSettingsManager.mods_location


func after_each() -> void:
	UserSettingsManager.set_mods_location(_saved_location)


func test_mods_location_persists() -> void:
	UserSettingsManager.set_mods_location("user://somewhere")

	var config := ConfigFile.new()
	assert_eq(config.load(UserSettingsManager.SAVE_PATH), OK, "settings written")
	assert_eq(config.get_value("settings", "mods_location"), "user://somewhere", "and saved")


func test_wrapper_points_the_mod_manager_at_the_mods_folder() -> void:
	var folder := "user://test_wrapper_mods_%d" % randi()
	DirAccess.make_dir_recursive_absolute(folder)
	UserSettingsManager.set_mods_location(folder)

	var wrapper := WRAPPER.instantiate()
	add_child_autofree(wrapper)
	await get_tree().process_frame

	var manager = wrapper.get_child(0)
	assert_eq(manager.mods_path, folder + "/", "the shared editor edits the chosen folder")
	DirAccess.remove_absolute(folder)
