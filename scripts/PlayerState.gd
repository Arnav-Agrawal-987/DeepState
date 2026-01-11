extends Node
class_name PlayerState

# Basic player resources
var cash: float = 1000.0
var bandwidth: float = 10.0
var exposure: float = 0.0

func adjust_cash(amount: float) -> void:
	cash += amount

func adjust_bandwidth(delta: float) -> void:
	bandwidth += delta

func adjust_exposure(delta: float) -> void:
	exposure += delta

func to_dict() -> Dictionary:
	return {"cash": cash, "bandwidth": bandwidth, "exposure": exposure}
