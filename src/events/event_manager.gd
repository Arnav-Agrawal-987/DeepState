extends Node
## EventManager: Resolves and applies event effects
## Reference: Logic section 3.1

class_name EventManager

signal event_triggered(event_id: String, institution: Institution)
signal event_resolved(event_id: String)
signal autonomous_event_occurred(event_node: Dictionary, institution: Institution)
signal action_available(action_node: Dictionary, institution: Institution)

var inst_manager: InstitutionManager
var player_state: PlayerState
var tension_mgr: TensionManager
var institution_configs: Dictionary = {}  # Reference to configs from SimulationRoot
var save_state: RegionSaveState  # Reference to save state

func _ready() -> void:
	pass

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
func apply_effects(effects: Dictionary, institution: Institution) -> void:
	# Institution effects
	if "stress_change" in effects:
		if effects["stress_change"] > 0:
			institution.apply_stress(effects["stress_change"])
		else:
			institution.reduce_stress(abs(effects["stress_change"]))
	
	if "capacity_change" in effects:
		institution.capacity = clamp(institution.capacity + effects["capacity_change"], 0.0, 100.0)
		institution.capacity_changed.emit(institution.capacity)
	
	if "strength_change" in effects:
		institution.strength = clamp(institution.strength + effects["strength_change"], 0.0, 100.0)
		institution.strength_changed.emit(institution.strength)
	
	if "influence_change" in effects:
		institution.increase_influence(effects["influence_change"])
	
	# Player effects
	if "cash_change" in effects:
		if effects["cash_change"] > 0:
			player_state.gain_cash(effects["cash_change"])
		else:
			player_state.spend_cash(abs(effects["cash_change"]))
	
	if "exposure_change" in effects:
		player_state.increase_exposure(effects["exposure_change"])
	
	# Tension effects
	if "tension_change" in effects:
		tension_mgr.add_tension(effects["tension_change"])

## Execute a player action from the tree
func execute_player_action(action_node: Dictionary, institution: Institution) -> bool:
	var cost = action_node.get("cost", {})
	
	# Check if player can afford the action
	if not _can_afford(cost):
		print("Cannot afford action: %s" % action_node.get("title", "Unknown"))
		return false
	
	# Spend the cost
	_spend_cost(cost)
	
	# Apply effects
	var effects = action_node.get("effects", {})
	apply_effects(effects, institution)
	
	# Record in save state
	if save_state:
		save_state.record_institution_event(institution.institution_id, action_node.get("node_id", ""), true)
	
	print("Executed action: %s on %s" % [action_node.get("title", "Unknown"), institution.institution_name])
	event_triggered.emit(action_node.get("node_id", ""), institution)
	return true

## Check if player can afford a cost
func _can_afford(cost: Dictionary) -> bool:
	if cost.get("cash", 0.0) > player_state.cash:
		return false
	if cost.get("bandwidth", 0.0) > player_state.bandwidth:
		return false
	return true

## Spend the cost
func _spend_cost(cost: Dictionary) -> void:
	if "cash" in cost:
		player_state.spend_cash(cost["cash"])
	if "bandwidth" in cost:
		player_state.spend_bandwidth(cost["bandwidth"])

## Get available actions from InstitutionConfig
func get_available_actions_from_config(institution: Institution, config: InstitutionConfig) -> Array:
	return config.get_available_player_actions(
		institution.player_influence,
		institution.stress,
		institution.capacity
	)

## Check and trigger autonomous events for an institution
func check_autonomous_events(institution: Institution, config: InstitutionConfig) -> Array:
	return config.get_triggered_autonomous_events(
		institution.stress,
		institution.strength,
		institution.capacity
	)

## Process an autonomous event (apply auto effects, return player choices)
func process_autonomous_event(event_node: Dictionary, institution: Institution) -> Array:
	# Apply automatic effects
	var auto_effects = event_node.get("auto_effects", {})
	apply_effects(auto_effects, institution)
	
	# Record in save state
	if save_state:
		save_state.record_institution_event(institution.institution_id, event_node.get("node_id", ""), false)
	
	# Emit signal
	autonomous_event_occurred.emit(event_node, institution)
	
	# Return player choices for UI
	return event_node.get("player_choices", [])

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
