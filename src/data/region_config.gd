extends Resource
## RegionConfig: Complete region definition with institutions, currencies, and crisis tree
## Reference: Logic section 7.1

class_name RegionConfig

@export var region_id: String = ""
@export var region_name: String = ""
@export var region_description: String = ""

# Institution config paths (inst_id -> path to InstitutionConfig.tres)
@export var institution_config_paths: Dictionary = {}

# Initial dependency graph (source_id -> {target_id: weight})
@export var initial_dependencies: Dictionary = {}

# Regional currencies with initial/fallback/max values
@export var currencies: Dictionary = {
	"cash": {"initial": 1000.0, "fallback": 500.0, "max": 999999.0},
	"bandwidth": {"initial": 50.0, "fallback": 25.0, "max": 100.0},
	"exposure": {"initial": 0.0, "fallback": 10.0, "max": 100.0}
}

# Global crisis tree
# Each node: {node_id, title, description, conditions, effects, choices}
@export var crisis_tree: Array[Dictionary] = []

## Create region from scratch
func create_region(
	id: String,
	name: String,
	description: String
) -> void:
	region_id = id
	region_name = name
	region_description = description

## Add institution config reference
func add_institution_config(inst_id: String, config_path: String) -> void:
	institution_config_paths[inst_id] = config_path

## Add dependency edge
func add_dependency(source_id: String, target_id: String, weight: float) -> void:
	if not source_id in initial_dependencies:
		initial_dependencies[source_id] = {}
	initial_dependencies[source_id][target_id] = clamp(weight, 0.0, 1.0)

## Get all institution IDs
func get_institution_ids() -> Array:
	return institution_config_paths.keys()

## Get institution config path
func get_institution_config_path(inst_id: String) -> String:
	return institution_config_paths.get(inst_id, "")

## Load institution config resource
func load_institution_config(inst_id: String) -> InstitutionConfig:
	var path = get_institution_config_path(inst_id)
	if path != "" and ResourceLoader.exists(path):
		return load(path) as InstitutionConfig
	return null

## Get currency initial value
func get_currency_initial(currency_name: String) -> float:
	return currencies.get(currency_name, {}).get("initial", 0.0)

## Get currency fallback value  
func get_currency_fallback(currency_name: String) -> float:
	return currencies.get(currency_name, {}).get("fallback", 0.0)

## Get currency max value
func get_currency_max(currency_name: String) -> float:
	return currencies.get(currency_name, {}).get("max", 100.0)

## Get crisis tree node by ID
func get_crisis_node(node_id: String) -> Dictionary:
	for node in crisis_tree:
		if node.get("node_id") == node_id:
			return node
	return {}

## Get the current crisis event based on tree state
## Returns empty dict if tree is exhausted or all nodes pruned
func get_current_crisis_event(current_node: String, pruned_branches: Array) -> Dictionary:
	# If we have a current node, try to return it
	if current_node != "":
		var node = get_crisis_node(current_node)
		if not node.is_empty() and current_node not in pruned_branches:
			return node
	
	# Otherwise return root node (first in tree) if not pruned
	if crisis_tree.size() > 0:
		var root = crisis_tree[0]
		var root_id = root.get("node_id", "")
		if root_id not in pruned_branches:
			return root
	
	return {}

## Check if crisis should trigger based on tension threshold
func should_trigger_crisis(tension: float, threshold: float = 100.0) -> bool:
	return tension >= threshold

## Check if crisis should trigger (legacy method)
func check_crisis_conditions(tension: float, node_id: String) -> bool:
	var node = get_crisis_node(node_id)
	if node.is_empty():
		return false
	
	var conditions = node.get("conditions", {})
	if conditions.has("tension_threshold"):
		return tension >= conditions["tension_threshold"]
	
	return false

## Filter available crisis choices based on player resources and institution states
func get_available_crisis_choices(node: Dictionary, player_state: Dictionary, inst_states: Dictionary) -> Array:
	var choices = node.get("choices", [])
	var available = []
	
	for choice in choices:
		var can_afford = true
		var meets_requirements = true
		
		# Check cost (cost can be int for bandwidth or Dictionary)
		var cost = choice.get("cost", 0)
		if cost is int:
			if cost > player_state.get("bandwidth", 0.0):
				can_afford = false
		elif cost is Dictionary:
			if cost.get("cash", 0.0) > player_state.get("cash", 0.0):
				can_afford = false
			if cost.get("bandwidth", 0.0) > player_state.get("bandwidth", 0.0):
				can_afford = false
		
		# Check institution-specific requirements
		var requires = choice.get("requires", {})
		for key in requires:
			if key.ends_with("_influence"):
				var inst_id = key.replace("min_", "").replace("_influence", "")
				var inst_state = inst_states.get(inst_id, {})
				if inst_state.get("influence", 0.0) < requires[key]:
					meets_requirements = false
		
		# Add choice with availability info
		var choice_info = choice.duplicate()
		choice_info["can_afford"] = can_afford
		choice_info["meets_requirements"] = meets_requirements
		choice_info["available"] = can_afford and meets_requirements
		available.append(choice_info)
	
	return available

## Create default crisis tree
func create_default_crisis_tree() -> void:
	crisis_tree = [
		{
			"node_id": "crisis_constitutional",
			"title": "Constitutional Crisis",
			"description": "Fundamental tensions between institutional powers threaten the system.",
			"conditions": {"tension_threshold": 80.0},
			"choices": [
				{
					"text": "Support centralization of power",
					"requires": {},
					"cost": {"cash": 1000.0, "bandwidth": 30.0},
					"effects": {
						"tension_change": -40.0,
						"exposure_change": 15.0
					},
					"next_node": "crisis_resolved_central"
				},
				{
					"text": "Facilitate compromise",
					"requires": {},
					"cost": {"bandwidth": 20.0},
					"effects": {
						"tension_change": -25.0,
						"exposure_change": 5.0
					},
					"next_node": "crisis_resolved_compromise"
				},
				{
					"text": "Exploit the chaos",
					"requires": {},
					"cost": {"cash": 500.0, "bandwidth": 40.0},
					"effects": {
						"tension_change": -15.0,
						"exposure_change": 25.0
					},
					"next_node": "crisis_resolved_chaos"
				}
			]
		},
		{
			"node_id": "crisis_resolved_central",
			"title": "Power Consolidated",
			"description": "Executive power has been strengthened. Institutions fall in line.",
			"effects": {
				"all_stress_change": -20.0,
				"dependency_boost": 0.1
			},
			"choices": []
		},
		{
			"node_id": "crisis_resolved_compromise",
			"title": "Fragile Peace",
			"description": "A temporary agreement holds. Underlying tensions remain.",
			"effects": {
				"all_stress_change": -10.0
			},
			"choices": []
		},
		{
			"node_id": "crisis_resolved_chaos",
			"title": "Opportunity in Disorder",
			"description": "The chaos created openings for deeper infiltration.",
			"effects": {
				"all_influence_change": 10.0,
				"all_stress_change": 15.0
			},
			"choices": []
		}
	]
