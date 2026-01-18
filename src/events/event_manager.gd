extends Node
## EventManager: Resolves and applies event effects
## NEW: Collects events on day start into pending_events map for UI bubbles
## NEW: Delayed effects are queued and applied at next day start
## NEW: Event history for tracking resolved events
## Reference: Logic section 3.1

class_name EventManager

signal event_triggered(event_id: String, institution: Institution)
signal event_resolved(event_id: String)
signal autonomous_event_occurred(event_node: Dictionary, institution: Institution)
signal action_available(action_node: Dictionary, institution: Institution)
signal events_ready(pending_events: Dictionary)  # Emitted when day start events are collected
signal crisis_triggered(crisis_events: Array)  # NEW: Emitted when crisis events are triggered
signal event_queue_changed()  # NEW: Emitted when event queue changes

var inst_manager: InstitutionManager
var player_state: PlayerState
var tension_mgr: TensionManager
var clock: SimulationClock  # Direct reference to clock for current_day
var institution_configs: Dictionary = {}  # Reference to configs from SimulationRoot
var save_state: RegionSaveState  # Reference to save state

# Pending events map for UI consumption (DEPRECATED - use decision_queue instead)
# Structure: { event_key: institution } where event_key contains event data
# For crisis events, institution is null
var pending_events: Dictionary = {}

# Crisis events queue (separate from regular events)
var pending_crisis_events: Array = []

# NEW: Decision queue for events requiring player choices
# Events are added silently (effects applied immediately) and shown one-by-one
# Structure: Array of { "event": Dictionary, "type": EventType, "inst_id": String, "institution": Institution or null }
var decision_queue: Array = []

# Queued effects to be applied at next day start
# Structure: Array of { "effects": Dictionary, "institution": Institution or null, "source": String }
var queued_effects: Array = []

# Event history for resolved events
# Structure: Array of { "event": Dictionary, "institution_id": String, "choice": Dictionary, "day": int, "type": EventType }
var event_history: Array = []

# Event type enum for tracking
enum EventType { STRESS, RANDOM, CRISIS }

# ============================================
# DEFAULT ACTIONS PER INSTITUTION
# ============================================

