extends Node
## EventManager: Resolves and applies event effects
## Reference: Logic section 3.1

class_name EventManager

signal event_triggered(event_id: String, institution: Institution)
signal event_resolved(event_id: String)

var inst_manager: InstitutionManager
var player_state: PlayerState
var tension_mgr: TensionManager

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
		if effects["capacity_change"] > 0:
			institution.capacity += effects["capacity_change"]
		else:
			institution.reduce_capacity(abs(effects["capacity_change"]))
	
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
