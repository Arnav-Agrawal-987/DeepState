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

# NEW: Event Queue and Crisis View UI
@onready var view_crisis_btn = $SimulationUI/MainLayout/MarginContainer/MainVBox/PlayerDashboard/VBoxContainer/HBoxContainer/ViewCrisisBtn
@onready var event_queue_btn = $SimulationUI/MainLayout/MarginContainer/MainVBox/PlayerDashboard/VBoxContainer/HBoxContainer/EventQueueBtn
@onready var relevance_label = $SimulationUI/MainLayout/MarginContainer/MainVBox/PlayerDashboard/VBoxContainer/HBoxContainer/RelevanceLabel

@onready var event_queue_overlay = $SimulationUI/EventQueueOverlay
@onready var event_queue_list = $SimulationUI/EventQueueOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QueueScroll/QueueList
@onready var close_queue_btn = $SimulationUI/EventQueueOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseQueueBtn

@onready var crisis_view_overlay = $SimulationUI/CrisisViewOverlay
@onready var crisis_view_relevance = $SimulationUI/CrisisViewOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/RelevanceLabel
@onready var crisis_list = $SimulationUI/CrisisViewOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CrisisScroll/CrisisList
@onready var close_crisis_btn = $SimulationUI/CrisisViewOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseCrisisBtn

# NEW: Default Actions UI
@onready var default_actions_panel = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/DefaultActionsPanel
@onready var action_inst_select = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/DefaultActionsPanel/ActionsVBox/ActionInstSelect
@onready var actions_container = $SimulationUI/MainLayout/MarginContainer/MainVBox/ContentHSplit/RightPanel/DefaultActionsPanel/ActionsVBox/ActionsContainer

var region_config: RegionConfig
var save_state: RegionSaveState
var institution_configs: Dictionary = {}  # inst_id -> InstitutionConfig

var pending_event_choices: Array = []
var current_event_institution: Institution = null
var current_pending_event_node: Dictionary = {}  # The event node being processed
var current_pending_event_is_player_action: bool = false  # Whether current event is player-triggered
var current_tree_type: int = 0

enum TreeType { STRESS_TRIGGERED, RANDOM_TRIGGERED, CRISIS_TREE }

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
	event_manager.dep_graph = dep_graph  # NEW: Wire dependency graph for crisis effects
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

func _input(event: InputEvent) -> void:
	# Quick save with F5
	if event.is_action_pressed("ui_save") or (event is InputEventKey and event.keycode == KEY_F5 and event.pressed):
		quick_save()
		get_viewport().set_input_as_handled()
	
	# Quick load with F9
	if event.is_action_pressed("ui_load") or (event is InputEventKey and event.keycode == KEY_F9 and event.pressed):
		quick_load()
		get_viewport().set_input_as_handled()


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
			# Use the config's institution_id as the canonical ID
			var canonical_id = inst_config.institution_id
			institution_configs[canonical_id] = inst_config
			print("[SimulationRoot] Loaded config for %s: %d stress events, %d random events" % [
				canonical_id, inst_config.stress_triggered_tree.size(), inst_config.randomly_triggered_tree.size()
			])
			
			var inst = Institution.new()
			inst.institution_id = canonical_id
			inst.institution_name = inst_config.institution_name
			inst.institution_type = inst_config.institution_type
			inst.capacity = inst_config.initial_capacity
			inst.strength = inst_config.initial_strength
			inst.stress = inst_config.initial_stress
			inst.player_influence = inst_config.initial_influence
			inst_manager.add_institution(inst)
			
			# Connect stress_maxed_out signal
			inst.stress_maxed_out.connect(_on_institution_stress_maxed.bind(inst))
			
			# Initialize institution state in save using canonical ID
			save_state.initialize_institution(canonical_id, inst_config)
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
	
	# Save to file using new path structure
	save_state.save_to_file(region_config.region_id)
	print("Game saved to: %s" % (RegionSaveState.SAVE_DIR + region_config.region_id + ".tres"))

## Load game state from file
func load_game(save_filename: String = "") -> bool:
	if save_filename == "" and region_config:
		save_filename = region_config.region_id
	
	var loaded_save = RegionSaveState.load_from_file(save_filename)
	if not loaded_save:
		push_error("Failed to load save file: %s" % save_filename)
		return false
	
	# Load the save state
	load_save_state(loaded_save)
	print("Game loaded: %s" % save_filename)
	return true

## Quick save (to default location)
func quick_save() -> void:
	save_game()
	_log_console("✓ Game saved (Day %d)" % clock.get_current_day())

## Quick load (from default location)
func quick_load() -> void:
	if load_game():
		_log_console("✓ Game loaded (Day %d)" % clock.get_current_day())
		_refresh_ui()
	else:
		_log_console("✗ No save file found")

## Refresh UI after loading
func _refresh_ui() -> void:
	# Update player dashboard
	_update_dashboard()
	
	# Refresh institution cards
	_setup_ui()
	
	# Refresh event tree viewer
	_refresh_event_tree()



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