## Get ALL default actions for an institution (always returns 5 actions)
## Actions have influence requirements at 0, 20, 40, 60, 80
## Each action shows whether it's unlocked based on current influence
func get_default_actions(institution: Institution) -> Array:
	var actions: Array = []
	var influence = institution.player_influence
	var inst_type = institution.institution_type
	
	# Define ALL 5 actions for each institution type
	match inst_type:
		Institution.InstitutionType.MILITANT:
			actions = [
				{
					"id": "mil_gather_intel",
					"title": "Gather Intelligence",
					"description": "Use contacts to collect military intelligence. Increases stress and influence.",
					"effects": {"stress": 5},
					"influence_change": 3,
					"cost": {"bandwidth": 5},
					"required_influence": 0
				},
				{
					"id": "mil_supply_ops",
					"title": "Supply Operations",
					"description": "Infiltrate supply lines. Increases stress and influence.",
					"effects": {"stress": 10},
					"influence_change": 5,
					"cost": {"bandwidth": 10, "cash": 50},
					"required_influence": 20
				},
				{
					"id": "mil_officer_network",
					"title": "Cultivate Officer Network",
					"description": "Build relationships with key officers. Causes tension.",
					"effects": {"stress": 15, "strength": -5},
					"influence_change": 8,
					"cost": {"bandwidth": 15, "cash": 100},
					"required_influence": 40
				},
				{
					"id": "mil_strategic_leak",
					"title": "Strategic Leak",
					"description": "Leak information to destabilize leadership. High risk, high reward.",
					"effects": {"stress": 25, "strength": -10},
					"influence_change": 10,
					"cost": {"bandwidth": 20},
					"required_influence": 60
				},
				{
					"id": "mil_coup_support",
					"title": "Support Coup Faction",
					"description": "Provide resources to dissenting officers. Maximum destabilization.",
					"effects": {"stress": 40, "capacity": -15},
					"influence_change": 15,
					"cost": {"bandwidth": 30, "cash": 200},
					"required_influence": 80
				}
			]
		
		Institution.InstitutionType.CIVILIAN:
			actions = [
				{
					"id": "civ_community_outreach",
					"title": "Community Outreach",
					"description": "Build grassroots support networks. Mild agitation.",
					"effects": {"stress": 5},
					"influence_change": 3,
					"cost": {"bandwidth": 5},
					"required_influence": 0
				},
				{
					"id": "civ_media_campaign",
					"title": "Media Campaign",
					"description": "Launch propaganda through civilian channels.",
					"effects": {"stress": 12, "exposure": 5},
					"influence_change": 5,
					"cost": {"bandwidth": 10, "cash": 30},
					"required_influence": 20
				},
				{
					"id": "civ_protest_organization",
					"title": "Organize Protests",
					"description": "Coordinate civilian demonstrations. Creates unrest.",
					"effects": {"stress": 20, "capacity": -5},
					"influence_change": 8,
					"cost": {"bandwidth": 15},
					"required_influence": 40
				},
				{
					"id": "civ_strike_action",
					"title": "General Strike",
					"description": "Orchestrate work stoppages. Major disruption.",
					"effects": {"stress": 30, "strength": -8},
					"influence_change": 10,
					"cost": {"bandwidth": 25, "cash": 100},
					"required_influence": 60
				},
				{
					"id": "civ_civil_unrest",
					"title": "Trigger Civil Unrest",
					"description": "Push civilian population to breaking point. Maximum chaos.",
					"effects": {"stress": 45, "capacity": -15},
					"influence_change": 15,
					"cost": {"bandwidth": 30, "cash": 150},
					"required_influence": 80
				}
			]
		
		Institution.InstitutionType.POLICY:
			actions = [
				{
					"id": "pol_policy_brief",
					"title": "Submit Policy Brief",
					"description": "Influence decision-making through analysis. Creates minor friction.",
					"effects": {"stress": 5},
					"influence_change": 3,
					"cost": {"bandwidth": 5},
					"required_influence": 0
				},
				{
					"id": "pol_lobby",
					"title": "Lobby Officials",
					"description": "Apply pressure to key policymakers.",
					"effects": {"stress": 10},
					"influence_change": 5,
					"cost": {"bandwidth": 10, "cash": 80},
					"required_influence": 20
				},
				{
					"id": "pol_scandal_expose",
					"title": "Expose Scandal",
					"description": "Leak damaging information about officials.",
					"effects": {"stress": 18, "strength": -8, "exposure": 8},
					"influence_change": 8,
					"cost": {"bandwidth": 15},
					"required_influence": 40
				},
				{
					"id": "pol_policy_sabotage",
					"title": "Sabotage Policy",
					"description": "Undermine government initiatives. Causes chaos.",
					"effects": {"stress": 28, "capacity": -10},
					"influence_change": 10,
					"cost": {"bandwidth": 20, "cash": 120},
					"required_influence": 60
				},
				{
					"id": "pol_regime_crisis",
					"title": "Trigger Regime Crisis",
					"description": "Create constitutional crisis. Maximum destabilization.",
					"effects": {"stress": 40, "strength": -15},
					"influence_change": 15,
					"cost": {"bandwidth": 30, "cash": 200},
					"required_influence": 80
				}
			]
		
		Institution.InstitutionType.INTELLIGENCE:
			actions = [
				{
					"id": "int_plant_asset",
					"title": "Plant Asset",
					"description": "Recruit an informant within the agency. Creates internal friction.",
					"effects": {"stress": 6},
					"influence_change": 3,
					"cost": {"bandwidth": 8},
					"required_influence": 0
				},
				{
					"id": "int_counter_intel",
					"title": "Counter-Intelligence Op",
					"description": "Feed disinformation to confuse operations.",
					"effects": {"stress": 12, "capacity": -3},
					"influence_change": 5,
					"cost": {"bandwidth": 12},
					"required_influence": 20
				},
				{
					"id": "int_data_breach",
					"title": "Data Breach",
					"description": "Steal classified information. High risk operation.",
					"effects": {"stress": 22, "strength": -8, "exposure": 10},
					"influence_change": 8,
					"cost": {"bandwidth": 18},
					"required_influence": 40
				},
				{
					"id": "int_double_agent",
					"title": "Turn Double Agent",
					"description": "Convert a senior officer. Creates major turmoil.",
					"effects": {"stress": 30},
					"influence_change": 12,
					"cost": {"bandwidth": 25, "cash": 150},
					"required_influence": 60
				},
				{
					"id": "int_agency_collapse",
					"title": "Trigger Agency Collapse",
					"description": "Expose the entire network. Maximum destabilization.",
					"effects": {"stress": 45, "strength": -20, "exposure": 15},
					"influence_change": 15,
					"cost": {"bandwidth": 35, "cash": 200},
					"required_influence": 80
				}
			]
	
	# Mark each action as unlocked/locked based on current influence
	for action in actions:
		action["unlocked"] = influence >= action.get("required_influence", 0)
	
	return actions

## Execute a default action on an institution
## Returns true if successful, false if failed (can't afford, locked, etc.)
func execute_default_action(action: Dictionary, institution: Institution) -> bool:
	# NOTE: Allow multiple actions per institution per day as long as the player can afford them.
	# The previous per-day limit check was removed to permit multiple affordable actions.
	
	# Check if action is unlocked
	var required_inf = action.get("required_influence", 0)
	if institution.player_influence < required_inf:
		print("[EventManager] Action locked - need %.0f influence, have %.0f" % [required_inf, institution.player_influence])
		return false
	
	var cost = action.get("cost", {})
	
	# Check if player can afford
	if not _can_afford(cost):
		print("[EventManager] Cannot afford default action: %s" % action.get("title", "?"))
		return false
	
	# Spend cost
	_spend_cost(cost)
	
	# Record action taken on this institution
	institution.record_action_taken()
	
	# Apply effects to institution
	var effects = action.get("effects", {})
	apply_effects(effects, institution)
	
	# Apply influence change (can be positive or negative)
	var influence_change = action.get("influence_change", 0)
	if influence_change != 0:
		institution.increase_influence(influence_change)
		print("[EventManager] Default action '%s' changed influence by %+d (now %.1f)" % [
			action.get("title", "?"), influence_change, institution.player_influence
		])
	
	# Add exposure from action (if any)
	var exposure_change = effects.get("exposure", 0)
	if exposure_change > 0:
		player_state.increase_exposure(exposure_change)
	
	print("[EventManager] Executed default action: %s on %s" % [action.get("title", "?"), institution.institution_name])
	return true

func _ready() -> void:
	pass

# ============================================
# DELAYED EFFECTS SYSTEM
# ============================================

## Queue effects to be applied at the start of the next day
func queue_delayed_effects(effects: Dictionary, institution: Institution = null, source: String = "") -> void:
	queued_effects.append({
		"effects": effects,
		"institution": institution,
		"source": source
	})
	print("[EventManager] Queued delayed effects from '%s': %s" % [source, str(effects)])

