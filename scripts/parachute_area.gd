extends Area2D

@export var parachute_duration: float = 10.0

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			body.is_near_parachute_area = true
			body.active_parachute_area = self

func _on_body_exited(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			body.is_near_parachute_area = false
			if body.active_parachute_area == self:
				body.active_parachute_area = null
