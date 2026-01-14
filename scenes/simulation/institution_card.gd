extends PanelContainer
## InstitutionCard: Visual representation of an institution
## Displays stats and provides action buttons

class_name InstitutionCard

var institution: Institution
var event_manager: EventManager
var institution_config: InstitutionConfig
var available_actions: Array = []  # Stores action nodes from config
var _ready_called = false

@onready var inst_name = $MarginContainer/VBoxContainer/HeaderHBox/InstitutionName
@onready var inst_type = $MarginContainer/VBoxContainer/HeaderHBox/InstitutionType
@onready var capacity_bar = $MarginContainer/VBoxContainer/StatsContainer/CapacityBar
@onready var strength_bar = $MarginContainer/VBoxContainer/StatsContainer/StrengthBar
@onready var stress_bar = $MarginContainer/VBoxContainer/StatsContainer/StressBar
@onready var influence_bar = $MarginContainer/VBoxContainer/StatsContainer/InfluenceBar
@onready var actions_container = $MarginContainer/VBoxContainer/ActionsHBox

func _ready() -> void:
	_ready_called = true
	# If institution was already set, update display now
	if institution:
		update_display()

## Initialize card with institution data
func set_institution(inst: Institution, event_mgr: EventManager, config: InstitutionConfig = null) -> void:
	institution = inst
	event_manager = event_mgr
	institution_config = config
	
	# Only update display if _ready has been called
	if _ready_called:
		update_display()
		# Connect to institution signals
		institution.stress_changed.connect(_on_stress_changed)
		institution.capacity_changed.connect(_on_capacity_changed)
		institution.strength_changed.connect(_on_strength_changed)
		institution.influence_changed.connect(_on_influence_changed)
	else:
		# Defer connection until _ready is called
		call_deferred("_deferred_setup")

## Update all displayed values
func update_display() -> void:
	if not institution or not _ready_called:
		return
	
	if inst_name:
		inst_name.text = institution.institution_name
	if inst_type:
		inst_type.text = institution.get_type_string()
	
	if capacity_bar:
		capacity_bar.value = institution.capacity
	if strength_bar:
		strength_bar.value = institution.strength
	if stress_bar:
		stress_bar.value = institution.stress
	if influence_bar:
		influence_bar.value = institution.player_influence
	
	update_actions()
	apply_stress_coloring()

## Deferred setup called after _ready
func _deferred_setup() -> void:
	if institution:
		update_display()
		institution.stress_changed.connect(_on_stress_changed)
		institution.capacity_changed.connect(_on_capacity_changed)
		institution.strength_changed.connect(_on_strength_changed)
		institution.influence_changed.connect(_on_influence_changed)

## Update available action buttons
func update_actions() -> void:
	if not institution or not event_manager or not actions_container:
		return
	
	# Clear existing buttons
	for child in actions_container.get_children():
		child.queue_free()
	
	# Get available actions from current stress event (if any)
	available_actions = []
	if institution_config and institution.stress >= institution.strength:
		var stress_event = event_manager.get_current_stress_event(institution, institution_config)
		if not stress_event.is_empty():
			available_actions = stress_event.get("choices", [])
	
	for action_node in available_actions:
		var button = Button.new()
		var title = action_node.get("title", "Unknown")
		var cost = action_node.get("cost", {})
		
		# Format button text with cost hint
		var cost_text = _format_cost(cost)
		button.text = title if cost_text.is_empty() else "%s (%s)" % [title, cost_text]
		button.tooltip_text = _format_tooltip(action_node)
		
		# Connect with action node
		button.pressed.connect(_on_action_node_pressed.bind(action_node))
		actions_container.add_child(button)

## Format cost for button display (cost is an int representing bandwidth)
func _format_cost(cost) -> String:
	if cost is int and cost > 0:
		return "%d BW" % cost
	elif cost is Dictionary:
		var parts: Array[String] = []
		if cost.get("cash", 0.0) > 0:
			parts.append("$%.0f" % cost["cash"])
		if cost.get("bandwidth", 0.0) > 0:
			parts.append("%.0f BW" % cost["bandwidth"])
		return ", ".join(parts)
	return ""

## Format tooltip with full action details
func _format_tooltip(action_node: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(action_node.get("title", "Unknown Action"))
	
	var desc = action_node.get("description", "")
	if not desc.is_empty():
		lines.append(desc)
	
	# Cost section (cost is an int representing bandwidth)
	var cost = action_node.get("cost", 0)
	if cost is int and cost > 0:
		lines.append("")
		lines.append("== Cost ==")
		lines.append("  Bandwidth: %d" % cost)
	elif cost is Dictionary and not cost.is_empty():
		lines.append("")
		lines.append("== Cost ==")
		if cost.get("cash", 0.0) > 0:
			lines.append("  Cash: $%.0f" % cost["cash"])
		if cost.get("bandwidth", 0.0) > 0:
			lines.append("  Bandwidth: %.0f" % cost["bandwidth"])
	
	# Effects section
	var effects = action_node.get("effects", {})
	if not effects.is_empty():
		lines.append("")
		lines.append("== Effects ==")
		for key in effects:
			lines.append("  %s: %+.0f" % [key.replace("_", " ").capitalize(), effects[key]])
	
	return "\n".join(lines)

## Apply color coding based on stress level
func apply_stress_coloring() -> void:
	if not institution or not stress_bar:
		return
	
	var stress_ratio = institution.stress / institution.strength
	
	if stress_ratio < 0.5:
		stress_bar.modulate = Color.GREEN
	elif stress_ratio < 0.8:
		stress_bar.modulate = Color.YELLOW
	else:
		stress_bar.modulate = Color.RED

## Handle action button press (data-driven)
func _on_action_node_pressed(action_node: Dictionary) -> void:
	if not institution or not event_manager:
		return
	
	var success = event_manager.execute_player_action(action_node, institution)
	if success:
		update_display()
		# Notify parent to update dashboard and refresh event tree
		get_tree().call_group("simulation_root", "_update_dashboard")
		get_tree().call_group("simulation_root", "_refresh_event_tree")
	else:
		# Visual feedback for failure (e.g., can't afford)
		modulate = Color.RED
		var tween = create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.3)

## Stress changed
func _on_stress_changed(new_stress: float) -> void:
	stress_bar.value = new_stress
	apply_stress_coloring()

## Capacity changed
func _on_capacity_changed(new_capacity: float) -> void:
	capacity_bar.value = new_capacity

## Strength changed
func _on_strength_changed(new_strength: float) -> void:
	strength_bar.value = new_strength

## Influence changed
func _on_influence_changed(new_influence: float) -> void:
	influence_bar.value = new_influence
	update_actions()
