extends Area2D

@export var wind_draft_path: NodePath
@export var prompt_text: String = "Press [E] to Toggle Wind"

var is_on: bool = true
var wiggle_seed: float = 0.0

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Match the initial state of the target wind draft
	var target = get_node_or_null(wind_draft_path)
	if target:
		is_on = target.is_on
	queue_redraw()

func _process(delta: float) -> void:
	wiggle_seed += delta
	queue_redraw()

func interact(player: CharacterBody2D) -> void:
	# Trigger the synchronized network RPC
	sync_toggle.rpc()

@rpc("any_peer", "call_local", "reliable")
func sync_toggle() -> void:
	is_on = not is_on
	var target = get_node_or_null(wind_draft_path)
	if target:
		target.is_on = is_on
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			if "active_interactables" in body:
				if not body.active_interactables.has(self):
					body.active_interactables.append(self)

func _on_body_exited(body: Node2D) -> void:
	if body.name.begins_with("Player"):
		if body.has_method("is_local") and body.is_local():
			if "active_interactables" in body:
				body.active_interactables.erase(self)

func _draw() -> void:
	var color = Color("#323232") # Dark pencil lead
	var bg_color = Color("#fcfaf2") # Warm paper background
	var pen_width = 3.0
	
	# Draw switch plate / box
	var rect = Rect2(-14, -18, 28, 36)
	draw_rect(rect, bg_color)
	
	# Double wobbly border for hand-drawn look
	var w1 = sin(wiggle_seed * 15.0) * 0.3
	var w2 = cos(wiggle_seed * 12.0) * 0.3
	
	# Draw wobbly border outlines
	draw_line(rect.position + Vector2(0, w1), Vector2(rect.end.x, rect.position.y + w2), color, pen_width)
	draw_line(Vector2(rect.position.x, rect.end.y + w2), rect.end + Vector2(0, w1), color, pen_width)
	draw_line(rect.position + Vector2(w1, 0), Vector2(rect.position.x + w2, rect.end.y), color, pen_width)
	draw_line(Vector2(rect.end.x + w2, rect.position.y), rect.end + Vector2(w1, 0), color, pen_width)
	
	# Draw lever
	var start = Vector2(0, 0)
	var end = Vector2(0, -12) if is_on else Vector2(0, 12)
	# Add some wiggle to the lever
	var lw = sin(wiggle_seed * 22.0) * 0.3
	end.x += lw
	
	# Lever base circle
	draw_circle(start, 4.0, color)
	
	# Lever stick
	draw_line(start, end, color, pen_width * 1.2)
	# Lever knob
	draw_circle(end, 5.0, color)
