extends PanelContainer
## InstitutionCard: Visual representation of an institution
## Displays stats and provides action buttons

class_name InstitutionCard

var institution: Institution
var event_manager: EventManager
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
func set_institution(inst: Institution, event_mgr: EventManager) -> void:
	institution = inst
	event_manager = event_mgr
	
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
	
	var available_actions = event_manager.get_available_actions(institution)
	
	for action_name in available_actions:
		var button = Button.new()
		button.text = action_name.to_upper()
		button.pressed.connect(_on_action_pressed.bindv([action_name]))
		actions_container.add_child(button)

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

## Handle action button press
func _on_action_pressed(action_name: String) -> void:
	# TODO: Execute action on institution
	print("Action pressed: %s on %s" % [action_name, institution.institution_name])

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
