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


func test_wrapper_points_the_mod_manager_at_the_copys_packs() -> void:
	var folder := ProjectSettings.globalize_path("user://test_wrapper_repo_%d" % randi())
	DirAccess.make_dir_recursive_absolute(folder.path_join("PACKS"))
	Contributing.use_runner(FakeCommandRunner.new(), folder)

	var wrapper := WRAPPER.instantiate()
	add_child_autofree(wrapper)
	await get_tree().process_frame

	var manager = wrapper.get_child(0)
	assert_eq(
		manager.mods_path, folder.path_join("PACKS") + "/", "the editor edits the copy's packs"
	)

	Contributing.use_runner(CommandRunner.new())
	OS.execute("rm", ["-rf", folder])
