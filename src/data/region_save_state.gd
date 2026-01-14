extends Resource
## RegionSaveState: Persistent save state for a region
## Contains current values, tree progress, and references to configs

class_name RegionSaveState

# Save file directory (relative to project root)
const SAVE_DIR = "res://saved-games/"

@export var region_id: String = ""
@export var region_config_path: String = ""  # Reference to RegionConfig
@export var current_day: int = 1
@export var is_lost: bool = false
@export var high_score: int = 0

# Current currency values
@export var currencies: Dictionary = {
	"cash": 1000.0,
	"bandwidth": 50.0,
	"exposure": 0.0
}

# Crisis tree progress (global for the game)
@export var crisis_tree_state: Dictionary = {
	"current_node": "",
	"pruned_branches": []
}

# Institution states with NEW tree progress structure
@export var institutions: Dictionary = {}

# Dependency graph current state
@export var dependency_graph: Dictionary = {}

# Global tension
@export var global_tension: float = 0.0

## Initialize from RegionConfig
func initialize_from_config(config: RegionConfig) -> void:
	region_id = config.region_id
	region_config_path = config.resource_path
	
	# Initialize currencies from config
	for currency_name in config.currencies:
		currencies[currency_name] = config.get_currency_initial(currency_name)
	
	# Initialize dependency graph
	dependency_graph = config.initial_dependencies.duplicate(true)
	
	# Initialize crisis tree state (first node is root)
	crisis_tree_state = {
		"current_node": "",
		"pruned_branches": []
	}
	if config.crisis_tree.size() > 0:
		crisis_tree_state["current_node"] = config.crisis_tree[0].get("node_id", "")

## Initialize institution state with NEW tree structure
func initialize_institution(inst_id: String, config: InstitutionConfig) -> void:
	institutions[inst_id] = {
		"config_path": config.resource_path,
		"capacity": config.initial_capacity,
		"strength": config.initial_strength,
		"stress": config.initial_stress,
		"influence": config.initial_influence,
		# NEW: Stress-triggered tree state
		"stress_tree_state": {
			"current_node": "",  # Current position in stress event tree
			"pruned_branches": []  # Nodes that are no longer accessible
		},
		# NEW: Randomly-triggered tree state
		"random_tree_state": {
			"current_node": "",  # Current position in random event tree
			"pruned_branches": []  # Nodes that are no longer accessible
		},
		# LEGACY: Keep for migration period
		"player_tree_state": {
			"current_node": "",
			"visited_nodes": [],
			"pruned_branches": [],
			"actions_taken": {},
			"choices_made": {}
		},
		"autonomous_tree_state": {
			"current_node": "",
			"triggered_events": [],
			"pruned_branches": [],
			"last_event_day": 0,
			"choices_made": {}
		}
	}

## Get institution state
func get_institution_state(inst_id: String) -> Dictionary:
	return institutions.get(inst_id, {})

## Update institution stat
func update_institution_stat(inst_id: String, stat_name: String, value: float) -> void:
	if inst_id in institutions:
		institutions[inst_id][stat_name] = value

## Apply effect to institution
func apply_institution_effect(inst_id: String, effect_name: String, value: float) -> void:
	if not inst_id in institutions:
		return
	
	var inst = institutions[inst_id]
	match effect_name:
		"stress_change":
			inst["stress"] = max(0.0, inst["stress"] + value)
		"capacity_change":
			inst["capacity"] = clamp(inst["capacity"] + value, 0.0, 100.0)
		"strength_change":
			inst["strength"] = clamp(inst["strength"] + value, 0.0, 100.0)
		"influence_change":
			inst["influence"] = clamp(inst["influence"] + value, 0.0, 100.0)

## Get currency value
func get_currency(currency_name: String) -> float:
	return currencies.get(currency_name, 0.0)

## Set currency value
func set_currency(currency_name: String, value: float, max_value: float = 999999.0) -> void:
	currencies[currency_name] = clamp(value, 0.0, max_value)

## Apply currency change
func apply_currency_change(currency_name: String, change: float, max_value: float = 999999.0) -> void:
	var current = get_currency(currency_name)
	set_currency(currency_name, current + change, max_value)

## Check if can afford cost
func can_afford(cost: Dictionary) -> bool:
	for currency_name in cost:
		if get_currency(currency_name) < cost[currency_name]:
			return false
	return true

## Spend cost
func spend_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	
	for currency_name in cost:
		apply_currency_change(currency_name, -cost[currency_name])
	
	return true

