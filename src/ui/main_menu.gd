extends Control
## MainMenu: Game entry point
## Reference: Logic section 8.1

class_name MainMenu

@onready var continue_button = $MenuUi/MenuControl/ContinueButton

func _ready() -> void:
	# Check if save exists
	var save_path = "user://saves/novara.tres"
	continue_button.disabled = not FileAccess.file_exists(save_path)
	if continue_button.disabled:
		continue_button.tooltip_text = "No save file found"

## New Game button pressed
func _on_play_pressed() -> void:
	# Delete existing save to start fresh
	var save_path = "user://saves/novara.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	get_tree().change_scene_to_file("res://scenes/simulation/simulation.tscn")

## Continue button pressed
func _on_continue_pressed() -> void:
	# TODO: Load save state before changing scene
	get_tree().change_scene_to_file("res://scenes/simulation/simulation.tscn")

## Event Tree Viewer button pressed
func _on_event_tree_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/event_tree_viewer.tscn")

## Options button pressed
func _on_options_pressed() -> void:
	# TODO: Open options menu
	print("Options menu not yet implemented")

## Quit button pressed
func _on_quit_pressed() -> void:
	get_tree().quit()
