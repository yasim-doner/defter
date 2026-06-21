extends Area2D

var player: CharacterBody2D = null
var spawner: Area2D = null
var parachute_duration: float = 10.0
var active_duration: float = 0.0
var is_active: bool = false

# Movement variables when not attached
var velocity: Vector2 = Vector2.ZERO
var parachute_gravity: float = 800.0
var lifetime: float = 1.5
var reattach_cooldown: float = 0.0

# Ride variables removed

@onready var sprite: Sprite2D = $Sprite2D
@onready var canopy_collision: CollisionPolygon2D = $CollisionPolygon2D
@onready var marker: Marker2D = $Marker2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_catch_area_body_entered)

func activate() -> void:
	is_active = true
	active_duration = parachute_duration
	velocity = Vector2.ZERO
	
	sprite.visible = true
	canopy_collision.disabled = false
	
	if is_instance_valid(player):
		if "is_parachute_active" in player:
			player.is_parachute_active = true
			player.active_parachute_node = self

func _physics_process(delta: float) -> void:
	if is_active and is_instance_valid(player):
		# Count down duration
		active_duration -= delta
		if active_duration <= 0.0:
			destroy_parachute()
			return
			
		# Align Marker2D to player's center Vector2(0, -21)
		var player_center = player.global_position + Vector2(0, -21)
		global_position = player_center - marker.position
		
		# Check if the player pressed E again to shoot
		if player.is_local() and Input.is_action_just_pressed("interact"):
			shoot_parachute()
			return
	else:
		# Not attached: check if inside any active wind drafts
		var has_wind = false
		var wind_push = Vector2.ZERO
		for area in get_overlapping_areas():
			if is_instance_valid(area) and (area.has_method("get_wind_direction_vector") or "is_on" in area):
				if area.get("is_on") == true:
					has_wind = true
					var wind_dir = area.get_wind_direction_vector()
					var wind_speed = area.speed
					wind_push += wind_dir * wind_speed
					
		if has_wind:
			var wind_accel = 2000.0
			velocity = velocity.move_toward(wind_push, wind_accel * delta)
		else:
			# Move independently under gravity
			velocity.y += parachute_gravity * delta
			
		global_position += velocity * delta
		lifetime -= delta
		
		if reattach_cooldown > 0.0:
			reattach_cooldown -= delta
		else:
			# Check if a player is already overlapping the catch area when cooldown expires
			var area = get_node_or_null("Area2D")
			if area:
				for body in area.get_overlapping_bodies():
					if body.name.begins_with("Player"):
						var target_player = body
						if target_player.has_method("is_local") and target_player.is_local():
							if not target_player.is_parachute_active:
								target_player.sync_catch_parachute.rpc(get_path())
								break
		
		if lifetime <= 0.0:
			queue_free()

	# No scheduled ride handling

func is_in_active_wind_draft() -> bool:
	if is_active and is_instance_valid(player):
		if "active_wind_drafts" in player:
			for draft in player.active_wind_drafts:
				if is_instance_valid(draft) and draft.get("is_on") == true:
					return true
	for area in get_overlapping_areas():
		if is_instance_valid(area) and (area.has_method("get_wind_direction_vector") or "is_on" in area):
			if area.get("is_on") == true:
				return true
	return false

func destroy_parachute() -> void:
	# Stop player glide state
	if is_instance_valid(player):
		if player.is_local():
			player.sync_deactivate_parachute_path.rpc()
			player.is_parachute_broken = true
		else:
			# For remote instances, just clean up state locally
			if "is_parachute_active" in player:
				player.is_parachute_active = false
				player.active_parachute_node = null
				
	# Immediately get killed
	queue_free()

func shoot_parachute() -> void:
	if not is_active:
		return
		
	if is_instance_valid(player):
		var launch_vel = player.velocity
		launch_vel.y = -350.0 # throw it upward
		if abs(player.velocity.x) < 10.0:
			launch_vel.x = 40.0 * (-1.0 if randf() < 0.5 else 1.0)
		else:
			launch_vel.x = player.velocity.x * 1.3
		
		if player.is_local():
			player.sync_shoot_parachute.rpc(launch_vel)