## Apply all queued effects (called at day start before collecting new events)
func apply_queued_effects() -> void:
	if queued_effects.is_empty():
		return
	
	print("[EventManager] === APPLYING %d QUEUED EFFECTS ===" % queued_effects.size())
	
	for queued in queued_effects:
		var effects = queued.get("effects", {})
		var institution = queued.get("institution")
		var source = queued.get("source", "unknown")
		
		print("[EventManager] Applying effects from '%s'" % source)
		
		if institution:
			apply_effects(effects, institution)
		else:
			_apply_global_effects(effects)
	
	queued_effects.clear()
	print("[EventManager] All queued effects applied")

# ============================================
# EXPOSURE CALCULATION SYSTEM
# ============================================

## Calculate exposure increase based on institution stats
## Linear function: exposure_gain = base_exposure * (stress/100 + influence/100 - strength/200) * (1 + current_exposure/100)
## Higher stress and influence = more exposure, higher strength = less exposure
func calculate_event_exposure(institution: Institution, base_exposure: float = 5.0) -> float:
	var stress_factor = institution.stress / 100.0  # 0.0 to 1.0
	var influence_factor = institution.player_influence / 100.0  # 0.0 to 1.0
	var strength_factor = institution.strength / 200.0  # 0.0 to 0.5 (higher strength reduces exposure)
	var current_exposure_factor = 1.0 + (player_state.exposure / 100.0)  # 1.0 to 2.0
	
	var exposure_gain = base_exposure * (stress_factor + influence_factor - strength_factor) * current_exposure_factor
	exposure_gain = max(0.0, exposure_gain)  # Don't go negative
	
	print("[EventManager] Exposure calc: base=%.1f, stress=%.2f, inf=%.2f, str=%.2f, curr=%.2f -> gain=%.1f" % [
		base_exposure, stress_factor, influence_factor, strength_factor, current_exposure_factor, exposure_gain
	])
	
	return exposure_gain

## Apply exposure increase when autonomous events trigger
func apply_event_triggered_exposure(institution: Institution) -> void:
	var exposure_gain = calculate_event_exposure(institution)
	if exposure_gain > 0:
		player_state.increase_exposure(exposure_gain)
		print("[EventManager] Auto-exposure increased by %.1f due to event at %s" % [exposure_gain, institution.institution_name])

# ============================================
# PROBABILISTIC AUTONOMOUS EFFECTS
# ============================================

## Apply probabilistic buffs/debuffs when autonomous event occurs
## Probability is based on institution capacity (lower capacity = higher chance of negative effects)
func apply_autonomous_event_effects(institution: Institution) -> void:
	# Base probability calculation: lower capacity = more likely to have effects
	# probability = (100 - capacity) / 100
	var effect_probability = (100.0 - institution.capacity) / 100.0
	
	print("[EventManager] === AUTONOMOUS EVENT EFFECTS ===")
	print("[EventManager] Institution: %s, Capacity: %.1f, Effect Prob: %.2f" % [
		institution.institution_name, institution.capacity, effect_probability
	])
	
	# Roll for each potential effect type
	var effects_applied: Array = []
	
	# Institution buffs/debuffs
	if randf() < effect_probability:
		# Stress increase (more likely with low capacity)
		var stress_change = randf_range(5.0, 15.0) * effect_probability
		institution.apply_stress(stress_change)
		effects_applied.append("stress +%.1f" % stress_change)
	
	if randf() < effect_probability * 0.5:
		# Strength decrease (less likely)
		var strength_change = randf_range(-8.0, -3.0) * effect_probability
		institution.strength = clamp(institution.strength + strength_change, 0.0, 100.0)
		institution.strength_changed.emit(institution.strength)
		effects_applied.append("strength %.1f" % strength_change)
	
	# Player/Deep State debuffs
	if randf() < effect_probability * 0.7:
		# Exposure increase
		var exposure_change = randf_range(2.0, 8.0) * effect_probability
		player_state.increase_exposure(exposure_change)
		effects_applied.append("exposure +%.1f" % exposure_change)
	
	if randf() < effect_probability * 0.3:
		# Bandwidth decrease (less likely)
		var bandwidth_change = randf_range(3.0, 10.0) * effect_probability
		player_state.spend_bandwidth(bandwidth_change)
		effects_applied.append("bandwidth -%.1f" % bandwidth_change)
	
	# Possible buff (inverse probability - higher capacity = more likely)
	var buff_probability = institution.capacity / 100.0 * 0.3
	if randf() < buff_probability:
		# Capacity increase
		var capacity_change = randf_range(2.0, 6.0)
		institution.capacity = clamp(institution.capacity + capacity_change, 0.0, 100.0)
		institution.capacity_changed.emit(institution.capacity)
		effects_applied.append("capacity +%.1f" % capacity_change)
	
	if effects_applied.is_empty():
		print("[EventManager] No probabilistic effects triggered")
	else:
		print("[EventManager] Applied effects: %s" % ", ".join(effects_applied))

# ============================================
# NEW EVENT COLLECTION SYSTEM
# ============================================

