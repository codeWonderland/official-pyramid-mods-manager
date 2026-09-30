class_name SubmitDialog extends PopupContainer

## Sends the edited packs to the official mods as a pull request: a title, an
## optional description, and the list of packs going with it.

signal submitted(url: String)

var _url: String = ""

@onready var _title_edit: LineEdit = %TitleEdit
@onready var _body_edit: TextEdit = %BodyEdit
@onready var _packs_label: Label = %PacksLabel
@onready var _submit_button: Button = %SubmitButton
@onready var _result_label: Label = %ResultLabel
@onready var _open_button: Button = %OpenButton


func _ready() -> void:
	super._ready()
	_submit_button.pressed.connect(_submit)
	_open_button.pressed.connect(func() -> void: OS.shell_open(_url))


## Opens the dialog for these edited packs.
func open_for(changed: Array) -> void:
	_title_edit.text = ""
	_body_edit.text = ""
	_url = ""
	_result_label.text = ""
	_open_button.hide()
	_submit_button.disabled = false
	_packs_label.text = "Packs going with this submission: " + ", ".join(changed)
	show()
	_title_edit.grab_focus()


func _submit() -> void:
	_submit_button.disabled = true
	_result_label.text = "Submitting..."
	var result := await Contributing.submit(_title_edit.text, _body_edit.text)
	show_result(result)


func show_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_url = result.url
		_result_label.text = (
			"Submitted! The Pyramid team will review it. The editor now shows the"
			+ " official packs again; your changes are in the submission."
		)
		_open_button.show()
		self.submitted.emit(_url)
		return

	_submit_button.disabled = false
	var text: String = result.get("message", "Something went wrong.")
	if not str(result.get("detail", "")).is_empty():
		text += "\n" + str(result.detail)
	_result_label.text = text