## Institution stress reached 100% - queue event for processing
func _on_institution_stress_maxed(institution: Institution) -> void:
	_log_console("⚠ %s stress maxed out!" % institution.institution_name)
	
	# Queue the event to pending events instead of showing immediately
	if institution.institution_id in institution_configs:
		var config: InstitutionConfig = institution_configs[institution.institution_id]
		
		print("[SimulationRoot] Stress maxed for %s - queueing event" % institution.institution_id)
		
		# Get current stress event from tree
		var tree_state = save_state.get_stress_tree_state(institution.institution_id) if save_state else {"current_node": "", "pruned_branches": []}
		var current_node = tree_state.get("current_node", "")
		var pruned_branches = tree_state.get("pruned_branches", [])
		
		var event_node = config.get_current_stress_event(current_node, pruned_branches)
		
		if not event_node.is_empty():
			# Add to event manager's pending events queue
			var event_key = {
				"event": event_node,
				"type": EventManager.EventType.STRESS,
				"inst_id": institution.institution_id
			}
			event_manager.pending_events[event_key] = institution
			_log_console("📢 Event queued: %s" % event_node.get("title", "?"))
			
			# If no event is currently being shown, show this one
			if not event_dialog.visible:
				_show_pending_events_as_dialogs()
			return
	else:
		push_warning("[SimulationRoot] No config found for institution: %s" % institution.institution_id)
	
	# If we get here, there's no valid event - just log it
	_log_console("⚠ No stress event defined for %s - stress remains maxed" % institution.institution_name)

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
		
		# Note: InstitutionConfig should be loaded from .tres files, not created here
		# For test mode without proper region data, events will not be available
		push_warning("Test region: No InstitutionConfig for %s - events disabled" % data["id"])
	
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
	
	# Connect NEW UI buttons
	if view_crisis_btn:
		view_crisis_btn.pressed.connect(_on_view_crisis_pressed)
	if event_queue_btn:
		event_queue_btn.pressed.connect(_on_event_queue_pressed)
	if close_queue_btn:
		close_queue_btn.pressed.connect(_on_close_queue_pressed)
	if close_crisis_btn:
		close_crisis_btn.pressed.connect(_on_close_crisis_pressed)
	
	# Setup default actions panel
	_setup_default_actions_ui()
	
	# Connect event queue changed signal
	event_manager.event_queue_changed.connect(_update_queue_buttons)
	event_manager.crisis_triggered.connect(_on_crisis_events_triggered)
	
	# Update dashboard
	_update_dashboard()
	
	# Add to simulation_root group for callback
	add_to_group("simulation_root")

## Setup default actions UI
func _setup_default_actions_ui() -> void:
	if not action_inst_select:
		return
	
	# Populate institution dropdown for default actions
	action_inst_select.clear()
	for inst_id in institution_configs:
		var config = institution_configs[inst_id]
		action_inst_select.add_item(config.institution_name)
		action_inst_select.set_item_metadata(action_inst_select.item_count - 1, inst_id)
	
	# Connect signal
	action_inst_select.item_selected.connect(_on_action_inst_select_changed)
	
	# Initial display
	if action_inst_select.item_count > 0:
		action_inst_select.select(0)
		_refresh_default_actions()

## Refresh default actions for selected institution
## Shows ALL 5 actions with locked/unlocked state based on influence
func _refresh_default_actions() -> void:
	if not actions_container:
		return
	
	# Clear existing buttons
	for child in actions_container.get_children():
		child.queue_free()
	
	var selected_idx = action_inst_select.selected
	if selected_idx < 0:
		return
	
	var inst_id = action_inst_select.get_item_metadata(selected_idx)
	var institution = inst_manager.get_institution(inst_id)
	if not institution:
		return
	
	# Show current influence
	var inf_label = Label.new()
	inf_label.text = "Influence: %.0f%%" % institution.player_influence
	inf_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	actions_container.add_child(inf_label)
	
	# Get ALL default actions (always returns 5)
	var all_actions = event_manager.get_default_actions(institution)
	
	# Create buttons for each action
	for action in all_actions:
		var button = Button.new()
		var title = action.get("title", "Unknown")
		var cost = action.get("cost", {})
		var required_inf = action.get("required_influence", 0)
		var is_unlocked = action.get("unlocked", false)
		
		# Format button text with cost and influence requirement
		var cost_text = _format_action_cost(cost)
		if is_unlocked:
			button.text = title if cost_text.is_empty() else "%s (%s)" % [title, cost_text]
		else:
			button.text = "🔒 %s [%d+ inf]" % [title, required_inf]
			button.disabled = true
			button.modulate = Color(0.5, 0.5, 0.5)
		
		button.tooltip_text = _format_action_tooltip(action)
		
		# Connect with action data (only if unlocked)
		if is_unlocked:
			button.pressed.connect(_on_default_action_pressed.bind(action, institution))
		
		actions_container.add_child(button)

## Format cost for action button
func _format_action_cost(cost: Dictionary) -> String:
	var parts: Array = []
	if cost.get("bandwidth", 0) > 0:
		parts.append("%d BW" % cost["bandwidth"])
	if cost.get("cash", 0) > 0:
		parts.append("$%d" % cost["cash"])
	return ", ".join(parts)

## Format tooltip for default action
func _format_action_tooltip(action: Dictionary) -> String:
	var lines: Array = []
	lines.append(action.get("title", "Unknown"))
	lines.append(action.get("description", ""))
	lines.append("")
	
	var required_inf = action.get("required_influence", 0)
	lines.append("Required Influence: %d" % required_inf)
	
	var effects = action.get("effects", {})
	if not effects.is_empty():
		lines.append("")
		lines.append("== Effects ==")
		for key in effects:
			lines.append("  %s: %+d" % [key.capitalize(), effects[key]])
	
	var inf_change = action.get("influence_change", 0)
	if inf_change != 0:
		lines.append("")
		lines.append("Influence Change: %+d" % inf_change)
	
	return "\n".join(lines)

