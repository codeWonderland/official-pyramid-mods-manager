class_name MainMenu extends Control

## The app's home screen: a checklist of what contributing needs, with a fix for
## each missing piece, and the things a contributor does - edit packs, get the
## latest from GitHub, submit changes, and follow up on submissions.

const ICON_OK: Texture2D = preload("res://assets/sprites/ui/icons/confirm.png")
const ICON_MISSING: Texture2D = preload("res://assets/sprites/ui/icons/close.png")
const ICON_SIZE: Vector2 = Vector2(40, 40)

var _busy_message: String = ""

@onready var _title: Label = %Title
@onready var _exit_button: TextureButton = %Exit
@onready var _github_button: TextureButton = %Github
@onready var _setup_list: VBoxContainer = %SetupList
@onready var _check_again_button: Button = %CheckAgain
@onready var _edit_button: Button = %EditMods
@onready var _refresh_button: Button = %Refresh
@onready var _submit_button: Button = %Submit
@onready var _submissions_button: Button = %Submissions
@onready var _message: Label = %Message
@onready var _own_copy_button: Button = %OwnCopy
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _submit_dialog: SubmitDialog = %SubmitDialog
@onready var _submissions_dialog: SubmissionsDialog = %SubmissionsDialog
@onready var _discard_dialog: DiscardDialog = %DiscardDialog


func _ready() -> void:
	_setup_ui()

	_exit_button.pressed.connect(_close_game)
	_github_button.pressed.connect(_open_github)
	_check_again_button.pressed.connect(check)
	_edit_button.pressed.connect(_edit_mods)
	_refresh_button.pressed.connect(refresh)
	_submit_button.pressed.connect(open_submit)
	_submissions_button.pressed.connect(_submissions_dialog.open)
	_own_copy_button.pressed.connect(_toggle_own_copy)
	_discard_dialog.discard_confirmed.connect(func() -> void: refresh(true))
	_submit_dialog.submitted.connect(func(_url: String) -> void: update())

	Contributing.state_changed.connect(update)
	Contributing.busy_changed.connect(_on_busy_changed)

	update()
	await check()


func check() -> void:
	await Contributing.check()


## Redraws the checklist and enables only the actions that can work right now.
func update() -> void:
	for child in _setup_list.get_children():
		_setup_list.remove_child(child)
		child.queue_free()

	var report := Contributing.report
	var checked := not report.is_empty()
	_add_git_row(report, checked)
	_add_gh_row(report, checked)
	_add_account_row(report, checked)
	_add_mods_row()

	var idle := not Contributing.busy
	_check_again_button.disabled = not idle
	_edit_button.disabled = not (idle and Contributing.can_edit())
	_refresh_button.disabled = not (idle and Contributing.can_refresh())
	_submit_button.disabled = not (idle and Contributing.can_submit())
	_submissions_button.disabled = not (idle and Contributing.can_submit())
	_own_copy_button.text = (
		"Use the app's own copy"
		if not UserSettingsManager.repo_location.is_empty()
		else "Use my own copy..."
	)


## Gets the latest mods from GitHub - asking first if that would throw edits away.
func refresh(discard_changes: bool = false) -> void:
	var result := await Contributing.refresh(discard_changes)
	if result.get("needs_confirmation", false):
		_discard_dialog.open_for(result.changed)
		return
	show_result(result, "You have the latest mods from GitHub.")


func open_submit() -> void:
	var changed := await Contributing.repo.changed_packs()
	if changed.is_empty():
		_message.text = "You haven't edited any packs yet. Edit some first, then submit them."
		return
	_submit_dialog.open_for(changed)


func show_result(result: Dictionary, success: String) -> void:
	if result.get("ok", false):
		_message.text = success
		return
	var text: String = result.get("message", "Something went wrong.")
	if not str(result.get("detail", "")).is_empty():
		text += "\n" + str(result.detail)
	_message.text = text


# --- Checklist rows ---


func _add_git_row(report: Dictionary, checked: bool) -> void:
	if report.get("git_ok", false):
		_add_row(true, "Git", report.git_version)
	else:
		_add_row(
			false,
			"Git",
			_problem_text(report, Toolchain.GIT_DOWNLOAD, checked),
			_link_button("Get Git", Toolchain.GIT_DOWNLOAD)
		)


