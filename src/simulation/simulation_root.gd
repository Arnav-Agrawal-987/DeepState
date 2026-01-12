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

# UI References
@onready var event_dialog = $SimulationUI/EventDialog
@onready var event_title = $SimulationUI/EventDialog/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var event_description = $SimulationUI/EventDialog/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DescriptionLabel
@onready var event_effects = $SimulationUI/EventDialog/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/EffectsLabel
@onready var event_choices_container = $SimulationUI/EventDialog/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ChoicesContainer
@onready var event_close_btn = $SimulationUI/EventDialog/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton

@onready var crisis_overlay = $SimulationUI/CrisisOverlay
@onready var crisis_description = $SimulationUI/CrisisOverlay/CenterContainer/CrisisPanel/MarginContainer/VBoxContainer/CrisisDescription
@onready var crisis_effects = $SimulationUI/CrisisOverlay/CenterContainer/CrisisPanel/MarginContainer/VBoxContainer/CrisisEffects
@onready var crisis_choices_container = $SimulationUI/CrisisOverlay/CenterContainer/CrisisPanel/MarginContainer/VBoxContainer/CrisisChoicesContainer

@onready var pause_menu = $SimulationUI/PauseMenu
@onready var console_label = $SimulationUI/MainLayout/MarginContainer/MainVBox/DebugPanel/MarginContainer/VBoxContainer/ConsoleLabel

@onready var event_tree = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/EventTreePanel/EventTreeScroll/EventTree
@onready var institution_select = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/TreeTypeHBox/InstitutionSelect
@onready var tree_type_select = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/TreeTypeHBox/TreeTypeSelect
@onready var menu_button = $SimulationUI/MainLayout/MarginContainer/MainVBox/PlayerDashboard/VBoxContainer/HBoxContainer/MenuButton

var region_config: RegionConfig
var save_state: RegionSaveState
var institution_configs: Dictionary = {}  # inst_id -> InstitutionConfig

var pending_event_choices: Array = []
var current_event_institution: Institution = null
var current_tree_type: int = 0

enum TreeType { PLAYER_ACTIONS, AUTONOMOUS_EVENTS, CRISIS_TREE }

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
	event_manager.institution_configs = institution_configs
	# save_state will be set after region initialization
	
	# Connect tension crisis signal
	tension_mgr.crisis_triggered.connect(_on_crisis)
	clock.crisis_phase.connect(_handle_crisis_phase)
	clock.player_turn_phase.connect(_handle_player_turn_phase)
	
	# Initialize with test region
	print("[SimulationRoot] Initializing test region...")
	_setup_test_region()
	
	print("[SimulationRoot] Setting up UI...")
	_setup_ui()
	
	print("[SimulationRoot] Setting up event tree...")
	_setup_event_tree_ui()
	
	print("[SimulationRoot] Connecting debug buttons...")
	_connect_debug_buttons()
	
	print("[SimulationRoot] Connecting menu buttons...")
	_connect_menu_buttons()
	
	print("[SimulationRoot] Initialization complete!")

## Initialize region from RegionConfig (data-driven)
func initialize_region(config: RegionConfig) -> void:
	region_config = config
	world_context.load_region(config.region_id, config.region_id)
	
	# Initialize save state
	save_state = RegionSaveState.new()
	save_state.initialize_from_config(config)
	
	# Connect save state to event manager
	event_manager.save_state = save_state
	
	# Load player currencies from save state
	player_state.cash = save_state.get_currency("cash")
	player_state.bandwidth = save_state.get_currency("bandwidth")
	player_state.exposure = save_state.get_currency("exposure")
	
	# Create institutions from InstitutionConfig files
	for inst_id in config.get_institution_ids():
		var inst_config = config.load_institution_config(inst_id)
		if inst_config:
			institution_configs[inst_id] = inst_config
			
			var inst = Institution.new()
			inst.institution_id = inst_config.institution_id
			inst.institution_name = inst_config.institution_name
			inst.institution_type = inst_config.institution_type
			inst.capacity = inst_config.initial_capacity
			inst.strength = inst_config.initial_strength
			inst.stress = inst_config.initial_stress
			inst.player_influence = inst_config.initial_influence
			inst_manager.add_institution(inst)
			
			# Connect stress_maxed_out signal
			inst.stress_maxed_out.connect(_on_institution_stress_maxed.bind(inst))
			
			# Initialize institution state in save
			save_state.initialize_institution(inst_id, inst_config)
		else:
			push_warning("Could not load institution config for: %s" % inst_id)
	
	# Build dependency graph
	for source_id in config.initial_dependencies:
		for target_id in config.initial_dependencies[source_id]:
			var weight = config.initial_dependencies[source_id][target_id]
			dep_graph.add_edge(source_id, target_id, weight)