## Collect all day-start events from all institutions and crisis tree
## NEW LOGIC:
## 1. Stress events (stress >= strength): Apply effects SILENTLY to graph (no decision popup)
## 2. Push ONE autonomous/random event to decision_queue for player choice
## 3. Crisis events still go to pending_crisis_events for emergency popup
func collect_day_start_events(institutions: Array, region_config: RegionConfig) -> Dictionary:
	pending_events.clear()
	pending_crisis_events.clear()
	# Don't clear decision_queue here - it persists across days until resolved
	
	print("[EventManager] === COLLECTING DAY START EVENTS ===")
	
	var random_events_pool: Array = []  # Pool of possible random events for autonomous selection
	
	# Check each institution for stress and random events
	for inst in institutions:
		if not inst.institution_id in institution_configs:
			continue
		
		var config: InstitutionConfig = institution_configs[inst.institution_id]
		var inst_state = {
			"stress": inst.stress,
			"strength": inst.strength,
			"capacity": inst.capacity,
			"influence": inst.player_influence
		}
		
		# Get tree states from save
		var stress_tree_state = save_state.get_stress_tree_state(inst.institution_id) if save_state else {"current_node": "", "pruned_branches": []}
		var random_tree_state = save_state.get_random_tree_state(inst.institution_id) if save_state else {"current_node": "", "pruned_branches": []}
		
		# Check stress-triggered event (stress >= strength)
		# SILENT: Apply effects immediately, NO popup (graph effects only)
		if config.should_trigger_stress_event(inst.stress, inst.strength):
			var stress_event = config.get_current_stress_event(
				stress_tree_state.get("current_node", ""),
				stress_tree_state.get("pruned_branches", [])
			)
			if not stress_event.is_empty():
				if config.check_node_conditions(stress_event, inst_state):
					print("  [%s] STRESS EVENT (SILENT): %s" % [inst.institution_name, stress_event.get("title", "?")])
					
					# SILENT: Apply base event effects to dependency graph
					var base_effects = stress_event.get("effects", {})
					if not base_effects.is_empty():
						apply_effects(base_effects, inst)
						print("  -> Applied silent graph effects: %s" % str(base_effects))
					
					# Apply exposure increase when stress event triggers
					apply_event_triggered_exposure(inst)
					# Apply autonomous effects based on capacity
					apply_autonomous_event_effects(inst)
					
					# Track in pending_events for backwards compatibility
					var event_key = {
						"event": stress_event,
						"type": EventType.STRESS,
						"inst_id": inst.institution_id
					}
					pending_events[event_key] = inst
		
		# Collect random events into pool for autonomous selection
		if config.should_trigger_random_event(inst.capacity):
			var random_event = config.get_current_random_event(
				random_tree_state.get("current_node", ""),
				random_tree_state.get("pruned_branches", [])
			)
			if not random_event.is_empty():
				if config.check_node_conditions(random_event, inst_state):
					random_events_pool.append({
						"event": random_event,
						"institution": inst,
						"probability": config.get_random_trigger_probability(inst.capacity)
					})
	
	# Push ONE random/autonomous event to decision queue
	if not random_events_pool.is_empty():
		# Weight selection by probability
		var total_weight = 0.0
		for evt in random_events_pool:
			total_weight += evt["probability"]
		
		var roll = randf() * total_weight
		var accumulated = 0.0
		var selected_event = null
		
		for evt in random_events_pool:
			accumulated += evt["probability"]
			if roll <= accumulated:
				selected_event = evt
				break
		
		if selected_event == null:
			selected_event = random_events_pool[0]
		
		var inst = selected_event["institution"]
		var random_event = selected_event["event"]
		
		print("  [%s] AUTONOMOUS EVENT -> QUEUE: %s" % [inst.institution_name, random_event.get("title", "?")])
		
		# Apply immediate graph effects
		var base_effects = random_event.get("effects", {})
		if not base_effects.is_empty():
			apply_effects(base_effects, inst)
			print("  -> Applied immediate effects: %s" % str(base_effects))
		
		# Apply exposure increase
		apply_event_triggered_exposure(inst)
		
		# Add to decision queue (player will see popup with choices)
		var queue_entry = {
			"event": random_event,
			"type": EventType.RANDOM,
			"inst_id": inst.institution_id,
			"institution": inst
		}
		decision_queue.append(queue_entry)
		
		# Also track in pending_events for backwards compatibility
		var event_key = {
			"event": random_event,
			"type": EventType.RANDOM,
			"inst_id": inst.institution_id
		}
		pending_events[event_key] = inst
	
	# Check global crisis event (tension >= threshold) - SEPARATE QUEUE
	if tension_mgr and region_config:
		var crisis_threshold = tension_mgr.crisis_threshold if tension_mgr else 100.0
		if tension_mgr.global_tension >= crisis_threshold:
			var crisis_state = save_state.crisis_tree_state if save_state else {"current_node": "", "pruned_branches": []}
			var crisis_event = _get_current_crisis_event(
				region_config,
				crisis_state.get("current_node", ""),
				crisis_state.get("pruned_branches", [])
			)
			if not crisis_event.is_empty():
				var crisis_data = {
					"event": crisis_event,
					"type": EventType.CRISIS,
					"inst_id": ""
				}
				pending_crisis_events.append(crisis_data)
				print("  [GLOBAL] CRISIS EVENT: %s" % crisis_event.get("title", "?"))
				
				# IMMEDIATE: Apply crisis base effects
				var base_effects = crisis_event.get("effects", {})
				if not base_effects.is_empty():
					_apply_global_effects(base_effects)
					print("  -> Applied immediate crisis effects: %s" % str(base_effects))
				
				# Emit crisis signal
				crisis_triggered.emit(pending_crisis_events)
	
	print("[EventManager] Silent stress events: %d, Decision queue: %d, Crisis events: %d" % [
		pending_events.size() - decision_queue.size(),
		decision_queue.size(),
		pending_crisis_events.size()
	])
	event_queue_changed.emit()
	events_ready.emit(pending_events)
	return pending_events