func _add_gh_row(report: Dictionary, checked: bool) -> void:
	if report.get("gh_ok", false):
		_add_row(true, "GitHub CLI", report.gh_version)
	else:
		_add_row(
			false,
			"GitHub CLI",
			_problem_text(report, Toolchain.GH_DOWNLOAD, checked),
			_link_button("Get the GitHub CLI", Toolchain.GH_DOWNLOAD)
		)


func _add_account_row(report: Dictionary, checked: bool) -> void:
	if report.get("signed_in", false):
		_add_row(true, "GitHub account", "Signed in as %s" % report.user)
		return

	if not report.get("gh_ok", false):
		_add_row(false, "GitHub account", "Needs the GitHub CLI first." if checked else "")
		return

	var copy := Button.new()
	copy.text = "Copy"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(Toolchain.SIGN_IN_COMMAND))
	_add_row(
		false,
		"GitHub account",
		"Not signed in. Run this in a terminal, then press Check Again:",
		copy,
		Toolchain.SIGN_IN_COMMAND
	)


func _add_mods_row() -> void:
	var repo := Contributing.repo
	if repo.is_cloned():
		_add_row(true, "Official mods", "Ready to edit, in %s" % repo.path)
		return

	var download := Button.new()
	download.text = "Download"
	download.disabled = Contributing.busy or not Contributing.can_download()
	download.pressed.connect(_download)
	_add_row(false, "Official mods", "Not downloaded yet.", download)


func _problem_text(report: Dictionary, link: String, checked: bool) -> String:
	if not checked:
		return "Checking..."
	for problem in report.get("problems", []):
		if problem.get("link", "") == link:
			return problem.text
	return ""


## One checklist line: a tick or cross, a name with detail under it, an optional
## extra line (such as a command to run), and an optional fix-it button at the
## right, kept on the same line so the checklist fits on screen.
func _add_row(
	ok: bool, name: String, detail: String, action: Button = null, extra: String = ""
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = ICON_OK if ok else ICON_MISSING
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var heading := Label.new()
	heading.text = name
	text.add_child(heading)
	for line in [detail, extra]:
		if line.is_empty():
			continue
		var body := Label.new()
		body.text = line
		body.theme_type_variation = &"SmallLabel"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(body)

	row.add_child(icon)
	row.add_child(text)
	if action != null:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
	_setup_list.add_child(row)


func _link_button(label: String, link: String) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: OS.shell_open(link))
	return button


# --- Actions ---


func _download() -> void:
	var result := await Contributing.download()
	show_result(result, "The official mods are downloaded and ready to edit.")


func _edit_mods() -> void:
	get_tree().change_scene_to_packed(load("res://source/menus/mod_manager_wrapper.tscn"))


func _toggle_own_copy() -> void:
	if not UserSettingsManager.repo_location.is_empty():
		Contributing.use_repo_location("")
		_message.text = "Using the app's own copy of the mods."
		return

	if not _file_dialog.dir_selected.is_connected(_on_dir_selected):
		_file_dialog.dir_selected.connect(_on_dir_selected)
	_file_dialog.popup_centered()


func _on_dir_selected(dir_path: String) -> void:
	if not Contributing.is_mods_repo(dir_path):
		var hint := "Choose the folder that has PACKS in it."
		_message.text = "That folder isn't a copy of pyramid-mods. " + hint
		return
	Contributing.use_repo_location(dir_path)
	_message.text = "Using your copy in %s." % dir_path


func _on_busy_changed(busy: bool, message: String) -> void:
	# The progress message clears when the work ends, unless something has
	# replaced it with a result in the meantime.
	if busy:
		_busy_message = message
		_message.text = message
	elif _message.text == _busy_message:
		_message.text = ""
	update()


## Pops the title in with a slight tilt, scaling about its own centre. Waits a
## frame so the layout has sized it; it is never moved, so it can't end up
## anywhere the layout didn't put it.
func _setup_ui() -> void:
	_title.scale = Vector2.ZERO
	await get_tree().process_frame
	_title.pivot_offset = _title.size * 0.5

	var intro := create_tween().set_parallel()
	intro.tween_property(_title, "scale", Vector2.ONE, 0.7)
	intro.tween_property(_title, "rotation_degrees", -5.0, 0.7)


func _close_game() -> void:
	get_tree().quit()


func _open_github() -> void:
	OS.shell_open("https://www.github.com/codeWonderland/official-pyramid-mods-manager")
