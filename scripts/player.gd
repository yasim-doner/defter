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

# Procedural physical animation rig — now a FALLBACK placeholder, used only
# until hand-drawn frame-by-frame art is dropped in (see assets/character/SPEC.md).
const StickRig = preload("res://scripts/stick_rig.gd")
var rig := StickRig.new()

# Frame-by-frame visuals. When the SpriteFrames resource exists we play hand-
# drawn frames and the "feel" layer (lean / squash / playback speed) is applied
# to the sprite transform. Frames are authored facing RIGHT, 64x80, feet centred
# at the bottom (pixel 32,72) — see SPEC.md.
const FRAMES_PATH := "res://assets/character/player_frames.tres"
const SPRITE_FEET := Vector2(128, 289)  # feet pixel in the 256x320 art
const SPRITE_BASE_SCALE := 0.52         # art is ~4x game size
# Per-clip size tweak without redrawing, e.g. {"jump_launch": 1.3}. Default 1.0.
const SPRITE_CLIP_SCALE := {}
# Jump finite-state machine: phase -> clip name; and where a finished one-shot goes.
const _PHASE_CLIP := {
	"launch": "jump_launch", "rise": "jump_rise",
	"tofall": "jump_fall_trans", "fall": "jump_fall", "land": "land",
}
const _ONESHOT_NEXT := {"launch": "rise", "tofall": "fall", "land": ""}
var sprite: AnimatedSprite2D = null
var use_frames: bool = false
var _anim: String = ""
var _lean: float = 0.0
var _vis_scale: Vector2 = Vector2.ONE
var _idle_t: float = 0.0
var _jump_phase: String = ""   # "", launch, rise, tofall, fall, land
var _was_on_floor: bool = true

# Parachute (paraşüt) feature
var is_parachute_active: bool = false
var parachute_timer: float = 0.0
var is_near_parachute_area: bool = false
var active_parachute_area: Area2D = null
var parachute_texture: Texture2D = preload("res://assets/parasut.png")
var teleport_cooldown: float = 0.0

func _ready() -> void:
	_setup_input_actions()
	if name == "Player1":
		player_id = 1
		pen_color = Color("#323232") # Graphite pencil
	elif name == "Player2":
		player_id = 2
		pen_color = Color("#1a3a60") # Blue pen ink
	_setup_sprite()

# Per-player frame set (p1 = şapka, p2 = bandana); shared set as fallback.
func _frames_path() -> String:
	var per_player := "res://assets/character/p%d_frames.tres" % player_id
	if ResourceLoader.exists(per_player):
		return per_player
	return FRAMES_PATH

func _setup_sprite() -> void:
	# Use hand-drawn frames if they exist; otherwise fall back to the rig.
	var path := _frames_path()
	if not ResourceLoader.exists(path):
		return
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = load(path)
	sprite.centered = false
	sprite.offset = -SPRITE_FEET  # put the feet pixel at the node origin
	add_child(sprite)
	sprite.animation_finished.connect(_on_sprite_anim_finished)
	use_frames = true

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
		"jump": [KEY_W, KEY_SPACE, KEY_UP],
		"interact": [KEY_E]
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
		if is_parachute_active:
			sync_deactivate_parachute.rpc()
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
		
	if event.is_action_pressed("interact"):
		if is_near_parachute_area and not is_parachute_active:
			var duration = 10.0
			if active_parachute_area and "parachute_duration" in active_parachute_area:
				duration = active_parachute_area.parachute_duration
			sync_activate_parachute.rpc(duration)
			
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
func sync_activate_parachute(duration: float) -> void:
	is_parachute_active = true
	parachute_timer = duration
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func sync_deactivate_parachute() -> void:
	is_parachute_active = false
	parachute_timer = 0.0
	queue_redraw()

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

	# Update parachute timer for both local and remote players
	if is_parachute_active:
		parachute_timer -= delta
		if parachute_timer <= 0.0:
			is_parachute_active = false
			queue_redraw()

	if not is_local():
		# Remote player: drive the rig from synced state, skip inputs/movement
		var r_holding: bool = has_node("DrawnGun") and $DrawnGun.lines.size() > 0
		var r_aim: float = $DrawnGun.rotation if r_holding else NAN
		var r_face: float = 1.0 if facing_right else -1.0
		var r_on_floor: bool = absf(velocity.y) < 40.0
		_drive_visual(delta, velocity, r_on_floor, r_face, r_holding, r_aim)
		return

	# Update teleport cooldown for local player
	if teleport_cooldown > 0.0:
		teleport_cooldown -= delta

	# Update interaction prompt visibility for local player
	var prompt = get_node_or_null("/root/Level1/UI/InteractionPrompt")
	if prompt:
		prompt.visible = is_near_parachute_area and not is_parachute_active

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
		
		# If parachute is active, only cap the falling/downward speed to create a glide
		if is_parachute_active and velocity.y > 90.0:
			velocity.y = 90.0

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

	# Check for spike collisions (using the editor-defined custom collision shapes of the spike tile)
	var parent_node = get_parent()
	if parent_node:
		for child in parent_node.get_children():
			if child is TileMapLayer:
				var check_points = [
					global_position + Vector2(0, 4), # slightly below feet (to query inside solid shape)
					global_position, # feet
					global_position + Vector2(0, -8) # lower body
				]
				var died = false
				for pt in check_points:
					var local_pt = child.to_local(pt)
					var map_pos = child.local_to_map(local_pt)
					var tile_data = child.get_cell_tile_data(map_pos)
					if tile_data and tile_data.get_custom_data("is_spike") == true:
						var cell_center = child.map_to_local(map_pos)
						var rel_pos = local_pt - cell_center # Offset from the tile center

						# Query all custom collision polygons drawn on this tile in Physics Layer 0
						var poly_count = tile_data.get_collision_polygons_count(0)
						for i in range(poly_count):
							var poly_points = tile_data.get_collision_polygon_points(0, i)
							if Geometry2D.is_point_in_polygon(rel_pos, poly_points):
								die()
								died = true
								break
					if died:
						break
				if died:
					break

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

	# Drive the procedural rig and redraw
	var holding: bool = has_node("DrawnGun") and $DrawnGun.lines.size() > 0
	var aim: float = gun_rot if holding else NAN
	var face: float = 1.0 if facing_right else -1.0
	_drive_visual(delta, velocity, is_on_floor(), face, holding, aim)

