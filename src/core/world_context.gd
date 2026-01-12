extends Node
## WorldContext: Static Context Layer
## Stores immutable world state loaded once at game start
## Reference: Logic section 2.1

class_name WorldContext

@export var active_region: String = ""  # Region ID
@export var region_name: String = ""
@export var region_config_path: String = ""

func _ready() -> void:
	# Ensure this node persists between scenes
	if not is_in_group("persistent"):
		add_to_group("persistent")

## Load a region configuration from resource
func load_region(region_id: String, config_path: String) -> bool:
	if active_region != "":
		push_warning("Cannot change region once loaded")
		return false
	
	active_region = region_id
	region_config_path = config_path
	return true

## Get the active region (immutable reference only)
func get_active_region() -> String:
	return active_region

## Get region config path
func get_region_config_path() -> String:
	return region_config_path
