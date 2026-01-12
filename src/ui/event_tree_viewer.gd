extends Control
## EventTreeViewer: Displays event trees for all institutions
## Allows viewing player actions, autonomous events, and crisis trees

class_name EventTreeViewer

@onready var institution_list = $MainContainer/VBoxContainer/ContentSplit/LeftPanel/VBoxContainer/InstitutionList
@onready var tree_type_option = $MainContainer/VBoxContainer/ContentSplit/LeftPanel/VBoxContainer/TreeTypeOption
@onready var event_tree = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/TreeView/TreeScroll/EventTree
@onready var node_title = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/NodeTitle
@onready var node_description = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/NodeDescription
@onready var conditions_label = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/ConditionsLabel
@onready var cost_label = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/CostLabel
@onready var effects_label = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/EffectsLabel
@onready var choices_label = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/ChoicesLabel
@onready var choices_container = $MainContainer/VBoxContainer/ContentSplit/RightPanel/MarginContainer/VSplitContainer/DetailsPanel/DetailsScroll/DetailsContainer/ChoicesContainer

var institution_configs: Dictionary = {}  # inst_id -> InstitutionConfig
var region_config: RegionConfig
var current_institution_id: String = ""
var current_tree_type: int = 0  # 0 = Player Actions, 1 = Autonomous Events

enum TreeType { PLAYER_ACTIONS, AUTONOMOUS_EVENTS, CRISIS_TREE }

func _ready() -> void:
	_load_data()
	_setup_tree_type_options()
	_populate_institution_list()

## Load all institution configs from region
func _load_data() -> void:
	var region_path = "res://assets/regions/novara.tres"
	
	if ResourceLoader.exists(region_path):
		region_config = load(region_path) as RegionConfig
		
		if region_config:
			# Load institution configs
			for inst_id in region_config.get_institution_ids():
				var inst_config = region_config.load_institution_config(inst_id)
				if inst_config:
					institution_configs[inst_id] = inst_config
	
	# Fallback: create default configs if none loaded
	if institution_configs.is_empty():
		_create_fallback_configs()

## Create fallback configs for testing
func _create_fallback_configs() -> void:
	var default_ids = ["govt", "military", "intel", "media"]
	var default_names = ["Government", "Military", "Intelligence", "Media"]
	
	for i in range(default_ids.size()):
		var config = InstitutionConfig.new()
		config.institution_id = default_ids[i]
		config.institution_name = default_names[i]
		config.create_default_player_tree()
		config.create_default_autonomous_tree()
		institution_configs[default_ids[i]] = config

## Setup tree type dropdown
func _setup_tree_type_options() -> void:
	tree_type_option.add_item("Player Actions", TreeType.PLAYER_ACTIONS)
	tree_type_option.add_item("Autonomous Events", TreeType.AUTONOMOUS_EVENTS)
	tree_type_option.add_item("Crisis Tree (Region)", TreeType.CRISIS_TREE)
	tree_type_option.select(0)

## Populate institution list
func _populate_institution_list() -> void:
	institution_list.clear()
	
	for inst_id in institution_configs:
		var config = institution_configs[inst_id]
		institution_list.add_item(config.institution_name)
		institution_list.set_item_metadata(institution_list.item_count - 1, inst_id)
	
	if institution_list.item_count > 0:
		institution_list.select(0)
		_on_institution_selected(0)

## Institution selected from list
func _on_institution_selected(index: int) -> void:
	current_institution_id = institution_list.get_item_metadata(index)
	_refresh_tree()

## Tree type changed
func _on_tree_type_selected(index: int) -> void:
	current_tree_type = tree_type_option.get_item_id(index)
	_refresh_tree()

## Refresh the event tree display
func _refresh_tree() -> void:
	event_tree.clear()
	_clear_details()
	
	var root = event_tree.create_item()
	
	match current_tree_type:
		TreeType.PLAYER_ACTIONS:
			_build_player_tree(root)
		TreeType.AUTONOMOUS_EVENTS:
			_build_autonomous_tree(root)
		TreeType.CRISIS_TREE:
			_build_crisis_tree(root)

