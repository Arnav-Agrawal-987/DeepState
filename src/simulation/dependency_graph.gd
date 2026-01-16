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

## Apply crisis effects to the dependency graph
## Rewiring based on distance from epicenter:
## - Adjacent (1st level): weight += 0.5 * (epicenter_stress / epicenter_strength)
## - 2nd level: weight += 0.25 * ratio
## - 3rd level+: no effect
func apply_crisis_effects(crisis_effects: Dictionary, inst_manager: InstitutionManager) -> void:
	print("[DependencyGraph] === APPLYING CRISIS EFFECTS ===")
	
	# Get all institutions and find epicenter
	var institutions = inst_manager.get_all_institutions()
	
	# Find the epicenter (highest stress institution)
	var epicenter: Institution = null
	var max_stress = 0.0
	for inst in institutions:
		if inst.stress > max_stress:
			max_stress = inst.stress
			epicenter = inst
	
	if not epicenter:
		print("[DependencyGraph] No epicenter found!")
		return
	
	var epicenter_id = epicenter.institution_id
	var stress_ratio = epicenter.stress / max(epicenter.strength, 1.0)
	
	print("[DependencyGraph] Epicenter: %s" % epicenter_id)
	print("[DependencyGraph] Epicenter Stress: %.1f / Strength: %.1f = Ratio: %.3f" % [
		epicenter.stress, epicenter.strength, stress_ratio
	])
	
	# Calculate multipliers based on stress ratio
	var level_1_multiplier = 0.5 * stress_ratio   # Adjacent to epicenter
	var level_2_multiplier = 0.25 * stress_ratio  # 2nd level from epicenter
	
	print("[DependencyGraph] Level 1 (adjacent) multiplier: +%.3f" % level_1_multiplier)
	print("[DependencyGraph] Level 2 multiplier: +%.3f" % level_2_multiplier)
	
	var changes_made = 0
	
	# Get 1st level neighbors (direct connections FROM epicenter)
	var level_1_nodes: Array = []
	if epicenter_id in edges:
		for target_id in edges[epicenter_id]:
			level_1_nodes.append(target_id)
			# Apply level 1 effect to edges FROM epicenter
			var old_weight = edges[epicenter_id][target_id]
			var new_weight = clamp(old_weight + level_1_multiplier, 0.0, 1.0)
			edges[epicenter_id][target_id] = new_weight
			print("  [L1] Edge %s -> %s: %.3f -> %.3f (+%.3f)" % [
				epicenter_id, target_id, old_weight, new_weight, level_1_multiplier
			])
			changes_made += 1
	
	# Get 2nd level neighbors (connections FROM level 1 nodes, excluding epicenter)
	var level_2_nodes: Array = []
	for l1_node in level_1_nodes:
		if l1_node in edges:
			for target_id in edges[l1_node]:
				# Skip if target is epicenter or already in level 1
				if target_id == epicenter_id or target_id in level_1_nodes:
					continue
				# Skip if already processed as level 2
				if target_id in level_2_nodes:
					continue
				
				level_2_nodes.append(target_id)
				
				# Apply level 2 effect to edges FROM level 1 nodes
				var old_weight = edges[l1_node][target_id]
				var new_weight = clamp(old_weight + level_2_multiplier, 0.0, 1.0)
				edges[l1_node][target_id] = new_weight
				print("  [L2] Edge %s -> %s: %.3f -> %.3f (+%.3f)" % [
					l1_node, target_id, old_weight, new_weight, level_2_multiplier
				])
				changes_made += 1
	
	# Also apply to edges TO epicenter (incoming edges get affected too)
	var incoming = get_incoming_edges(epicenter_id)
	for source_id in incoming:
		if source_id in level_1_nodes:
			continue  # Already processed
		var old_weight = edges[source_id][epicenter_id]
		var new_weight = clamp(old_weight + level_1_multiplier, 0.0, 1.0)
		edges[source_id][epicenter_id] = new_weight
		print("  [L1-IN] Edge %s -> %s: %.3f -> %.3f (+%.3f)" % [
			source_id, epicenter_id, old_weight, new_weight, level_1_multiplier
		])
		changes_made += 1
	
	print("[DependencyGraph] Level 1 nodes: %s" % str(level_1_nodes))
	print("[DependencyGraph] Level 2 nodes: %s" % str(level_2_nodes))
	print("[DependencyGraph] Crisis made %d edge changes" % changes_made)

