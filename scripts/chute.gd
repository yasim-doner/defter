extends Area2D

@export var chute_id: String = ""
@export var launch_speed: float = 500.0

func _ready() -> void:
	# Add to group so they can find each other
	add_to_group("chutes")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			# Check cooldown on the player to avoid teleport loops
			if "teleport_cooldown" in body and body.teleport_cooldown > 0.0:
				return
				
			# Find the matching chute
			var destination_chute = _find_matching_chute()
			if destination_chute:
				# Teleport the player
				body.global_position = destination_chute.global_position
				
				# Reset camera smoothing so the camera teleports instantly
				if body.has_node("Camera2D"):
					var camera = body.get_node("Camera2D")
					if camera is Camera2D:
						camera.reset_smoothing()
				
				# Set player velocity based on destination chute's rotation
				var exit_dir = Vector2.RIGHT.rotated(destination_chute.global_rotation)
				body.velocity = exit_dir * destination_chute.launch_speed
				
				# Set teleport cooldown on player to prevent instant back-teleportation
				if "teleport_cooldown" in body:
					body.teleport_cooldown = 0.3
	elif body.has_method("is_letter"):
		if body.get("state") == 0: # State.IDLE
			var is_auth = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
			if is_auth:
				if "teleport_cooldown" in body and body.teleport_cooldown > 0.0:
					return
				var destination_chute = _find_matching_chute()
				if destination_chute:
					body.global_position = destination_chute.global_position
					var exit_dir = Vector2.RIGHT.rotated(destination_chute.global_rotation)
					body.velocity = exit_dir * destination_chute.launch_speed
					if "teleport_cooldown" in body:
						body.teleport_cooldown = 0.3


func _find_matching_chute() -> Area2D:
	if chute_id == "":
		return null
		
	var chutes = get_tree().get_nodes_in_group("chutes")
	for chute in chutes:
		if chute != self and chute.get("chute_id") == chute_id:
			return chute
			
	return null