## Build player action tree
func _build_player_tree(root: TreeItem) -> void:
	if current_institution_id.is_empty() or current_institution_id not in institution_configs:
		return
	
	var config = institution_configs[current_institution_id]
	
	for action_node in config.player_event_tree:
		var item = event_tree.create_item(root)
		var title = action_node.get("title", "Unknown Action")
		var node_id = action_node.get("node_id", "")
		
		# Format display
		var display_text = title
		var conditions = action_node.get("conditions", {})
		if not conditions.is_empty():
			var cond_hints = []
			if conditions.get("min_influence", 0) > 0:
				cond_hints.append("Inf>=%d" % conditions["min_influence"])
			if not cond_hints.is_empty():
				display_text += " [%s]" % ", ".join(cond_hints)
		
		item.set_text(0, display_text)
		item.set_metadata(0, {"type": "player", "node": action_node})
		
		# Add child choices if any
		var choices = action_node.get("choices", [])
		for choice in choices:
			var choice_item = event_tree.create_item(item)
			choice_item.set_text(0, "→ " + choice.get("label", "Choice"))
			choice_item.set_metadata(0, {"type": "choice", "node": choice, "parent": action_node})

## Build autonomous event tree
func _build_autonomous_tree(root: TreeItem) -> void:
	if current_institution_id.is_empty() or current_institution_id not in institution_configs:
		return
	
	var config = institution_configs[current_institution_id]
	
	for event_node in config.autonomous_event_tree:
		var item = event_tree.create_item(root)
		var title = event_node.get("title", "Unknown Event")
		
		# Show trigger conditions
		var conditions = event_node.get("trigger_conditions", {})
		var trigger_text = ""
		if conditions.get("stress_above", 0) > 0:
			trigger_text = " [Stress>%d]" % conditions["stress_above"]
		elif conditions.get("strength_below", 0) > 0:
			trigger_text = " [Strength<%d]" % conditions["strength_below"]
		
		item.set_text(0, title + trigger_text)
		item.set_metadata(0, {"type": "autonomous", "node": event_node})
		
		# Add player choices
		var choices = event_node.get("player_choices", [])
		for choice in choices:
			var choice_item = event_tree.create_item(item)
			choice_item.set_text(0, "→ " + choice.get("label", "Choice"))
			choice_item.set_metadata(0, {"type": "auto_choice", "node": choice, "parent": event_node})

## Build crisis tree (region-level)
func _build_crisis_tree(root: TreeItem) -> void:
	if not region_config:
		var no_data = event_tree.create_item(root)
		no_data.set_text(0, "No region config loaded")
		return
	
	for crisis_node in region_config.crisis_tree:
		var item = event_tree.create_item(root)
		var title = crisis_node.get("title", "Unknown Crisis")
		var node_id = crisis_node.get("node_id", "")
		
		item.set_text(0, "[%s] %s" % [node_id, title])
		item.set_metadata(0, {"type": "crisis", "node": crisis_node})
		
		# Add choices
		var choices = crisis_node.get("choices", [])
		for choice in choices:
			var choice_item = event_tree.create_item(item)
			var next = choice.get("next_node", "end")
			choice_item.set_text(0, "→ %s (→ %s)" % [choice.get("label", "Choice"), next])
			choice_item.set_metadata(0, {"type": "crisis_choice", "node": choice, "parent": crisis_node})

## Event node selected in tree
func _on_event_node_selected() -> void:
	var selected = event_tree.get_selected()
	if not selected:
		return
	
	var meta = selected.get_metadata(0)
	if not meta or not meta.has("node"):
		return
	
	var node = meta["node"]
	var node_type = meta.get("type", "")
	
	match node_type:
		"player":
			_show_player_action_details(node)
		"autonomous":
			_show_autonomous_event_details(node)
		"crisis":
			_show_crisis_node_details(node)
		"choice", "auto_choice", "crisis_choice":
			_show_choice_details(node, meta.get("parent", {}))

