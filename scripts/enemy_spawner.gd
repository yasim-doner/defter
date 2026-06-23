extends Area2D

@export var spawn_rate: float = 3.0
@export var max_enemies: int = 5
@export var patrol_range: float = 65.0
@export var speed: float = 60.0

var spawn_timer: float = 0.0

func _ready() -> void:
	# Spawner doesn't need to detect overlap, it just uses CollisionShape2D for bounds checking.
	# We randomize seed to ensure different spawn timers if there are multiple spawners.
	randomize()
	spawn_timer = randf_range(0.0, spawn_rate)

func is_leader() -> bool:
	if not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return multiplayer.is_server()

func _physics_process(delta: float) -> void:
	if not is_leader():
		return
		
	spawn_timer += delta
	if spawn_timer >= spawn_rate:
		spawn_timer = 0.0
		
		# Check if there is already an enemy inside the spawner's Area2D
		var enemy_in_area = false
		for body in get_overlapping_bodies():
			if body.has_method("die_by_bullet"):
				enemy_in_area = true
				break
				
		if not enemy_in_area:
			var group_name = "spawner_enemies_" + str(get_instance_id())
			if get_tree().get_nodes_in_group(group_name).size() < max_enemies:
				_spawn_enemy()

func _spawn_enemy() -> void:
	var spawn_pos = global_position
	
	# Determine spawn coordinates within the collision shape boundary if it exists
	if has_node("CollisionShape2D"):
		var col_shape = $CollisionShape2D
		if col_shape.shape is RectangleShape2D:
			var rect_size = col_shape.shape.size
			var rx = randf_range(-rect_size.x / 2.0, rect_size.x / 2.0)
			var ry = randf_range(-rect_size.y / 2.0, rect_size.y / 2.0)
			spawn_pos = col_shape.global_position + Vector2(rx, ry).rotated(col_shape.global_rotation)
		elif col_shape.shape is CircleShape2D:
			var radius = col_shape.shape.radius
			var r = randf() * radius
			var angle = randf() * PI * 2.0
			spawn_pos = col_shape.global_position + Vector2(cos(angle), sin(angle)).rotated(col_shape.global_rotation) * r
			
	var enemy_name = "SpawnerEnemy_" + str(get_instance_id()) + "_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
	sync_spawn_enemy.rpc(enemy_name, spawn_pos, patrol_range, speed)

@rpc("any_peer", "call_local", "reliable")
func sync_spawn_enemy(enemy_name: String, spawn_pos: Vector2, p_range: float, p_speed: float) -> void:
	var enemy_script = preload("res://scripts/enemy.gd")
	var enemy = CharacterBody2D.new()
	enemy.set_script(enemy_script)
	enemy.name = enemy_name
	enemy.position = spawn_pos
	enemy.patrol_range = p_range
	enemy.speed = p_speed
	
	# Register inside the spawner-specific tracking group
	var group_name = "spawner_enemies_" + str(get_instance_id())
	enemy.add_to_group(group_name)
	
	# Add to current scene's Enemies container if it exists
	var tree = get_tree()
	var level = tree.current_scene if tree else null
	if level:
		if level.has_node("Enemies"):
			level.get_node("Enemies").add_child(enemy)
		else:
			level.add_child(enemy)
