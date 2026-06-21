extends CharacterBody2D

@export var patrol_range: float = 65.0
@export var speed: float = 60.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var direction: float = -1.0
var spawn_x: float
var spawn_pos: Vector2
var wiggle_seed: float = 0.0
var active_wind_drafts: Array = []
var rotation_speed: float = 0.0
var visual_rotation: float = 0.0

func _ready() -> void:
	platform_floor_layers = 0
	spawn_pos = position
	spawn_x = position.x
	
	# 1. Physics collision shape
	var col_shape: CollisionShape2D
	if has_node("CollisionShape2D"):
		col_shape = get_node("CollisionShape2D")
	else:
		col_shape = CollisionShape2D.new()
		col_shape.name = "CollisionShape2D"
		add_child(col_shape)
	
	var shape = CircleShape2D.new()
	shape.radius = 12.0
	col_shape.shape = shape
	col_shape.position = Vector2(0, -12)
	
	# 2. Hitbox Area2D to damage the player
	var hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	add_child(hitbox)
	
	var hitbox_col = CollisionShape2D.new()
	hitbox_col.name = "CollisionShape2D"
	hitbox.add_child(hitbox_col)
	
	var hitbox_shape = CircleShape2D.new()
	hitbox_shape.radius = 14.0 # Slightly wider than physical collision
	hitbox_col.shape = hitbox_shape
	hitbox_col.position = Vector2(0, -12)
	
	hitbox.body_entered.connect(_on_hitbox_body_entered)

@rpc("any_peer", "unreliable")
func sync_enemy_state(pos: Vector2, dir: float, rot: float) -> void:
	if not is_multiplayer_authority_local():
		position = pos
		direction = dir
		visual_rotation = rot

func is_multiplayer_authority_local() -> bool:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return multiplayer.is_server()

func _physics_process(delta: float) -> void:
	# Check pause state
	var main = get_tree().current_scene
	if main and main.get("is_game_paused") == true:
		velocity = Vector2.ZERO
		return

	if not is_multiplayer_authority_local():
		# Clients only update wiggle animation
		wiggle_seed += delta
		queue_redraw()
		return

	var is_gravity_disabled = false
	var wind_push = Vector2.ZERO
	var has_wind = false
	
	var valid_drafts = []
	for draft in active_wind_drafts:
		if is_instance_valid(draft) and draft.has_method("get_wind_direction_vector"):
			valid_drafts.append(draft)
			if draft.get("is_on") == true:
				is_gravity_disabled = true
				has_wind = true
				var wind_dir = draft.get_wind_direction_vector()
				var wind_speed = draft.speed
				wind_push += wind_dir * wind_speed
	active_wind_drafts = valid_drafts

	if not is_on_floor():
		if not is_gravity_disabled:
			velocity.y += gravity * delta
			if velocity.y > 700.0:
				velocity.y = 700.0
		
	# Apply wind draft velocity
	if has_wind:
		if abs(wind_push.x) > 0.01:
			velocity.x = wind_push.x
		if abs(wind_push.y) > 0.01:
			velocity.y = wind_push.y
	else:
		if is_on_floor():
			# Patrol horizontally
			if abs(position.x - spawn_x) > patrol_range:
				direction = -sign(position.x - spawn_x)
				
			if is_on_wall():
				direction = -direction
				
			velocity.x = direction * speed
		else:
			# In the air: carry horizontal momentum but bounce off walls
			if is_on_wall():
				velocity.x = -velocity.x
				if abs(velocity.x) > 0.01:
					direction = sign(velocity.x)
		
	# Check for spike collisions (using the editor-defined custom collision shapes of the spike tile)
	var level = get_tree().current_scene
	if level:
		for child in level.get_children():
			if child is TileMapLayer:
				var check_points = [
					global_position + Vector2(0, 4), # slightly below bottom (to query inside solid shape)
					global_position, # bottom
					global_position + Vector2(0, -8) # lower body
				]
				var touched_spike = false
				for pt in check_points:
					var local_pt = child.to_local(pt)
					var map_pos = child.local_to_map(local_pt)
					var tile_data = child.get_cell_tile_data(map_pos)
					if tile_data and tile_data.get_custom_data("is_spike") == true:
						var cell_center = child.map_to_local(map_pos)
						var rel_pos = local_pt - cell_center # Offset from the tile center
						
						# Query all custom collision polygons drawn on this tile in Physics Layer 0
						var poly_count = tile_data.get_collision_polygons_count(0)
						for i in range(poly_count):
							var poly_points = tile_data.get_collision_polygon_points(0, i)
							if Geometry2D.is_point_in_polygon(rel_pos, poly_points):
								touched_spike = true
								break
					if touched_spike:
						break
				if touched_spike:
					velocity.y = randf_range(-500.0, -350.0)
					velocity.x = randf_range(-150.0, 150.0)
					if abs(velocity.x) > 0.01:
						direction = sign(velocity.x)
					rotation_speed = randf_range(5.0, 12.0) * (-1.0 if randf() < 0.5 else 1.0)
					break
		
	move_and_slide()
	
	# Apply rotation logic based on air state
	if not is_on_floor():
		visual_rotation += rotation_speed * delta
	else:
		rotation_speed = 0.0
		visual_rotation = rotate_toward(visual_rotation, 0.0, 5.0 * delta)
	
	# Send position and rotation update to clients
	if multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_enemy_state.rpc(position, direction, visual_rotation)
	
	wiggle_seed += delta
	queue_redraw()

func _draw() -> void:
	var color = Color("#323232") # Dark pencil lead
	var pen_width = 3.0
	
	# Rotate the drawing around the center of the spiked ball (0, -12)
	draw_set_transform(Vector2(0, -12), visual_rotation, Vector2.ONE)
	
	var center = Vector2.ZERO
	var radius = 10.0
	
	# Draw a spiked ball (procedural points alternating between normal and spike radii)
	var num_points = 12
	var points = PackedVector2Array()
	for i in range(num_points + 1):
		var angle = i * PI * 2.0 / num_points
		var r = radius
		if i % 2 == 1:
			r = radius * 1.5
			
		var wiggle = Vector2(
			sin(angle * 4.0 + wiggle_seed * 35.0),
			cos(angle * 3.0 + wiggle_seed * 40.0)
		) * 0.7
		points.append(center + Vector2(cos(angle), sin(angle)) * r + wiggle)
		
	draw_polyline(points, color, pen_width, true)
	
	# Draw angry eyebrows/eyes
	draw_line(center + Vector2(-4, -3), center + Vector2(-1, -4), color, 2.0)
	draw_line(center + Vector2(4, -3), center + Vector2(1, -4), color, 2.0)

func die_by_bullet() -> void:
	# Inform Main of the death so it can schedule a respawn (only for standard level enemies)
	if not name.begins_with("SpawnerEnemy"):
		var main = get_tree().current_scene
		if main and main.has_method("_on_enemy_died"):
			main._on_enemy_died(name, spawn_pos, patrol_range)
	sync_die.rpc()

@rpc("any_peer", "call_local", "reliable")
func sync_die() -> void:
	queue_free()


func _on_hitbox_body_entered(body: Node) -> void:
	if body.name.begins_with("Player"):
		# Trigger player death if it hits the player
		if body.has_method("die"):
			body.die()