## Clear details panel
func _clear_details() -> void:
	node_title.text = "Select an event node"
	node_description.text = ""
	conditions_label.text = ""
	cost_label.text = ""
	effects_label.text = ""
	choices_label.text = ""
	
	for child in choices_container.get_children():
		child.queue_free()

## Show player action details
func _show_player_action_details(node: Dictionary) -> void:
	node_title.text = node.get("title", "Unknown Action")
	node_description.text = node.get("description", "No description available.")
	
	# Conditions
	var conditions = node.get("conditions", {})
	if not conditions.is_empty():
		var cond_parts = []
		if conditions.get("min_influence", 0) > 0:
			cond_parts.append("Minimum Influence: %d%%" % conditions["min_influence"])
		if conditions.get("max_stress", 0) > 0:
			cond_parts.append("Maximum Stress: %d" % conditions["max_stress"])
		conditions_label.text = "CONDITIONS:\n" + "\n".join(cond_parts)
	else:
		conditions_label.text = "CONDITIONS: None"
	
	# Cost
	var cost = node.get("cost", {})
	if not cost.is_empty():
		var cost_parts = []
		if cost.get("cash", 0) > 0:
			cost_parts.append("Cash: $%.0f" % cost["cash"])
		if cost.get("bandwidth", 0) > 0:
			cost_parts.append("Bandwidth: %.0f" % cost["bandwidth"])
		cost_label.text = "COST:\n" + "\n".join(cost_parts)
	else:
		cost_label.text = "COST: Free"
	
	# Effects
	var effects = node.get("effects", {})
	if not effects.is_empty():
		var effect_parts = []
		for key in effects:
			var formatted_key = key.replace("_", " ").capitalize()
			effect_parts.append("%s: %+.0f" % [formatted_key, effects[key]])
		effects_label.text = "EFFECTS:\n" + "\n".join(effect_parts)
	else:
		effects_label.text = "EFFECTS: None"
	
	# Choices
	var choices = node.get("choices", [])
	if not choices.is_empty():
		choices_label.text = "FOLLOW-UP CHOICES:"
		_create_choice_buttons(choices)
	else:
		choices_label.text = ""

## Show autonomous event details
func _show_autonomous_event_details(node: Dictionary) -> void:
	node_title.text = node.get("title", "Unknown Event")
	node_description.text = node.get("description", "No description available.")
	
	# Trigger conditions
	var trigger = node.get("trigger_conditions", {})
	if not trigger.is_empty():
		var trig_parts = []
		if trigger.get("stress_above", 0) > 0:
			trig_parts.append("Stress > %d" % trigger["stress_above"])
		if trigger.get("strength_below", 0) > 0:
			trig_parts.append("Strength < %d" % trigger["strength_below"])
		if trigger.get("capacity_below", 0) > 0:
			trig_parts.append("Capacity < %d" % trigger["capacity_below"])
		conditions_label.text = "TRIGGERS WHEN:\n" + "\n".join(trig_parts)
	else:
		conditions_label.text = "TRIGGERS: Always available"
	
	cost_label.text = ""
	
	# Auto effects
	var auto_effects = node.get("auto_effects", {})
	if not auto_effects.is_empty():
		var effect_parts = []
		for key in auto_effects:
			var formatted_key = key.replace("_", " ").capitalize()
			effect_parts.append("%s: %+.0f" % [formatted_key, auto_effects[key]])
		effects_label.text = "AUTOMATIC EFFECTS:\n" + "\n".join(effect_parts)
	else:
		effects_label.text = "AUTOMATIC EFFECTS: None"
	
	# Player choices
	var choices = node.get("player_choices", [])
	if not choices.is_empty():
		choices_label.text = "PLAYER RESPONSE OPTIONS:"
		_create_choice_buttons(choices)
	else:
		choices_label.text = "PLAYER RESPONSE: None (event proceeds automatically)"

