class_name DiscardDialog extends PopupContainer

## Asks before a refresh throws away edits that haven't been submitted.

signal discard_confirmed

@onready var _message: Label = %Message
@onready var _discard_button: Button = %DiscardButton
@onready var _keep_button: Button = %KeepButton


func _ready() -> void:
	super._ready()
	_discard_button.pressed.connect(_on_discard)
	_keep_button.pressed.connect(_close)


func open_for(changed: Array) -> void:
	_message.text = (
		(
			"You have edits to %s that haven't been submitted. Getting the latest mods"
			% ", ".join(changed)
		)
		+ " will throw them away. Submit them first to keep them."
	)
	show()


func _on_discard() -> void:
	_close()
	self.discard_confirmed.emit()
