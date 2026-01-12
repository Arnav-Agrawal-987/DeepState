extends Resource
## InstitutionConfig: Complete institution definition with event trees
## Contains player action tree and autonomous event tree

class_name InstitutionConfig

@export var institution_id: String = ""
@export var institution_name: String = ""
@export var institution_type: int = 2  # 0=MILITANT, 1=CIVILIAN, 2=POLICY, 3=INTELLIGENCE

# Initial stats
@export var initial_capacity: float = 50.0
@export var initial_strength: float = 100.0
@export var initial_stress: float = 0.0
@export var initial_influence: float = 0.0

# Player-triggered event tree (when player takes actions)
# Each node: {node_id, title, description, conditions, cost, effects, choices}
@export var player_event_tree: Array[Dictionary] = []

# Autonomous event tree (institution self-triggers based on stress/stability)
# Each node: {node_id, trigger_type, title, description, conditions, probability, auto_effects, player_choices}
@export var autonomous_event_tree: Array[Dictionary] = []

## Get player tree node by ID
func get_player_node(node_id: String) -> Dictionary:
	for node in player_event_tree:
		if node.get("node_id") == node_id:
			return node
	return {}

## Get autonomous tree node by ID
func get_autonomous_node(node_id: String) -> Dictionary:
	for node in autonomous_event_tree:
		if node.get("node_id") == node_id:
			return node
	return {}

## Get all player nodes that match conditions
func get_available_player_actions(influence: float, stress: float, capacity: float) -> Array:
	var available = []
	for node in player_event_tree:
		var conditions = node.get("conditions", {})
		var meets_conditions = true
		
		if conditions.has("min_influence") and influence < conditions["min_influence"]:
			meets_conditions = false
		if conditions.has("max_influence") and influence > conditions["max_influence"]:
			meets_conditions = false
		if conditions.has("min_stress") and stress < conditions["min_stress"]:
			meets_conditions = false
		if conditions.has("max_stress") and stress > conditions["max_stress"]:
			meets_conditions = false
		if conditions.has("min_capacity") and capacity < conditions["min_capacity"]:
			meets_conditions = false
		
		if meets_conditions:
			available.append(node)
	
	return available

## Get triggered autonomous events based on current state
func get_triggered_autonomous_events(stress: float, strength: float, capacity: float) -> Array:
	var triggered = []
	var stress_ratio = stress / strength if strength > 0 else 0.0
	
	for node in autonomous_event_tree:
		var trigger_type = node.get("trigger_type", "stress")
		var conditions = node.get("conditions", {})
		var meets_conditions = true
		
		# Check trigger type
		if trigger_type == "stress":
			if stress_ratio < 1.0:  # Only trigger when stress >= strength
				continue
		elif trigger_type == "stress_max":
			# Only trigger when stress reaches 100% (absolute value)
			if stress < 100.0:
				continue
		elif trigger_type == "stable":
			if stress_ratio > 0.5:  # Only trigger when relatively stable
				continue
			# Check probability
			var prob = node.get("probability", 0.3)
			if randf() > prob:
				continue
		
		# Check additional conditions
		if conditions.has("min_stress") and stress < conditions["min_stress"]:
			meets_conditions = false
		if conditions.has("max_stress") and stress > conditions["max_stress"]:
			meets_conditions = false
		if conditions.has("min_capacity") and capacity < conditions["min_capacity"]:
			meets_conditions = false
		
		if meets_conditions:
			triggered.append(node)
	
	return triggered

## Create default player event tree for an institution type
func create_default_player_tree() -> void:
	player_event_tree = [
		{
			"node_id": "action_light",
			"title": "Light Pressure",
			"description": "Apply subtle influence through unofficial channels.",
			"conditions": {"min_influence": 10.0, "max_stress": 90.0},
			"cost": {"cash": 200.0, "bandwidth": 10.0},
			"effects": {
				"stress_change": 15.0,
				"influence_change": 3.0,
				"exposure_change": 2.0,
				"tension_change": 2.0
			}
		},
		{
			"node_id": "action_moderate",
			"title": "Moderate Intervention",
			"description": "Direct manipulation of internal processes.",
			"conditions": {"min_influence": 30.0, "max_stress": 80.0},
			"cost": {"cash": 500.0, "bandwidth": 20.0},
			"effects": {
				"stress_change": 25.0,
				"influence_change": 5.0,
				"exposure_change": 5.0,
				"tension_change": 5.0
			}
		},
		{
			"node_id": "action_heavy",
			"title": "Heavy Pressure",
			"description": "Aggressive destabilization tactics.",
			"conditions": {"min_influence": 60.0},
			"cost": {"cash": 1000.0, "bandwidth": 35.0},
			"effects": {
				"stress_change": 40.0,
				"influence_change": 8.0,
				"capacity_change": -5.0,
				"exposure_change": 10.0,
				"tension_change": 10.0
			}
		},
		{
			"node_id": "action_deep",
			"title": "Deep State Action",
			"description": "Fundamental restructuring of institutional loyalty.",
			"conditions": {"min_influence": 80.0},
			"cost": {"cash": 2000.0, "bandwidth": 50.0},
			"effects": {
				"stress_change": 60.0,
				"influence_change": 15.0,
				"capacity_change": -10.0,
				"exposure_change": 20.0,
				"tension_change": 15.0
			}
		}
	]