## Get all pending crisis events
func get_pending_crisis_events() -> Array:
	return pending_crisis_events

## Get the decision queue (events requiring player choices)
func get_decision_queue() -> Array:
	return decision_queue

## Get the size of the decision queue
func get_decision_queue_size() -> int:
	return decision_queue.size()

## Check if there are events in the decision queue
func has_pending_decisions() -> bool:
	return not decision_queue.is_empty()

## Get the next event from the decision queue (peek, doesn't remove)
func peek_next_decision() -> Dictionary:
	if decision_queue.is_empty():
		return {}
	return decision_queue[0]

## Resolve the next event in the decision queue with a player choice
## Applies choice effects IMMEDIATELY (not delayed) and pops from queue
func resolve_queue_decision(choice_index: int) -> Dictionary:
	if decision_queue.is_empty():
		push_warning("[EventManager] No events in decision queue")
		return {}
	
	var queue_entry = decision_queue[0]
	var event_node = queue_entry.get("event", {})
	var event_type = queue_entry.get("type", EventType.RANDOM)
	var inst_id = queue_entry.get("inst_id", "")
	var institution = queue_entry.get("institution")
	
	var node_id = event_node.get("node_id", "")
	var choices = event_node.get("choices", [])
	
	print("[EventManager] === RESOLVING QUEUED DECISION ===")
	print("[EventManager] Event: %s" % event_node.get("title", "?"))
	print("[EventManager] Queue position: 1/%d" % decision_queue.size())
	
	if choice_index < 0 or choice_index >= choices.size():
		push_warning("[EventManager] Invalid choice index: %d" % choice_index)
		return {}
	
	var choice = choices[choice_index]
	print("[EventManager] Choice: %s" % choice.get("text", "?"))
	
	# Check cost
	var cost = choice.get("cost", {})
	if not _can_afford(cost):
		push_warning("[EventManager] Cannot afford choice cost")
		return {"error": "cannot_afford"}
	
	# Spend cost (costs apply immediately)
	_spend_cost(cost)
	
	# IMMEDIATE EFFECTS: Apply choice effects NOW (not delayed)
	var choice_effects = choice.get("effects", {})
	var effects_applied = {}
	if not choice_effects.is_empty():
		# Apply to institution if available
		if institution:
			apply_effects(choice_effects, institution)
		else:
			_apply_global_effects(choice_effects)
		effects_applied = choice_effects
		print("[EventManager] Applied immediate choice effects: %s" % str(choice_effects))
	
	# Auto-adjust influence based on player response
	if institution:
		var influence_change = _calculate_event_influence_change(choice, event_type)
		if influence_change != 0:
			institution.increase_influence(influence_change)
			print("[EventManager] Influence changed by %+.1f" % influence_change)
	
	# Update tree state in save
	if save_state:
		match event_type:
			EventType.STRESS:
				save_state.record_stress_event(inst_id, node_id, choice)
			EventType.RANDOM:
				save_state.record_random_event(inst_id, node_id, choice)
	
	# Get current day for history
	var current_day = clock.get_current_day() if clock else 0
	
	# Add to event history
	event_history.append({
		"event": event_node,
		"institution_id": inst_id,
		"choice": choice,
		"day": current_day,
		"type": event_type
	})
	
	# Pop from queue
	decision_queue.remove_at(0)
	event_queue_changed.emit()
	event_resolved.emit(node_id)
	
	print("[EventManager] Decision resolved, %d decisions remaining" % decision_queue.size())
	
	return {
		"event": event_node,
		"choice": choice,
		"effects_applied": effects_applied,
		"remaining": decision_queue.size()
	}

## Skip the current queued decision (do nothing)
func skip_queue_decision() -> Dictionary:
	if decision_queue.is_empty():
		push_warning("[EventManager] No events in decision queue")
		return {}
	
	var queue_entry = decision_queue[0]
	var event_node = queue_entry.get("event", {})
	
	print("[EventManager] Skipping queued decision: %s" % event_node.get("title", "?"))
	
	# Pop from queue without applying effects
	decision_queue.remove_at(0)
	event_queue_changed.emit()
	
	return {
		"event": event_node,
		"skipped": true,
		"remaining": decision_queue.size()
	}

## Clear the entire decision queue
func clear_decision_queue() -> void:
	decision_queue.clear()
	event_queue_changed.emit()

# Reference to dependency graph (set by SimulationRoot)
var dep_graph: DependencyGraph

