extends Control
## MainMenu: Game entry point
## Reference: Logic section 8.1

class_name MainMenu

func _ready() -> void:
	pass

## Play button pressed
func _on_play_pressed() -> void:
	# Load simulation scene directly (with test region initialization)
	get_tree().change_scene_to_file("res://scenes/simulation/simulation.tscn")

## Quit button pressed
func _on_quit_pressed() -> void:
	get_tree().quit()
