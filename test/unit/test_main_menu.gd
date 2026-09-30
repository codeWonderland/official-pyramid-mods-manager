extends GutTest

# Tests the main menu: the setup checklist, which actions it allows, and the
# refresh / submit / submissions flows, all against a fake runner.

const MAIN_MENU: PackedScene = preload("res://source/menus/main_menu.tscn")
const READY_STATUS: String = " M PACKS/alpha/p2.png\n"

var _root: String
var _copy: String


func before_each() -> void:
	_root = ProjectSettings.globalize_path("user://test_main_menu_%d" % randi())
	_copy = _root.path_join("copy")


func after_each() -> void:
	Contributing.use_runner(CommandRunner.new())
	Contributing.report = {}
	OS.execute("rm", ["-rf", _root])


func _fake_clone() -> void:
	DirAccess.make_dir_recursive_absolute(_copy.path_join(".git"))
	DirAccess.make_dir_recursive_absolute(_copy.path_join("PACKS"))


func _all_set_up() -> FakeCommandRunner:
	return (
		FakeCommandRunner
		. new()
		. on("git --version", 0, "git version 2.43.0")
		. on("gh --version", 0, "gh version 2.45.0")
		. on("gh api user --jq .login", 0, "alice")
	)


func _menu(runner: FakeCommandRunner) -> MainMenu:
	Contributing.use_runner(runner, _copy)
	var menu := MAIN_MENU.instantiate() as MainMenu
	add_child_autofree(menu)
	await wait_for_signal(Contributing.state_changed, 2)
	await get_tree().process_frame
	return menu


func _row_texts(menu: MainMenu) -> String:
	var texts := PackedStringArray()
	for label in menu._setup_list.find_children("*", "Label", true, false):
		texts.append(label.text)
	return "\n".join(texts)


# --- Checklist ---


func test_a_complete_setup_shows_every_item_ready() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	var text := _row_texts(menu)
	assert_string_contains(text, "git version 2.43.0", "git found")
	assert_string_contains(text, "Signed in as alice", "account")
	assert_string_contains(text, "Ready to edit", "mods downloaded")


func test_missing_git_offers_the_download() -> void:
	var menu := await _menu(FakeCommandRunner.new().on("git --version", CommandRunner.NOT_FOUND))

	var buttons: Array = []
	for button in menu._setup_list.find_children("*", "Button", true, false):
		buttons.append(button.text)
	assert_has(buttons, "Get Git", "a way to fix it")


func test_signed_out_shows_the_command_to_copy() -> void:
	var menu := await _menu(_all_set_up().on("gh auth status", 1, "not logged in"))

	assert_string_contains(_row_texts(menu), Toolchain.SIGN_IN_COMMAND, "the command")
	var copy_buttons := menu._setup_list.find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Copy"
	)
	assert_eq(copy_buttons.size(), 1, "with a button to copy it")


func test_not_yet_downloaded_offers_the_download() -> void:
	var menu := await _menu(_all_set_up())

	assert_string_contains(_row_texts(menu), "Not downloaded yet.", "says so")
	var download := menu._setup_list.find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Download"
	)
	assert_eq(download.size(), 1, "and offers to")
	assert_false(download[0].disabled, "enabled once git is there")


# --- Which actions are allowed ---


func test_everything_is_enabled_when_set_up() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	for button in [
		menu._edit_button, menu._refresh_button, menu._submit_button, menu._submissions_button
	]:
		assert_false(button.disabled, "%s enabled" % button.text)


func test_signed_out_can_still_edit_but_not_submit() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up().on("gh auth status", 1, "not logged in"))

	assert_false(menu._edit_button.disabled, "editing needs no GitHub account")
	assert_false(menu._refresh_button.disabled, "nor does getting the latest")
	assert_true(menu._submit_button.disabled, "submitting does")
	assert_true(menu._submissions_button.disabled, "and so do submissions")


func test_nothing_to_edit_before_downloading() -> void:
	var menu := await _menu(_all_set_up())

	assert_true(menu._edit_button.disabled, "nothing to edit yet")


# --- Flows ---


func test_refresh_with_unsubmitted_edits_asks_first() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up().on("status --porcelain", 0, READY_STATUS))

	await menu.refresh()

	assert_true(menu._discard_dialog.visible, "asks before discarding")
	assert_string_contains(menu._discard_dialog._message.text, "alpha", "names the pack")


func test_submit_with_no_edits_says_so_instead_of_opening() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up().on("status --porcelain", 0, ""))

	await menu.open_submit()

	assert_false(menu._submit_dialog.visible, "nothing to submit")
	assert_string_contains(menu._message.text, "haven't edited any packs", "explains why")


func test_submit_opens_with_the_changed_packs() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up().on("status --porcelain", 0, READY_STATUS))

	await menu.open_submit()

	assert_true(menu._submit_dialog.visible, "opened")
	assert_string_contains(menu._submit_dialog._packs_label.text, "alpha", "lists the packs")


func test_a_successful_submission_links_to_the_pr() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	menu._submit_dialog.show_result({"ok": true, "url": "https://github.com/x/y/pull/9"})

	assert_true(menu._submit_dialog._open_button.visible, "offers the link")
	assert_eq(menu._submit_dialog._url, "https://github.com/x/y/pull/9", "to the new PR")


func test_a_failed_submission_explains_itself() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	menu._submit_dialog.show_result(
		{"ok": false, "message": "Couldn't upload.", "detail": "fatal: no network"}
	)

	assert_string_contains(menu._submit_dialog._result_label.text, "Couldn't upload.", "what")
	assert_string_contains(menu._submit_dialog._result_label.text, "no network", "and why")
	assert_false(menu._submit_dialog._submit_button.disabled, "and allows another try")


func test_submissions_are_listed_with_their_status() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	(
		menu
		. _submissions_dialog
		. show_submissions(
			{
				"ok": true,
				"submissions":
				[
					{
						"number": 7,
						"title": "Add Balatro",
						"url": "https://github.com/x/y/pull/7",
						"checks": "passing",
						"review": "approved",
					}
				],
			}
		)
	)

	var texts := PackedStringArray()
	for label in menu._submissions_dialog._list.find_children("*", "Label", true, false):
		texts.append(label.text)
	assert_string_contains("\n".join(texts), "#7  Add Balatro", "the PR")
	assert_string_contains("\n".join(texts), "Checks: passing  -  Review: approved", "its status")


func test_no_submissions_says_so() -> void:
	_fake_clone()
	var menu := await _menu(_all_set_up())

	menu._submissions_dialog.show_submissions({"ok": true, "submissions": []})

	assert_eq(menu._submissions_dialog._status_label.text, "You have no open submissions.", "empty")
