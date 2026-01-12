extends Node
## PlayerState: Deep State Resource Management
## Manages cash, bandwidth, and exposure
## Reference: Logic section 2.4

class_name PlayerState

signal cash_changed(new_cash: float)
signal bandwidth_changed(new_bandwidth: float)
signal exposure_changed(new_exposure: float)

const MAX_BANDWIDTH: float = 100.0
const MAX_EXPOSURE: float = 100.0
const EXPOSURE_DECAY_RATE: float = 0.5  # Decays per day

var cash: float = 1000.0
var bandwidth: float = 50.0
var max_bandwidth: float = MAX_BANDWIDTH

var exposure: float = 0.0
var exposure_decay: float = EXPOSURE_DECAY_RATE

func _ready() -> void:
	if not is_in_group("persistent"):
		add_to_group("persistent")

## Deduct cash and return success
func spend_cash(amount: float) -> bool:
	if cash >= amount:
		cash -= amount
		cash_changed.emit(cash)
		return true
	return false

## Add cash
func gain_cash(amount: float) -> void:
	cash += amount
	cash_changed.emit(cash)

## Deduct bandwidth and return success
func spend_bandwidth(amount: float) -> bool:
	if bandwidth >= amount:
		bandwidth -= amount
		bandwidth_changed.emit(bandwidth)
		return true
	return false

## Add bandwidth
func gain_bandwidth(amount: float) -> void:
	bandwidth = min(bandwidth + amount, max_bandwidth)
	bandwidth_changed.emit(bandwidth)

## Increase exposure (from actions)
func increase_exposure(amount: float) -> void:
	exposure = min(exposure + amount, MAX_EXPOSURE)
	exposure_changed.emit(exposure)

## Apply daily exposure decay
func decay_exposure(day_count: int = 1) -> void:
	exposure = max(exposure - (exposure_decay * day_count), 0.0)
	exposure_changed.emit(exposure)

## Get current relevance score (used in crisis evaluation)
## Note: Full calculation happens in crisis system
func get_exposure_factor() -> float:
	return exposure / MAX_EXPOSURE

## Serialize state for saving
func to_dict() -> Dictionary:
	return {
		"cash": cash,
		"bandwidth": bandwidth,
		"exposure": exposure
	}

## Deserialize state from saving
func from_dict(data: Dictionary) -> void:
	cash = data.get("cash", 1000.0)
	bandwidth = data.get("bandwidth", 50.0)
	exposure = data.get("exposure", 0.0)
	cash_changed.emit(cash)
	bandwidth_changed.emit(bandwidth)
	exposure_changed.emit(exposure)
