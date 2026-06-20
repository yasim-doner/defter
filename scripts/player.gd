extends CharacterBody2D

const SPEED = 230.0
const JUMP_VELOCITY = -510.0
const ACCELERATION = 1400.0
const FRICTION = 1600.0
const AIR_ACCELERATION = 900.0
const AIR_FRICTION = 600.0
const COYOTE_TIME = 0.12 # 120ms jump window after walking off ledges
const JUMP_BUFFER_TIME = 0.12 # 120ms jump input buffer

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)

var walk_time: float = 0.0
var facing_right: bool = true
var wiggle_seed: float = 0.0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0


var player_id: int = 1
var pen_color: Color = Color("#323232")
var spawn_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_setup_input_actions()
	if name == "Player1":
		player_id = 1
		pen_color = Color("#323232") # Graphite pencil
	elif name == "Player2":
		player_id = 2
		pen_color = Color("#1a3a60") # Blue pen ink

func setup_camera() -> void:
	if has_node("Camera2D"):
		get_node("Camera2D").queue_free()
		
	if is_local():
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 5.0
		
		# Prevent camera from showing outside page boundaries by scanning the backgrounds
		var scene = get_tree().current_scene
		if scene:
			var bg_container = scene.get_node_or_null("Backgrounds")
			if bg_container and bg_container.get_child_count() > 0:
				var min_pos = Vector2(INF, INF)
				var max_pos = Vector2(-INF, -INF)
				for child in bg_container.get_children():
					if child is Sprite2D and child.texture:
						var tex_size = child.texture.get_size()
						var half_size = tex_size / 2.0
						var top_left = child.position - half_size
						var bottom_right = child.position + half_size
						min_pos.x = min(min_pos.x, top_left.x)
						min_pos.y = min(min_pos.y, top_left.y)
						max_pos.x = max(max_pos.x, bottom_right.x)
						max_pos.y = max(max_pos.y, bottom_right.y)
				
				if min_pos.x != INF:
					camera.limit_left = int(min_pos.x)
					camera.limit_top = int(min_pos.y)
					camera.limit_right = int(max_pos.x)
					camera.limit_bottom = int(max_pos.y)
		
		add_child(camera)
		camera.make_current()


func is_local() -> bool:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return player_id == 1
	var is_server = multiplayer.is_server()
	return (player_id == 1 and is_server) or (player_id == 2 and not is_server)

func _setup_input_actions() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_W, KEY_SPACE, KEY_UP]
	}
	
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
			
		for keycode in actions[action]:
			var ev = InputEventKey.new()
			ev.keycode = keycode
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

func set_weapon_lines(new_lines: Array) -> void:
	if has_node("DrawnGun"):
		$DrawnGun.lines = new_lines
	if is_local():
		sync_weapon_drawing.rpc(new_lines)

@rpc("any_peer", "reliable")
func sync_weapon_drawing(new_lines: Array) -> void:
	if not is_local():
		if has_node("DrawnGun"):
			$DrawnGun.lines = new_lines

func die() -> void:
	# Endless game: respawn immediately at spawn point and clear gun
	if is_local():
		_respawn()

func _respawn() -> void:
	velocity = Vector2.ZERO
	set_weapon_lines([])
	if spawn_position != Vector2.ZERO:
		position = spawn_position
	else:
		if player_id == 1:
			position = Vector2(200, 400)
		else:
			position = Vector2(300, 400)

func _input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Only shoot if we have weapon lines and are actively processing physics (not paused/dead/drawing)
			if has_node("DrawnGun") and $DrawnGun.lines.size() > 0:
				if is_physics_processing():
					var flip = 1.0 if facing_right else -1.0
					var gun_pos = global_position + Vector2(14 * flip, -26)
					
					var mouse_pos = get_global_mouse_position()
					var dir = (mouse_pos - gun_pos).normalized()
					var spawn_pos = gun_pos + dir * 24.0
					
					sync_shoot.rpc(spawn_pos, dir)

@rpc("any_peer", "call_local", "reliable")
func sync_shoot(bullet_pos: Vector2, bullet_dir: Vector2) -> void:
	var bullet_script = preload("res://scripts/bullet.gd")
	var bullet = Area2D.new()
	bullet.set_script(bullet_script)
	bullet.name = "Bullet"
	bullet.position = bullet_pos
	bullet.direction = bullet_dir
	bullet.rotation = bullet_dir.angle()
	
	# Add bullet to the Bullets container under Main
	var main = get_parent()
	if main.has_node("Bullets"):
		main.get_node("Bullets").add_child(bullet)
	else:
		main.add_child(bullet)

@rpc("any_peer", "unreliable")
func sync_state(pos: Vector2, vel: Vector2, facing: bool, gun_rot: float) -> void:
	if not is_local():
		position = pos
		velocity = vel
		facing_right = facing
		if has_node("DrawnGun"):
			$DrawnGun.rotation = gun_rot
			var flip = 1.0 if facing_right else -1.0
			$DrawnGun.position = Vector2(14 * flip, -26)
			if facing_right:
				$DrawnGun.scale = Vector2(1.0, 1.0)
			else:
				$DrawnGun.scale = Vector2(1.0, -1.0)

