extends Control

var local_player: CharacterBody2D = null
var remote_player: CharacterBody2D = null
var arrow_pos: Vector2 = Vector2.ZERO
var arrow_dir: Vector2 = Vector2.ZERO
var arrow_color: Color = Color("#323232")
var wiggle_seed: float = 0.0

func _ready() -> void:
	# Find players in the active scene
	var tree = get_tree()
	var level = tree.current_scene if tree else null
	if level:
		var p1 = level.get_node_or_null("Player1")
		var p2 = level.get_node_or_null("Player2")
		if p1 and p2:
			if p1.has_method("is_local") and p1.is_local():
				local_player = p1
				remote_player = p2
				arrow_color = Color("#1a3a60") # Other is P2 (blue)
			else:
				local_player = p2
				remote_player = p1
				arrow_color = Color("#323232") # Other is P1 (charcoal)

func _process(delta: float) -> void:
	if not is_instance_valid(local_player) or not is_instance_valid(remote_player):
		# Try to find them again (if level transitioned or respawned)
		_ready()
		if not is_instance_valid(local_player) or not is_instance_valid(remote_player):
			hide()
			return
			
	wiggle_seed += delta
	
	var viewport_size = get_viewport_rect().size
	var canvas_transform = get_viewport().get_canvas_transform()
	var remote_screen_pos = canvas_transform * remote_player.global_position
	
	# Set a margin of 28 pixels from the edge of the screen
	var margin = 28.0
	var screen_rect = Rect2(margin, margin, viewport_size.x - margin * 2.0, viewport_size.y - margin * 2.0)
	
	if screen_rect.has_point(remote_screen_pos):
		hide()
	else:
		var screen_center = viewport_size / 2.0
		arrow_dir = (remote_screen_pos - screen_center).normalized()
		arrow_pos = get_ray_rect_intersection(screen_center, arrow_dir, screen_rect)
		show()
		queue_redraw()

func get_ray_rect_intersection(center: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var t_x = INF
	var t_y = INF
	
	if dir.x > 0:
		t_x = (rect.end.x - center.x) / dir.x
	elif dir.x < 0:
		t_x = (rect.position.x - center.x) / dir.x
		
	if dir.y > 0:
		t_y = (rect.end.y - center.y) / dir.y
	elif dir.y < 0:
		t_y = (rect.position.y - center.y) / dir.y
		
	var t = min(t_x, t_y)
	return center + t * dir

func _draw() -> void:
	if not visible:
		return
		
	# Draw sketched wobbly arrow pointing in arrow_dir at arrow_pos
	var P = arrow_pos
	var dir = arrow_dir
	var angle = dir.angle()
	var pen_width = 3.5
	
	# Sketched wobbly offset helpers for hand-drawn look
	var w1 = Vector2(sin(wiggle_seed * 48.0), cos(wiggle_seed * 52.0)) * 0.8
	var w2 = Vector2(cos(wiggle_seed * 44.0), sin(wiggle_seed * 56.0)) * 0.8
	
	# Main shaft (P - dir * 22 to P)
	var shaft_start = P - dir * 22.0
	draw_line(shaft_start + w1, P + w2, arrow_color, pen_width)
	draw_line(shaft_start - w2 * 0.5, P - w1 * 0.5, arrow_color, pen_width * 0.7)
	
	# Left wing of arrowhead
	var left_wing = P + Vector2.from_angle(angle + PI * 0.85) * 14.0
	draw_line(P + w2, left_wing + w1, arrow_color, pen_width)
	draw_line(P - w1 * 0.5, left_wing - w2 * 0.5, arrow_color, pen_width * 0.7)
	
	# Right wing of arrowhead
	var right_wing = P + Vector2.from_angle(angle - PI * 0.85) * 14.0
	draw_line(P + w1, right_wing + w2, arrow_color, pen_width)
	draw_line(P - w2 * 0.5, right_wing - w1 * 0.5, arrow_color, pen_width * 0.7)
