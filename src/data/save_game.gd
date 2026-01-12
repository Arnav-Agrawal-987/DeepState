extends Resource
## SaveGame: Persistent game state serialization
## Reference: Logic section 7.1

class_name SaveGame

@export var region_id: String = ""
@export var current_day: int = 1
@export var is_lost: bool = false
@export var high_score: int = 0

@export var player_state_data: Dictionary = {}
@export var institutions_data: Dictionary = {}
@export var dependency_graph_data: Dictionary = {}
@export var global_tension: float = 0.0

## Save complete game state
func save_game_state(
	region: String,
	day: int,
	player_state: PlayerState,
	inst_manager: InstitutionManager,
	dep_graph: DependencyGraph,
	tension: float
) -> void:
	region_id = region
	current_day = day
	player_state_data = player_state.to_dict()
	institutions_data = inst_manager.to_dict()
	dependency_graph_data = dep_graph.to_dict()
	global_tension = tension

## Restore game state
func restore_game_state(
	player_state: PlayerState,
	inst_manager: InstitutionManager,
	dep_graph: DependencyGraph,
	tension_mgr: TensionManager,
	clock: SimulationClock
) -> void:
	player_state.from_dict(player_state_data)
	inst_manager.from_dict(institutions_data)
	dep_graph.from_dict(dependency_graph_data)
	tension_mgr.from_dict({"global_tension": global_tension})
	clock.from_dict({"current_day": current_day})

## Mark game as lost and save score
func mark_lost(score: int) -> void:
	is_lost = true
	high_score = score