## Reset currency to fallback value
func reset_currency_to_fallback(currency_name: String, fallback_value: float) -> void:
	currencies[currency_name] = fallback_value

## Record crisis node visit
func visit_crisis_node(node_id: String, choice_index: int = -1) -> void:
	if not node_id in crisis_tree_state["visited_nodes"]:
		crisis_tree_state["visited_nodes"].append(node_id)
	
	crisis_tree_state["current_node"] = node_id
	
	if choice_index >= 0:
		crisis_tree_state["node_choices_made"][node_id] = choice_index

## Record institution event
func record_institution_event(inst_id: String, event_id: String, is_player_action: bool, choice_taken: Dictionary = {}, choice_index: int = -1) -> void:
	if not inst_id in institutions:
		return
	
	var inst = institutions[inst_id]
	
	if is_player_action:
		# Record player action
		if not event_id in inst["player_tree_state"]["visited_nodes"]:
			inst["player_tree_state"]["visited_nodes"].append(event_id)
		inst["player_tree_state"]["actions_taken"][event_id] = current_day
		
		# Record which choice was made
		if choice_index >= 0 or not choice_taken.is_empty():
			inst["player_tree_state"]["choices_made"][event_id] = {
				"choice_index": choice_index,
				"choice_text": choice_taken.get("text", ""),
				"next_node": choice_taken.get("next_node", "")
			}
		
		# Update current node to next_node if choice was made
		if choice_taken.has("next_node") and choice_taken["next_node"] != "":
			inst["player_tree_state"]["current_node"] = choice_taken["next_node"]
			
			# Prune alternative branches if this choice is exclusive
			if choice_taken.has("prunes_branches"):
				for pruned_node in choice_taken["prunes_branches"]:
					if not pruned_node in inst["player_tree_state"]["pruned_branches"]:
						inst["player_tree_state"]["pruned_branches"].append(pruned_node)
	else:
		# Record autonomous event
		if not event_id in inst["autonomous_tree_state"]["triggered_events"]:
			inst["autonomous_tree_state"]["triggered_events"].append(event_id)
		inst["autonomous_tree_state"]["last_event_day"] = current_day
		
		# Record which choice was made
		if choice_index >= 0 or not choice_taken.is_empty():
			inst["autonomous_tree_state"]["choices_made"][event_id] = {
				"choice_index": choice_index,
				"choice_text": choice_taken.get("text", ""),
				"next_node": choice_taken.get("next_node", "")
			}
		
		# Update current node if choice leads to next event
		if choice_taken.has("next_node") and choice_taken["next_node"] != "":
			inst["autonomous_tree_state"]["current_node"] = choice_taken["next_node"]
			
			# Prune alternative branches
			if choice_taken.has("prunes_branches"):
				for pruned_node in choice_taken["prunes_branches"]:
					if not pruned_node in inst["autonomous_tree_state"]["pruned_branches"]:
						inst["autonomous_tree_state"]["pruned_branches"].append(pruned_node)

## Check if event node is available (not pruned)
func is_event_available(inst_id: String, event_id: String, is_player_action: bool) -> bool:
	if not inst_id in institutions:
		return false
	
	var inst = institutions[inst_id]
	
	if is_player_action:
		return not event_id in inst["player_tree_state"]["pruned_branches"]
	else:
		return not event_id in inst["autonomous_tree_state"]["pruned_branches"]

## Update dependency weight
func update_dependency(source_id: String, target_id: String, weight: float) -> void:
	if not source_id in dependency_graph:
		dependency_graph[source_id] = {}
	dependency_graph[source_id][target_id] = clamp(weight, 0.0, 1.0)

# ============================================
# NEW EVENT TREE STATE METHODS
# ============================================

## Get stress tree state for an institution
func get_stress_tree_state(inst_id: String) -> Dictionary:
	if not inst_id in institutions:
		return {"current_node": "", "pruned_branches": []}
	return institutions[inst_id].get("stress_tree_state", {"current_node": "", "pruned_branches": []})

## Get random tree state for an institution
func get_random_tree_state(inst_id: String) -> Dictionary:
	if not inst_id in institutions:
		return {"current_node": "", "pruned_branches": []}
	return institutions[inst_id].get("random_tree_state", {"current_node": "", "pruned_branches": []})

