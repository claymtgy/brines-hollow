@tool
class_name GodotDualSensePlugin
extends EditorPlugin
## Editor plugin registering the GodotDualSense addon and DualSenseManager autoload.

const AUTOLOAD_NAME := "DualSense"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot_dualsense/dualsense_manager.gd")


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
