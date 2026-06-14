extends Node2D

var lines = []:
	set(value):
		lines = value
		queue_redraw()
var wiggle_seed: float = 0.0

func _process(delta: float) -> void:
	if lines.size() > 0:
		wiggle_seed += delta
		queue_redraw()

func _draw() -> void:
	if lines.size() == 0:
		return
		
	var color = Color("#2a2a2a") # Charcoal pencil color
	if get_parent() and "pen_color" in get_parent():
		color = get_parent().pen_color
	var pen_width = 2.0
	
	for line in lines:
		if line.size() < 2:
			continue
			
		# Add a hand-drawn sketch wiggle to the gun lines
		var wiggled_line = PackedVector2Array()
		for p in line:
			var wiggle = Vector2(
				sin(p.x * 0.3 + wiggle_seed * 42.0),
				cos(p.y * 0.3 + wiggle_seed * 38.0)
			) * 0.5
			wiggled_line.append(p + wiggle)
			
		draw_polyline(wiggled_line, color, pen_width)
