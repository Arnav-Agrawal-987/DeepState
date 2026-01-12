extends Control
## GameOverScreen: Game over sequence and replay options

class_name GameOverScreen

@onready var score_label = $CenterContainer/VBoxContainer/ScoreLabel
@onready var reason_label = $CenterContainer/VBoxContainer/ReasonLabel
@onready var high_score_label = $CenterContainer/VBoxContainer/HighScoreLabel

var final_score: int = 0
var region_id: String = ""
var save_game: SaveGame

func _ready() -> void:
	$CenterContainer/VBoxContainer/ButtonHBox/RetryButton.pressed.connect(_on_retry_pressed)
	$CenterContainer/VBoxContainer/ButtonHBox/MenuButton.pressed.connect(_on_menu_pressed)

## Display game over with score
func show_game_over(score: int, region: String, save: SaveGame) -> void:
	final_score = score
	region_id = region
	save_game = save
	
	score_label.text = "Days Survived: %d" % score
	high_score_label.text = "Best: %d days" % save.high_score
	reason_label.text = "The Deep State lost structural relevance during the crisis"
	
	visible = true

## Retry current region
func _on_retry_pressed() -> void:
	# Load region and start new game
	get_tree().change_scene_to_file("res://scenes/simulation/simulation.tscn")

## Return to main menu
func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
