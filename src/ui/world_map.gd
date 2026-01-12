extends Control
## WorldMap: Region selection interface
## Reference: Logic section 8.2

class_name WorldMap

var selected_region: String = ""
var regions: Dictionary = {}  # region_id -> RegionConfig

@onready var region_container = $RegionContainer
@onready var region_name_label = $RegionInfoPanel/VBoxContainer/RegionName
@onready var region_description = $RegionInfoPanel/VBoxContainer/RegionDescription
@onready var region_stats = $RegionInfoPanel/VBoxContainer/RegionStats
@onready var start_button = $RegionInfoPanel/VBoxContainer/StartButton

func _ready() -> void:
	load_available_regions()
	start_button.pressed.connect(_on_start_pressed)

## Load all available region configs
func load_available_regions() -> void:
	# TODO: Load region configs from assets/regions/
	# Placeholder regions for testing
	
	var region1 = RegionConfig.new()
	region1.create_region("test_nation_1", "Test Nation 1", "A test region for development")
	regions["test_nation_1"] = region1
	
	var region2 = RegionConfig.new()
	region2.create_region("test_nation_2", "Test Nation 2", "Another test region")
	regions["test_nation_2"] = region2
	
	display_regions()

## Display region buttons
func display_regions() -> void:
	for region_id in regions:
		var config = regions[region_id]
		var button = Button.new()
		button.text = config.region_name
		button.pressed.connect(_on_region_selected.bindv([region_id]))
		region_container.add_child(button)

## Region selected
func _on_region_selected(region_id: String) -> void:
	selected_region = region_id
	var config = regions[region_id]
	
	region_name_label.text = config.region_name
	region_description.text = config.region_description
	region_stats.text = "Institutions: %d" % config.get_institution_ids().size()
	start_button.disabled = false

## Start game with selected region
func _on_start_pressed() -> void:
	if selected_region == "":
		return
	
	# Create simulation with selected region
	var config = regions[selected_region]
	
	# TODO: Check for existing save
	# TODO: Load or create new game
	
	get_tree().change_scene_to_file("res://scenes/simulation/simulation.tscn")
