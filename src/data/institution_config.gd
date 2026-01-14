extends Resource
## InstitutionConfig: Complete institution definition with event trees
## Contains stress-triggered tree and randomly-triggered tree
## Events are evaluated on day start

class_name InstitutionConfig

@export var institution_id: String = ""
@export var institution_name: String = ""
@export var institution_type: int = 2  # 0=MILITANT, 1=CIVILIAN, 2=POLICY, 3=INTELLIGENCE

# Initial stats
@export var initial_capacity: float = 50.0
@export var initial_strength: float = 100.0
@export var initial_stress: float = 0.0
@export var initial_influence: float = 0.0

# Stress-triggered event tree (triggers when stress >= strength on day start)
# Each node: {node_id, title, description, conditions, effects, choices[]}
# Each choice: {text, next_node, prunes_branches[], effects, cost, requires}
@export var stress_triggered_tree: Array[Dictionary] = []

# Randomly-triggered event tree (triggers with probability based on capacity on day start)
# Each node: {node_id, title, description, conditions, effects, choices[]}
# Each choice: {text, next_node, prunes_branches[], effects, cost, requires}
@export var randomly_triggered_tree: Array[Dictionary] = []

## Calculate random trigger probability based on capacity
## Linear function: 0.1 + capacity / 200.0 (max ~60% at capacity=100)
func get_random_trigger_probability(capacity: float) -> float:
	return 0.1 + (capacity / 200.0)

## Get node from stress tree by ID
func get_stress_node(node_id: String) -> Dictionary:
	for node in stress_triggered_tree:
		if node.get("node_id") == node_id:
			return node
	return {}

## Get node from random tree by ID  
func get_random_node(node_id: String) -> Dictionary:
	for node in randomly_triggered_tree:
		if node.get("node_id") == node_id:
			return node
	return {}

## Get the current stress event to display (based on tree state)
## Returns empty dict if tree is exhausted or all nodes pruned
func get_current_stress_event(current_node: String, pruned_branches: Array) -> Dictionary:
	# If we have a current node, try to return it
	if current_node != "":
		var node = get_stress_node(current_node)
		if not node.is_empty() and current_node not in pruned_branches:
			return node
	
	# Otherwise return root node (first in tree) if not pruned
	if stress_triggered_tree.size() > 0:
		var root = stress_triggered_tree[0]
		var root_id = root.get("node_id", "")
		if root_id not in pruned_branches:
			return root
	
	return {}

## Get the current random event to display (based on tree state)
## Returns empty dict if tree is exhausted or all nodes pruned
func get_current_random_event(current_node: String, pruned_branches: Array) -> Dictionary:
	# If we have a current node, try to return it
	if current_node != "":
		var node = get_random_node(current_node)
		if not node.is_empty() and current_node not in pruned_branches:
			return node
	
	# Otherwise return root node (first in tree) if not pruned
	if randomly_triggered_tree.size() > 0:
		var root = randomly_triggered_tree[0]
		var root_id = root.get("node_id", "")
		if root_id not in pruned_branches:
			return root
	
	return {}

## Check if stress event should trigger (stress >= strength)
func should_trigger_stress_event(stress: float, strength: float) -> bool:
	return stress >= strength

## Check if random event should trigger (probabilistic based on capacity)
func should_trigger_random_event(capacity: float) -> bool:
	var probability = get_random_trigger_probability(capacity)
	return randf() < probability

## Check if a specific node's conditions are met
func check_node_conditions(node: Dictionary, institution_state: Dictionary) -> bool:
	var conditions = node.get("conditions", {})
	
	if conditions.has("min_stress") and institution_state.get("stress", 0.0) < conditions["min_stress"]:
		return false
	if conditions.has("max_stress") and institution_state.get("stress", 0.0) > conditions["max_stress"]:
		return false
	if conditions.has("min_capacity") and institution_state.get("capacity", 0.0) < conditions["min_capacity"]:
		return false
	if conditions.has("max_capacity") and institution_state.get("capacity", 0.0) > conditions["max_capacity"]:
		return false
	if conditions.has("min_strength") and institution_state.get("strength", 0.0) < conditions["min_strength"]:
		return false
	if conditions.has("max_strength") and institution_state.get("strength", 0.0) > conditions["max_strength"]:
		return false
	if conditions.has("min_influence") and institution_state.get("influence", 0.0) < conditions["min_influence"]:
		return false
	if conditions.has("max_influence") and institution_state.get("influence", 0.0) > conditions["max_influence"]:
		return false
	
	return true

## Filter available choices based on player resources and institution state
func get_available_choices(node: Dictionary, player_state: Dictionary, institution_state: Dictionary) -> Array:
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
		
		# Check requirements
		var requires = choice.get("requires", {})
		if requires.get("min_influence", 0.0) > institution_state.get("influence", 0.0):
			meets_requirements = false
		
		# Add choice with availability info
		var choice_info = choice.duplicate()
		choice_info["can_afford"] = can_afford
		choice_info["meets_requirements"] = meets_requirements
		choice_info["available"] = can_afford and meets_requirements
		available.append(choice_info)
	
	return available
