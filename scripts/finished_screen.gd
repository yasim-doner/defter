extends Control

var wiggle_seed: float = 0.0
var has_next_level: bool = false

func _ready() -> void:
	# Ensure the UI overlay is on top and captures input
	process_mode = PROCESS_MODE_ALWAYS
	
	# Anchor self to full viewport
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Check if there is a next level
	var next_level = ""
	if GameManager:
		next_level = GameManager.get_next_level()
	has_next_level = (next_level != "")
	
	# Programmatically build children to keep Level1.tscn robust
	var panel = Control.new()
	panel.name = "Panel"
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	
	var label = Label.new()
	label.name = "Label"
	label.text = "Level Completed!"
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#323232"))
	label.add_theme_font_size_override("font_size", 28)
	label.anchors_preset = Control.PRESET_CENTER
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.offset_left = -180
	label.offset_top = -80
	label.offset_right = 180
	label.offset_bottom = -20
	panel.add_child(label)
	
	# Flat sketched button styling
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color("#fcfaf2")
	style_normal.border_width_left = 3
	style_normal.border_width_top = 3
	style_normal.border_width_right = 3
	style_normal.border_width_bottom = 3
	style_normal.border_color = Color("#323232")
	style_normal.corner_detail = 1
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color("#e5e2d9")
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color("#d0cdb8")
	
	if has_next_level:
		var next_button = Button.new()
		next_button.name = "NextLevelButton"
		next_button.text = "Next Level"
		next_button.add_theme_color_override("font_color", Color("#323232"))
		next_button.add_theme_color_override("font_hover_color", Color("#323232"))
		next_button.add_theme_color_override("font_pressed_color", Color("#323232"))
		next_button.add_theme_font_size_override("font_size", 18)
		next_button.add_theme_stylebox_override("normal", style_normal)
		next_button.add_theme_stylebox_override("hover", style_hover)
		next_button.add_theme_stylebox_override("pressed", style_pressed)
		
		next_button.anchors_preset = Control.PRESET_CENTER
		next_button.anchor_left = 0.5
		next_button.anchor_top = 0.5
		next_button.anchor_right = 0.5
		next_button.anchor_bottom = 0.5
		next_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
		next_button.grow_vertical = Control.GROW_DIRECTION_BOTH
		next_button.offset_left = -100
		next_button.offset_top = 10
		next_button.offset_right = 100
		next_button.offset_bottom = 58
		next_button.pressed.connect(_on_next_level_pressed)
		panel.add_child(next_button)
		
	var button = Button.new()
	button.name = "MainMenuButton"
	button.text = "Return to Lobby"
	button.add_theme_color_override("font_color", Color("#323232"))
	button.add_theme_color_override("font_hover_color", Color("#323232"))
	button.add_theme_color_override("font_pressed_color", Color("#323232"))
	button.add_theme_font_size_override("font_size", 18)
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	
	button.anchors_preset = Control.PRESET_CENTER
	button.anchor_left = 0.5
	button.anchor_top = 0.5
	button.anchor_right = 0.5
	button.anchor_bottom = 0.5
	button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	button.grow_vertical = Control.GROW_DIRECTION_BOTH
	button.offset_left = -100
	button.offset_top = 70 if has_next_level else 10
	button.offset_right = 100
	button.offset_bottom = 118 if has_next_level else 58
	button.pressed.connect(_on_main_menu_pressed)
	panel.add_child(button)

func _process(delta: float) -> void:
	if visible:
		wiggle_seed += delta
		queue_redraw()

func _draw() -> void:
	var panel_size = Vector2(400, 310) if has_next_level else Vector2(400, 250)
	var rect = Rect2((size - panel_size) / 2.0, panel_size)
	
	var color = Color("#323232") # Dark pencil lead
	var bg_color = Color("#fcfaf2") # Warm paper background
	
	# Draw background panel
	draw_rect(rect, bg_color)
	
	# Hand-drawn pencil outline strokes
	var w1 = sin(wiggle_seed * 42.0) * 0.4
	var w2 = cos(wiggle_seed * 38.0) * 0.4
	
	var pen_width = 3.0
	var r = rect
	
	# Double wobbly strokes for sketchy aesthetic
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

func _on_main_menu_pressed() -> void:
	# Clean up network state and switch to Lobby menu
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_next_level_pressed() -> void:
	if GameManager:
		GameManager.load_next_level()