## Create default autonomous event tree
func create_default_autonomous_tree() -> void:
	autonomous_event_tree = [
		{
			"node_id": "stress_max_crisis",
			"trigger_type": "stress_max",
			"title": "Critical Stress Point",
			"description": "The institution has reached maximum stress levels. Internal systems are breaking down.",
			"conditions": {},
			"auto_effects": {
				"capacity_change": -10.0,
				"tension_change": 15.0
			},
			"player_choices": [
				{
					"label": "Seize Control",
					"cost": {"cash": 500.0, "bandwidth": 25.0},
					"effects": {
						"influence_change": 25.0,
						"stress_change": -30.0,
						"exposure_change": 20.0
					}
				},
				{
					"label": "Provide Covert Aid",
					"cost": {"cash": 300.0},
					"effects": {
						"stress_change": -40.0,
						"influence_change": 10.0,
						"exposure_change": 5.0
					}
				},
				{
					"label": "Watch It Burn",
					"cost": {},
					"effects": {
						"strength_change": -15.0,
						"tension_change": 10.0
					}
				}
			]
		},
		{
			"node_id": "stress_internal_conflict",
			"trigger_type": "stress",
			"title": "Internal Conflict",
			"description": "Factions within the institution clash over direction.",
			"conditions": {"min_stress": 80.0},
			"auto_effects": {
				"stress_change": -20.0,
				"tension_change": 8.0
			},
			"player_choices": [
				{
					"text": "Exploit the division",
					"requires": {"min_influence": 40.0},
					"cost": {"cash": 300.0, "bandwidth": 15.0},
					"effects": {
						"influence_change": 12.0,
						"exposure_change": 8.0
					}
				},
				{
					"text": "Stay uninvolved",
					"effects": {
						"tension_change": 3.0
					}
				}
			]
		},
		{
			"node_id": "stress_leak",
			"trigger_type": "stress",
			"title": "Information Leak",
			"description": "Sensitive documents have been leaked to outside parties.",
			"conditions": {"min_stress": 90.0},
			"auto_effects": {
				"stress_change": -15.0,
				"capacity_change": -5.0,
				"tension_change": 12.0
			},
			"player_choices": [
				{
					"text": "Acquire the documents",
					"requires": {"min_influence": 50.0},
					"cost": {"cash": 800.0, "bandwidth": 25.0},
					"effects": {
						"influence_change": 20.0,
						"exposure_change": 15.0
					}
				},
				{
					"text": "Let it play out",
					"effects": {}
				}
			]
		},
		{
			"node_id": "stable_reform",
			"trigger_type": "stable",
			"title": "Reform Initiative",
			"description": "Leadership proposes structural reforms to improve efficiency.",
			"conditions": {"max_stress": 40.0, "min_capacity": 50.0},
			"probability": 0.25,
			"auto_effects": {
				"capacity_change": 5.0,
				"strength_change": 3.0
			},
			"player_choices": [
				{
					"text": "Sabotage reforms",
					"requires": {"min_influence": 50.0},
					"cost": {"cash": 500.0, "bandwidth": 20.0},
					"effects": {
						"stress_change": 25.0,
						"capacity_change": -8.0,
						"exposure_change": 10.0
					}
				},
				{
					"text": "Allow reforms",
					"effects": {
						"influence_change": -3.0
					}
				}
			]
		},
		{
			"node_id": "stable_audit",
			"trigger_type": "stable",
			"title": "Internal Audit",
			"description": "The institution conducts an internal review of operations.",
			"conditions": {"max_stress": 30.0},
			"probability": 0.2,
			"auto_effects": {
				"capacity_change": 3.0
			},
			"player_choices": [
				{
					"text": "Bribe auditors",
					"requires": {"min_influence": 30.0},
					"cost": {"cash": 600.0},
					"effects": {
						"influence_change": 5.0,
						"exposure_change": 12.0
					}
				},
				{
					"text": "Avoid attention",
					"effects": {
						"influence_change": -2.0
					}
				}
			]
		}
	]
