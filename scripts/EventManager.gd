extends Node
class_name EventManager

# Simple event manager that queues minor events and runs major-event handlers.
var minor_queue: Array = []

func queue_minor(event) -> void:
	minor_queue.append(event)

func resolve_minor_events(game_state: Node) -> void:
	# Each event is expected to be a callable or a Dictionary describing effects.
	for e in minor_queue:
		if typeof(e) == TYPE_CALLABLE:
			e.call_func(game_state)
		elif typeof(e) == TYPE_DICTIONARY and e.has("apply"):
			var fn = e["apply"]
			if typeof(fn) == TYPE_CALLABLE:
				fn.call_func(game_state)
	minor_queue.clear()

func handle_major_event(game_state: Node) -> bool:
	# Placeholder major-event resolution.
	# Returns `true` if a loss condition was declared by resolution.
	# Default: no loss.
	return false