# Routes the "feel" layer either to the hand-drawn sprite or the rig fallback.
func _drive_visual(delta: float, vel: Vector2, on_floor: bool, face: float, holding: bool, aim: float) -> void:
	if use_frames:
		_update_sprite(delta, vel, on_floor, face, holding)
	else:
		rig.update(delta, vel, on_floor, face, holding, aim)
		queue_redraw()

func _has_clip(c: String) -> bool:
	return c != "" and sprite.sprite_frames.has_animation(c)

func _ground_state(vel: Vector2) -> String:
	if absf(vel.x) > SPEED * 0.55:
		return "run"
	if absf(vel.x) > 12.0:
		return "walk"
	return "idle"

# Set the jump phase. A missing one-shot clip auto-advances so we never stall.
func _enter_phase(p: String) -> void:
	_jump_phase = p
	if p == "":
		return
	if not _has_clip(_PHASE_CLIP[p]) and _ONESHOT_NEXT.has(p):
		_enter_phase(_ONESHOT_NEXT[p])

func _on_sprite_anim_finished() -> void:
	if _ONESHOT_NEXT.has(_jump_phase):
		_enter_phase(_ONESHOT_NEXT[_jump_phase])

# Drive the AnimatedSprite2D: jump FSM + ground states, speed scaling, and the
# momentum lean / squash-stretch feel layer.
func _update_sprite(delta: float, vel: Vector2, on_floor: bool, face: float, holding: bool) -> void:
	sprite.flip_h = face < 0.0

	# Jump state-machine edges.
	if on_floor and not _was_on_floor:
		_enter_phase("land")
	elif not on_floor and _was_on_floor:
		_enter_phase("launch" if vel.y < 0.0 else "fall")
	if _jump_phase == "rise" and vel.y > -40.0:   # past the apex
		_enter_phase("tofall")
	if on_floor and _jump_phase != "land":
		_jump_phase = ""
	elif not on_floor and _jump_phase == "":
		_enter_phase("fall")
	_was_on_floor = on_floor

	# Resolve the clip (+ a generic label for the feel layer).
	var st: String = _jump_phase if _jump_phase != "" else _ground_state(vel)
	var clip: String = st
	if _jump_phase != "":
		clip = _PHASE_CLIP[_jump_phase]
	if not _has_clip(clip):
		clip = "run" if absf(vel.x) > 12.0 else "idle"   # fallback while art is missing
	if clip != _anim:
		_anim = clip
		if _has_clip(clip):
			sprite.play(clip)

	if st == "run" or st == "walk":
		sprite.speed_scale = clampf(absf(vel.x) / (SPEED * 0.5), 0.6, 2.2)
	else:
		sprite.speed_scale = 1.0

	# Momentum lean (pivots at the feet because the sprite origin is the feet).
	var run_t := clampf(absf(vel.x) / SPEED, 0.0, 1.0)
	var dir := signf(vel.x)
	var target_lean := dir * run_t * 0.45
	if not on_floor:
		# Air lean scales with horizontal speed (near-vertical jumps barely lean).
		var h := clampf(absf(vel.x) / 140.0, 0.0, 1.0)
		if vel.y < 0.0:
			target_lean = dir * h * 0.40    # rising: lean forward, hands lead the jump
		else:
			target_lean = -dir * h * 0.32   # falling: lean back so the feet lead forward
	_lean = lerp(_lean, target_lean, clampf(delta * 10.0, 0.0, 1.0))

	# Squash & stretch.
	var ts := Vector2.ONE
	if not on_floor:
		# rising: stretch up; falling: a slight dive-stretch (no shrink — the
		# impact squash belongs to the `land` clip, not free-fall).
		ts = Vector2(0.92, 1.12) if vel.y < 0.0 else Vector2(0.97, 1.05)
	_vis_scale = _vis_scale.lerp(ts, clampf(delta * 12.0, 0.0, 1.0))
	var cscale: float = SPRITE_CLIP_SCALE.get(clip, 1.0)
	sprite.scale = _vis_scale * (SPRITE_BASE_SCALE * cscale)

	# Final orientation: momentum lean + a gentle idle breathing bob/sway.
	if st == "idle":
		_idle_t += delta
		sprite.position = Vector2(0, sin(_idle_t * 2.2) * 1.5)
		sprite.rotation = _lean + sin(_idle_t * 1.3) * 0.02
	else:
		_idle_t = 0.0
		sprite.position = Vector2.ZERO
		sprite.rotation = _lean

func _draw() -> void:
	if not use_frames:
		rig.draw(self, pen_color, 3.5)

	# Parachute overlay — drawn above the character in either render mode.
	if is_parachute_active and parachute_texture:
		var tex_size = parachute_texture.get_size()
		var dest_rect = Rect2(Vector2(-tex_size.x / 2.0, -25.5 - tex_size.y / 2.0), tex_size)
		draw_texture_rect(parachute_texture, dest_rect, false)