## Resolve a crisis event with player choice
func resolve_crisis_event(crisis_index: int, choice_index: int) -> void:
	if crisis_index < 0 or crisis_index >= pending_crisis_events.size():
		push_warning("[EventManager] Invalid crisis index: %d" % crisis_index)
		return
	
	var crisis_data = pending_crisis_events[crisis_index]
	var event_node = crisis_data.get("event", {})
	var choices = event_node.get("choices", [])
	
	if choice_index < 0 or choice_index >= choices.size():
		push_warning("[EventManager] Invalid crisis choice index: %d" % choice_index)
		return
	
	var choice = choices[choice_index]
	var node_id = event_node.get("node_id", "")
	
	print("[EventManager] === RESOLVING CRISIS ===")
	print("[EventManager] Crisis: %s" % event_node.get("title", "?"))
	print("[EventManager] Choice: %s" % choice.get("text", "?"))
	
	# Check cost
	var cost = choice.get("cost", {})
	if not _can_afford(cost):
		push_warning("[EventManager] Cannot afford crisis choice cost")
		return
	
	# Spend cost
	_spend_cost(cost)
	
	# CRISIS EFFECTS ON DEPENDENCY GRAPH
	# Apply crisis base effects to rewire graph
	var base_effects = event_node.get("effects", {})
	if dep_graph and inst_manager:
		dep_graph.apply_crisis_effects(base_effects, inst_manager)
		print("[EventManager] Applied crisis effects to dependency graph")
	
	# Queue choice effects for next day (delayed)
	var choice_effects = choice.get("effects", {})
	if not choice_effects.is_empty():
		queue_delayed_effects(choice_effects, null, "Crisis Choice: %s" % choice.get("text", "?"))
	
	# After crisis resolution, morph graph based on perceived deep state influence
	if dep_graph and inst_manager and player_state:
		dep_graph.morph_after_crisis(player_state.exposure, inst_manager)
	
	# Update tree state
	if save_state:
		save_state.record_crisis_event(node_id, choice)
	
	# Add to history
	# Get current day safely
	var current_day = clock.get_current_day() if clock else 0
	
	event_history.append({
		"event": event_node,
		"institution_id": "",
		"choice": choice,
		"day": current_day,
		"type": EventType.CRISIS
	})
	
	# Remove from pending
	pending_crisis_events.remove_at(crisis_index)
	event_queue_changed.emit()
	event_resolved.emit(node_id)
	print("[EventManager] Crisis resolved, %d crisis events remaining" % pending_crisis_events.size())

## Get current crisis event based on tree state
func _get_current_crisis_event(region_config: RegionConfig, current_node: String, pruned_branches: Array) -> Dictionary:
	if current_node != "":
		var node = region_config.get_crisis_node(current_node)
		if not node.is_empty() and current_node not in pruned_branches:
			return node
	
	# Return root node if not pruned
	if region_config.crisis_tree.size() > 0:
		var root = region_config.crisis_tree[0]
		var root_id = root.get("node_id", "")
		if root_id not in pruned_branches:
			return root
	
	return {}

## Resolve an event with a player choice
## event_key: The key from pending_events (contains event, type, inst_id)
## choice_index: Which choice the player picked
func resolve_event(event_key: Dictionary, choice_index: int) -> void:
	var event_node = event_key.get("event", {})
	var event_type = event_key.get("type", EventType.STRESS)
	var inst_id = event_key.get("inst_id", "")
	var institution = pending_events.get(event_key)
	
	var node_id = event_node.get("node_id", "")
	var choices = event_node.get("choices", [])
	
	print("[EventManager] === RESOLVING EVENT ===")
	print("[EventManager] Node: [%s] %s" % [node_id, event_node.get("title", "?")])
	print("[EventManager] Type: %s" % EventType.keys()[event_type])
	
	if choice_index < 0 or choice_index >= choices.size():
		push_warning("[EventManager] Invalid choice index: %d" % choice_index)
		return
	
	var choice = choices[choice_index]
	print("[EventManager] Choice: %s" % choice.get("text", "?"))
	
	# Check cost
	var cost = choice.get("cost", {})
	if not _can_afford(cost):
		push_warning("[EventManager] Cannot afford choice cost")
		return
	
	# Spend cost (costs apply immediately)
	_spend_cost(cost)
	
	# Note: Base event effects were already applied immediately when event was collected
	# Now queue only choice-specific effects for next day start (DELAYED EFFECTS)
	var choice_effects = choice.get("effects", {})
	if not choice_effects.is_empty():
		queue_delayed_effects(choice_effects, institution, "Choice: %s" % choice.get("text", "?"))
	
	# Auto-adjust influence based on player response to event
	# Influence change depends on event type and choice aggressiveness
	if institution:
		var influence_change = _calculate_event_influence_change(choice, event_type)
		if influence_change != 0:
			institution.increase_influence(influence_change)
			print("[EventManager] Event response changed influence by %+.1f (now %.1f)" % [
				influence_change, institution.player_influence
			])
	
	print("[EventManager] Effects queued for next day start (%d total queued)" % queued_effects.size())
	
	# Update tree state in save
	if save_state:
		match event_type:
			EventType.STRESS:
				save_state.record_stress_event(inst_id, node_id, choice)
			EventType.RANDOM:
				save_state.record_random_event(inst_id, node_id, choice)
			EventType.CRISIS:
				save_state.record_crisis_event(node_id, choice)
	
	# Add to event history
	var current_day = clock.get_current_day() if clock else 0
	
	event_history.append({
		"event": event_node,
		"institution_id": inst_id,
		"choice": choice,
		"day": current_day,
		"type": event_type
	})
	
	# Remove from pending
	pending_events.erase(event_key)
	event_queue_changed.emit()
	
	# Emit signals
	event_resolved.emit(node_id)
	print("[EventManager] Event resolved, %d events remaining" % pending_events.size())

## Calculate influence change based on player's event response
func _calculate_event_influence_change(choice: Dictionary, event_type: int) -> float:
	var change = 0.0
	var choice_effects = choice.get("effects", {})
	
	# Influence change based on effect types in choice
	# Aggressive actions (high stress, negative strength) = more influence
	# Passive/stabilizing actions = less influence change
	
	var stress_effect = choice_effects.get("stress", 0)
	var strength_effect = choice_effects.get("strength", 0)
	var capacity_effect = choice_effects.get("capacity", 0)
	
	# Higher stress caused = more influence (aggressive action)
	if stress_effect > 0:
		change += stress_effect * 0.2
	elif stress_effect < 0:
		change += stress_effect * 0.1  # Reducing stress also gains some influence
	
	# Negative strength = more influence (destabilizing)
	if strength_effect < 0:
		change += abs(strength_effect) * 0.15
	
	# Cost spent indicates investment = small influence gain
	var cost = choice.get("cost", {})
	if cost is Dictionary:
		change += (cost.get("bandwidth", 0) + cost.get("cash", 0) / 10) * 0.05
	elif cost is int:
		change += cost * 0.05
	
	return clamp(change, -5.0, 10.0)

