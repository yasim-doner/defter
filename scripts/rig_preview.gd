extends Node2D
# Dev-only harness to eyeball StickRig poses without needing input/physics.
# Draws each motion state side by side. Safe to delete once tuning is done.

const StickRig = preload("res://scripts/stick_rig.gd")

var _states := [
	{"name": "idle", "vel": Vector2(0, 0), "floor": true},
	{"name": "walk", "vel": Vector2(95, 0), "floor": true},
	{"name": "run", "vel": Vector2(230, 0), "floor": true},
	{"name": "jump", "vel": Vector2(150, -420), "floor": false},
	{"name": "fall", "vel": Vector2(150, 360), "floor": false},
]
var _rigs := []

func _ready() -> void:
	for s in _states:
		_rigs.append(StickRig.new())

func _process(delta: float) -> void:
	for i in _rigs.size():
		var s = _states[i]
		_rigs[i].update(delta, s.vel, s.floor, 1.0, false, NAN)
	queue_redraw()

func _draw() -> void:
	# paper-ish background
	draw_rect(Rect2(0, 0, 1152, 648), Color("#fcfaf2"))
	var line_c := Color("#cbdced")
	var y := 0.0
	while y < 648:
		draw_line(Vector2(0, y), Vector2(1152, y), line_c, 1.0)
		y += 24.0

	var font := ThemeDB.fallback_font
	var base_x := 140.0
	var base_y := 360.0
	for i in _rigs.size():
		var cx = base_x + i * 200.0
		draw_set_transform(Vector2(cx, base_y), 0.0, Vector2.ONE)
		_rigs[i].draw(self, Color("#242424"), 3.5)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_string(font, Vector2(cx - 30, base_y + 60), _states[i]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#242424"))
