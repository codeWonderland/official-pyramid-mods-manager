class_name ModManagerWrapper extends Control

const MOD_MANAGER: PackedScene = preload("res://source/mod-manager/mod_manager.tscn")


func _ready() -> void:
	var mod_manager = MOD_MANAGER.instantiate()
	mod_manager.mods_path = Contributing.repo.packs_path() + "/"
	add_child(mod_manager)
