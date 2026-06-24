extends AnimatableBody2D

@export var speed: float = 100.0

var original_position: Vector2
var target_position: Vector2
var moving_to_target: bool = false

@onready var marker: Marker2D = $Marker2D

func _ready() -> void:
	add_to_group("moving_platforms")
	original_position = global_position
	if marker:
		target_position = marker.global_position
	else:
		target_position = original_position

func _physics_process(delta: float) -> void:
	# Only move if the game is not paused
	if GameManager.is_game_paused:
		return

	var dest = target_position if moving_to_target else original_position
	if global_position.distance_to(dest) > 0.1:
		global_position = global_position.move_toward(dest, speed * delta)


func _update_movement_state() -> void:
	var any_pressed = false
	for incoming in get_incoming_connections():
		var sender = incoming.signal.get_object()
		if sender and sender.has_signal("pressed_state_changed"):
			if sender.get("is_pressed") == true:
				any_pressed = true
				break
	moving_to_target = any_pressed


func _on_pressure_plate_pressed_state_changed(is_pressed: bool) -> void:
	_update_movement_state()


func _on_pressure_plate_3_pressed_state_changed(is_pressed: bool) -> void:
	_update_movement_state()


func _on_pressure_plate_4_pressed_state_changed(is_pressed: bool) -> void:
	_update_movement_state()
