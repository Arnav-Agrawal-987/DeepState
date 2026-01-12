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