## Show crisis node details
func _show_crisis_node_details(node: Dictionary) -> void:
	node_title.text = "[CRISIS] " + node.get("title", "Unknown Crisis")
	node_description.text = node.get("description", "No description available.")
	
	# Conditions
	var conditions = node.get("conditions", {})
	if not conditions.is_empty():
		var cond_parts = []
		if conditions.get("tension_above", 0) > 0:
			cond_parts.append("Global Tension > %d" % conditions["tension_above"])
		conditions_label.text = "TRIGGERS WHEN:\n" + "\n".join(cond_parts)
	else:
		conditions_label.text = ""
	
	# Effects
	var effects = node.get("effects", {})
	if not effects.is_empty():
		var effect_parts = []
		for key in effects:
			var formatted_key = key.replace("_", " ").capitalize()
			effect_parts.append("%s: %+.0f" % [formatted_key, effects[key]])
		effects_label.text = "CRISIS EFFECTS:\n" + "\n".join(effect_parts)
	else:
		effects_label.text = ""
	
	cost_label.text = ""
	
	# Choices
	var choices = node.get("choices", [])
	if not choices.is_empty():
		choices_label.text = "CRISIS DECISIONS:"
		_create_choice_buttons(choices, true)
	else:
		choices_label.text = ""

## Show choice details
func _show_choice_details(choice: Dictionary, parent: Dictionary) -> void:
	node_title.text = "Choice: " + choice.get("label", "Unknown")
	node_description.text = "From: " + parent.get("title", "Unknown Event")
	
	conditions_label.text = ""
	
	# Cost
	var cost = choice.get("cost", {})
	if not cost.is_empty():
		var cost_parts = []
		for key in cost:
			cost_parts.append("%s: %.0f" % [key.capitalize(), cost[key]])
		cost_label.text = "CHOICE COST:\n" + "\n".join(cost_parts)
	else:
		cost_label.text = "CHOICE COST: Free"
	
	# Effects
	var effects = choice.get("effects", {})
	if not effects.is_empty():
		var effect_parts = []
		for key in effects:
			var formatted_key = key.replace("_", " ").capitalize()
			effect_parts.append("%s: %+.0f" % [formatted_key, effects[key]])
		effects_label.text = "CHOICE EFFECTS:\n" + "\n".join(effect_parts)
	else:
		effects_label.text = "CHOICE EFFECTS: None"
	
	# Next node
	var next = choice.get("next_node", "")
	if not next.is_empty():
		choices_label.text = "LEADS TO: %s" % next
	else:
		choices_label.text = ""

## Create choice buttons
func _create_choice_buttons(choices: Array, show_next: bool = false) -> void:
	for child in choices_container.get_children():
		child.queue_free()
	
	for choice in choices:
		var btn = Button.new()
		var label = choice.get("label", "Choice")
		
		if show_next:
			var next = choice.get("next_node", "end")
			btn.text = "%s → %s" % [label, next]
		else:
			btn.text = label
		
		btn.tooltip_text = _format_choice_tooltip(choice)
		choices_container.add_child(btn)

## Format choice tooltip
func _format_choice_tooltip(choice: Dictionary) -> String:
	var lines = [choice.get("label", "Choice")]
	
	var cost = choice.get("cost", {})
	if not cost.is_empty():
		lines.append("\nCost:")
		for key in cost:
			lines.append("  %s: %.0f" % [key.capitalize(), cost[key]])
	
	var effects = choice.get("effects", {})
	if not effects.is_empty():
		lines.append("\nEffects:")
		for key in effects:
			lines.append("  %s: %+.0f" % [key.replace("_", " ").capitalize(), effects[key]])
	
	return "\n".join(lines)

## Back button pressed
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