## Handle default action button pressed
func _on_default_action_pressed(action: Dictionary, institution: Institution) -> void:
	var success = event_manager.execute_default_action(action, institution)
	if success:
		_log_console("Executed: %s on %s" % [action.get("title", "?"), institution.institution_name])
		_update_dashboard()
		_refresh_default_actions()
		_refresh_event_tree()
	else:
		_log_console("Cannot afford: %s" % action.get("title", "?"))

## Action institution select changed
func _on_action_inst_select_changed(_index: int) -> void:
	_refresh_default_actions()

## Update queue button counts
func _update_queue_buttons() -> void:
	var event_count = event_manager.get_pending_events().size()
	var crisis_count = event_manager.get_pending_crisis_events().size()
	
	if event_queue_btn:
		event_queue_btn.text = "Event Queue (%d)" % event_count
	if view_crisis_btn:
		view_crisis_btn.text = "View Crisis (%d)" % crisis_count
		view_crisis_btn.modulate = Color.RED if crisis_count > 0 else Color.WHITE

## Handle View Crisis button
func _on_view_crisis_pressed() -> void:
	_show_crisis_view()

## Handle Event Queue button
func _on_event_queue_pressed() -> void:
	_show_event_queue()

## Handle close queue button
func _on_close_queue_pressed() -> void:
	event_queue_overlay.visible = false

## Handle close crisis button
func _on_close_crisis_pressed() -> void:
	crisis_view_overlay.visible = false

## Show event queue overlay
func _show_event_queue() -> void:
	# Clear existing items
	for child in event_queue_list.get_children():
		child.queue_free()
	
	var pending = event_manager.get_pending_events()
	
	if pending.is_empty():
		var label = Label.new()
		label.text = "No pending events"
		label.modulate = Color(0.6, 0.6, 0.6)
		event_queue_list.add_child(label)
	else:
		for event_key in pending:
			var event_data = event_key.get("event", {})
			var event_type = event_key.get("type", EventManager.EventType.STRESS)
			var institution = pending[event_key]
			
			var panel = PanelContainer.new()
			var vbox = VBoxContainer.new()
			panel.add_child(vbox)
			
			# Title
			var title_label = Label.new()
			var type_str = EventManager.EventType.keys()[event_type]
			var inst_name = institution.institution_name if institution else "Global"
			title_label.text = "[%s] %s" % [type_str, event_data.get("title", "Unknown")]
			title_label.add_theme_font_size_override("font_size", 14)
			vbox.add_child(title_label)
			
			# Institution
			var inst_label = Label.new()
			inst_label.text = "Institution: %s" % inst_name
			inst_label.modulate = Color(0.7, 0.7, 0.7)
			vbox.add_child(inst_label)
			
			# Description
			var desc_label = Label.new()
			desc_label.text = event_data.get("description", "")
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(desc_label)
			
			# Effects already applied
			var effects = event_data.get("effects", {})
			if not effects.is_empty():
				var effects_label = Label.new()
				var effects_parts: Array = []
				for key in effects:
					effects_parts.append("%s: %+d" % [key, effects[key]])
				effects_label.text = "Effects (applied): " + ", ".join(effects_parts)
				effects_label.modulate = Color(0.5, 0.7, 1.0)
				vbox.add_child(effects_label)
			
			# Respond button
			var respond_btn = Button.new()
			respond_btn.text = "Respond to Event"
			respond_btn.pressed.connect(_on_queue_event_respond.bind(event_key))
			vbox.add_child(respond_btn)
			
			event_queue_list.add_child(panel)
	
	event_queue_overlay.visible = true

## Handle respond to event from queue
func _on_queue_event_respond(event_key: Dictionary) -> void:
	event_queue_overlay.visible = false
	_show_pending_event_dialog(event_key)

## Show pending event dialog for a specific event
func _show_pending_event_dialog(event_key: Dictionary) -> void:
	var event_data = event_key.get("event", {})
	var institution = event_manager.get_pending_events().get(event_key)
	var choices = event_data.get("choices", [])
	
	show_event_dialog(event_data, institution, choices, false)
	_current_pending_event_key = event_key

## Show crisis view overlay
func _show_crisis_view() -> void:
	# Clear existing items
	for child in crisis_list.get_children():
		child.queue_free()
	
	# Update relevance display
	var insts = inst_manager.get_all_institutions()
	var relevance = player_state.calculate_relevance(insts)
	crisis_view_relevance.text = "Your Relevance: %.1f%%" % relevance
	
	var crises = event_manager.get_pending_crisis_events()
	
	if crises.is_empty():
		var label = Label.new()
		label.text = "No active crises"
		label.modulate = Color(0.6, 0.6, 0.6)
		crisis_list.add_child(label)
	else:
		for i in range(crises.size()):
			var crisis_data = crises[i]
			var event_data = crisis_data.get("event", {})
			
			var panel = PanelContainer.new()
			var vbox = VBoxContainer.new()
			panel.add_child(vbox)
			
			# Title
			var title_label = Label.new()
			title_label.text = "⚠ %s" % event_data.get("title", "Unknown Crisis")
			title_label.add_theme_font_size_override("font_size", 16)
			title_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			vbox.add_child(title_label)
			
			# Description
			var desc_label = Label.new()
			desc_label.text = event_data.get("description", "")
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(desc_label)
			
			# Effects already applied
			var effects = event_data.get("effects", {})
			if not effects.is_empty():
				var effects_label = Label.new()
				var effects_parts: Array = []
				for key in effects:
					effects_parts.append("%s: %+d" % [key, effects[key]])
				effects_label.text = "Crisis Effects (applied): " + ", ".join(effects_parts)
				effects_label.modulate = Color(1, 0.7, 0.3)
				vbox.add_child(effects_label)
			
			# Choices
			var choices = event_data.get("choices", [])
			if not choices.is_empty():
				var choices_label = Label.new()
				choices_label.text = "Response Options:"
				vbox.add_child(choices_label)
				
				for j in range(choices.size()):
					var choice = choices[j]
					var choice_btn = Button.new()
					choice_btn.text = choice.get("text", "Option %d" % (j + 1))
					choice_btn.tooltip_text = _format_choice_tooltip(choice)
					choice_btn.pressed.connect(_on_crisis_choice_selected.bind(i, j))
					vbox.add_child(choice_btn)
			
			crisis_list.add_child(panel)
	
	crisis_view_overlay.visible = true

