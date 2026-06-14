extends Control

var wiggle_seed: float = 0.0

func _process(delta: float) -> void:
	if visible:
		wiggle_seed += delta
		queue_redraw()

func _draw() -> void:
	var viewport_size = get_viewport_rect().size
	var panel_size = Vector2(400, 250)
	var rect = Rect2((viewport_size - panel_size) / 2.0, panel_size)
	
	var color = Color("#323232") # Dark pencil lead
	var bg_color = Color("#fcfaf2") # Warm paper background
	
	# Draw background panel
	draw_rect(rect, bg_color)
	
	# Create hand-drawn pencil strokes for the panel border
	var w1 = sin(wiggle_seed * 42.0) * 0.4
	var w2 = cos(wiggle_seed * 38.0) * 0.4
	
	var pen_width = 3.0
	var r = rect
	
	# Double stroke borders
	# Top
	draw_line(r.position + Vector2(0, w1), Vector2(r.end.x, r.position.y + w2), color, pen_width)
	draw_line(r.position + Vector2(-2, 2 + w2), Vector2(r.end.x + 2, r.position.y + 2 + w1), color, pen_width * 0.7)
	# Bottom
	draw_line(Vector2(r.position.x, r.end.y + w2), r.end + Vector2(0, w1), color, pen_width)
	draw_line(Vector2(r.position.x - 2, r.end.y - 2 + w1), r.end + Vector2(2, -2 + w2), color, pen_width * 0.7)
	# Left
	draw_line(r.position + Vector2(w1, 0), Vector2(r.position.x + w2, r.end.y), color, pen_width)
	draw_line(r.position + Vector2(2 + w2, -2), Vector2(r.position.x + 2 + w1, r.end.y + 2), color, pen_width * 0.7)
	# Right
	draw_line(Vector2(r.end.x + w2, r.position.y), r.end + Vector2(w1, 0), color, pen_width)
	draw_line(Vector2(r.end.x - 2 + w1, r.position.y - 2), r.end + Vector2(-2 + w2, 2), color, pen_width * 0.7)