## Load existing save state
func load_save_state(save: RegionSaveState) -> void:
	save_state = save
	
	# Load region config
	if ResourceLoader.exists(save.region_config_path):
		region_config = load(save.region_config_path) as RegionConfig
	
	# Restore player currencies
	player_state.cash = save.get_currency("cash")
	player_state.bandwidth = save.get_currency("bandwidth")
	player_state.exposure = save.get_currency("exposure")
	
	# Restore tension
	tension_mgr.global_tension = save.global_tension
	
	# Restore clock
	clock.current_day = save.current_day
	
	# Restore institutions
	for inst_id in save.institutions:
		var inst_state = save.get_institution_state(inst_id)
		var inst = inst_manager.get_institution(inst_id)
		if inst:
			inst.capacity = inst_state.get("capacity", 50.0)
			inst.strength = inst_state.get("strength", 100.0)
			inst.stress = inst_state.get("stress", 0.0)
			inst.player_influence = inst_state.get("influence", 0.0)

## Save current game state
func save_game() -> void:
	if not save_state:
		save_state = RegionSaveState.new()
	
	# Update save state from current game
	save_state.region_id = region_config.region_id
	save_state.current_day = clock.get_current_day()
	save_state.global_tension = tension_mgr.global_tension
	
	# Save currencies
	save_state.set_currency("cash", player_state.cash)
	save_state.set_currency("bandwidth", player_state.bandwidth)
	save_state.set_currency("exposure", player_state.exposure)
	
	# Save institution states
	for inst in inst_manager.get_all_institutions():
		save_state.update_institution_stat(inst.institution_id, "capacity", inst.capacity)
		save_state.update_institution_stat(inst.institution_id, "strength", inst.strength)
		save_state.update_institution_stat(inst.institution_id, "stress", inst.stress)
		save_state.update_institution_stat(inst.institution_id, "influence", inst.player_influence)
	
	# Save to file
	var save_path = "user://saves/%s.tres" % region_config.region_id
	DirAccess.make_dir_recursive_absolute("user://saves")
	save_state.save_to_file(save_path)
	print("Game saved to: %s" % save_path)

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
	if save_state:
		save_state.mark_lost(score)
		save_game()
	# TODO: Load game over screen
	print("Game Over! Score: %d days" % score)

## Crisis triggered
func _on_crisis(epicenter: Institution) -> void:
	print("Crisis triggered at %s" % epicenter.institution_name)

## Institution stress reached 100% - trigger immediate event
func _on_institution_stress_maxed(institution: Institution) -> void:
	_log_console("⚠ %s stress maxed out!" % institution.institution_name)
	
	# Find stress_max events from config
	if institution.institution_id in institution_configs:
		var config = institution_configs[institution.institution_id]
		
		# Look for stress_max trigger events
		for event_node in config.autonomous_event_tree:
			if event_node.get("trigger_type") == "stress_max":
				# Process the event
				var choices = event_manager.process_autonomous_event(event_node, institution)
				
				# Show event dialog immediately
				show_event_dialog(event_node, institution, choices)
				return
		
		# Fallback: create a generic stress max event if none defined
		var fallback_event = {
			"title": "Critical Breakdown",
			"description": "%s has reached maximum stress! The institution is on the verge of collapse." % institution.institution_name,
			"auto_effects": {"tension_change": 10.0, "capacity_change": -5.0},
			"player_choices": [
				{"label": "Intervene", "cost": {"cash": 200.0}, "effects": {"stress_change": -30.0, "influence_change": 10.0}},
				{"label": "Do Nothing", "cost": {}, "effects": {"strength_change": -10.0}}
			]
		}
		event_manager.apply_effects(fallback_event["auto_effects"], institution)
		show_event_dialog(fallback_event, institution, fallback_event["player_choices"])

