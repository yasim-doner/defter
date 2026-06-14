extends Area2D

signal collected(body)

var time_passed: float = 0.0
var base_y: float

func _ready() -> void:
	base_y = position.y
	# Ensure a CollisionShape2D exists
	var collision_shape: CollisionShape2D
	if has_node("CollisionShape2D"):
		collision_shape = get_node("CollisionShape2D")
	else:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		add_child(collision_shape)
	
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	collision_shape.shape = shape
	
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	time_passed += delta
	# Gentle bobbing up and down (absolute position)
	position.y = base_y + sin(time_passed * 5.0) * 8.0
	# Slight rocking rotation
	rotation = sin(time_passed * 2.2) * 0.15
	queue_redraw()

func _draw() -> void:
	var color = Color("#2a2a2a") # Dark pencil lead color
	var pen_width = 2.5
	
	# Draw a fountain pen shape: body + cap + nib
	var points = PackedVector2Array([
		Vector2(-4, 12),
		Vector2(-4, -2),
		Vector2(0, -10), # Nib tip
		Vector2(4, -2),
		Vector2(4, 12),
		Vector2(-4, 12)
	])
	
	# Add a hand-drawn wiggle to the pen shape
	var wiggled_points = PackedVector2Array()
	for p in points:
		var wiggle = Vector2(
			sin(p.x * 1.5 + time_passed * 12.0),
			cos(p.y * 1.5 + time_passed * 10.0)
		) * 0.4
		wiggled_points.append(p + wiggle)
		
	draw_polyline(wiggled_points, color, pen_width, true)
	
	# Draw the pen clip
	draw_line(Vector2(2, 4), Vector2(6, 4), color, pen_width)
	draw_line(Vector2(6, 4), Vector2(6, -1), color, pen_width * 0.8)

func _on_body_entered(body: Node) -> void:
	if body.name.begins_with("Player"):
		collected.emit(body)
