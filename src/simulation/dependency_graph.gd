extends Node
## DependencyGraph: Directed weighted dependency network
## Manages institutional dependencies
## Reference: Logic section 2.3

class_name DependencyGraph

# Adjacency structure: source_id -> {target_id: weight}
var edges: Dictionary = {}

func _ready() -> void:
	pass

## Add an edge from source to target with weight
func add_edge(source_id: String, target_id: String, weight: float) -> void:
	if not source_id in edges:
		edges[source_id] = {}
	edges[source_id][target_id] = clamp(weight, 0.0, 1.0)

## Remove an edge
func remove_edge(source_id: String, target_id: String) -> void:
	if source_id in edges:
		edges[source_id].erase(target_id)

## Get outgoing edges from institution
func get_outgoing_edges(source_id: String) -> Dictionary:
	return edges.get(source_id, {}).duplicate()

## Get incoming edges to institution
func get_incoming_edges(target_id: String) -> Dictionary:
	var incoming = {}
	for source_id in edges:
		if target_id in edges[source_id]:
			incoming[source_id] = edges[source_id][target_id]
	return incoming

## Propagate stress through graph
## Returns stress multiplier for target based on incoming dependencies
func calculate_stress_propagation(source_id: String, target_id: String) -> float:
	if source_id in edges and target_id in edges[source_id]:
		return edges[source_id][target_id]
	return 0.0

## Rewire dependencies after crisis
## Institutions attempt to improve resilience by adjusting edges
func rewire_for_resilience(inst_manager: InstitutionManager) -> void:
	# For each institution, try to reduce incoming stress sources
	# and increase outgoing stability
	for inst_id in edges.keys():
		var inst = inst_manager.get_institution(inst_id)
		if inst == null:
			continue
		
		var current_outgoing = edges[inst_id].duplicate()
		for target_id in current_outgoing:
			# Reduce weight of high-stress dependencies
			var target = inst_manager.get_institution(target_id)
			if target and target.stress > target.strength * 0.7:
				edges[inst_id][target_id] *= 0.8

## Serialize graph
func to_dict() -> Dictionary:
	return {
		"edges": edges.duplicate(true)
	}

## Deserialize graph
func from_dict(data: Dictionary) -> void:
	edges = data.get("edges", {})
