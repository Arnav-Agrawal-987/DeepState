extends Resource
## RegionSaveState: Persistent save state for a region
## Contains current values, tree progress, and references to configs

class_name RegionSaveState

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

# Crisis tree progress
@export var crisis_tree_state: Dictionary = {
	"current_node": "",
	"visited_nodes": [],
	"node_choices_made": {}
}

# Institution states with tree progress
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
	
	# Initialize crisis tree state
	if config.crisis_tree.size() > 0:
		crisis_tree_state["current_node"] = config.crisis_tree[0].get("node_id", "")

## Initialize institution state
func initialize_institution(inst_id: String, config: InstitutionConfig) -> void:
	institutions[inst_id] = {
		"config_path": config.resource_path,
		"capacity": config.initial_capacity,
		"strength": config.initial_strength,
		"stress": config.initial_stress,
		"influence": config.initial_influence,
		"player_tree_state": {
			"visited_nodes": [],
			"actions_taken": {}
		},
		"autonomous_tree_state": {
			"triggered_events": [],
			"last_event_day": 0
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
func record_institution_event(inst_id: String, event_id: String, is_player_action: bool) -> void:
	if not inst_id in institutions:
		return
	
	var inst = institutions[inst_id]
	
	if is_player_action:
		if not event_id in inst["player_tree_state"]["visited_nodes"]:
			inst["player_tree_state"]["visited_nodes"].append(event_id)
		inst["player_tree_state"]["actions_taken"][event_id] = current_day
	else:
		if not event_id in inst["autonomous_tree_state"]["triggered_events"]:
			inst["autonomous_tree_state"]["triggered_events"].append(event_id)
		inst["autonomous_tree_state"]["last_event_day"] = current_day

## Update dependency weight
func update_dependency(source_id: String, target_id: String, weight: float) -> void:
	if not source_id in dependency_graph:
		dependency_graph[source_id] = {}
	dependency_graph[source_id][target_id] = clamp(weight, 0.0, 1.0)

## Mark game as lost
func mark_lost(score: int) -> void:
	is_lost = true
	if score > high_score:
		high_score = score

## Save to file
func save_to_file(path: String) -> Error:
	return ResourceSaver.save(self, path)

## Load from file
static func load_from_file(path: String) -> RegionSaveState:
	if ResourceLoader.exists(path):
		return load(path) as RegionSaveState
	return null
