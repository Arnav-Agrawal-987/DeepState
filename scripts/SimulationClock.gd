extends Node
class_name SimulationClock

signal day_started(day)
signal day_ended(day)

var current_day := 0

func tick_day(game_state: Node) -> void:
	# Advance the authoritative day counter and run the deterministic pipeline.
	current_day += 1
	emit_signal("day_started", current_day)

	# (1) Institutions auto-update
	if game_state and game_state.has_method("institutions_auto_update"):
		game_state.institutions_auto_update()

	# (2) Resolve all minor events
	if game_state and game_state.has_method("resolve_minor_events"):
		game_state.resolve_minor_events()

	# (3) Update tension
	if game_state and game_state.has_method("update_tension"):
		game_state.update_tension()

	# (4) Major event (if any)
	var loss_declared := false
	if game_state and game_state.tension_manager and game_state.tension_manager.has_method("is_threshold_crossed"):
		if game_state.tension_manager.is_threshold_crossed():
			if game_state.has_method("handle_major_event"):
				loss_declared = game_state.handle_major_event()

	if loss_declared:
		push_error("MajorEvent declared loss on day %d" % current_day)
		emit_signal("day_ended", current_day)
		return

	# (5) Player turn
	if game_state and game_state.has_method("player_turn"):
		game_state.player_turn()

	emit_signal("day_ended", current_day)
