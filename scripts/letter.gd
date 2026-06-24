extends CharacterBody2D

@export_range(0.2, 5.0, 0.1) var mass: float = 1.0
@export_range(0.0, 1.2, 0.05) var bounciness: float = 0.6

enum State { IDLE, DRAGGING, CARRYING }
var state: State = State.IDLE

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var teleport_cooldown: float = 0.0
var carried_by_id: int = 0
var drag_offset_x: float = 24.0

@onready var sprite: Sprite2D = $Sprite2D

func is_letter() -> bool:
	return true

func _ready() -> void:
	# Add to group so they can be easily found if needed
	add_to_group("letters")
	
	# Scale the letter slightly based on mass
	scale = Vector2.ONE * (0.8 + mass * 0.2)
	
	# Only server/host selects the texture and broadcasts it
	var is_auth = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_auth:
		_load_random_texture()

func _load_random_texture() -> void:
	var files = []
	
	# Load from letters
	var dir_letters = DirAccess.open("res://assets/letters/")
	if dir_letters:
		dir_letters.list_dir_begin()
		var file_name = dir_letters.get_next()
		while file_name != "":
			if not dir_letters.current_is_dir() and file_name.ends_with(".png"):
				files.append("res://assets/letters/" + file_name)
			file_name = dir_letters.get_next()
			
	# Load from symbols
	var dir_symbols = DirAccess.open("res://assets/symbols/")
	if dir_symbols:
		dir_symbols.list_dir_begin()
		var file_name = dir_symbols.get_next()
		while file_name != "":
			if not dir_symbols.current_is_dir() and file_name.ends_with(".png"):
				files.append("res://assets/symbols/" + file_name)
			file_name = dir_symbols.get_next()
			
	if files.size() > 0:
		var rand_idx = randi() % files.size()
		var texture_path = files[rand_idx]
		_set_texture(texture_path)
		
		# Sync to clients
		if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			sync_texture.rpc(texture_path)

func _set_texture(path: String) -> void:
	var tex = load(path)
	if tex and sprite:
		sprite.texture = tex

@rpc("any_peer", "call_local", "reliable")
func sync_texture(path: String) -> void:
	_set_texture(path)

func _physics_process(delta: float) -> void:
	# Cooldown timer
	if teleport_cooldown > 0.0:
		teleport_cooldown -= delta

	# Check pause state
	if GameManager.is_game_paused:
		return

	var local_id = _get_local_player_id()
	
	if state != State.IDLE:
		# Follow the player carrying it on all clients
		if carried_by_id != 0:
			var player = _get_player_by_id(carried_by_id)
			if is_instance_valid(player):
				if state == State.DRAGGING:
					var distance = global_position.distance_to(player.global_position)
					if distance > 400.0: # Failsafe disconnect if pulled too far
						_stop_carrying(player, Vector2.ZERO)
						return
						
					var shape_height = 8.0 * scale.y
					var target_pos = player.global_position + Vector2(drag_offset_x, -shape_height)
					
					if carried_by_id == local_id:
						# Physics-based dragging with forces to avoid snapping
						var diff = target_pos - global_position
						var k = minf(5000.0 / mass, 1000.0) # Cap stiffness to maintain Euler integration stability
						var damp = 2.0 * sqrt(k)            # Mathematically perfect critical damping
						
						var acc = Vector2.ZERO
						# Spring force and relative damping to match player's velocity
						acc.x = k * diff.x - damp * (velocity.x - player.velocity.x)
						acc.y = k * diff.y - damp * (velocity.y - player.velocity.y)
						
						# Input-based force to help push/pull based on player's movement direction
						var input_dir = Input.get_axis("move_left", "move_right")
						if input_dir != 0:
							acc.x += input_dir * (650.0 / mass)
							
						velocity += acc * delta
					else:
						# For remote players, keep position near the target to prevent drifting
						var diff = target_pos - global_position
						if diff.length() > 400.0: # Failsafe sync snap
							global_position = target_pos
					
					move_and_slide()
					rotation = 0.0
				elif state == State.CARRYING:
					# Directly set position above player head, scaling offset so it doesn't clip
					global_position = player.global_position + Vector2(0, -56 - 12.0 * scale.y)
					rotation = 0.0
					
				# Send position update unreliably to correct any drift on other peers
				if carried_by_id == local_id:
					if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
						sync_letter_physics.rpc(global_position, velocity, rotation)
	else:
		# Physics state (not carried)
		# Server (or singleplayer host) runs physics authority
		var is_auth = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
		if is_auth:
			# Gravity
			velocity.y += gravity * delta
			
			# Move and collide to bounce
			var collision = move_and_collide(velocity * delta)
			var on_floor = false
			if collision:
				var normal = collision.get_normal()
				velocity = velocity.bounce(normal) * bounciness
				if normal.y < -0.7:
					on_floor = true
					if abs(velocity.y) < 80.0:
						velocity.y = 0.0
				
				# Rotate slightly on bounce
				if not on_floor or abs(velocity.x) > 10.0:
					rotation += velocity.x * 0.005
			
			if on_floor:
				velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
				rotation = rotate_toward(rotation, 0.0, 6.0 * delta)
				
			# Send updated physics state to clients unreliably
			if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				sync_letter_physics.rpc(global_position, velocity, rotation)
		else:
			# Client: just move passively based on velocity or wait for position updates
			var collision = move_and_collide(velocity * delta)
			var on_floor = false
			if collision:
				var normal = collision.get_normal()
				velocity = velocity.bounce(normal) * bounciness
				if normal.y < -0.7:
					on_floor = true
					if abs(velocity.y) < 80.0:
						velocity.y = 0.0
				
				if not on_floor or abs(velocity.x) > 10.0:
					rotation += velocity.x * 0.005
					
			if on_floor:
				velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
				rotation = rotate_toward(rotation, 0.0, 6.0 * delta)

