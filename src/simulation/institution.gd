extends Node
## Institution: Autonomous agent in the network
## Reference: Logic section 2.2

class_name Institution

enum InstitutionType { MILITANT, CIVILIAN, POLICY, INTELLIGENCE }

signal stress_changed(new_stress: float)
signal capacity_changed(new_capacity: float)
signal influence_changed(new_influence: float)
signal strength_changed(new_strength: float)
signal stress_maxed_out()  # Emitted when stress reaches 100%

@export var institution_id: String = ""
@export var institution_name: String = ""
@export var institution_type: InstitutionType = InstitutionType.POLICY

# Core state
var capacity: float = 50.0
var strength: float = 100.0
var stress: float = 0.0
var player_influence: float = 0.0  # Range 0-100

# Daily action tracking
var actions_taken_today: int = 0
const MAX_ACTIONS_PER_DAY: int = 1

# Configuration
var capacity_regeneration: float = 2.0  # Strength gain per day
var stress_decay_rate: float = 0.05  # 5% natural stress decay per day

func _ready() -> void:
	pass

## Get institution type as string
func get_type_string() -> String:
	return InstitutionType.keys()[institution_type]

## Daily update: increase strength by capacity function
func daily_auto_update() -> void:
	# Reset daily action counter
	actions_taken_today = 0
	
	# Increase strength based on capacity
	strength = min(strength + (capacity * capacity_regeneration / 100.0), 100.0)
	strength_changed.emit(strength)

## Check if action can be taken today
func can_take_action() -> bool:
	return actions_taken_today < MAX_ACTIONS_PER_DAY

## Record an action taken
func record_action_taken() -> void:
	actions_taken_today += 1

## Apply stress to institution
func apply_stress(amount: float) -> void:
	var old_stress = stress
	stress = min(stress + amount, strength * 2.0)  # Cap at 2x strength
	stress_changed.emit(stress)
	
	# Check if stress just reached 100% (strength threshold)
	if old_stress < 100.0 and stress >= 100.0:
		stress_maxed_out.emit()

## Reduce stress
func reduce_stress(amount: float) -> void:
	stress = max(stress - amount, 0.0)
	stress_changed.emit(stress)

## Apply natural decay each day (percentage-based)
func apply_stress_decay() -> void:
	# Decay by percentage of current stress
	var decay_amount = stress * stress_decay_rate
	reduce_stress(decay_amount)

## Check if stress triggers an event
func should_trigger_stress_event() -> bool:
	return stress >= strength

## Check if stable event should trigger (probabilistic)
func should_trigger_stable_event() -> float:
	# Probability decreases with stress
	var stability = max(1.0 - (stress / strength), 0.0)
	return stability * 0.3  # 0-30% chance based on stability

## Modify player influence
func set_player_influence(value: float) -> void:
	player_influence = clamp(value, 0.0, 100.0)
	influence_changed.emit(player_influence)

## Increase player influence (from actions)
func increase_influence(amount: float) -> void:
	set_player_influence(player_influence + amount)

## Reduce capacity (from player pressure)
func reduce_capacity(amount: float) -> void:
	capacity = max(capacity - amount, 0.0)
	capacity_changed.emit(capacity)

## Serialize state
func to_dict() -> Dictionary:
	return {
		"id": institution_id,
		"name": institution_name,
		"type": institution_type,
		"capacity": capacity,
		"strength": strength,
		"stress": stress,
		"influence": player_influence,
		"actions_taken_today": actions_taken_today
	}

## Deserialize state
func from_dict(data: Dictionary) -> void:
	institution_id = data.get("id", "")
	institution_name = data.get("name", "")
	capacity = data.get("capacity", 50.0)
	strength = data.get("strength", 100.0)
	stress = data.get("stress", 0.0)
	player_influence = data.get("influence", 0.0)
	actions_taken_today = data.get("actions_taken_today", 0)