## Setup test region for development (data-driven)
func _setup_test_region() -> void:
	# Try to load the Novara region from file
	var region_path = "res://assets/regions/novara.tres"
	
	if ResourceLoader.exists(region_path):
		var config = load(region_path) as RegionConfig
		if config:
			initialize_region(config)
			print("Loaded region '%s' with %d institutions" % [config.region_name, inst_manager.get_all_institutions().size()])
			return
	
	# Fallback: Create inline test region if file not found
	print("Region file not found, creating fallback test region...")
	_create_fallback_test_region()

## Create fallback test region (inline data)
func _create_fallback_test_region() -> void:
	var config = RegionConfig.new()
	config.create_region("test_fallback", "Fallback Test Region", "Testing region when data files unavailable")
	
	# Create inline institutions since we can't load from files
	var inst_data = [
		{"id": "govt", "name": "Government", "type": Institution.InstitutionType.POLICY, "capacity": 55.0, "strength": 90.0},
		{"id": "military", "name": "Military", "type": Institution.InstitutionType.MILITANT, "capacity": 70.0, "strength": 95.0},
		{"id": "media", "name": "Media", "type": Institution.InstitutionType.CIVILIAN, "capacity": 45.0, "strength": 75.0},
		{"id": "intel", "name": "Intelligence", "type": Institution.InstitutionType.INTELLIGENCE, "capacity": 65.0, "strength": 85.0}
	]
	
	region_config = config
	save_state = RegionSaveState.new()
	
	for data in inst_data:
		var inst = Institution.new()
		inst.institution_id = data["id"]
		inst.institution_name = data["name"]
		inst.institution_type = data["type"]
		inst.capacity = data["capacity"]
		inst.strength = data["strength"]
		inst.stress = randf_range(5.0, 15.0)
		inst_manager.add_institution(inst)
		
		# Connect stress_maxed_out signal
		inst.stress_maxed_out.connect(_on_institution_stress_maxed.bind(inst))
		
		# Create default InstitutionConfig for actions
		var inst_config = InstitutionConfig.new()
		inst_config.institution_id = data["id"]
		inst_config.institution_name = data["name"]
		inst_config.create_default_player_tree()
		inst_config.create_default_autonomous_tree()
		institution_configs[data["id"]] = inst_config
	
	# Add dependencies
	config.add_dependency("govt", "military", 0.8)
	config.add_dependency("govt", "media", 0.6)
	config.add_dependency("military", "intel", 0.75)
	config.add_dependency("media", "govt", 0.45)
	
	for source_id in config.initial_dependencies:
		for target_id in config.initial_dependencies[source_id]:
			dep_graph.add_edge(source_id, target_id, config.initial_dependencies[source_id][target_id])
	
	print("Fallback region initialized with %d institutions" % inst_manager.get_all_institutions().size())

## Setup UI and populate institution cards
func _setup_ui() -> void:
	var institution_panel = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/LeftPanel/InstitutionPanel/ScrollContainer/VBoxContainer
	var institution_card_scene = preload("res://scenes/simulation/institution_card.tscn")
	
	for inst in inst_manager.get_all_institutions():
		var card = institution_card_scene.instantiate()
		if card.has_method("set_institution"):
			var config = institution_configs.get(inst.institution_id, null)
			card.set_institution(inst, event_manager, config)
			institution_panel.add_child(card)
		else:
			push_error("Institution card missing set_institution method")
	
	# Connect event close button
	if event_close_btn:
		event_close_btn.pressed.connect(_on_event_close)
	
	# Update dashboard
	_update_dashboard()
	
	# Add to simulation_root group for callback
	add_to_group("simulation_root")

## Setup event tree UI
func _setup_event_tree_ui() -> void:
	# Populate institution dropdown
	institution_select.clear()
	for inst_id in institution_configs:
		var config = institution_configs[inst_id]
		institution_select.add_item(config.institution_name)
		institution_select.set_item_metadata(institution_select.item_count - 1, inst_id)
	
	# Populate tree type dropdown
	tree_type_select.clear()
	tree_type_select.add_item("Player Actions", TreeType.PLAYER_ACTIONS)
	tree_type_select.add_item("Autonomous Events", TreeType.AUTONOMOUS_EVENTS)
	tree_type_select.add_item("Crisis Tree", TreeType.CRISIS_TREE)
	
	# Connect signals
	institution_select.item_selected.connect(_on_institution_select_changed)
	tree_type_select.item_selected.connect(_on_tree_type_select_changed)
	event_tree.item_selected.connect(_on_event_tree_item_selected)
	
	# Initial display
	if institution_select.item_count > 0:
		institution_select.select(0)
		_refresh_event_tree()

