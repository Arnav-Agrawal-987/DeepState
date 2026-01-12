extends Resource
## RegionConfig: Region metadata and setup
## Reference: Logic section 7.1

class_name RegionConfig

@export var region_id: String = ""
@export var region_name: String = ""
@export var region_description: String = ""

# Institution templates (institution_id -> Institution properties)
@export var institutions: Dictionary = {}

# Initial dependency graph (source_id -> {target_id: weight})
@export var initial_dependencies: Dictionary = {}

## Create region from scratch
func create_region(
	id: String,
	name: String,
	description: String
) -> void:
	region_id = id
	region_name = name
	region_description = description

## Add institution template
func add_institution_template(
	inst_id: String,
	inst_name: String,
	inst_type: int,  # Institution.InstitutionType
	capacity: float,
	strength: float
) -> void:
	institutions[inst_id] = {
		"id": inst_id,
		"name": inst_name,
		"type": inst_type,
		"capacity": capacity,
		"strength": strength
	}

## Add dependency edge
func add_dependency(source_id: String, target_id: String, weight: float) -> void:
	if not source_id in initial_dependencies:
		initial_dependencies[source_id] = {}
	initial_dependencies[source_id][target_id] = clamp(weight, 0.0, 1.0)

## Get all institution IDs
func get_institution_ids() -> Array:
	return institutions.keys()

## Get institution template
func get_institution_template(inst_id: String) -> Dictionary:
	return institutions.get(inst_id, {})
