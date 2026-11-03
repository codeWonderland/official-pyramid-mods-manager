class_name DiscardDialog extends PopupContainer

## Asks before getting the latest mods throws away work that hasn't reached
## GitHub.

signal discard_confirmed

@onready var _message: Label = %Message
@onready var _discard_button: Button = %DiscardButton
@onready var _keep_button: Button = %KeepButton


func _ready() -> void:
	super._ready()
	_discard_button.pressed.connect(_on_discard)
	_keep_button.pressed.connect(_close)


## Says exactly what getting the latest mods would throw away - see
## ModsRepo.unsaved_work().
func open_for(work: Dictionary) -> void:
	_message.text = describe(work)
	show()


static func describe(work: Dictionary) -> String:
	var lost := PackedStringArray()
	var changed: Array = work.get("changed", [])
	if not changed.is_empty():
		lost.append("edits to %s that haven't been submitted" % ", ".join(changed))
	var other_files: Array = work.get("other_files", [])
	if not other_files.is_empty():
		lost.append("changes to %s" % ", ".join(other_files))
	var unsent := int(work.get("unsent_commits", 0))
	if unsent > 0:
		lost.append(
			"%d saved change%s that never reached GitHub" % [unsent, "" if unsent == 1 else "s"]
		)

	return (
		"You have %s. Syncing with GitHub will throw that away. Submit your edits first to keep them."
		% _join_list(lost)
	)


static func _join_list(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return "%s and %s" % [", ".join(items.slice(0, items.size() - 1)), items[items.size() - 1]]


func _on_discard() -> void:
	_close()
	self.discard_confirmed.emit()
