class_name SubmissionsDialog extends PopupContainer

## The player's open pull requests to the official mods, with where each stands.

@onready var _list: VBoxContainer = %List
@onready var _status_label: Label = %StatusLabel
@onready var _reload_button: Button = %ReloadButton


func _ready() -> void:
	super._ready()
	_reload_button.pressed.connect(reload)


func open() -> void:
	show()
	await reload()


func reload() -> void:
	_clear()
	_status_label.text = "Loading..."
	var result := await Contributing.submissions()
	show_submissions(result)


func show_submissions(result: Dictionary) -> void:
	_clear()
	if not result.get("ok", false):
		_status_label.text = result.get("message", "Couldn't load your submissions.")
		return

	var submissions: Array = result.submissions
	_status_label.text = (
		"You have no open submissions." if submissions.is_empty() else "Your open submissions:"
	)
	for submission in submissions:
		_list.add_child(_row(submission))


## "#7 Add Balatro", then "Checks: passing - Review: approved", and an Open button.
func _row(submission: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "#%d  %s" % [submission.number, submission.title]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)

	var status := Label.new()
	status.text = "Checks: %s  -  Review: %s" % [submission.checks, submission.review]
	status.theme_type_variation = &"SmallLabel"
	text.add_child(status)

	var open := Button.new()
	open.text = "Open"
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open.pressed.connect(func() -> void: OS.shell_open(submission.url))

	row.add_child(text)
	row.add_child(open)
	return row


func _clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
