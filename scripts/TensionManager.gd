extends Node
class_name TensionManager

var tension: float = 0.0
var threshold: float = 100.0

func add(amount: float) -> void:
	tension += amount

func is_threshold_crossed() -> bool:
	return tension >= threshold

func reset_partial() -> void:
	tension *= 0.5

func get_tension() -> float:
	return tension
