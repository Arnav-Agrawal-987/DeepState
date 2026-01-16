extends Node
## InstitutionManager: Owns and manages all institutions
## Executes daily institution logic
## Reference: Logic section 2.2.3

class_name InstitutionManager

var institutions: Dictionary = {}  # ID -> Institution

func _ready() -> void:
	pass

## Register a new institution
func add_institution(inst: Institution) -> void:
	institutions[inst.institution_id] = inst
	add_child(inst)

## Get institution by ID
func get_institution(inst_id: String) -> Institution:
	return institutions.get(inst_id)

## Get all institutions
func get_all_institutions() -> Array:
	return institutions.values()

## Get institutions by type
func get_institutions_by_type(type: Institution.InstitutionType) -> Array:
	return institutions.values().filter(func(inst: Institution) -> bool:
		return inst.institution_type == type
	)

## Execute daily institution logic
## Order: capacity -> strength -> stress decay -> event check
func daily_update() -> void:
	for inst in institutions.values():
		# Daily increase strength by capacity
		inst.daily_auto_update()
		
		# Apply natural stress decay
		inst.apply_stress_decay()

## Check which institutions should trigger events
func get_stress_triggered_institutions() -> Array:
	return institutions.values().filter(func(inst: Institution) -> bool:
		return inst.should_trigger_stress_event()
	)

## Check stable events with probability
func get_stable_triggered_institutions() -> Array:
	var result = []
	for inst in institutions.values():
		var prob = inst.should_trigger_stable_event()
		if randf() < prob:
			result.append(inst)
	return result

## Get institution network stats
func get_total_stress() -> float:
	var total = 0.0
	for inst in institutions.values():
		total += inst.stress
	return total

## Serialize all institutions
func to_dict() -> Dictionary:
	var inst_data = {}
	for id in institutions:
		inst_data[id] = institutions[id].to_dict()
	return inst_data

## Deserialize institutions
func from_dict(data: Dictionary) -> void:
	for id in data:
		if id in institutions:
			institutions[id].from_dict(data[id])

# ============================================
# RELEVANCE CALCULATION SYSTEM
# ============================================

## Select crisis epicenter using weighted random selection
## Institutions with higher tension (stress) have higher probability
func select_crisis_epicenter() -> Institution:
	var insts = get_all_institutions()
	if insts.is_empty():
		return null
	
	# Calculate total weight (stress as weight)
	var total_weight: float = 0.0
	for inst in insts:
		# Use stress as weight, with minimum weight to ensure all have a chance
		var weight = max(inst.stress, 1.0)
		total_weight += weight
	
	# Weighted random selection
	var random_val = randf() * total_weight
	var cumulative: float = 0.0
	
	for inst in insts:
		cumulative += max(inst.stress, 1.0)
		if random_val <= cumulative:
			print("[InstitutionManager] Selected epicenter: %s (stress: %.1f)" % [inst.institution_name, inst.stress])
			return inst
	
	# Fallback to last institution
	return insts[-1]

## Calculate external deep state influence (ext_ds) for an institution
## ext_ds = max(incoming_neighbor.ds * edge_weight) for all incoming neighbors
func calculate_ext_ds(inst_id: String, dep_graph: Node) -> float:
	var incoming_edges = dep_graph.get_incoming_edges(inst_id)
	var ext_ds: float = 0.0
	
	for source_id in incoming_edges:
		var source_inst = get_institution(source_id)
		if source_inst:
			var edge_weight = incoming_edges[source_id]
			var ds = source_inst.player_influence  # ds = player's influence on that institution
			var weighted_ds = ds * edge_weight
			ext_ds = max(ext_ds, weighted_ds)
	
	return ext_ds

## Calculate relevance at crisis epicenter using recursive algorithm
## Returns relevance score (0-100) based on graph traversal with depth limit of 2
## 
## Algorithm:
##   nr = insti.ds; dr = 1
##   for each outgoing neighbor (up to depth 2):
##       (sub_nr, sub_dr) = calculate_relevance(neighbor, depth+1)
##       nr += sub_nr * 0.5 * insti.ext_ds
##       dr += sub_dr * 0.5
##   return nr / dr
func calculate_crisis_relevance(epicenter: Institution, dep_graph: Node) -> float:
	if not epicenter:
		return 0.0
	
	# Pre-calculate ext_ds for all institutions
	var ext_ds_map: Dictionary = {}
	for inst_id in institutions:
		ext_ds_map[inst_id] = calculate_ext_ds(inst_id, dep_graph)
	
	# Calculate relevance recursively from epicenter
	var result = _calculate_relevance_recursive(epicenter.institution_id, dep_graph, ext_ds_map, 0)
	var nr = result[0]
	var dr = result[1]
	
	# Avoid division by zero
	var relevance = nr / max(dr, 0.01)
	
	# Normalize to 0-100 range (influence is 0-100, so relevance should be similar)
	relevance = clamp(relevance, 0.0, 100.0)
	
	print("[InstitutionManager] Crisis relevance calculated: %.2f (nr=%.2f, dr=%.2f)" % [relevance, nr, dr])
	return relevance

## Recursive helper for relevance calculation
## Returns [numerator, denominator] tuple
func _calculate_relevance_recursive(inst_id: String, dep_graph: Node, ext_ds_map: Dictionary, depth: int) -> Array:
	# Depth limit of 2
	if depth > 2:
		return [0.0, 0.0]
	
	var inst = get_institution(inst_id)
	if not inst:
		return [0.0, 0.0]
	
	# Base values
	var nr: float = inst.player_influence  # ds = player's influence
	var dr: float = 1.0
	
	# Get ext_ds for this institution
	var ext_ds: float = ext_ds_map.get(inst_id, 0.0)
	
	# Traverse outgoing neighbors
	var outgoing_edges = dep_graph.get_outgoing_edges(inst_id)
	for target_id in outgoing_edges:
		var sub_result = _calculate_relevance_recursive(target_id, dep_graph, ext_ds_map, depth + 1)
		var sub_nr = sub_result[0]
		var sub_dr = sub_result[1]
		
		# Apply decay factor and ext_ds weight
		nr += sub_nr * 0.5 * (ext_ds / 100.0 + 0.1)  # Normalize ext_ds and add small base
		dr += sub_dr * 0.5
	
	return [nr, dr]