func start_dragging_by_player(player_node: CharacterBody2D) -> void:
	var local_id = _get_local_player_id()
	_start_dragging(player_node, local_id)

func start_carrying_by_player(player_node: CharacterBody2D) -> void:
	var local_id = _get_local_player_id()
	_start_carrying(player_node, local_id)

func drop_letter() -> void:
	var local_player = _get_local_player()
	if is_instance_valid(local_player):
		_stop_carrying(local_player, Vector2.ZERO)

func throw_letter() -> void:
	var local_player = _get_local_player()
	if is_instance_valid(local_player):
		var facing_dir = 1.0 if local_player.facing_right else -1.0
		var base_impulse = Vector2(350.0 * facing_dir, -250.0)
		var total_impulse = base_impulse + local_player.velocity
		var throw_vel = total_impulse / mass
		_stop_carrying(local_player, throw_vel)

func _apply_carry_to_player(player_node: CharacterBody2D, enable: bool) -> void:
	if is_instance_valid(player_node):
		if enable:
			player_node.is_carrying_letter = true
			player_node.is_dragging_letter = (state == State.DRAGGING)
			player_node.carried_letter_mass = mass
			player_node.set("active_letter_node", self)
			if state == State.DRAGGING:
				player_node.set("dragged_letter_node", self)
			else:
				player_node.set("dragged_letter_node", null)
		else:
			player_node.is_carrying_letter = false
			player_node.is_dragging_letter = false
			player_node.carried_letter_mass = 1.0
			player_node.set("dragged_letter_node", null)
			player_node.set("active_letter_node", null)

func _start_dragging(player_node: CharacterBody2D, player_id: int) -> void:
	# Determine offset based on grab side
	var diff_x = global_position.x - player_node.global_position.x
	var grab_side = 1.0 if diff_x >= 0.0 else -1.0
	var offset = grab_side * 24.0
	
	if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_letter_state.rpc(global_position, Vector2.ZERO, rotation, player_id, State.DRAGGING, offset)
	else:
		sync_letter_state(global_position, Vector2.ZERO, rotation, player_id, State.DRAGGING, offset)

func _start_carrying(player_node: CharacterBody2D, player_id: int) -> void:
	if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_letter_state.rpc(global_position, Vector2.ZERO, rotation, player_id, State.CARRYING, drag_offset_x)
	else:
		sync_letter_state(global_position, Vector2.ZERO, rotation, player_id, State.CARRYING, drag_offset_x)

func _stop_carrying(player_node: CharacterBody2D, exit_velocity: Vector2) -> void:
	if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_letter_state.rpc(global_position, exit_velocity, rotation, 0, State.IDLE, drag_offset_x)
	else:
		sync_letter_state(global_position, exit_velocity, rotation, 0, State.IDLE, drag_offset_x)

@rpc("any_peer", "call_local", "reliable")
func sync_letter_state(pos: Vector2, vel: Vector2, rot: float, carried_by: int, new_state: int, drag_offset: float = 24.0) -> void:
	var prev_carried_by = carried_by_id
	
	global_position = pos
	velocity = vel
	rotation = rot
	carried_by_id = carried_by
	state = new_state
	drag_offset_x = drag_offset
	
	# Update player carry variables on clients
	if prev_carried_by != 0 and prev_carried_by != carried_by_id:
		var prev_p = _get_player_by_id(prev_carried_by)
		_apply_carry_to_player(prev_p, false)
		if is_instance_valid(prev_p):
			remove_collision_exception_with(prev_p)
		
	if carried_by_id != 0:
		var p = _get_player_by_id(carried_by_id)
		_apply_carry_to_player(p, true)
		if is_instance_valid(p):
			if state == State.CARRYING:
				add_collision_exception_with(p)
			else:
				remove_collision_exception_with(p)



@rpc("any_peer", "unreliable")
func sync_letter_physics(pos: Vector2, vel: Vector2, rot: float) -> void:
	var local_id = _get_local_player_id()
	if carried_by_id != 0 and carried_by_id == local_id:
		return
		
	var is_auth = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if carried_by_id == 0 and is_auth:
		return
		
	global_position = pos
	velocity = vel
	rotation = rot


func _get_local_player() -> CharacterBody2D:
	if not is_inside_tree() or get_viewport() == null:
		return null
	var tree = get_tree()
	if not tree:
		return null
	var level = tree.current_scene
	if level:
		if level.has_node("Player1") and level.get_node("Player1").is_local():
			return level.get_node("Player1")
		if level.has_node("Player2") and level.get_node("Player2").is_local():
			return level.get_node("Player2")
	return null

func _get_local_player_id() -> int:
	var player_node = _get_local_player()
	if player_node:
		return player_node.player_id
	return 1

func _get_player_by_id(id: int) -> CharacterBody2D:
	if not is_inside_tree() or get_viewport() == null:
		return null
	var tree = get_tree()
	if not tree:
		return null
	var level = tree.current_scene
	if level:
		if id == 1 and level.has_node("Player1"):
			return level.get_node("Player1")
		if id == 2 and level.has_node("Player2"):
			return level.get_node("Player2")
	return null