## Get event history
func get_event_history() -> Array:
	return event_history

## Apply effects that are global (not institution-specific) - supports both formats
func _apply_global_effects(effects: Dictionary) -> void:
	var tension_val = effects.get("tension_change", effects.get("tension", null))
	if tension_val != null:
		tension_mgr.add_tension(tension_val)
	
	var cash_val = effects.get("cash_change", effects.get("cash", null))
	if cash_val != null:
		if cash_val > 0:
			player_state.gain_cash(cash_val)
		else:
			player_state.spend_cash(abs(cash_val))
	
	var bandwidth_val = effects.get("bandwidth_change", effects.get("bandwidth", null))
	if bandwidth_val != null:
		if bandwidth_val > 0:
			player_state.gain_bandwidth(bandwidth_val)
		else:
			player_state.spend_bandwidth(abs(bandwidth_val))
	
	var exposure_val = effects.get("exposure_change", effects.get("exposure", null))
	if exposure_val != null:
		if exposure_val > 0:
			player_state.increase_exposure(exposure_val)
		else:
			player_state.decrease_exposure(abs(exposure_val))
	
	# Handle "all institutions" effects for crisis events
	if "all_stress_change" in effects and inst_manager:
		for inst in inst_manager.get_all_institutions():
			if effects["all_stress_change"] > 0:
				inst.apply_stress(effects["all_stress_change"])
			else:
				inst.reduce_stress(abs(effects["all_stress_change"]))
	
	if "all_influence_change" in effects and inst_manager:
		for inst in inst_manager.get_all_institutions():
			inst.increase_influence(effects["all_influence_change"])

## Get pending events (for UI to read)
func get_pending_events() -> Dictionary:
	return pending_events

## Check if there are pending events
func has_pending_events() -> bool:
	return pending_events.size() > 0

# ============================================
# EXISTING METHODS (kept for compatibility)
# ============================================

## Trigger event and apply effects
func trigger_event(
	event_id: String,
	institution: Institution,
	effects: Dictionary
) -> void:
	event_triggered.emit(event_id, institution)
	apply_effects(effects, institution)
	event_resolved.emit(event_id)

## Apply event effects to game state
## Supports both formats: "stress_change" (long) and "stress" (short)
func apply_effects(effects: Dictionary, institution: Institution) -> void:
	# Institution effects - support both "stress_change" and "stress" formats
	var stress_val = effects.get("stress_change", effects.get("stress", null))
	if stress_val != null:
		if stress_val > 0:
			institution.apply_stress(stress_val)
		else:
			institution.reduce_stress(abs(stress_val))
	
	var capacity_val = effects.get("capacity_change", effects.get("capacity", null))
	if capacity_val != null:
		institution.capacity = clamp(institution.capacity + capacity_val, 0.0, 100.0)
		institution.capacity_changed.emit(institution.capacity)
	
	var strength_val = effects.get("strength_change", effects.get("strength", null))
	if strength_val != null:
		institution.strength = clamp(institution.strength + strength_val, 0.0, 100.0)
		institution.strength_changed.emit(institution.strength)
	
	var influence_val = effects.get("influence_change", effects.get("influence", null))
	if influence_val != null:
		institution.increase_influence(influence_val)
	
	# Player effects - support both formats
	var cash_val = effects.get("cash_change", effects.get("cash", null))
	if cash_val != null:
		if cash_val > 0:
			player_state.gain_cash(cash_val)
		else:
			player_state.spend_cash(abs(cash_val))
	
	var bandwidth_val = effects.get("bandwidth_change", effects.get("bandwidth", null))
	if bandwidth_val != null:
		if bandwidth_val > 0:
			player_state.gain_bandwidth(bandwidth_val)
		else:
			player_state.spend_bandwidth(abs(bandwidth_val))
	
	var exposure_val = effects.get("exposure_change", effects.get("exposure", null))
	if exposure_val != null:
		if exposure_val > 0:
			player_state.increase_exposure(exposure_val)
		else:
			player_state.decrease_exposure(abs(exposure_val))
	
	# Tension effects
	var tension_val = effects.get("tension_change", effects.get("tension", null))
	if tension_val != null:
		tension_mgr.add_tension(tension_val)

