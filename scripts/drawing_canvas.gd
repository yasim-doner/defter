extends Control

signal drawing_finished(lines)

@onready var timer_label = $Panel/TimerLabel
@onready var clear_button = $Panel/ClearButton
@onready var done_button = $Panel/DoneButton

var lines = []
var current_line: PackedVector2Array = PackedVector2Array()
var is_drawing: bool = false
var time_left: float = 10.0
var drawing_area: Rect2

func _ready() -> void:
	clear_button.pressed.connect(clear_canvas)
	done_button.pressed.connect(finish_drawing)
	
	# Viewport is 1152x648. The panel size is 640x440 (centered: top-left is at 256, 104).
	# Define a slightly smaller bounding box for active drawing area
	drawing_area = Rect2(Vector2(266, 144), Vector2(620, 310))

func start_drawing() -> void:
	lines.clear()
	current_line.clear()
	is_drawing = false
	time_left = 10.0
	show()
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
		
	time_left -= delta
	timer_label.text = "Ink Dry Time: %d" % ceil(max(time_left, 0.0))
	
	if time_left <= 0.0:
		finish_drawing()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if drawing_area.has_point(event.position):
					is_drawing = true
					current_line = PackedVector2Array([event.position])
					lines.append(current_line)
			else:
				is_drawing = false
				current_line = PackedVector2Array()
				
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			clear_canvas()
			
	elif event is InputEventMouseMotion and is_drawing:
		if drawing_area.has_point(event.position):
			if current_line.size() == 0 or current_line[-1].distance_to(event.position) > 2.0:
				current_line.append(event.position)
				lines[-1] = current_line
				queue_redraw()

func clear_canvas() -> void:
	lines.clear()
	current_line.clear()
	is_drawing = false
	queue_redraw()

func finish_drawing() -> void:
	if not visible:
		return
		
	var normalized_lines: Array[PackedVector2Array] = []
	var has_points = false
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for line in lines:
		for p in line:
			has_points = true
			min_pos.x = min(min_pos.x, p.x)
			min_pos.y = min(min_pos.y, p.y)
			max_pos.x = max(max_pos.x, p.x)
			max_pos.y = max(max_pos.y, p.y)
			
	if has_points:
		var center = (min_pos + max_pos) / 2.0
		var drawing_size = max_pos - min_pos
		var max_dim = max(drawing_size.x, drawing_size.y)
		var scale_factor = 1.0
		if max_dim > 0.0:
			scale_factor = 32.0 / max_dim # Scale largest dimension to 32px
			
		for line in lines:
			var normalized_line = PackedVector2Array()
			for p in line:
				var np = (p - center) * scale_factor
				normalized_line.append(np)
			normalized_lines.append(normalized_line)
			
	drawing_finished.emit(normalized_lines)
	hide()

func _draw() -> void:
	if not visible:
		return
		
	# Draw paper panel
	var viewport_size = get_viewport_rect().size
	var panel_size = Vector2(640, 440)
	var rect = Rect2((viewport_size - panel_size) / 2.0, panel_size)
	
	var bg_color = Color("#fcfaf2") # Paper
	var line_color = Color("#cbdced") # Blue lines
	var margin_color = Color("#e8a5a5") # Red margin
	var pencil_color = Color("#323232")
	var pen_width = 3.0
	
	# Draw paper background
	draw_rect(rect, bg_color)
	
	# Draw horizontal blue lines inside the panel bounds
	var start_y = ceil(rect.position.y / 24.0) * 24.0
	var y = start_y
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), line_color, 1.0)
		y += 24.0
		
	# Draw vertical red margin inside the panel bounds
	var margin_x = rect.position.x + 80.0
	draw_line(Vector2(margin_x, rect.position.y), Vector2(margin_x, rect.end.y), margin_color, 1.5)
	
	# Draw borders
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), pencil_color, pen_width)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, pencil_color, pen_width)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), pencil_color, pen_width)
	draw_line(Vector2(rect.end.x, r_position_y_helper(rect.position.y)), rect.end, pencil_color, pen_width)
	
	# Draw user lines
	for line in lines:
		if line.size() >= 2:
			draw_polyline(line, Color("#242424"), 3.5)

func r_position_y_helper(y: float) -> float:
	return y