## Format choice tooltip
func _format_choice_tooltip(choice: Dictionary) -> String:
	var lines: Array = []
	lines.append(choice.get("text", ""))
	
	var cost = choice.get("cost", {})
	if cost is Dictionary and not cost.is_empty():
		lines.append("")
		lines.append("Cost:")
		if cost.get("bandwidth", 0) > 0:
			lines.append("  Bandwidth: %d" % cost["bandwidth"])
		if cost.get("cash", 0) > 0:
			lines.append("  Cash: $%d" % cost["cash"])
	elif cost is int and cost > 0:
		lines.append("")
		lines.append("Cost: %d bandwidth" % cost)
	
	var effects = choice.get("effects", {})
	if not effects.is_empty():
		lines.append("")
		lines.append("Effects:")
		for key in effects:
			lines.append("  %s: %+d" % [key.capitalize(), effects[key]])
	
	return "\n".join(lines)

## Handle crisis choice selected
func _on_crisis_choice_selected(crisis_index: int, choice_index: int) -> void:
	event_manager.resolve_crisis_event(crisis_index, choice_index)
	_update_dashboard()
	_refresh_event_tree()
	_update_queue_buttons()
	
	# Refresh crisis view if still open
	if crisis_view_overlay.visible:
		_show_crisis_view()

## Handle crisis events triggered (shows relevance notification)
func _on_crisis_events_triggered(crisis_events: Array) -> void:
	var insts = inst_manager.get_all_institutions()
	var relevance = player_state.calculate_relevance(insts)
	_log_console("⚠ CRISIS TRIGGERED! Your relevance: %.1f%%" % relevance)
	_update_queue_buttons()

## Setup event tree UI
func _setup_event_tree_ui() -> void:
	# Populate institution dropdown
	institution_select.clear()
	for inst_id in institution_configs:
		var config = institution_configs[inst_id]
		institution_select.add_item(config.institution_name)
		institution_select.set_item_metadata(institution_select.item_count - 1, inst_id)
	
	# Populate tree type dropdown with NEW types
	tree_type_select.clear()
	tree_type_select.add_item("Stress Triggered", TreeType.STRESS_TRIGGERED)
	tree_type_select.add_item("Random Triggered", TreeType.RANDOM_TRIGGERED)
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
		TreeType.STRESS_TRIGGERED:
			_build_stress_triggered_tree(root, inst_id)
		TreeType.RANDOM_TRIGGERED:
			_build_random_triggered_tree(root, inst_id)
		TreeType.CRISIS_TREE:
			_build_crisis_tree(root)

func _build_stress_triggered_tree(root: TreeItem, inst_id: String) -> void:
	if inst_id not in institution_configs:
		return
	
	var config: InstitutionConfig = institution_configs[inst_id]
	
	# Get tree state from save
	var tree_state = save_state.get_stress_tree_state(inst_id) if save_state else {"current_node": "", "pruned_branches": []}
	var current_node = tree_state.get("current_node", "")
	var pruned_branches = tree_state.get("pruned_branches", [])
	
	# Build node map for hierarchy
	var node_map: Dictionary = {}
	for node in config.stress_triggered_tree:
		var node_id = node.get("node_id", "")
		if node_id != "":
			node_map[node_id] = node
	
	# Find child nodes (referenced by next_node)
	var child_nodes: Dictionary = {}
	for node in config.stress_triggered_tree:
		for choice in node.get("choices", []):
			var next_node = choice.get("next_node", "")
			if next_node != "":
				child_nodes[next_node] = node.get("node_id", "")
	
	# Find root nodes
	var root_nodes: Array = []
	for node in config.stress_triggered_tree:
		var node_id = node.get("node_id", "")
		if node_id not in child_nodes:
			root_nodes.append(node)
	
	# Build tree from root nodes
	for node in root_nodes:
		_add_new_tree_node(root, node, node_map, current_node, pruned_branches, inst_id, "stress")

## Build randomly-triggered event tree (NEW)
func _build_random_triggered_tree(root: TreeItem, inst_id: String) -> void:
	if inst_id not in institution_configs:
		return
	
	var config: InstitutionConfig = institution_configs[inst_id]
	
	# Get tree state from save
	var tree_state = save_state.get_random_tree_state(inst_id) if save_state else {"current_node": "", "pruned_branches": []}
	var current_node = tree_state.get("current_node", "")
	var pruned_branches = tree_state.get("pruned_branches", [])
	
	# Build node map for hierarchy
	var node_map: Dictionary = {}
	for node in config.randomly_triggered_tree:
		var node_id = node.get("node_id", "")
		if node_id != "":
			node_map[node_id] = node
	
	# Find child nodes (referenced by next_node)
	var child_nodes: Dictionary = {}
	for node in config.randomly_triggered_tree:
		for choice in node.get("choices", []):
			var next_node = choice.get("next_node", "")
			if next_node != "":
				child_nodes[next_node] = node.get("node_id", "")
	
	# Find root nodes
	var root_nodes: Array = []
	for node in config.randomly_triggered_tree:
		var node_id = node.get("node_id", "")
		if node_id not in child_nodes:
			root_nodes.append(node)
	
	# Build tree from root nodes
	for node in root_nodes:
		_add_new_tree_node(root, node, node_map, current_node, pruned_branches, inst_id, "random")