## Execute a player action from the tree
func execute_player_action(action_node: Dictionary, institution: Institution, choice_index: int = -1) -> bool:
	var node_id = str(action_node.get("node_id", "NO_ID"))
	var title = str(action_node.get("title", "NO_TITLE"))
	var cost = action_node.get("cost", {})
	
	print("[EventManager] === EXECUTE PLAYER ACTION ===" )
	print("[EventManager] Node: [%s] %s" % [node_id, title])
	print("[EventManager] Institution: %s" % institution.institution_name)
	print("[EventManager] Cost: %s" % str(cost))
	
	# Check if player can afford the action
	if not _can_afford(cost):
		print("[EventManager] FAILED - Cannot afford action")
		return false
	
	# Spend the cost
	_spend_cost(cost)
	
	# Apply effects
	var effects = action_node.get("effects", {})
	print("[EventManager] Base Effects: %s" % str(effects))
	apply_effects(effects, institution)
	
	# Get the choice that was made (for branching)
	var choice_data = {}
	if choice_index >= 0 and action_node.has("choices"):
		var choices = action_node.get("choices", [])
		if choice_index < choices.size():
			choice_data = choices[choice_index]
			print("[EventManager] Choice made: %s" % str(choice_data.get("text", "?")))
			
			# Apply choice-specific effects
			if choice_data.has("effects"):
				print("[EventManager] Choice Effects: %s" % str(choice_data["effects"]))
				apply_effects(choice_data["effects"], institution)
			
			# Log branching info
			if choice_data.has("next_node"):
				print("[EventManager] -> BRANCHES TO: %s" % choice_data["next_node"])
			if choice_data.has("prunes_branches"):
				print("[EventManager] -> PRUNES: %s" % str(choice_data["prunes_branches"]))
	
	# Record in save state with branching info
	if save_state:
		save_state.record_institution_event(institution.institution_id, node_id, true, choice_data, choice_index)
		print("[EventManager] Recorded to save state")
	
	print("[EventManager] SUCCESS - Action completed")
	event_triggered.emit(node_id, institution)
	return true

## Check if player can afford a cost (cost can be int for bandwidth or Dictionary)
func _can_afford(cost) -> bool:
	if cost is int:
		return cost <= player_state.bandwidth
	elif cost is Dictionary:
		if cost.get("cash", 0.0) > player_state.cash:
			return false
		if cost.get("bandwidth", 0.0) > player_state.bandwidth:
			return false
	return true

## Spend the cost (cost can be int for bandwidth or Dictionary)
func _spend_cost(cost) -> void:
	if cost is int:
		player_state.spend_bandwidth(cost)
	elif cost is Dictionary:
		if "cash" in cost:
			player_state.spend_cash(cost["cash"])
		if "bandwidth" in cost:
			player_state.spend_bandwidth(cost["bandwidth"])

## Get current stress event for institution (NEW - uses tree system)
func get_current_stress_event(institution: Institution, config: InstitutionConfig) -> Dictionary:
	var tree_state = save_state.get_stress_tree_state(institution.institution_id) if save_state else {"current_node": "", "pruned_branches": []}
	var current_node = tree_state.get("current_node", "")
	var pruned_branches = tree_state.get("pruned_branches", [])
	return config.get_current_stress_event(current_node, pruned_branches)

## Get current random event for institution (NEW - uses tree system)
func get_current_random_event(institution: Institution, config: InstitutionConfig) -> Dictionary:
	var tree_state = save_state.get_random_tree_state(institution.institution_id) if save_state else {"current_node": "", "pruned_branches": []}
	var current_node = tree_state.get("current_node", "")
	var pruned_branches = tree_state.get("pruned_branches", [])
	return config.get_current_random_event(current_node, pruned_branches)

## Process an autonomous event (apply auto effects, return player choices)
func process_autonomous_event(event_node: Dictionary, institution: Institution, choice_index: int = -1) -> Array:
	var node_id = str(event_node.get("node_id", "NO_ID"))
	var title = str(event_node.get("title", "NO_TITLE"))
	
	print("[EventManager] === PROCESS AUTONOMOUS EVENT ===" )
	print("[EventManager] Node: [%s] %s" % [node_id, title])
	print("[EventManager] Institution: %s" % institution.institution_name)
	
	# Apply automatic effects (use "effects" from new format)
	var auto_effects = event_node.get("effects", event_node.get("auto_effects", {}))
	print("[EventManager] Auto Effects: %s" % str(auto_effects))
	apply_effects(auto_effects, institution)
	
	# Get choices - support both "choices" (new format) and "player_choices" (old format)
	var choices_array = event_node.get("choices", event_node.get("player_choices", []))
	
	# Get the choice that was made (for branching)
	var choice_data = {}
	if choice_index >= 0 and choices_array.size() > 0:
		if choice_index < choices_array.size():
			choice_data = choices_array[choice_index]
			var choice_text = choice_data.get("text", choice_data.get("label", "?"))
			print("[EventManager] Choice made: %s" % choice_text)
			
			# Apply choice-specific effects
			if choice_data.has("effects"):
				print("[EventManager] Choice Effects: %s" % str(choice_data["effects"]))
				apply_effects(choice_data["effects"], institution)
			
			# Log branching info
			if choice_data.has("next_node"):
				print("[EventManager] -> BRANCHES TO: %s" % choice_data["next_node"])
			if choice_data.has("prunes_branches"):
				print("[EventManager] -> PRUNES: %s" % str(choice_data["prunes_branches"]))
	
	# Record in save state with branching info
	if save_state:
		save_state.record_institution_event(institution.institution_id, node_id, false, choice_data, choice_index)
		print("[EventManager] Recorded to save state")
	
	# Emit signal
	autonomous_event_occurred.emit(event_node, institution)
	
	# Return choices for UI (if choice hasn't been made yet)
	if choice_index < 0:
		print("[EventManager] Returning %d choices" % choices_array.size())
		for i in range(choices_array.size()):
			var c = choices_array[i]
			var txt = c.get("text", c.get("label", "?"))
			print("  [%d] %s" % [i, txt])
		return choices_array
	else:
		return []

## Get available actions for institution and player state
func get_available_actions(institution: Institution) -> Array:
	# Actions limited by influence tier
	var actions = []
	
	if institution.player_influence >= 10:
		actions.append("light_pressure")
	if institution.player_influence >= 30:
		actions.append("moderate_pressure")
	if institution.player_influence >= 60:
		actions.append("heavy_pressure")
	if institution.player_influence >= 80:
		actions.append("deep_action")
	
	return actions