func _physics_process(delta: float) -> void:
	# Check pause state from Main
	var main = get_parent()
	if main and main.get("is_game_paused") == true:
		velocity = Vector2.ZERO
		return

	if not is_local():
		# Remote player: update wiggle seed and redraw, skip inputs/movement
		wiggle_seed += delta
		queue_redraw()
		return

	# Update coyote jump window
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer -= delta
		
	# Update jump input buffer
	jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	# Apply gravity (with Celeste-style gravity scaling at the peak of the jump)
	if not is_on_floor():
		var active_gravity = gravity
		if abs(velocity.y) < 70.0 and Input.is_action_pressed("jump"):
			active_gravity = gravity * 0.55
		velocity.y += active_gravity * delta

	# Trigger jump if within coyote and jump buffer windows
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Variable jump height: release jump button early to jump lower
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.55

	# Smooth horizontal movement using distinct ground/air acceleration & friction
	var direction := Input.get_axis("move_left", "move_right")
	var active_accel = ACCELERATION if is_on_floor() else AIR_ACCELERATION
	var active_frict = FRICTION if is_on_floor() else AIR_FRICTION

	if direction:
		velocity.x = move_toward(velocity.x, direction * SPEED, active_accel * delta)
		if not (has_node("DrawnGun") and $DrawnGun.lines.size() > 0):
			facing_right = direction > 0
		walk_time += delta * 12.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, active_frict * delta)
		walk_time = move_toward(walk_time, 0.0, delta * 10.0)

	move_and_slide()
	
	# Position and rotate the gun to point at the mouse
	var gun_rot = 0.0
	if has_node("DrawnGun") and $DrawnGun.lines.size() > 0:
		var mouse_pos = get_global_mouse_position()
		facing_right = mouse_pos.x > global_position.x
		
		var flip = 1.0 if facing_right else -1.0
		$DrawnGun.position = Vector2(14 * flip, -26)
		
		# Rotate gun towards the mouse
		var direction_to_mouse = (mouse_pos - $DrawnGun.global_position).normalized()
		var target_angle = direction_to_mouse.angle()
		
		# Set gun scale and rotation to avoid drawing it upside down when facing left
		if facing_right:
			$DrawnGun.scale = Vector2(1.0, 1.0)
		else:
			$DrawnGun.scale = Vector2(1.0, -1.0)
		$DrawnGun.rotation = target_angle
		gun_rot = target_angle
	
	# Send updated local player state to the remote peer
	if multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_state.rpc(position, velocity, facing_right, gun_rot)
	
	# Redraw for the hand-drawn wiggle
	wiggle_seed += delta
	queue_redraw()

# Helper to draw a circle for the head
func draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points = PackedVector2Array()
	var num_points = 16
	for i in range(num_points + 1):
		var angle = i * PI * 2.0 / num_points
		var wiggle = Vector2(
			sin(angle * 3.0 + wiggle_seed * 40.0),
			cos(angle * 2.0 + wiggle_seed * 35.0)
		) * 0.8
		points.append(center + Vector2(cos(angle), sin(angle)) * radius + wiggle)
	draw_polyline(points, color, width, true)

# Helper to draw a wiggle line
func draw_wiggle_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var w1 = Vector2(sin(wiggle_seed * 62.0), cos(wiggle_seed * 54.0)) * 0.7
	var w2 = Vector2(cos(wiggle_seed * 48.0), sin(wiggle_seed * 58.0)) * 0.7
	draw_line(from + w1, to + w2, color, width)

func _draw() -> void:
	var flip = 1.0 if facing_right else -1.0
	var color = pen_color
	var pen_width = 3.5
	
	# 1. Head
	var head_center = Vector2(0, -42)
	draw_circle_outline(head_center, 9.0, color, pen_width)
	
	# 2. Torso (Neck to Hips)
	var neck = Vector2(0, -33)
	var hips = Vector2(0, -16)
	draw_wiggle_line(neck, hips, color, pen_width)
	
	# Calculate legs and arms positions
	var left_foot = Vector2(-8 * flip, 0)
	var right_foot = Vector2(8 * flip, 0)
	var left_hand = Vector2(-12 * flip, -24)
	var right_hand = Vector2(12 * flip, -24)
	
	if not is_on_floor():
		# Air animations (jumping/falling)
		var arm_raise = clamp(-velocity.y / 200.0, -1.0, 1.0)
		left_hand = Vector2(-10 * flip, -32 - arm_raise * 10)
		right_hand = Vector2(10 * flip, -32 - arm_raise * 10)
		# Pull legs up slightly
		left_foot = Vector2(-6 * flip, -4)
		right_foot = Vector2(6 * flip, -4)
	else:
		# Ground animations (standing/walking)
		if abs(velocity.x) > 10.0:
			var left_phase = walk_time
			var right_phase = walk_time + PI
			
			left_foot = Vector2(sin(left_phase) * 10 * flip, cos(left_phase) * 3 - 1)
			right_foot = Vector2(sin(right_phase) * 10 * flip, cos(right_phase) * 3 - 1)
			
			left_hand = Vector2(-8 * flip + sin(right_phase) * 6 * flip, -24 + cos(right_phase) * 4)
			right_hand = Vector2(8 * flip + sin(left_phase) * 6 * flip, -24 + cos(left_phase) * 4)
		else:
			# Idle standing pose
			left_foot = Vector2(-7 * flip, 0)
			right_foot = Vector2(7 * flip, 0)
			left_hand = Vector2(-10 * flip, -20)
			right_hand = Vector2(10 * flip, -20)

	# Override arm posture if holding a gun
	if has_node("DrawnGun") and $DrawnGun.lines.size() > 0:
		if facing_right:
			right_hand = Vector2(14, -26)
			left_hand = Vector2(4, -24)
		else:
			left_hand = Vector2(-14, -26)
			right_hand = Vector2(-4, -24)

	# 3. Draw Legs (Hips to feet)
	draw_wiggle_line(hips, left_foot, color, pen_width)
	draw_wiggle_line(hips, right_foot, color, pen_width)
	
	# 4. Draw Arms (Shoulders to hands)
	var shoulders = Vector2(0, -30)
	draw_wiggle_line(shoulders, left_hand, color, pen_width)
	draw_wiggle_line(shoulders, right_hand, color, pen_width)
