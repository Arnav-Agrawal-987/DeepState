extends Node2D
## SimulationRoot: Main simulation orchestrator
## Initializes all systems and runs game loop
## Reference: Logic section 7

class_name SimulationRoot

@onready var world_context = WorldContext.new()
@onready var player_state = PlayerState.new()
@onready var inst_manager = InstitutionManager.new()
@onready var dep_graph = DependencyGraph.new()
@onready var tension_mgr = TensionManager.new()
@onready var event_manager = EventManager.new()
@onready var clock = SimulationClock.new()

var region_config: RegionConfig
var current_save: SaveGame

func _ready() -> void:
	# Initialize simulation hierarchy
	add_child(world_context)
	add_child(player_state)
	add_child(inst_manager)
	add_child(dep_graph)
	add_child(tension_mgr)
	add_child(event_manager)
	add_child(clock)
	
	# Wire up event manager
	event_manager.inst_manager = inst_manager
	event_manager.player_state = player_state
	event_manager.tension_mgr = tension_mgr
	
	# Connect tension crisis signal
	tension_mgr.crisis_triggered.connect(_on_crisis)
	clock.crisis_phase.connect(_handle_crisis_phase)
	clock.player_turn_phase.connect(_handle_player_turn_phase)
	
	# Initialize with test region
	print("[SimulationRoot] Initializing test region...")
	_setup_test_region()
	
	print("[SimulationRoot] Setting up UI...")
	_setup_ui()
	
	print("[SimulationRoot] Connecting debug buttons...")
	_connect_debug_buttons()
	
	print("[SimulationRoot] Initialization complete!")

## Initialize region from RegionConfig
func initialize_region(config: RegionConfig) -> void:
	region_config = config
	world_context.load_region(config.region_id, config.region_id)
	
	# Create institutions from config
	for inst_id in config.get_institution_ids():
		var template = config.get_institution_template(inst_id)
		var inst = Institution.new()
		inst.institution_id = template["id"]
		inst.institution_name = template["name"]
		inst.institution_type = template["type"]
		inst.capacity = template["capacity"]
		inst.strength = template["strength"]
		inst_manager.add_institution(inst)
	
	# Build dependency graph
	for source_id in config.initial_dependencies:
		for target_id in config.initial_dependencies[source_id]:
			var weight = config.initial_dependencies[source_id][target_id]
			dep_graph.add_edge(source_id, target_id, weight)

## Load existing game
func load_game(save: SaveGame) -> void:
	current_save = save
	# TODO: Load region config for region
	var config = RegionConfig.new()  # Load from resource
	initialize_region(config)
	save.restore_game_state(player_state, inst_manager, dep_graph, tension_mgr, clock)

## Save current game
func save_game() -> void:
	if not current_save:
		current_save = SaveGame.new()
	current_save.save_game_state(
		region_config.region_id,
		clock.get_current_day(),
		player_state,
		inst_manager,
		dep_graph,
		tension_mgr.global_tension
	)
	# TODO: Write to disk

## Start game loop
func start_simulation() -> void:
	pass  # TODO: Implement game loop

## Handle crisis phase
func _handle_crisis_phase() -> void:
	var epicenter = tension_mgr.get_crisis_epicenter(inst_manager)
	if epicenter:
		tension_mgr.trigger_crisis(epicenter)
		_evaluate_crisis(epicenter)

## Handle player turn
func _handle_player_turn_phase() -> void:
	# Wait for player input
	# TODO: Connect UI signals
	pass

## Evaluate crisis outcome
func _evaluate_crisis(epicenter: Institution) -> void:
	# Calculate Deep State relevance
	var relevance = _calculate_relevance()
	const CRISIS_THRESHOLD: float = 0.3
	
	if relevance < CRISIS_THRESHOLD:
		# Game over - Deep State is no longer relevant
		_end_game_lost()
	else:
		# Crisis survived, reset tension
		tension_mgr.reset_after_crisis()
		dep_graph.rewire_for_resilience(inst_manager)

## Calculate Deep State relevance during crisis
func _calculate_relevance() -> float:
	var total_influence = 0.0
	var inst_count = float(inst_manager.get_all_institutions().size())
	
	for inst in inst_manager.get_all_institutions():
		total_influence += inst.player_influence / 100.0
	
	var influence_score = total_influence / inst_count if inst_count > 0 else 0.0
	var exposure_penalty = player_state.get_exposure_factor() * 0.5
	
	return max(influence_score - exposure_penalty, 0.0)

## Game over - player lost
func _end_game_lost() -> void:
	var score = clock.get_current_day()
	if current_save:
		current_save.mark_lost(score)
		save_game()
	# TODO: Load game over screen
	print("Game Over! Score: %d days" % score)

## Crisis triggered
func _on_crisis(epicenter: Institution) -> void:
	print("Crisis triggered at %s" % epicenter.institution_name)

