extends Node
class_name GameState

var GAMESTATE_SPEC := """
GameState is the authoritative container for all mutable simulation state in the game.

Rules:
- All gameplay-affecting state lives under GameState.
- UI never mutates state directly.
- Time advances in discrete days via SimulationClock.
- A day executes in a strict, deterministic order.

Owned subsystems:
- WorldContext (immutable after setup)
- PlayerState
- InstitutionManager
- DependencyGraph
- EventManager (MinorEventSystem, MajorEventSystem)
- TensionManager
- SimulationClock

Daily update order:
1. Institutions auto-update (strength increase, event checks)
2. Resolve all minor events
3. Update global tension
4. Trigger and resolve major event if threshold crossed
5. Player turn (actions and decisions)
6. End day

Institutions:
- Are semi-autonomous
- Never apply event effects directly
- Never mutate global state directly
- Report triggers upward to GameState

Events:
- Minor events increment tension
- Major events assess deep-state relevance
- Loss can occur only during major events

DependencyGraph:
- Is mutable
- Rewired after each major event by all institutions
- Never contains event or UI logic

GameState enforces ordering, owns state, and applies consequences.
"""

# Subsystem placeholders (set these up during initialization/scene composition)
var world_context = null
var player_state = null
var institution_manager = null
var dependency_graph = null
var event_manager = null
var tension_manager = null
var simulation_clock = null

func _ready():
	# Initialize or attach core subsystems. Prefer existing children, else instantiate.
	if has_node("SimulationClock"):
		simulation_clock = get_node("SimulationClock")

	# Lazy-instantiation via resource paths to ensure scripts are available at runtime.
	if not player_state:
		var ps_scr = preload("res://scripts/PlayerState.gd")
		player_state = ps_scr.new()
		add_child(player_state)

	if not tension_manager:
		var t_scr = preload("res://scripts/TensionManager.gd")
		tension_manager = t_scr.new()
		add_child(tension_manager)

	if not institution_manager:
		var im_scr = preload("res://scripts/InstitutionManager.gd")
		institution_manager = im_scr.new()
		add_child(institution_manager)

	if not event_manager:
		var ev_scr = preload("res://scripts/EventManager.gd")
		event_manager = ev_scr.new()
		add_child(event_manager)

	if not dependency_graph:
		var dg_scr = preload("res://scripts/DependencyGraph.gd")
		dependency_graph = dg_scr.new()
		add_child(dependency_graph)

# --- Pipeline entry points (placeholders to be implemented) ---
func institutions_auto_update() -> void:
	if institution_manager and institution_manager.has_method("auto_update"):
		institution_manager.auto_update()

func resolve_minor_events() -> void:
	if event_manager and event_manager.has_method("resolve_minor_events"):
		event_manager.resolve_minor_events(self)

	# Minor events are expected to apply effects which may call `tension_manager.add(...)` etc.


func update_tension() -> void:
	# Tension updates are typically performed by event effects. This hook is available
	# for any periodic recomputation that needs to occur after minor events.
	# Keep as a noop unless the tension manager defines a recompute method.
	if tension_manager and tension_manager.has_method("get_tension"):
		var t = tension_manager.get_tension()
		# could log or clamp tension here


func handle_major_event() -> bool:
	if event_manager and event_manager.has_method("handle_major_event"):
		var loss = event_manager.handle_major_event(self)
		# After a major event, rewire dependency graph
		if dependency_graph and institution_manager and institution_manager.has_method("rewire_graph"):
			institution_manager.rewire_graph(dependency_graph)
		# allow tension manager to partially reset if defined
		if tension_manager and tension_manager.has_method("reset_partial"):
			tension_manager.reset_partial()
		return loss
	return false

func player_turn() -> void:
	# Placeholder: UI/input systems should emit intents that this method consumes.
	# Example: convert currencies, apply queued player actions, etc.
	return
