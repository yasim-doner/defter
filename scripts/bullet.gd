extends Area2D

@export var speed: float = 650.0
var direction: Vector2 = Vector2.RIGHT
var wiggle_seed: float = 0.0
var bullet_color: Color = Color("#323232")
var lifetime: float = 2.0

func _ready() -> void:
	# Add a CollisionShape2D if it doesn't exist
	var collision_shape: CollisionShape2D
	if has_node("CollisionShape2D"):
		collision_shape = get_node("CollisionShape2D")
	else:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		add_child(collision_shape)
		
	var shape = CircleShape2D.new()
	shape.radius = 5.0
	collision_shape.shape = shape
	
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Check pause state
	if GameManager.is_game_paused:
		return
		
	# Move bullet
	position += direction * speed * delta
	
	# Delete if lifetime expires
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
		
	wiggle_seed += delta
	queue_redraw()

func _draw() -> void:
	var color = bullet_color
	var w1 = sin(wiggle_seed * 55.0) * 0.45
	var w2 = cos(wiggle_seed * 48.0) * 0.45
	
	# Draw a rough double-drawn pencil bullet line
	draw_line(Vector2(-6, w1), Vector2(6, w2), color, 2.8)
	draw_line(Vector2(-4, -1.5 + w2), Vector2(4, -1.5 + w1), color, 1.8)

func _on_body_entered(body: Node) -> void:
	if body is TileMapLayer or body.name.begins_with("Platform"):
		queue_free()
	elif body.has_method("die_by_bullet"):
		# Only the authority (server/host) should register the hit and trigger the death RPC chain
		var is_auth = true
		if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			is_auth = multiplayer.is_server()
		
		if is_auth:
			body.die_by_bullet()
		queue_free()
	elif body.has_method("is_letter"):
		var is_auth = true
		if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			is_auth = multiplayer.is_server()
			
		if is_auth:
			# Only push if the letter is IDLE (not carried or dragged)
			if body.get("state") == 0: # State.IDLE
				var l_mass = body.get("mass")
				var l_bounciness = body.get("bounciness")
				var bullet_mass_factor = 0.3
				var push_impulse = direction * speed * bullet_mass_factor * (1.0 + l_bounciness) / l_mass
				body.velocity += push_impulse
		queue_free()