## Graph morphing after crisis based on perceived deep state influence
## Each institution calculates perceived influence of incoming neighbors:
## - High exposure: perception is more accurate
## - Low exposure: perception is more random
## Then reduces highest-influence edge by 25% and increases lowest-influence edge by 25%
const MORPH_PERCENT: float = 0.25  # 25% adjustment

func morph_after_crisis(exposure: float, inst_manager: InstitutionManager) -> void:
	print("[DependencyGraph] === GRAPH MORPHING AFTER CRISIS ===")
	print("[DependencyGraph] Player exposure: %.1f%%" % exposure)
	
	var changes_made = 0
	
	# For each institution, adjust incoming edge weights based on perceived deep state influence
	for inst_id in edges.keys():
		var inst = inst_manager.get_institution(inst_id)
		if inst == null:
			continue
		
		# Get incoming edges for this institution
		var incoming = get_incoming_edges(inst_id)
		if incoming.size() < 2:
			continue  # Need at least 2 edges to morph
		
		# Calculate perceived deep state influence for each incoming neighbor
		var perceived_influences: Dictionary = {}  # source_id -> perceived_influence
		
		for source_id in incoming:
			var source_inst = inst_manager.get_institution(source_id)
			if not source_inst:
				continue
			
			var actual_influence = source_inst.player_influence
			var perceived = _calculate_perceived_influence(actual_influence, exposure)
			perceived_influences[source_id] = perceived
		
		if perceived_influences.size() < 2:
			continue
		
		# Find highest and lowest perceived influence edges
		var highest_id: String = ""
		var highest_perceived: float = -1.0
		var lowest_id: String = ""
		var lowest_perceived: float = 101.0
		
		for source_id in perceived_influences:
			var perceived = perceived_influences[source_id]
			if perceived > highest_perceived:
				highest_perceived = perceived
				highest_id = source_id
			if perceived < lowest_perceived:
				lowest_perceived = perceived
				lowest_id = source_id
		
		if highest_id == "" or lowest_id == "" or highest_id == lowest_id:
			continue
		
		# Reduce weight of highest-influence edge by 25%
		var old_high_weight = edges[highest_id][inst_id]
		var reduction = old_high_weight * MORPH_PERCENT
		var new_high_weight = clamp(old_high_weight - reduction, 0.05, 1.0)
		edges[highest_id][inst_id] = new_high_weight
		
		# Increase weight of lowest-influence edge by the same amount (25% of original high weight)
		var old_low_weight = edges[lowest_id][inst_id]
		var new_low_weight = clamp(old_low_weight + reduction, 0.0, 1.0)
		edges[lowest_id][inst_id] = new_low_weight
		
		print("  [MORPH] %s: Reduced %s->%s (%.3f -> %.3f, perceived DS: %.1f)" % [
			inst_id, highest_id, inst_id, old_high_weight, new_high_weight, highest_perceived
		])
		print("  [MORPH] %s: Increased %s->%s (%.3f -> %.3f, perceived DS: %.1f)" % [
			inst_id, lowest_id, inst_id, old_low_weight, new_low_weight, lowest_perceived
		])
		changes_made += 2
	
	print("[DependencyGraph] Graph morphing made %d edge changes" % changes_made)

## Calculate perceived deep state influence based on exposure level
## High exposure = accurate perception, Low exposure = random/noisy perception
func _calculate_perceived_influence(actual_influence: float, exposure: float) -> float:
	# Accuracy factor: 0.0 (completely random) to 1.0 (perfectly accurate)
	var accuracy = exposure / 100.0
	
	# Random noise inversely proportional to exposure
	var noise_range = 50.0 * (1.0 - accuracy)  # 0-50 noise at low exposure
	var noise = randf_range(-noise_range, noise_range)
	
	# Perceived = weighted average of actual and random + noise
	var random_guess = randf_range(0.0, 100.0)
	var perceived = (actual_influence * accuracy) + (random_guess * (1.0 - accuracy)) + noise
	
	return clamp(perceived, 0.0, 100.0)

