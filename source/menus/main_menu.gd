class_name MainMenu extends Control

@onready var _title: Label = %Title
@onready var _exit_button: TextureButton = %Exit
@onready var _github_button: TextureButton = %Github
@onready var _select_folder: Button = %SelectFolder
@onready var _edit_mods: Button = %EditMods
@onready var _file_dialog: FileDialog = %FileDialog


func _ready() -> void:
	_setup_ui()

	_exit_button.pressed.connect(_close_game)
	_github_button.pressed.connect(_open_github)
	_select_folder.pressed.connect(_select_mods_folder)
	_edit_mods.pressed.connect(_on_edit_mods_pressed)


func _setup_ui() -> void:
	var og_title_pos = _title.position
	_title.scale = Vector2.ZERO
	_title.position = Vector2.ZERO

	var title_tween = create_tween()
	title_tween.tween_property(_title, "scale", Vector2.ONE, 0.7)
	var title_pos_tween = create_tween()
	title_pos_tween.tween_property(_title, "position", og_title_pos, 0.7)

	var title_rot_tween = create_tween()
	title_rot_tween.tween_property(_title, "rotation_degrees", -5, 0.7)

	if UserSettingsManager.mods_location != "":
		_edit_mods.show()


func _close_game() -> void:
	get_tree().quit()


func _open_github() -> void:
	OS.shell_open("https://www.github.com/codeWonderland/official-pyramid-mods-manager")


func _select_mods_folder() -> void:
	_file_dialog.dir_selected.connect(_on_dir_selected)
	_file_dialog.popup_centered()


func _on_dir_selected(dir_path: String) -> void:
	UserSettingsManager.set_mods_location(dir_path)
	_edit_mods.show()


func _on_edit_mods_pressed() -> void:
	get_tree().change_scene_to_packed(load("res://source/menus/mod_manager_wrapper.tscn"))