## Setup test region for development
func _setup_test_region() -> void:
	var config = RegionConfig.new()
	config.create_region("test_dev", "Test Development Region", "Development region for testing")
	
	# Create test institutions
	var inst_types = [
		Institution.InstitutionType.POLICY,
		Institution.InstitutionType.MILITANT,
		Institution.InstitutionType.CIVILIAN,
		Institution.InstitutionType.INTELLIGENCE
	]
	
	var institution_names = ["Government", "Military", "Media", "Intelligence Agency"]
	
	for i in range(4):
		config.add_institution_template(
			"inst_%d" % i,
			institution_names[i],
			inst_types[i],
			50.0 + randf_range(-20, 20),
			100.0
		)
	
	# Add some dependencies
	config.add_dependency("inst_0", "inst_1", 0.8)  # Government -> Military
	config.add_dependency("inst_1", "inst_3", 0.6)  # Military -> Intelligence
	config.add_dependency("inst_0", "inst_2", 0.7)  # Government -> Media
	config.add_dependency("inst_2", "inst_0", 0.5)  # Media -> Government (feedback)
	
	initialize_region(config)
	print("Test region initialized with %d institutions" % inst_manager.get_all_institutions().size())

## Setup UI and populate institution cards
func _setup_ui() -> void:
	var institution_panel = get_node("SimulationUI/InstitutionPanel/ScrollContainer/VBoxContainer")
	var institution_card_scene = preload("res://scenes/simulation/institution_card.tscn")
	
	for inst in inst_manager.get_all_institutions():
		var card = institution_card_scene.instantiate()
		if card.has_method("set_institution"):
			card.set_institution(inst, event_manager)
			institution_panel.add_child(card)
		else:
			push_error("Institution card missing set_institution method")
	
	# Update dashboard
	_update_dashboard()

## Connect debug buttons
func _connect_debug_buttons() -> void:
	var debug_panel = get_node("SimulationUI/DebugPanel/MarginContainer/HBoxContainer")

	var buttons := {
		"AdvanceDayBtn": _on_debug_advance_day,
		"AddStressBtn": _on_debug_add_stress,
		"AddTensionBtn": _on_debug_add_tension,
		"TriggerCrisisBtn": _on_debug_trigger_crisis,
		"AddCashBtn": _on_debug_add_cash,
		"AddBandwidthBtn": _on_debug_add_bandwidth,
		"AddInfluenceBtn": _on_debug_add_influence,
		"TestEventBtn": _on_debug_test_event,
	}

	for btn_name in buttons.keys():
		var btn = debug_panel.get_node_or_null(btn_name)
		if btn:
			btn.pressed.connect(buttons[btn_name])
			print("[DEBUG] Connected %s" % btn_name)
		else:
			print("[ERROR] Button not found: %s" % btn_name)

## DEBUG: Advance to next day
func _on_debug_advance_day() -> void:
	var insts = inst_manager.get_all_institutions()
	for inst in insts:
		inst.daily_auto_update()
		inst.apply_stress_decay()
	
	player_state.decay_exposure()
	clock.current_day += 1
	print("Day advanced to: %d" % clock.current_day)
	_update_dashboard()

## DEBUG: Add stress to random institution
func _on_debug_add_stress() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	target.apply_stress(20.0)
	print("Added 20 stress to %s (stress: %.1f)" % [target.institution_name, target.stress])

## DEBUG: Add global tension
func _on_debug_add_tension() -> void:
	tension_mgr.add_tension(10.0)
	print("Added 10 tension (total: %.1f)" % tension_mgr.global_tension)
	_update_dashboard()

## DEBUG: Trigger crisis immediately
func _on_debug_trigger_crisis() -> void:
	var epicenter = tension_mgr.get_crisis_epicenter(inst_manager)
	if epicenter:
		print("DEBUG: Triggering crisis at %s" % epicenter.institution_name)
		_evaluate_crisis(epicenter)

## DEBUG: Add cash
func _on_debug_add_cash() -> void:
	player_state.gain_cash(500.0)
	print("Added $500 (total: $%.0f)" % player_state.cash)

## DEBUG: Add bandwidth
func _on_debug_add_bandwidth() -> void:
	player_state.gain_bandwidth(25.0)
	print("Added 25 bandwidth (total: %.0f)" % player_state.bandwidth)

## DEBUG: Add influence to random institution
func _on_debug_add_influence() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	target.increase_influence(15.0)
	print("Added 15 influence to %s (influence: %.0f)" % [target.institution_name, target.player_influence])

## DEBUG: Test event effects
func _on_debug_test_event() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	var effects = {
		"stress_change": -15.0,
		"cash_change": 100.0,
		"exposure_change": 10.0,
		"tension_change": 5.0
	}
	
	event_manager.trigger_event("test_event_001", target, effects)
	print("Test event triggered on %s" % target.institution_name)

## Update dashboard labels
func _update_dashboard() -> void:
	var dashboard = get_node("SimulationUI/PlayerDashboard/VBoxContainer")
	var day_label = dashboard.get_node("HBoxContainer/Label")
	var cash_label = dashboard.get_node("HBoxContainer/CashLabel")
	var bandwidth_label = dashboard.get_node("HBoxContainer/BandwidthLabel")
	var exposure_label = dashboard.get_node("HBoxContainer/ExposureLabel")
	var tension_bar = dashboard.get_node("TensionBar")
	
	day_label.text = "Day: %d" % clock.current_day
	cash_label.text = "Cash: $%.0f" % player_state.cash
	bandwidth_label.text = "Bandwidth: %.0f/%.0f" % [player_state.bandwidth, player_state.max_bandwidth]
	exposure_label.text = "Exposure: %.0f%%" % (player_state.exposure)
	tension_bar.value = tension_mgr.global_tension / tension_mgr.crisis_threshold * 100.0
