extends Area2D
# Death zone: enemies that enter are removed; players that enter respawn.
# Attach to an Area2D trigger placed in the level (with a CollisionShape2D).
# Works on every peer — each side frees its own copy of an entering body.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("die_by_bullet"):
		# An enemy fell in — delete it.
		body.queue_free()
	elif body.has_method("die"):
		# A player fell in — respawn (die() guards is_local internally).
		body.die()
