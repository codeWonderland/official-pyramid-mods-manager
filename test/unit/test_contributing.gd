extends GutTest

# Tests the shared Contributing state: what each action needs before it's
# allowed, busy signalling, and picking up a copy the player made by hand in an
# earlier version.

var _root: String
var _saved_repo: String
var _saved_mods: String


func before_each() -> void:
	_root = ProjectSettings.globalize_path("user://test_contributing_%d" % randi())
	DirAccess.make_dir_recursive_absolute(_root)
	_saved_repo = UserSettingsManager.repo_location
	_saved_mods = UserSettingsManager.mods_location


func after_each() -> void:
	UserSettingsManager.set_repo_location(_saved_repo)
	UserSettingsManager.set_mods_location(_saved_mods)
	Contributing.use_runner(CommandRunner.new())
	Contributing.report = {}
	OS.execute("rm", ["-rf", _root])


func _fake_clone(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder.path_join(".git"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("PACKS"))


func test_nothing_is_allowed_before_the_first_check() -> void:
	Contributing.use_runner(FakeCommandRunner.new(), _root.path_join("copy"))
	Contributing.report = {}

	assert_false(Contributing.can_download(), "download")
	assert_false(Contributing.can_edit(), "edit")
	assert_false(Contributing.can_submit(), "submit")


func test_git_alone_is_enough_to_download_and_refresh() -> void:
	var copy := _root.path_join("copy")
	Contributing.use_runner(FakeCommandRunner.new(), copy)
	Contributing.report = {"git_ok": true, "ready": false}

	assert_true(Contributing.can_download(), "download needs only git")
	_fake_clone(copy)
	assert_true(Contributing.can_refresh(), "so does refresh")
	assert_false(Contributing.can_download(), "nothing to download once it's there")


func test_editing_needs_only_the_downloaded_mods() -> void:
	var copy := _root.path_join("copy")
	_fake_clone(copy)
	Contributing.use_runner(FakeCommandRunner.new(), copy)
	Contributing.report = {}

	assert_true(Contributing.can_edit(), "no git or GitHub needed to edit")


func test_submitting_needs_everything() -> void:
	var copy := _root.path_join("copy")
	_fake_clone(copy)
	Contributing.use_runner(FakeCommandRunner.new(), copy)

	Contributing.report = {"git_ok": true, "gh_ok": true, "ready": false}
	assert_false(Contributing.can_submit(), "not while signed out")

	Contributing.report = {"ready": true}
	assert_true(Contributing.can_submit(), "once everything is in place")


func test_operations_announce_that_they_are_busy() -> void:
	Contributing.use_runner(FakeCommandRunner.new(), _root.path_join("copy"))
	watch_signals(Contributing)

	await Contributing.check()

	assert_signal_emitted_with_parameters(Contributing, "busy_changed", [false, ""])
	assert_signal_emit_count(Contributing, "busy_changed", 2)
	assert_false(Contributing.busy, "idle again afterwards")


func test_a_chosen_copy_must_be_a_mods_repo() -> void:
	assert_false(Contributing.is_mods_repo(_root), "an empty folder is not")
	_fake_clone(_root)
	assert_true(Contributing.is_mods_repo(_root), "a git folder with PACKS is")


func test_a_hand_made_copy_from_an_earlier_version_is_kept() -> void:
	var copy := _root.path_join("my-clone")
	_fake_clone(copy)
	UserSettingsManager.set_repo_location("")
	UserSettingsManager.set_mods_location(copy.path_join("PACKS"))

	Contributing._migrate_old_mods_location()

	assert_eq(UserSettingsManager.repo_location, copy, "carried over as the player's own copy")


func test_an_old_folder_that_isnt_a_repo_is_left_alone() -> void:
	DirAccess.make_dir_recursive_absolute(_root.path_join("loose/PACKS"))
	UserSettingsManager.set_repo_location("")
	UserSettingsManager.set_mods_location(_root.path_join("loose/PACKS"))

	Contributing._migrate_old_mods_location()

	assert_eq(UserSettingsManager.repo_location, "", "the app's own copy is used instead")