## Rewire dependencies after crisis resolution (LEGACY - kept for compatibility)
## Institutions ALWAYS attempt to improve resilience after a crisis
func rewire_for_resilience(inst_manager: InstitutionManager) -> void:
	print("[DependencyGraph] === REWIRING FOR RESILIENCE ===")
	
	var changes_made = 0
	
	# For each institution, reduce dependencies on stressed institutions
	# and slightly strengthen stable connections
	for inst_id in edges.keys():
		var inst = inst_manager.get_institution(inst_id)
		if inst == null:
			continue
		
		var current_outgoing = edges[inst_id].duplicate()
		for target_id in current_outgoing:
			var target = inst_manager.get_institution(target_id)
			if not target:
				continue
			
			var target_stress_ratio = target.stress / max(target.strength, 1.0)
			var old_weight = edges[inst_id][target_id]
			var new_weight = old_weight
			
			# Reduce weight to stressed institutions (>30% stress ratio)
			if target_stress_ratio > 0.3:
				var reduction = 0.1 * target_stress_ratio  # More stress = more reduction
				new_weight = clamp(old_weight - reduction, 0.05, 1.0)  # Don't go below 0.05
				print("  [RESILIENCE] Edge %s -> %s: %.3f -> %.3f (target stressed %.0f%%)" % [
					inst_id, target_id, old_weight, new_weight, target_stress_ratio * 100
				])
				changes_made += 1
			# Slightly increase weight to stable institutions (<20% stress ratio)
			elif target_stress_ratio < 0.2 and old_weight < 0.9:
				var increase = 0.05 * (1.0 - target_stress_ratio)
				new_weight = clamp(old_weight + increase, 0.0, 0.95)
				print("  [RESILIENCE] Edge %s -> %s: %.3f -> %.3f (target stable)" % [
					inst_id, target_id, old_weight, new_weight
				])
				changes_made += 1
			
			edges[inst_id][target_id] = new_weight
	
	print("[DependencyGraph] Resilience rewiring made %d edge changes" % changes_made)

## Propagate stress through the graph based on edge weights
## Called when stress changes on an institution
func propagate_stress(source_inst: Institution, inst_manager: InstitutionManager) -> void:
	var source_id = source_inst.institution_id
	if not source_id in edges:
		return
	
	var outgoing = edges[source_id]
	for target_id in outgoing:
		var weight = outgoing[target_id]
		var target = inst_manager.get_institution(target_id)
		if target:
			# Propagate a portion of source stress based on weight
			var propagated_stress = source_inst.stress * weight * 0.1  # 10% of stress * weight
			if propagated_stress > 1.0:
				target.apply_stress(propagated_stress)
				print("[DependencyGraph] Propagated %.1f stress from %s to %s (weight: %.2f)" % [
					propagated_stress, source_id, target_id, weight
				])

## Serialize graph
func to_dict() -> Dictionary:
	return {
		"edges": edges.duplicate(true)
	}

## Deserialize graph
func from_dict(data: Dictionary) -> void:
	edges = data.get("edges", {})

## Print all current graph weights in a readable format
func print_graph_weights(header: String = "GRAPH STATE", epicenter_id: String = "") -> void:
	print("")
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║ %s" % header.to_upper())
	if epicenter_id != "":
		print("║ Change originated from: %s" % epicenter_id)
	print("╠══════════════════════════════════════════════════════════════╣")
	
	if edges.is_empty():
		print("║ (No edges in graph)")
	else:
		for source_id in edges:
			var outgoing = edges[source_id]
			for target_id in outgoing:
				var weight = outgoing[target_id]
				var bar = _weight_to_bar(weight)
				print("║ %s → %s: %.3f %s" % [
					source_id.substr(0, 12).rpad(12),
					target_id.substr(0, 12).rpad(12),
					weight,
					bar
				])
	
	print("╚══════════════════════════════════════════════════════════════╝")
	print("")

## Helper to visualize weight as ASCII bar
func _weight_to_bar(weight: float) -> String:
	var bar_length = int(weight * 10)
	var bar = ""
	for i in range(10):
		if i < bar_length:
			bar += "█"
		else:
			bar += "░"
	return "[%s]" % bar