## Institution selection changed
func _on_institution_select_changed(_index: int) -> void:
	_refresh_event_tree()

## Tree type selection changed
func _on_tree_type_select_changed(index: int) -> void:
	current_tree_type = tree_type_select.get_item_id(index)
	_refresh_event_tree()

## Refresh event tree display
func _refresh_event_tree() -> void:
	event_tree.clear()
	var root = event_tree.create_item()
	
	var selected_idx = institution_select.selected
	if selected_idx < 0:
		return
	
	var inst_id = institution_select.get_item_metadata(selected_idx)
	
	match current_tree_type:
		TreeType.PLAYER_ACTIONS:
			_build_player_action_tree(root, inst_id)
		TreeType.AUTONOMOUS_EVENTS:
			_build_autonomous_event_tree(root, inst_id)
		TreeType.CRISIS_TREE:
			_build_crisis_tree(root)

## Build player action tree
func _build_player_action_tree(root: TreeItem, inst_id: String) -> void:
	if inst_id not in institution_configs:
		return
	
	var config = institution_configs[inst_id]
	for action_node in config.player_event_tree:
		var item = event_tree.create_item(root)
		var title = action_node.get("title", "Unknown")
		var conditions = action_node.get("conditions", {})
		
		var display = title
		if conditions.get("min_influence", 0) > 0:
			display += " [Inf>=%d]" % conditions["min_influence"]
		
		item.set_text(0, display)
		item.set_metadata(0, {"type": "player", "node": action_node, "inst_id": inst_id})

## Build autonomous event tree
func _build_autonomous_event_tree(root: TreeItem, inst_id: String) -> void:
	if inst_id not in institution_configs:
		return
	
	var config = institution_configs[inst_id]
	for event_node in config.autonomous_event_tree:
		var item = event_tree.create_item(root)
		var title = event_node.get("title", "Unknown")
		var trigger = event_node.get("trigger_conditions", {})
		
		var display = title
		if trigger.get("stress_above", 0) > 0:
			display += " [Stress>%d]" % trigger["stress_above"]
		elif trigger.get("strength_below", 0) > 0:
			display += " [Str<%d]" % trigger["strength_below"]
		
		item.set_text(0, display)
		item.set_metadata(0, {"type": "autonomous", "node": event_node, "inst_id": inst_id})

## Build crisis tree
func _build_crisis_tree(root: TreeItem) -> void:
	if not region_config:
		return
	
	for crisis_node in region_config.crisis_tree:
		var item = event_tree.create_item(root)
		var title = crisis_node.get("title", "Unknown")
		var node_id = crisis_node.get("node_id", "")
		
		item.set_text(0, "[%s] %s" % [node_id, title])
		item.set_metadata(0, {"type": "crisis", "node": crisis_node})

## Event tree item selected - show details and allow execution
func _on_event_tree_item_selected() -> void:
	var selected = event_tree.get_selected()
	if not selected:
		return
	
	var meta = selected.get_metadata(0)
	if not meta or not meta.has("node"):
		return
	
	var node = meta["node"]
	var node_type = meta.get("type", "")
	
	# Show in console
	var title = node.get("title", "Unknown")
	var desc = node.get("description", "")
	_log_console("%s: %s" % [title, desc])

## Connect menu buttons
func _connect_menu_buttons() -> void:
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	
	# Pause menu buttons
	var resume_btn = $SimulationUI/PauseMenu/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeBtn
	var save_btn = $SimulationUI/PauseMenu/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveBtn
	var main_menu_btn = $SimulationUI/PauseMenu/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuBtn
	var quit_btn = $SimulationUI/PauseMenu/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitBtn
	
	if resume_btn:
		resume_btn.pressed.connect(_on_resume_pressed)
	if save_btn:
		save_btn.pressed.connect(_on_save_pressed)
	if main_menu_btn:
		main_menu_btn.pressed.connect(_on_main_menu_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)

## Menu button pressed
func _on_menu_pressed() -> void:
	pause_menu.visible = true

## Resume button pressed
func _on_resume_pressed() -> void:
	pause_menu.visible = false

## Save button pressed
func _on_save_pressed() -> void:
	save_game()
	_log_console("Game saved!")

## Main menu button pressed
func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

## Quit button pressed
func _on_quit_pressed() -> void:
	get_tree().quit()

