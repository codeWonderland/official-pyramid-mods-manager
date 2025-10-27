class_name PopupContainer extends PanelContainer

signal closing

@onready var _close_button: TextureButton = %Close


func _ready() -> void:
	_resize()
	get_tree().get_root().size_changed.connect(_resize)

	_close_button.pressed.connect(_close)


func _override_resize() -> void:
	get_tree().get_root().size_changed.disconnect(_resize)


func _resize() -> void:
	var screen_size = get_viewport().size as Vector2
	var scale_mult = screen_size.x / 1920.0

	if screen_size.y / 1080.0 < scale_mult:
		scale_mult = screen_size.y / 1080.0

	scale = Vector2(scale_mult, scale_mult)
	size = screen_size * 0.8
	position = screen_size / 2 - size * scale / 2


func _close() -> void:
	hide()
	self.closing.emit()
