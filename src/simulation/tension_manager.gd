extends Node
## TensionManager: Global systemic tension tracking
## Manages crisis threshold and triggers
## Reference: Logic section 3.2 and 3.3

class_name TensionManager

signal tension_changed(new_tension: float)
signal crisis_triggered(epicenter_inst: Institution)

const CRISIS_THRESHOLD: float = 100.0
const TENSION_RESET_FACTOR: float = 0.3  # Reset to 30% after crisis

var global_tension: float = 0.0
var crisis_threshold: float = CRISIS_THRESHOLD

func _ready() -> void:
	pass

## Increase tension from events
func add_tension(amount: float) -> void:
	global_tension += amount
	tension_changed.emit(global_tension)

## Check if crisis should trigger
func check_crisis() -> bool:
	return global_tension >= crisis_threshold

## Get epicenter institution (highest stress)
func get_crisis_epicenter(inst_manager: InstitutionManager) -> Institution:
	var epicenter = null
	var max_stress = 0.0
	
	for inst in inst_manager.get_all_institutions():
		if inst.stress > max_stress:
			max_stress = inst.stress
			epicenter = inst
	
	return epicenter

## Trigger crisis event
func trigger_crisis(epicenter: Institution) -> void:
	crisis_triggered.emit(epicenter)

## Reset tension after crisis resolution
func reset_after_crisis() -> void:
	global_tension *= TENSION_RESET_FACTOR
	tension_changed.emit(global_tension)

## Get current crisis progress (0.0 to 1.0)
func get_crisis_progress() -> float:
	return min(global_tension / crisis_threshold, 1.0)

## Serialize state
func to_dict() -> Dictionary:
	return {
		"global_tension": global_tension
	}

## Deserialize state
func from_dict(data: Dictionary) -> void:
	global_tension = data.get("global_tension", 0.0)
	tension_changed.emit(global_tension)