## Add a node to the new tree structure (stress/random)
func _add_new_tree_node(parent_item: TreeItem, node: Dictionary, node_map: Dictionary, current_node: String, pruned_branches: Array, inst_id: String, tree_type: String) -> void:
	var node_id = node.get("node_id", "")
	var title = node.get("title", "Unknown")
	var conditions = node.get("conditions", {})
	var choices = node.get("choices", [])
	
	var item = event_tree.create_item(parent_item)
	
	# Determine node status
	var is_current = (node_id == current_node) or (current_node == "" and parent_item == event_tree.get_root())
	var is_pruned = node_id in pruned_branches
	
	# Build display text
	var status_icon = ""
	if is_pruned:
		status_icon = "✗ "
	elif is_current:
		status_icon = "▶ "  # Current/active node
	else:
		status_icon = "○ "
	
	var display = "%s[%s] %s" % [status_icon, node_id, title]
	
	# Add condition hints
	var cond_parts: Array = []
	for key in conditions:
		cond_parts.append("%s: %s" % [key, conditions[key]])
	if not cond_parts.is_empty():
		display += " {%s}" % ", ".join(cond_parts)
	
	item.set_text(0, display)
	item.set_metadata(0, {"type": tree_type, "node": node, "inst_id": inst_id})
	
	# Color based on status
	if is_pruned:
		item.set_custom_color(0, Color(0.9, 0.3, 0.3))  # Red
	elif is_current:
		item.set_custom_color(0, Color(0.3, 0.9, 0.5))  # Green
	
	# Add choices as children
	for i in range(choices.size()):
		var choice = choices[i]
		var choice_text = choice.get("text", "Choice %d" % (i + 1))
		var next_node_id = choice.get("next_node", "")
		var prunes = choice.get("prunes_branches", [])
		
		var choice_item = event_tree.create_item(item)
		var choice_display = "→ %s" % choice_text
		if not prunes.is_empty():
			choice_display += " [PRUNES: %s]" % ", ".join(prunes)
		
		choice_item.set_text(0, choice_display)
		choice_item.set_metadata(0, {"type": "choice", "choice": choice, "parent_node": node, "choice_index": i})
		choice_item.set_custom_color(0, Color(0.6, 0.8, 1.0))  # Light blue
		
		# Add next node as child of choice
		if next_node_id != "" and next_node_id in node_map:
			var next_node = node_map[next_node_id]
			_add_new_tree_node(choice_item, next_node, node_map, current_node, pruned_branches, inst_id, tree_type)

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
	quick_save()
	# Keep menu open but show feedback
	_log_console("✓ Game saved successfully!")

## Load button pressed (if exists)
func _on_load_pressed() -> void:
	quick_load()
	pause_menu.visible = false
	_log_console("Game saved!")

## Main menu button pressed
func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

## Quit button pressed
func _on_quit_pressed() -> void:
	get_tree().quit()

