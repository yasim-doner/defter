extends StaticBody2D

@export var width: float = 120.0

var wiggle_seed: float = 0.0

func _ready() -> void:
	# Add a CollisionShape2D if it doesn't exist
	var collision_shape: CollisionShape2D
	if has_node("CollisionShape2D"):
		collision_shape = get_node("CollisionShape2D")
	else:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		add_child(collision_shape)
	
	# Set up a thin rectangle shape for collision
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = Vector2(width, 12.0)
	collision_shape.shape = rect_shape
	collision_shape.position = Vector2(0, 0)

func _process(delta: float) -> void:
	wiggle_seed += delta
	queue_redraw()

func _draw() -> void:
	var color = Color("#3c3c3c") # Pencil color
	var half_w = width / 2.0
	var pen_width = 3.5
	
	# Create a hand-drawn look using a few slightly wiggling and offset lines
	var w1 = sin(wiggle_seed * 40.0) * 0.5
	var w2 = cos(wiggle_seed * 35.0) * 0.5
	var w3 = sin(wiggle_seed * 45.0 + 10.0) * 0.5
	
	# Draw main stroke
	draw_line(Vector2(-half_w, w1), Vector2(half_w, w2), color, pen_width)
	
	# Draw a secondary slightly shorter overlapping stroke to give a rough sketch texture
	draw_line(Vector2(-half_w + 4.0, w2 - 1.0 + w3), Vector2(half_w - 4.0, w1 + 1.0 - w2), color, pen_width * 0.7)