## Record stress event choice and update tree state
func record_stress_event(inst_id: String, node_id: String, choice: Dictionary) -> void:
	if not inst_id in institutions:
		return
	
	var tree_state = institutions[inst_id]["stress_tree_state"]
	
	# Update current node to next_node
	if choice.has("next_node") and choice["next_node"] != "":
		tree_state["current_node"] = choice["next_node"]
	else:
		# No next node means tree ends here for this branch
		tree_state["current_node"] = ""
	
	# Prune branches based on choice
	if choice.has("prunes_branches"):
		for pruned_node in choice["prunes_branches"]:
			if not pruned_node in tree_state["pruned_branches"]:
				tree_state["pruned_branches"].append(pruned_node)

## Record random event choice and update tree state
func record_random_event(inst_id: String, node_id: String, choice: Dictionary) -> void:
	if not inst_id in institutions:
		return
	
	var tree_state = institutions[inst_id]["random_tree_state"]
	
	# Update current node to next_node
	if choice.has("next_node") and choice["next_node"] != "":
		tree_state["current_node"] = choice["next_node"]
	else:
		tree_state["current_node"] = ""
	
	# Prune branches based on choice
	if choice.has("prunes_branches"):
		for pruned_node in choice["prunes_branches"]:
			if not pruned_node in tree_state["pruned_branches"]:
				tree_state["pruned_branches"].append(pruned_node)

## Record crisis event choice and update crisis tree state
func record_crisis_event(node_id: String, choice: Dictionary) -> void:
	# Update current node to next_node
	if choice.has("next_node") and choice["next_node"] != "":
		crisis_tree_state["current_node"] = choice["next_node"]
	else:
		crisis_tree_state["current_node"] = ""
	
	# Prune branches based on choice
	if choice.has("prunes_branches"):
		for pruned_node in choice["prunes_branches"]:
			if not pruned_node in crisis_tree_state["pruned_branches"]:
				crisis_tree_state["pruned_branches"].append(pruned_node)

## Check if stress event is available (not pruned)
func is_stress_event_available(inst_id: String, node_id: String) -> bool:
	var tree_state = get_stress_tree_state(inst_id)
	return not node_id in tree_state.get("pruned_branches", [])

## Check if random event is available (not pruned)
func is_random_event_available(inst_id: String, node_id: String) -> bool:
	var tree_state = get_random_tree_state(inst_id)
	return not node_id in tree_state.get("pruned_branches", [])

## Check if crisis event is available (not pruned)
func is_crisis_event_available(node_id: String) -> bool:
	return not node_id in crisis_tree_state.get("pruned_branches", [])

## Prune a crisis branch (mark as no longer accessible)
func prune_crisis_branch(node_id: String) -> void:
	if not node_id in crisis_tree_state["pruned_branches"]:
		crisis_tree_state["pruned_branches"].append(node_id)
		print("[SaveState] Pruned crisis branch: %s" % node_id)

## Mark game as lost
func mark_lost(score: int) -> void:
	is_lost = true
	if score > high_score:
		high_score = score

# ============================================
# SAVE/LOAD METHODS
# ============================================

## Save to file in saved-games directory
## filename: just the name without path or extension (e.g., "save1")
func save_to_file(filename: String) -> Error:
	# Ensure saved-games directory exists
	var dir = DirAccess.open("res://")
	if dir:
		if not dir.dir_exists("saved-games"):
			var err = dir.make_dir("saved-games")
			if err != OK:
				push_error("Failed to create saved-games directory: %s" % error_string(err))
				return err
	
	var path = SAVE_DIR + filename + ".tres"
	var err = ResourceSaver.save(self, path)
	if err == OK:
		print("[RegionSaveState] Saved to: %s" % path)
	else:
		push_error("[RegionSaveState] Failed to save: %s" % error_string(err))
	return err

## Load from file in saved-games directory
## filename: just the name without path or extension (e.g., "save1")
static func load_from_file(filename: String) -> RegionSaveState:
	var path = SAVE_DIR + filename + ".tres"
	if ResourceLoader.exists(path):
		var loaded = load(path) as RegionSaveState
		if loaded:
			print("[RegionSaveState] Loaded from: %s" % path)
		return loaded
	push_warning("[RegionSaveState] Save file not found: %s" % path)
	return null

## Get list of available save files
static func get_save_files() -> Array[String]:
	var saves: Array[String] = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				saves.append(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()
	return saves

## Delete a save file
static func delete_save(filename: String) -> Error:
	var path = SAVE_DIR + filename + ".tres"
	var dir = DirAccess.open(SAVE_DIR)
	if dir and dir.file_exists(filename + ".tres"):
		return dir.remove(filename + ".tres")
	return ERR_FILE_NOT_FOUND