## Show event dialog with choices
func show_event_dialog(event_node: Dictionary, institution: Institution, choices: Array) -> void:
	current_event_institution = institution
	pending_event_choices = choices
	
	event_title.text = event_node.get("title", "Event")
	event_description.text = event_node.get("description", "Something has happened...")
	
	# Show auto effects
	var auto_effects = event_node.get("auto_effects", {})
	if not auto_effects.is_empty():
		var effect_lines = []
		for key in auto_effects:
			effect_lines.append("%s: %+.0f" % [key.replace("_", " ").capitalize(), auto_effects[key]])
		event_effects.text = "Effects: " + ", ".join(effect_lines)
	else:
		event_effects.text = ""
	
	# Clear old choice buttons
	for child in event_choices_container.get_children():
		child.queue_free()
	
	# Create choice buttons
	if choices.is_empty():
		event_close_btn.visible = true
	else:
		event_close_btn.visible = false
		for i in range(choices.size()):
			var choice = choices[i]
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 40)
			
			var label = choice.get("label", "Choice %d" % (i + 1))
			var cost = choice.get("cost", {})
			if not cost.is_empty():
				var cost_parts = []
				if cost.get("cash", 0) > 0:
					cost_parts.append("$%.0f" % cost["cash"])
				if cost.get("bandwidth", 0) > 0:
					cost_parts.append("%.0f BW" % cost["bandwidth"])
				label += " (%s)" % ", ".join(cost_parts)
			
			btn.text = label
			btn.pressed.connect(_on_event_choice_selected.bind(i))
			event_choices_container.add_child(btn)
	
	event_dialog.visible = true

## Event choice selected
func _on_event_choice_selected(choice_index: int) -> void:
	if choice_index >= pending_event_choices.size():
		return
	
	var choice = pending_event_choices[choice_index]
	var cost = choice.get("cost", {})
	var effects = choice.get("effects", {})
	
	# Check cost
	if cost.get("cash", 0) > player_state.cash:
		_log_console("Not enough cash!")
		return
	if cost.get("bandwidth", 0) > player_state.bandwidth:
		_log_console("Not enough bandwidth!")
		return
	
	# Spend cost
	if cost.get("cash", 0) > 0:
		player_state.spend_cash(cost["cash"])
	if cost.get("bandwidth", 0) > 0:
		player_state.spend_bandwidth(cost["bandwidth"])
	
	# Apply effects
	if current_event_institution:
		event_manager.apply_effects(effects, current_event_institution)
	
	_log_console("Chose: %s" % choice.get("label", "Unknown"))
	_update_dashboard()
	event_dialog.visible = false

## Close event dialog
func _on_event_close() -> void:
	event_dialog.visible = false

## Log to console
func _log_console(msg: String) -> void:
	if console_label:
		console_label.text = msg
	print(msg)

## Connect debug buttons
func _connect_debug_buttons() -> void:
	var button_row1 = $SimulationUI/MainLayout/MarginContainer/MainVBox/DebugPanel/MarginContainer/VBoxContainer/ButtonRow1
	var button_row2 = $SimulationUI/MainLayout/MarginContainer/MainVBox/DebugPanel/MarginContainer/VBoxContainer/ButtonRow2

	var buttons_row1 := {
		"AdvanceDayBtn": _on_debug_advance_day,
		"AddStressBtn": _on_debug_add_stress,
		"AddTensionBtn": _on_debug_add_tension,
		"TriggerCrisisBtn": _on_debug_trigger_crisis,
	}
	
	var buttons_row2 := {
		"AddCashBtn": _on_debug_add_cash,
		"AddBandwidthBtn": _on_debug_add_bandwidth,
		"AddInfluenceBtn": _on_debug_add_influence,
		"TestEventBtn": _on_debug_test_event,
	}

	for btn_name in buttons_row1.keys():
		var btn = button_row1.get_node_or_null(btn_name)
		if btn:
			btn.pressed.connect(buttons_row1[btn_name])
			print("[DEBUG] Connected %s" % btn_name)
		else:
			print("[ERROR] Button not found: %s" % btn_name)
	
	for btn_name in buttons_row2.keys():
		var btn = button_row2.get_node_or_null(btn_name)
		if btn:
			btn.pressed.connect(buttons_row2[btn_name])
			print("[DEBUG] Connected %s" % btn_name)
		else:
			print("[ERROR] Button not found: %s" % btn_name)