func _on_body_entered(body: Node2D) -> void:
	if is_active:
		if body == player:
			return
			
		if body is TileMapLayer:
			destroy_parachute()
			return
			
		if body.has_method("die_by_bullet") or body.name.begins_with("Enemy") or body.name.begins_with("SpawnerEnemy"):
			# Ricochet the enemy off the parachute instead of killing them
			var bounce_dir = (body.global_position - global_position).normalized()
			if bounce_dir.y > -0.2:
				bounce_dir.y = -0.5 # Ensure a good upward bounce
			bounce_dir = bounce_dir.normalized()
			body.velocity = bounce_dir * 450.0
			if "direction" in body:
				body.direction = sign(body.velocity.x) if abs(body.velocity.x) > 10.0 else body.direction
			if "rotation_speed" in body:
				body.rotation_speed = randf_range(4.0, 8.0) * (-1.0 if body.velocity.x < 0.0 else 1.0)
				
			destroy_parachute()
			return
			
		if body.name.begins_with("Player"):
			var other_player = body
			if is_instance_valid(player) and other_player.has_method("is_local") and other_player.is_local():
				var relative_y = other_player.global_position.y - player.global_position.y
				if relative_y < -60.0 and other_player.velocity.y >= -150.0:
					var e = 1.4
					var v1 = other_player.velocity.y
					var v2 = player.velocity.y
					var new_v1 = (v1 + v2 - e * (v1 - v2)) / 2.0
					if new_v1 > -510.0:
						new_v1 = -510.0
					other_player.velocity.y = new_v1
				# Destroy the parachute via RPC since we are the local player colliding with it unless inside wind draft
				if not is_in_active_wind_draft():
					player.sync_deactivate_parachute.rpc()
			elif is_instance_valid(player) and player.is_local():
				# We are the owner of the parachute, and a remote player collided with it
				var relative_y = other_player.global_position.y - player.global_position.y
				if relative_y < -60.0 and other_player.velocity.y >= -150.0:
					var e = 1.4
					var v1 = other_player.velocity.y
					var v2 = player.velocity.y
					var new_v1 = (v1 + v2 - e * (v1 - v2)) / 2.0
					var new_v2 = (v1 + v2 + e * (v1 - v2)) / 2.0
					if new_v1 > -510.0:
						var diff = -510.0 - new_v1
						new_v2 -= diff
					player.velocity.y = new_v2
				# Destroy the parachute unless inside wind draft
				if not is_in_active_wind_draft():
					destroy_parachute()
			return
	else:
		# Shot/independent parachute collision
		if body.name.begins_with("Player"):
			var other_player = body
			if other_player.has_method("is_local") and other_player.is_local():
				if reattach_cooldown > 0.0:
					var relative_y = other_player.global_position.y - global_position.y
					if relative_y < -60.0 and other_player.velocity.y >= -150.0:
						var e = 1.4
						var v1 = other_player.velocity.y
						var v2 = velocity.y
						var new_v1 = (v1 + v2 - e * (v1 - v2)) / 2.0
						var new_v2 = (v1 + v2 + e * (v1 - v2)) / 2.0
						if new_v1 > -510.0:
							var diff = -510.0 - new_v1
							new_v1 = -510.0
							new_v2 -= diff
						other_player.velocity.y = new_v1
						velocity.y = new_v2
					if not is_in_active_wind_draft():
						queue_free()
			elif is_instance_valid(player) and player.is_local():
				if reattach_cooldown > 0.0:
					var relative_y = other_player.global_position.y - global_position.y
					if relative_y < -60.0 and other_player.velocity.y >= -150.0:
						var e = 1.4
						var v1 = other_player.velocity.y
						var v2 = velocity.y
						var new_v1 = (v1 + v2 - e * (v1 - v2)) / 2.0
						var new_v2 = (v1 + v2 + e * (v1 - v2)) / 2.0
						if new_v1 > -510.0:
							var diff = -510.0 - new_v1
							new_v2 -= diff
						velocity.y = new_v2
					if not is_in_active_wind_draft():
						queue_free()
			return
			
		if body is TileMapLayer:
			queue_free()
			return
			
		if body.has_method("die_by_bullet") or body.name.begins_with("Enemy") or body.name.begins_with("SpawnerEnemy"):
			# Ricochet the enemy off the parachute instead of killing them
			var bounce_dir = (body.global_position - global_position).normalized()
			if bounce_dir.y > -0.2:
				bounce_dir.y = -0.5
			bounce_dir = bounce_dir.normalized()
			body.velocity = bounce_dir * 450.0
			if "direction" in body:
				body.direction = sign(body.velocity.x) if abs(body.velocity.x) > 10.0 else body.direction
			if "rotation_speed" in body:
				body.rotation_speed = randf_range(4.0, 8.0) * (-1.0 if body.velocity.x < 0.0 else 1.0)
				
			queue_free()
			return

func _on_catch_area_body_entered(body: Node2D) -> void:
	if not is_active and reattach_cooldown <= 0.0:
		# Parachute is in not attached state
		if body.name.begins_with("Player"):
			var target_player = body
			if target_player.has_method("is_local") and target_player.is_local():
				# Local player catches the parachute
				if not target_player.is_parachute_active:
					target_player.sync_catch_parachute.rpc(get_path())
