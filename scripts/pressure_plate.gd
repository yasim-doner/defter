extends Area2D

signal pressed_state_changed(is_pressed: bool)

@export var button_id: String = "finish"

var is_pressed: bool = false
var pressed_objects: Array = []
var wiggle_seed: float = 0.0

func _ready() -> void:
	add_to_group("pressure_plates")
	monitoring = true
	monitorable = true
	
	# Connect body signals (players, enemies)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Connect area signals (parachutes)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	# Create collision shape programmatically if not already present
	if not has_node("CollisionShape2D"):
		var col_shape = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(40, 16)
		col_shape.shape = shape
		col_shape.position = Vector2(0, -8) # Grounded top-aligned
		add_child(col_shape)
		
	queue_redraw()

func _process(delta: float) -> void:
	wiggle_seed += delta
	
	# Filter out freed/invalid references (e.g. players dying or parachutes getting destroyed)
	var original_count = pressed_objects.size()
	pressed_objects = pressed_objects.filter(func(obj): return is_instance_valid(obj))
	if pressed_objects.size() != original_count:
		_update_pressed_state()
		
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.name.begins_with("Player") or body.name.begins_with("Enemy") or body.name.begins_with("SpawnerEnemy") or body.has_method("die_by_bullet") or body.has_method("is_letter"):
		if not pressed_objects.has(body):
			pressed_objects.append(body)
			_update_pressed_state()


func _on_body_exited(body: Node2D) -> void:
	if pressed_objects.has(body):
		pressed_objects.erase(body)
		_update_pressed_state()

func _on_area_entered(area: Area2D) -> void:
	if area.name.begins_with("Parachute"):
		if not pressed_objects.has(area):
			pressed_objects.append(area)
			_update_pressed_state()

func _on_area_exited(area: Area2D) -> void:
	if pressed_objects.has(area):
		pressed_objects.erase(area)
		_update_pressed_state()

func _update_pressed_state() -> void:
	# Filter out freed/invalid references
	pressed_objects = pressed_objects.filter(func(obj): return is_instance_valid(obj))
	var new_pressed = not pressed_objects.is_empty()
	if new_pressed != is_pressed:
		is_pressed = new_pressed
		pressed_state_changed.emit(is_pressed)
		queue_redraw()

func _draw() -> void:
	var color = Color("#323232") # Dark pencil lead
	var bg_color = Color("#fcfaf2") # Warm paper background
	var pen_width = 3.0
	
	# Draw bottom mounting line (flat on the floor)
	draw_line(Vector2(-24, 0), Vector2(24, 0), color, pen_width)
	
	# Determine button plate height based on state
	var button_height = -5.0 if is_pressed else -12.0
	var w = sin(wiggle_seed * 18.0) * 0.4
	
	# Draw filled wobbly button body
	var rect = Rect2(-16, button_height + w, 32, -button_height)
	draw_rect(rect, bg_color)
	
	# Draw outline borders for hand-drawn look
	draw_line(Vector2(-16, button_height + w), Vector2(16, button_height + w), color, pen_width)
	draw_line(Vector2(-16, button_height + w), Vector2(-16, 0), color, pen_width)
	draw_line(Vector2(16, button_height + w), Vector2(16, 0), color, pen_width)