## Show event dialog with choices
func show_event_dialog(event_node: Dictionary, institution: Institution, choices: Array, is_player_action: bool = false) -> void:
	current_event_institution = institution
	pending_event_choices = choices
	current_pending_event_node = event_node
	current_pending_event_is_player_action = is_player_action
	
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
			
			# Support both "label" and "text" keys for backwards compatibility
			var label = choice.get("label", choice.get("text", "Choice %d" % (i + 1)))
			var cost = choice.get("cost", 0)
			var cost_parts = []
			if cost is int and cost > 0:
				cost_parts.append("%d BW" % cost)
			elif cost is Dictionary and not cost.is_empty():
				if cost.get("cash", 0) > 0:
					cost_parts.append("$%.0f" % cost["cash"])
				if cost.get("bandwidth", 0) > 0:
					cost_parts.append("%.0f BW" % cost["bandwidth"])
			if not cost_parts.is_empty():
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
	
	# Handle cost - support both number and dictionary format
	var cash_cost = 0.0
	var bandwidth_cost = 0.0
	if typeof(cost) == TYPE_DICTIONARY:
		cash_cost = cost.get("cash", 0.0)
		bandwidth_cost = cost.get("bandwidth", 0.0)
	elif typeof(cost) == TYPE_FLOAT or typeof(cost) == TYPE_INT:
		cash_cost = float(cost)  # Simple cost = cash cost
	
	# Check cost
	if cash_cost > player_state.cash:
		_log_console("Not enough cash!")
		return
	if bandwidth_cost > player_state.bandwidth:
		_log_console("Not enough bandwidth!")
		return
	
	# Spend cost
	if cash_cost > 0:
		player_state.spend_cash(cash_cost)
	if bandwidth_cost > 0:
		player_state.spend_bandwidth(bandwidth_cost)
	
	# Apply effects to institution
	if current_event_institution:
		event_manager.apply_effects(effects, current_event_institution)
	
	# Update tree state with branching
	if save_state and current_pending_event_node:
		var node_id = current_pending_event_node.get("node_id", "")
		var next_node = choice.get("next_node", "")
		var prunes = choice.get("prunes_branches", [])
		
		print("[SimulationRoot] Recording choice - node: %s, next: %s, prunes: %s" % [node_id, next_node, str(prunes)])
		
		# Determine event type by checking which tree contains this node
		if current_event_institution:
			var inst_id = current_event_institution.institution_id
			if inst_id in institution_configs:
				var config: InstitutionConfig = institution_configs[inst_id]
				
				# Check if this is a stress event
				var is_stress_event = false
				for event in config.stress_triggered_tree:
					if event.get("node_id", "") == node_id:
						is_stress_event = true
						break
				
				if is_stress_event:
					save_state.record_stress_event(inst_id, node_id, choice)
				else:
					save_state.record_random_event(inst_id, node_id, choice)
	
	# Support both "label" and "text" keys
	var choice_label = choice.get("label", choice.get("text", "Unknown"))
	_log_console("Chose: %s" % choice_label)
	_update_dashboard()
	_refresh_event_tree()  # Refresh tree to show updated state
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
	}
	
	var buttons_row2 := {
		"AddCashBtn": _on_debug_add_cash,
		"AddBandwidthBtn": _on_debug_add_bandwidth,
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
	
	# Step 0: Apply delayed effects from previous day's decisions
	print("[SimulationRoot] === APPLYING DELAYED EFFECTS FROM YESTERDAY ===")
	event_manager.apply_queued_effects()
	
	# Step 1: Daily updates for all institutions
	for inst in insts:
		inst.daily_auto_update()
		inst.apply_stress_decay()
	
	# Step 2: Collect day start events using new system
	# Note: This also triggers exposure increase and autonomous effects when events trigger
	var pending = event_manager.collect_day_start_events(insts, region_config)
	
	# Step 3: End of day updates
	player_state.decay_exposure()
	clock.current_day += 1
	_log_console("Day advanced to: %d" % clock.current_day)
	_update_dashboard()
	
	# Step 4: Display pending events as bubbles (for now, show count)
	if not pending.is_empty():
		_log_console("📢 %d events triggered! (Events shown as bubbles)" % pending.size())
		# For now, show each event in a dialog sequentially
		# TODO: Replace with UI bubbles system
		_show_pending_events_as_dialogs()

## Show pending events as dialogs (temporary until bubble UI is implemented)
func _show_pending_events_as_dialogs() -> void:
	var pending = event_manager.get_pending_events()
	if pending.is_empty():
		return
	
	# Get first event to show
	var first_key = pending.keys()[0]
	var event_data = first_key.get("event", {})
	var event_type = first_key.get("type", EventManager.EventType.STRESS)
	var institution = pending[first_key]
	
	# Convert to dialog format
	var choices = event_data.get("choices", [])
	show_event_dialog(event_data, institution, choices, false)
	
	# Store for resolution
	_current_pending_event_key = first_key

## Current pending event key being displayed
var _current_pending_event_key: Dictionary = {}

## Handle event choice when using new system
func _on_new_event_choice_selected(choice_index: int) -> void:
	if _current_pending_event_key.is_empty():
		return
	
	# Use the new resolve_event method
	event_manager.resolve_event(_current_pending_event_key, choice_index)
	_current_pending_event_key = {}
	
	_update_dashboard()
	_refresh_event_tree()
	event_dialog.visible = false
	
	# Show next event if any
	_show_pending_events_as_dialogs()

## DEBUG: Add stress to random institution
func _on_debug_add_stress() -> void:
	var insts = inst_manager.get_all_institutions()
	if insts.is_empty():
		return
	
	var target = insts[randi() % insts.size()]
	target.apply_stress(20.0)
	_log_console("Added 20 stress to %s (stress: %.1f)" % [target.institution_name, target.stress])

## DEBUG: Add global tension and auto-trigger crisis at threshold
func _on_debug_add_tension() -> void:
	tension_mgr.add_tension(10.0)
	_log_console("Added 10 tension (total: %.1f / %.1f)" % [tension_mgr.global_tension, tension_mgr.crisis_threshold])
	_update_dashboard()
	
	# Auto-trigger crisis when tension reaches threshold
	if tension_mgr.check_crisis():
		_auto_trigger_crisis()

## Auto-trigger crisis when tension reaches threshold
## Shows EMERGENCY POPUP immediately - crisis affects global graph
func _auto_trigger_crisis() -> void:
	_log_console("🚨 CRISIS TRIGGERED! Tension threshold reached!")
	
	# Get epicenter (highest stress institution)
	var epicenter = tension_mgr.get_crisis_epicenter(inst_manager)
	if not epicenter:
		push_warning("[Crisis] No epicenter found")
		return
	
	print("")
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║           🚨 CRISIS TRIGGERED 🚨                             ║")
	print("║ Epicenter: %s" % epicenter.institution_name.rpad(48) + "║")
	print("║ Epicenter Stress: %.1f / Strength: %.1f" % [epicenter.stress, epicenter.strength] + "".rpad(20) + "║")
	print("╚══════════════════════════════════════════════════════════════╝")
	
	# Print graph state BEFORE crisis effects
	if dep_graph:
		dep_graph.print_graph_weights("GRAPH BEFORE CRISIS", epicenter.institution_id)
	
	# Get crisis event from tree
	var crisis_state = save_state.crisis_tree_state if save_state else {"current_node": "", "pruned_branches": []}
	var current_node = crisis_state.get("current_node", "")
	var pruned_branches = crisis_state.get("pruned_branches", [])
	
	var crisis_event = _get_crisis_event(current_node, pruned_branches)
	if crisis_event.is_empty():
		push_warning("[Crisis] No crisis event available")
		_evaluate_crisis(epicenter)  # Fall back to simple evaluation
		return
	
	# IMMEDIATELY affect global graph via dependency graph
	print("[Crisis] Applying IMMEDIATE crisis effects to global graph")
	print("[Crisis] Change originates from: %s" % epicenter.institution_id)
	var base_effects = crisis_event.get("effects", {})
	if not base_effects.is_empty() and dep_graph:
		dep_graph.apply_crisis_effects(base_effects, inst_manager)
	
	# Propagate stress from epicenter through dependency graph
	if dep_graph:
		dep_graph.propagate_stress(epicenter, inst_manager)
		# Print graph state AFTER crisis effects
		dep_graph.print_graph_weights("GRAPH AFTER CRISIS EFFECTS", epicenter.institution_id)
	
	# Show EMERGENCY POPUP with choices
	_show_emergency_crisis_popup(crisis_event, epicenter)

## Get crisis event from region config tree
func _get_crisis_event(current_node: String, pruned_branches: Array) -> Dictionary:
	if not region_config:
		return {}
	
	# If we have a current node, get it
	if current_node != "":
		var node = region_config.get_crisis_node(current_node)
		if not node.is_empty() and current_node not in pruned_branches:
			return node
	
	# Otherwise get root node
	if region_config.crisis_tree.size() > 0:
		var root = region_config.crisis_tree[0]
		var root_id = root.get("node_id", "")
		if root_id not in pruned_branches:
			return root
	
	return {}

## Show emergency crisis popup with randomized currency effects
func _show_emergency_crisis_popup(crisis_event: Dictionary, epicenter: Institution) -> void:
	# Build popup content
	var title = crisis_event.get("title", "CRISIS!")
	var description = crisis_event.get("description", "A crisis has erupted!")
	var choices = crisis_event.get("choices", [])
	
	# Clear crisis overlay
	for child in crisis_choices_container.get_children():
		child.queue_free()
	
	# Set crisis info
	crisis_description.text = "🚨 EMERGENCY: %s\n\nEpicenter: %s\n\n%s" % [
		title, epicenter.institution_name, description
	]
	
	# Show base effects that were already applied
	var base_effects = crisis_event.get("effects", {})
	if not base_effects.is_empty():
		var effects_parts: Array = []
		for key in base_effects:
			effects_parts.append("%s: %+d" % [key.capitalize(), base_effects[key]])
		crisis_effects.text = "Global Effects (APPLIED): " + ", ".join(effects_parts)
	else:
		crisis_effects.text = "The crisis is destabilizing institutions..."
	
	# Add choice buttons with RANDOMIZED currency effects
	if choices.is_empty():
		# No choices - auto-resolve
		var close_btn = Button.new()
		close_btn.text = "Acknowledge Crisis"
		close_btn.pressed.connect(_on_crisis_acknowledged.bind(crisis_event, epicenter))
		crisis_choices_container.add_child(close_btn)
	else:
		for i in range(choices.size()):
			var choice = choices[i]
			var choice_btn = Button.new()
			
			# Calculate randomized effects preview
			var random_preview = _calculate_crisis_choice_preview(choice)
			choice_btn.text = "%s\n%s" % [choice.get("text", "Option"), random_preview]
			choice_btn.tooltip_text = _format_crisis_choice_tooltip(choice)
			choice_btn.pressed.connect(_on_emergency_crisis_choice.bind(i, crisis_event, epicenter))
			crisis_choices_container.add_child(choice_btn)
	
	# Show overlay
	crisis_overlay.visible = true

## Calculate randomized effects preview for crisis choice
func _calculate_crisis_choice_preview(choice: Dictionary) -> String:
	var effects = choice.get("effects", {})
	var cost = choice.get("cost", {})
	var parts: Array = []
	
	# Show costs
	if cost is Dictionary:
		if cost.get("cash", 0) > 0:
			parts.append("Cost: $%d" % cost["cash"])
		if cost.get("bandwidth", 0) > 0:
			parts.append("BW: %d" % cost["bandwidth"])
	
	# Show RANDOMIZED effects range
	for key in effects:
		var base = effects[key]
		var variance = abs(base) * 0.3  # 30% variance
		var min_val = base - variance if base > 0 else base + variance
		var max_val = base + variance if base > 0 else base - variance
		parts.append("%s: %+.0f to %+.0f" % [key.capitalize(), min_val, max_val])
	
	return " | ".join(parts) if parts.size() > 0 else "(Unknown outcome)"

## Format crisis choice tooltip with full details
func _format_crisis_choice_tooltip(choice: Dictionary) -> String:
	var lines: Array = []
	lines.append("=== %s ===" % choice.get("text", "Choice"))
	lines.append(choice.get("description", ""))
	lines.append("")
	
	var requires = choice.get("requires", {})
	if not requires.is_empty():
		lines.append("Requirements:")
		for key in requires:
			lines.append("  %s: %.0f" % [key, requires[key]])
		lines.append("")
	
	var cost = choice.get("cost", {})
	if cost is Dictionary and not cost.is_empty():
		lines.append("Cost:")
		for key in cost:
			lines.append("  %s: %.0f" % [key.capitalize(), cost[key]])
		lines.append("")
	
	var effects = choice.get("effects", {})
	if not effects.is_empty():
		lines.append("Effects (with randomness ±30%):")
		for key in effects:
			lines.append("  %s: %+d" % [key.capitalize(), effects[key]])
	
	return "\n".join(lines)

## Handle emergency crisis choice selection
func _on_emergency_crisis_choice(choice_index: int, crisis_event: Dictionary, epicenter: Institution) -> void:
	var choices = crisis_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	
	var choice = choices[choice_index]
	var node_id = crisis_event.get("node_id", "")
	
	print("")
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║           CRISIS RESOLUTION                                  ║")
	print("║ Player chose: %s" % choice.get("text", "?").rpad(44) + "║")
	print("╚══════════════════════════════════════════════════════════════╝")
	
	# Check cost
	var cost = choice.get("cost", {})
	if cost is Dictionary:
		if player_state.cash < cost.get("cash", 0) or player_state.bandwidth < cost.get("bandwidth", 0):
			_log_console("Cannot afford crisis choice!")
			return
		# Spend cost
		player_state.spend_cash(cost.get("cash", 0))
		player_state.spend_bandwidth(cost.get("bandwidth", 0))
	
	# Apply RANDOMIZED effects
	var effects = choice.get("effects", {})
	_apply_randomized_crisis_effects(effects, epicenter)
	
	# Update crisis tree state - prune other branches
	if save_state:
		save_state.record_crisis_event(node_id, choice)
		
		# Prune branches not selected
		for i in range(choices.size()):
			if i != choice_index:
				var other_choice = choices[i]
				var other_next = other_choice.get("next_node", "")
				if other_next != "" and save_state:
					save_state.prune_crisis_branch(other_next)
	
	# Reset tension after crisis
	tension_mgr.reset_after_crisis()
	
	# Rewire graph for resilience
	if dep_graph:
		dep_graph.rewire_for_resilience(inst_manager)
		# Print final graph state after crisis resolution
		dep_graph.print_graph_weights("GRAPH AFTER CRISIS RESOLUTION", epicenter.institution_id)
	
	# Close popup and update UI
	crisis_overlay.visible = false
	_update_dashboard()
	_refresh_event_tree()
	_log_console("Crisis resolved! Tension reset to %.1f" % tension_mgr.global_tension)

## Apply randomized effects from crisis choice (±30% variance)
func _apply_randomized_crisis_effects(effects: Dictionary, epicenter: Institution) -> void:
	for key in effects:
		var base_value = effects[key]
		var variance = abs(base_value) * 0.3  # 30% variance
		var random_value = base_value + randf_range(-variance, variance)
		
		match key:
			"tension_change":
				tension_mgr.add_tension(random_value)
				print("[Crisis] Tension changed by %+.1f (base: %+d)" % [random_value, base_value])
			"exposure_change":
				player_state.increase_exposure(random_value)
				print("[Crisis] Exposure changed by %+.1f (base: %+d)" % [random_value, base_value])
			"all_influence_change":
				for inst in inst_manager.get_all_institutions():
					inst.increase_influence(random_value)
				print("[Crisis] All influence changed by %+.1f (base: %+d)" % [random_value, base_value])
			"govt_influence_change":
				var govt = inst_manager.get_institution("govt_novara")
				if govt:
					govt.increase_influence(random_value)
			"military_influence_change":
				var mil = inst_manager.get_institution("military_novara")
				if mil:
					mil.increase_influence(random_value)
			"all_stress_change":
				for inst in inst_manager.get_all_institutions():
					if random_value > 0:
						inst.apply_stress(random_value)
					else:
						inst.reduce_stress(abs(random_value))
				print("[Crisis] All stress changed by %+.1f (base: %+d)" % [random_value, base_value])
			"all_capacity_change":
				for inst in inst_manager.get_all_institutions():
					inst.capacity = clamp(inst.capacity + random_value, 0, 100)
					inst.capacity_changed.emit(inst.capacity)
				print("[Crisis] All capacity changed by %+.1f (base: %+d)" % [random_value, base_value])
			# Handle specific institution effects
			var inst_key:
				if inst_key.ends_with("_stress_change"):
					var inst_id = inst_key.replace("_stress_change", "_novara")
					var inst = inst_manager.get_institution(inst_id)
					if inst:
						if random_value > 0:
							inst.apply_stress(random_value)
						else:
							inst.reduce_stress(abs(random_value))
				elif inst_key.ends_with("_strength_change"):
					var inst_id = inst_key.replace("_strength_change", "_novara")
					var inst = inst_manager.get_institution(inst_id)
					if inst:
						inst.strength = clamp(inst.strength + random_value, 0, 100)
						inst.strength_changed.emit(inst.strength)
				elif inst_key.ends_with("_capacity_change"):
					var inst_id = inst_key.replace("_capacity_change", "_novara")
					var inst = inst_manager.get_institution(inst_id)
					if inst:
						inst.capacity = clamp(inst.capacity + random_value, 0, 100)
						inst.capacity_changed.emit(inst.capacity)

## Handle crisis acknowledged (no choices)
func _on_crisis_acknowledged(crisis_event: Dictionary, epicenter: Institution) -> void:
	# Reset tension
	tension_mgr.reset_after_crisis()
	
	# Rewire graph
	if dep_graph:
		dep_graph.rewire_for_resilience(inst_manager)
	
	# Close popup
	crisis_overlay.visible = false
	_update_dashboard()
	_refresh_event_tree()
	_log_console("Crisis acknowledged. Tension reset.")

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
	
	# Update relevance
	if relevance_label:
		var insts = inst_manager.get_all_institutions()
		var relevance = player_state.calculate_relevance(insts)
		relevance_label.text = "Relevance: %.1f%%" % relevance
	
	# Update queue button counts
	_update_queue_buttons()
