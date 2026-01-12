extends Node
## SimulationClock: Enforces strict daily execution order
## Reference: Logic section 4

class_name SimulationClock

signal day_started(day: int)
signal day_ended(day: int)
signal crisis_phase
signal player_turn_phase

var current_day: int = 1
var is_paused: bool = false

func _ready() -> void:
	pass

## Advance to next day with strict order enforcement
func advance_day(
	inst_manager: InstitutionManager,
	tension_mgr: TensionManager,
	player_state: PlayerState
) -> void:
	if is_paused:
		return
	
	# STRICT ORDER (must not be bypassed):
	# 1. Day Start
	day_started.emit(current_day)
	
	# 2. Institutions auto-update
	inst_manager.daily_update()
	
	# 3. Minor events triggered and resolved (handled by EventManager)
	# TODO: EventManager processes events
	
	# 4. Global tension updated
	# TODO: Update from event effects
	
	# 5. Crisis (if triggered)
	if tension_mgr.check_crisis():
		crisis_phase.emit()
		# TODO: Execute crisis sequence
	
	# 6. Player turn
	player_turn_phase.emit()
	# TODO: Wait for player input
	
	# 7. Day End
	player_state.decay_exposure()
	current_day += 1
	day_ended.emit(current_day - 1)

## Get current day
func get_current_day() -> int:
	return current_day

## Pause/unpause simulation
func set_paused(paused: bool) -> void:
	is_paused = paused

## Serialize state
func to_dict() -> Dictionary:
	return {
		"current_day": current_day
	}

## Deserialize state
func from_dict(data: Dictionary) -> void:
	current_day = data.get("current_day", 1)