## DEBUG: Advance to next day
func _on_debug_advance_day() -> void:
	var insts = inst_manager.get_all_institutions()
	var events_to_show: Array = []
	
	for inst in insts:
		inst.daily_auto_update()
		inst.apply_stress_decay()
		
		# Check autonomous events
		if inst.institution_id in institution_configs:
			var config = institution_configs[inst.institution_id]
			var triggered_events = event_manager.check_autonomous_events(inst, config)
			for event_node in triggered_events:
				var choices = event_manager.process_autonomous_event(event_node, inst)
				if not choices.is_empty():
					events_to_show.append({"event": event_node, "institution": inst, "choices": choices})
					_log_console("[Event] %s: %s" % [inst.institution_name, event_node.get("title", "Unknown")])
	
	player_state.decay_exposure()
	clock.current_day += 1
	_log_console("Day advanced to: %d" % clock.current_day)
	_update_dashboard()
	
	# Show first event with choices (queue others)
	if not events_to_show.is_empty():
		var first = events_to_show[0]
		show_event_dialog(first["event"], first["institution"], first["choices"])

## DEBUG: Add stress to random institution
func _on_debug_add_stress() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	target.apply_stress(20.0)
	_log_console("Added 20 stress to %s (stress: %.1f)" % [target.institution_name, target.stress])

## DEBUG: Add global tension
func _on_debug_add_tension() -> void:
	tension_mgr.add_tension(10.0)
	_log_console("Added 10 tension (total: %.1f)" % tension_mgr.global_tension)
	_update_dashboard()

## DEBUG: Trigger crisis immediately
func _on_debug_trigger_crisis() -> void:
	var epicenter = tension_mgr.get_crisis_epicenter(inst_manager)
	if epicenter:
		_log_console("DEBUG: Triggering crisis at %s" % epicenter.institution_name)
		_evaluate_crisis(epicenter)

## DEBUG: Add cash
func _on_debug_add_cash() -> void:
	player_state.gain_cash(500.0)
	_log_console("Added $500 (total: $%.0f)" % player_state.cash)
	_update_dashboard()

## DEBUG: Add bandwidth
func _on_debug_add_bandwidth() -> void:
	player_state.gain_bandwidth(25.0)
	_log_console("Added 25 bandwidth (total: %.0f)" % player_state.bandwidth)
	_update_dashboard()

## DEBUG: Add influence to random institution
func _on_debug_add_influence() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	target.increase_influence(15.0)
	_log_console("Added 15 influence to %s (influence: %.0f)" % [target.institution_name, target.player_influence])

## DEBUG: Test event effects
func _on_debug_test_event() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	
	# Create a test event with choices
	var test_event = {
		"title": "Test Event: Opportunity",
		"description": "A test opportunity has appeared at %s. How do you respond?" % target.institution_name,
		"auto_effects": {"tension_change": 5.0},
		"player_choices": [
			{"label": "Invest Resources", "cost": {"cash": 100.0}, "effects": {"influence_change": 10.0}},
			{"label": "Gather Intel", "cost": {"bandwidth": 10.0}, "effects": {"stress_change": -5.0}},
			{"label": "Do Nothing", "cost": {}, "effects": {}}
		]
	}
	
	show_event_dialog(test_event, target, test_event["player_choices"])
	_log_console("Test event triggered on %s" % target.institution_name)

## Update dashboard labels
func _update_dashboard() -> void:
	var dashboard = $SimulationUI/MainLayout/MarginContainer/MainVBox/PlayerDashboard/VBoxContainer
	var day_label = dashboard.get_node("HBoxContainer/Label")
	var cash_label = dashboard.get_node("HBoxContainer/CashLabel")
	var bandwidth_label = dashboard.get_node("HBoxContainer/BandwidthLabel")
	var exposure_label = dashboard.get_node("HBoxContainer/ExposureLabel")
	var tension_bar = dashboard.get_node("TensionHBox/TensionBar")
	
	day_label.text = "Day: %d" % clock.current_day
	cash_label.text = "Cash: $%.0f" % player_state.cash
	bandwidth_label.text = "Bandwidth: %.0f/%.0f" % [player_state.bandwidth, player_state.max_bandwidth]
	exposure_label.text = "Exposure: %.0f%%" % (player_state.exposure)
	tension_bar.value = tension_mgr.global_tension / tension_mgr.crisis_threshold * 100.0
