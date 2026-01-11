extends Control


func _on_button_pressed() -> void:
	$AnimationPlayer.play("fade_out")
