@tool
extends Area2D

enum WindDirection { UP, DOWN, LEFT, RIGHT }

@export var direction: WindDirection = WindDirection.UP:
	set(val):
		direction = val
		update_wind_draft_shapes()
		update_wind_draft()

@export var speed: float = 300.0:
	set(val):
		speed = val
		update_wind_draft()

@export var is_on: bool = true:
	set(val):
		is_on = val
		update_wind_draft()

@export var height: float = 256.0:
	set(val):
		height = val
		update_wind_draft_shapes()
		update_wind_draft()

@export var thickness: float = 75.0:
	set(val):
		thickness = val
		update_wind_draft_shapes()
		update_wind_draft()

func _ready() -> void:
	update_wind_draft_shapes()
	update_wind_draft()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

func set_is_on(val: bool) -> void:
	is_on = val

func update_wind_draft_shapes() -> void:
	var is_vertical = (direction == WindDirection.UP or direction == WindDirection.DOWN)
	
	# Update main CollisionShape2D
	if has_node("CollisionShape2D"):
		var col_shape = $CollisionShape2D
		if col_shape.shape is RectangleShape2D:
			if not col_shape.shape.resource_local_to_scene:
				col_shape.shape = col_shape.shape.duplicate()
			if is_vertical:
				col_shape.shape.size.y = height
				col_shape.shape.size.x = thickness
			else:
				col_shape.shape.size.x = height
				col_shape.shape.size.y = thickness

func get_wind_direction_vector() -> Vector2:
	match direction:
		WindDirection.UP:
			return Vector2(0, -1)
		WindDirection.DOWN:
			return Vector2(0, 1)
		WindDirection.LEFT:
			return Vector2(-1, 0)
		WindDirection.RIGHT:
			return Vector2(1, 0)
	return Vector2.ZERO

func update_wind_draft() -> void:
	if not has_node("CPUParticles2D"):
		return
		
	var particles = $CPUParticles2D
	particles.emitting = is_on
	
	if not is_on:
		return
		
	var dir_vec = get_wind_direction_vector()
	particles.direction = dir_vec
	particles.spread = 0.0
	particles.gravity = Vector2.ZERO
	var particle_speed = speed * 0.75
	
	# Sketched look: increase amount, size, and dark graphite opacity for high visibility
	particles.amount = 60
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 8.0
	particles.color = Color(0.2, 0.2, 0.2, 0.4)
	
	# Determine bounds size based on CollisionShape2D
	var size = Vector2(128, 256) # default fallback
	if has_node("CollisionShape2D"):
		var col_shape = $CollisionShape2D
		if col_shape.shape is RectangleShape2D:
			size = col_shape.shape.size
			
	# Adjust lifetime so particles reach the end of the area
	if has_node("CollisionShape2D"):
		var col_shape = $CollisionShape2D
		if col_shape.shape is RectangleShape2D:
			particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			
			# Position the emitter line at the starting edge based on direction
			match direction:
				WindDirection.UP:
					particles.emission_rect_extents = Vector2(size.x / 2.0, 0.0)
					particles.position = Vector2(0.0, size.y / 2.0)
				WindDirection.DOWN:
					particles.emission_rect_extents = Vector2(size.x / 2.0, 0.0)
					particles.position = Vector2(0.0, -size.y / 2.0)
				WindDirection.LEFT:
					particles.emission_rect_extents = Vector2(0.0, size.y / 2.0)
					particles.position = Vector2(size.x / 2.0, 0.0)
				WindDirection.RIGHT:
					particles.emission_rect_extents = Vector2(0.0, size.y / 2.0)
					particles.position = Vector2(-size.x / 2.0, 0.0)
			
			var distance = size.y if (direction == WindDirection.UP or direction == WindDirection.DOWN) else size.x
			# Use a tighter velocity range to keep the fade out aligned with the boundary
			particles.initial_velocity_min = particle_speed * 0.95
			particles.initial_velocity_max = particle_speed * 1.05
			particles.lifetime = max(0.2, distance / particle_speed)
		elif col_shape.shape is CircleShape2D:
			var radius = col_shape.shape.radius
			particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			particles.emission_sphere_radius = radius
			particles.lifetime = max(0.2, (radius * 2.0) / particle_speed)
			particles.position = Vector2.ZERO
	
	particles.preprocess = particles.lifetime

func _on_body_entered(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			if "active_wind_drafts" in body:
				if not body.active_wind_drafts.has(self):
					body.active_wind_drafts.append(self)
	elif body.has_method("die_by_bullet"):
		if "active_wind_drafts" in body:
			if not body.active_wind_drafts.has(self):
				body.active_wind_drafts.append(self)

func _on_body_exited(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			if "active_wind_drafts" in body:
				body.active_wind_drafts.erase(self)
	elif body.has_method("die_by_bullet"):
		if "active_wind_drafts" in body:
			body.active_wind_drafts.erase(self)


var _prev_is_on: bool = true

func _on_pressure_plate_2_pressed_state_changed(is_pressed: bool) -> void:
	if is_pressed:
		# Store current state and toggle
		_prev_is_on = is_on
		set_is_on(!is_on)
	else:
		# Restore previous state when released
		set_is_on(_prev_is_on)


func _on_wind_switch_toggle_state_changed(new_state: bool) -> void:
	_prev_is_on = new_state
	set_is_on(new_state)
