extends Node2D

@export var line_spacing: float = 48.0
@export var margin_offset: float = 120.0

func _draw() -> void:
	var size = get_viewport_rect().size
	
	# Warm off-white notebook paper color
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f7f4eb"))
	
	# Horizontal blue ruled lines
	var y = line_spacing
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#cbdced"), 1.2)
		y += line_spacing
		
	# Vertical pink/red margin line
	draw_line(Vector2(margin_offset, 0), Vector2(margin_offset, size.y), Color("#e8a5a5"), 1.5)
