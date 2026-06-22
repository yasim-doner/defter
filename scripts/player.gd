extends CharacterBody2D

const SPEED = 230.0
const JUMP_VELOCITY = -510.0
const ACCELERATION = 1400.0
const FRICTION = 1600.0
const AIR_ACCELERATION = 900.0
const AIR_FRICTION = 600.0
const COYOTE_TIME = 0.12 # 120ms jump window after walking off ledges
const JUMP_BUFFER_TIME = 0.12 # 120ms jump input buffer
const SPRINT_SPEED = 360.0      # top speed once the sprint has ramped up
const SPRINT_RAMP = 1.0         # seconds of running to reach full sprint
const FALL_GRAVITY_MULT = 1.3   # heavier gravity while falling (momentum)
const TERMINAL_FALL = 1150.0    # max fall speed

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
var _run_trans: bool = false   # playing the idle->run start transition
var _prev_ground: String = "idle"
var _sprint_t: float = 0.0     # 0 = base speed, 1 = full sprint

# Parachute (paraşüt) feature
var is_parachute_active: bool = false
var parachute_timer: float = 0.0
var is_near_parachute_area: bool = false
var active_parachute_area: Area2D = null
var active_parachute_node: Area2D = null
var is_parachute_broken: bool = false
var parachute_hold_time: float = 0.0
const PARACHUTE_HOLD_REQUIRED: float = 1.0
var teleport_cooldown: float = 0.0
var active_wind_drafts: Array = []
var active_interactables: Array = []
var fall_start_y: float = 0.0
var is_first_physics_frame: bool = true
var is_noclip: bool = false
var is_carrying_letter: bool = false
var is_dragging_letter: bool = false
var carried_letter_mass: float = 1.0

func _ready() -> void:
	platform_floor_layers = 0
	_setup_input_actions()
	if name == "Player1":
		player_id = 1
		pen_color = Color("#323232") # Graphite pencil
	elif name == "Player2":
		player_id = 2
		pen_color = Color("#1a3a60") # Blue pen ink
	_setup_sprite()
	
	pass

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
	if not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return player_id == 1
	var is_server = multiplayer.is_server()
	return (player_id == 1 and is_server) or (player_id == 2 and not is_server)

func _setup_input_actions() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_W, KEY_SPACE, KEY_UP],
		"interact": [KEY_E],
		"move_down": [KEY_S, KEY_DOWN],
		"noclip": [KEY_V]
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
	if is_noclip:
		return
	
	if is_local():
		var level = get_node_or_null("/root/Level1")
		if level and level.has_method("sync_global_death"):
			if multiplayer and multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				level.sync_global_death.rpc()
			else:
				level.sync_global_death()
		else:
			if is_parachute_active:
				sync_deactivate_parachute.rpc()
			_respawn()


func _respawn() -> void:
	is_noclip = false
	is_parachute_broken = false
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", false)
	velocity = Vector2.ZERO
	set_weapon_lines([])
	if spawn_position != Vector2.ZERO:
		position = spawn_position
	else:
		if player_id == 1:
			position = Vector2(200, 400)
		else:
			position = Vector2(300, 400)
	fall_start_y = position.y

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or get_viewport() == null:
		return
	if not is_local():
		return
		
	if event.is_action_pressed("noclip"):
		is_noclip = not is_noclip
		if has_node("CollisionShape2D"):
			$CollisionShape2D.set_deferred("disabled", is_noclip)
		
	if event.is_action_pressed("interact"):
		var current_interactable = active_interactables.back() if not active_interactables.is_empty() else null
		if current_interactable:
			if current_interactable.has_method("interact"):
				current_interactable.interact(self)
			
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
func sync_activate_parachute_path(parachute_path: NodePath, duration: float = 10.0) -> void:
	is_parachute_active = true
	if not has_node("Parachute"):
		var parachute_scene = load("res://scenes/parachute.tscn")
		if parachute_scene:
			var parachute = parachute_scene.instantiate()
			parachute.name = "Parachute"
			parachute.player = self
			parachute.parachute_duration = duration
			add_child(parachute)
			active_parachute_node = parachute
			parachute.activate()
	else:
		active_parachute_node = get_node("Parachute")
		active_parachute_node.parachute_duration = duration
		active_parachute_node.activate()
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func sync_deactivate_parachute_path() -> void:
	is_parachute_active = false
	if active_parachute_node:
		if is_instance_valid(active_parachute_node):
			active_parachute_node.queue_free()
		active_parachute_node = null
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func sync_shoot_parachute(launch_velocity: Vector2) -> void:
	is_parachute_active = false
	if active_parachute_node and is_instance_valid(active_parachute_node):
		active_parachute_node.velocity = launch_velocity
		active_parachute_node.is_active = false
		if "reattach_cooldown" in active_parachute_node:
			active_parachute_node.reattach_cooldown = 1.0
		
		# Reparent to root so we move independently
		var old_global_pos = active_parachute_node.global_position
		if active_parachute_node.get_parent():
			active_parachute_node.get_parent().remove_child(active_parachute_node)
		get_tree().current_scene.add_child(active_parachute_node)
		active_parachute_node.global_position = old_global_pos
		
		active_parachute_node = null
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func sync_catch_parachute(parachute_path: NodePath) -> void:
	is_parachute_active = true
	var parachute = get_node_or_null(parachute_path)
	if parachute and is_instance_valid(parachute):
		# Reparent to this player
		if parachute.get_parent():
			parachute.get_parent().remove_child(parachute)
		add_child(parachute)
		parachute.name = "Parachute"
		parachute.player = self
		active_parachute_node = parachute
		
		# Reactivate it
		parachute.is_active = true
		parachute.active_duration = parachute.parachute_duration
		if "bounce_count" in parachute:
			parachute.bounce_count = 0
		
		# Enable canopy collision polygon
		var canopy = parachute.get_node_or_null("CollisionPolygon2D")
		if canopy:
			canopy.set_deferred("disabled", false)
			
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func sync_activate_parachute(duration: float = 10.0) -> void:
	pass

@rpc("any_peer", "call_local", "reliable")
func sync_deactivate_parachute() -> void:
	sync_deactivate_parachute_path()

func destroy_parachute() -> void:
	is_parachute_broken = true
	if is_instance_valid(active_parachute_node):
		active_parachute_node.destroy_parachute()

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

@rpc("any_peer", "call_local", "reliable")
func sync_push_letter(letter_path: NodePath, push_vel: Vector2) -> void:
	var letter_node = get_node_or_null(letter_path)
	if letter_node and letter_node.has_method("is_letter"):
		if letter_node.get("mass") < 3.0 and letter_node.get("state") == 0: # State.IDLE
			letter_node.velocity.x = push_vel.x

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
	if not is_inside_tree() or get_viewport() == null:
		return
		
	# Check pause state from Main
	var main = get_parent()
	if main and main.get("is_game_paused") == true:
		velocity = Vector2.ZERO
		return

	if is_on_floor():
		is_parachute_broken = false

	# Input-based parachute activation for local player
	if is_local() and not is_noclip:
		if is_near_parachute_area and not is_parachute_active and not is_parachute_broken:
			if Input.is_action_pressed("interact"):
				parachute_hold_time += delta
				queue_redraw()
				if parachute_hold_time >= PARACHUTE_HOLD_REQUIRED:
					parachute_hold_time = 0.0
					queue_redraw()
					if is_instance_valid(active_parachute_area):
						active_parachute_area.activate_parachute(self)
			else:
				if parachute_hold_time > 0.0:
					parachute_hold_time = 0.0
					queue_redraw()
		else:
			if parachute_hold_time > 0.0:
				parachute_hold_time = 0.0
				queue_redraw()

	if not is_local():
		# Remote player: drive the rig from synced state, skip inputs/movement
		var r_holding: bool = has_node("DrawnGun") and $DrawnGun.lines.size() > 0
		var r_aim: float = $DrawnGun.rotation if r_holding else NAN
		var r_face: float = 1.0 if facing_right else -1.0
		var r_on_floor: bool = absf(velocity.y) < 40.0
		_drive_visual(delta, velocity, r_on_floor, r_face, r_holding, r_aim)
		return

	if is_noclip:
		var h_dir = Input.get_axis("move_left", "move_right")
		var v_dir = Input.get_axis("jump", "move_down")
		velocity.x = h_dir * SPEED * 2.0
		velocity.y = v_dir * SPEED * 2.0
		
		move_and_slide()
		
		# Send updated local player state to the remote peer
		var gun_rot = 0.0
		if has_node("DrawnGun") and $DrawnGun.lines.size() > 0:
			var mouse_pos = get_global_mouse_position()
			facing_right = mouse_pos.x > global_position.x
			
			var flip = 1.0 if facing_right else -1.0
			$DrawnGun.position = Vector2(14 * flip, -26)
			
			var direction_to_mouse = (mouse_pos - $DrawnGun.global_position).normalized()
			var target_angle = direction_to_mouse.angle()
			
			if facing_right:
				$DrawnGun.scale = Vector2(1.0, 1.0)
			else:
				$DrawnGun.scale = Vector2(1.0, -1.0)
			$DrawnGun.rotation = target_angle
			gun_rot = target_angle
			
		if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			sync_state.rpc(position, velocity, facing_right, gun_rot)
			
		# Drive visual rig and redraw
		var holding: bool = has_node("DrawnGun") and $DrawnGun.lines.size() > 0
		var aim: float = gun_rot if holding else NAN
		var face: float = 1.0 if facing_right else -1.0
		_drive_visual(delta, velocity, true, face, holding, aim)
		return

	if is_first_physics_frame:
		fall_start_y = global_position.y
		is_first_physics_frame = false

	if is_local():
		if is_on_floor():
			var fall_distance = global_position.y - fall_start_y
			if fall_distance > 128.0 * 5.0: # 640.0 pixels
				die()
				return
			fall_start_y = global_position.y
		else:
			if is_parachute_active:
				fall_start_y = global_position.y
			elif global_position.y < fall_start_y:
				fall_start_y = global_position.y

	# Update teleport cooldown for local player
	if teleport_cooldown > 0.0:
		teleport_cooldown -= delta

	# Update interaction prompt visibility for local player
	var prompt = get_node_or_null("/root/Level1/UI/InteractionPrompt")
	if prompt:
		var current_interactable = active_interactables.back() if not active_interactables.is_empty() else null
		if current_interactable:
			prompt.text = current_interactable.get("prompt_text") if "prompt_text" in current_interactable else "Press E to Interact"
			prompt.visible = true
		else:
			prompt.visible = is_near_parachute_area and not is_parachute_active
			if prompt.visible:
				prompt.text = "Hold E to Glide"

	# Update coyote jump window
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer -= delta
		
	# Update jump input buffer
	jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	# Wind drafts (parachute) can hold the player up and push them around.
	var is_gravity_disabled = false
	var wind_push = Vector2.ZERO
	var has_wind = false

	if is_parachute_active:
		var valid_drafts = []
		for draft in active_wind_drafts:
			if is_instance_valid(draft) and draft.has_method("get_wind_direction_vector") and draft.get("is_on") == true:
				valid_drafts.append(draft)
				is_gravity_disabled = true
				has_wind = true
				var wind_dir = draft.get_wind_direction_vector()
				var wind_speed = draft.speed
				wind_push += wind_dir * wind_speed
		active_wind_drafts = valid_drafts

	# Apply gravity (Celeste float at apex, heavier on the way down) unless wind holds us.
	if not is_on_floor():
		if not is_gravity_disabled:
			var active_gravity = gravity
			if abs(velocity.y) < 70.0 and Input.is_action_pressed("jump"):
				active_gravity = gravity * 0.55          # floaty apex
			elif velocity.y > 0.0:
				active_gravity = gravity * FALL_GRAVITY_MULT  # falling momentum
			
			if is_carrying_letter:
				active_gravity = active_gravity * (1.0 + carried_letter_mass * 0.3)
				
			velocity.y += active_gravity * delta
			
			var active_terminal_fall = TERMINAL_FALL
			if is_carrying_letter:
				active_terminal_fall *= (1.0 + carried_letter_mass * 0.2)
			velocity.y = minf(velocity.y, active_terminal_fall)     # terminal velocity

			# Parachute glide cap
			if is_parachute_active:
				var glide_cap = 90.0
				if is_carrying_letter:
					glide_cap = 90.0 + carried_letter_mass * 120.0
				if velocity.y > glide_cap:
					velocity.y = glide_cap

	# Apply wind draft velocity if parachute is active
	if has_wind:
		var wind_accel = 2000.0
		if abs(wind_push.x) > 0.01:
			velocity.x = move_toward(velocity.x, wind_push.x, wind_accel * delta)
		if abs(wind_push.y) > 0.01:
			velocity.y = move_toward(velocity.y, wind_push.y, wind_accel * delta)

	# Trigger jump if within coyote and jump buffer windows
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_dragging_letter:
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

	# Sprint momentum: holding a steady ground direction ramps the top speed up;
	# reversing kills it; airborne keeps it so a running jump carries the speed.
	if is_on_floor():
		if direction == 0.0:
			_sprint_t = maxf(_sprint_t - delta / (SPRINT_RAMP * 0.5), 0.0)
		elif velocity.x != 0.0 and signf(direction) != signf(velocity.x):
			_sprint_t = 0.0
		else:
			_sprint_t = minf(_sprint_t + delta / SPRINT_RAMP, 1.0)
	var top_speed: float = lerp(SPEED, SPRINT_SPEED, _sprint_t)

	if direction:
		velocity.x = move_toward(velocity.x, direction * top_speed, active_accel * delta)
		if not (has_node("DrawnGun") and $DrawnGun.lines.size() > 0):
			facing_right = direction > 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, active_frict * delta)
		walk_time = move_toward(walk_time, 0.0, delta * 10.0)

	if is_dragging_letter:
		velocity.x *= (1.0 - 0.45 * carried_letter_mass * delta)

	move_and_slide()

	# Push letters with mass < 3.0 when colliding
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		if collider and collider.has_method("is_letter"):
			if collider.get("mass") < 3.0 and collider.get("state") == 0: # State.IDLE is 0
				var push_dir = -c.get_normal()
				if abs(push_dir.x) > 0.3:
					var push_force = 120.0
					if abs(velocity.x) > 100.0:
						push_force = abs(velocity.x) * 1.1
					var target_vx = sign(push_dir.x) * push_force
					if abs(collider.velocity.x - target_vx) > 20.0:
						if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
							sync_push_letter.rpc(collider.get_path(), Vector2(target_vx, 0.0))
						else:
							collider.velocity.x = target_vx

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
	if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
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
	if _anim == "run_trans":
		_run_trans = false   # transition done -> fall through to the run loop

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
	var st: String
	var clip: String
	if _jump_phase != "":
		st = _jump_phase
		clip = _PHASE_CLIP[_jump_phase]
	else:
		var ground := _ground_state(vel)
		# Start-running transition: idle -> run_trans (one-shot) -> run.
		if _prev_ground == "idle" and ground != "idle" and _has_clip("run_trans"):
			_run_trans = true
		if ground == "idle":
			_run_trans = false
		_prev_ground = ground
		st = "run_trans" if _run_trans else ground
		clip = st
	if not _has_clip(clip):
		clip = "run" if absf(vel.x) > 12.0 else "idle"   # fallback while art is missing
	if clip != _anim:
		_anim = clip
		if _has_clip(clip):
			sprite.play(clip)

	if st == "run" or st == "walk":
		# Match the leg cadence to ground speed (~1.0 at full run) so it no
		# longer looks like a frantic sprint while moving slowly.
		sprite.speed_scale = clampf(absf(vel.x) / SPEED, 0.5, 1.6)
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

	# Orientation: momentum lean only. The idle clip is now hand-animated
	# (7 frames), so no code-side breathing is needed.
	sprite.position = Vector2.ZERO
	sprite.rotation = _lean

func _draw() -> void:
	if not use_frames:
		rig.draw(self, pen_color, 3.5)

	# Draw loading E circle if holding E near parachute trigger
	if parachute_hold_time > 0.0 and is_instance_valid(active_parachute_area):
		var center = Vector2(0, -55) # Position above player's head
		var radius = 16.0
		var progress = parachute_hold_time / PARACHUTE_HOLD_REQUIRED
		
		# Draw background circle outline (faint graphite)
		draw_arc(center, radius, 0, PI * 2, 32, Color(0.6, 0.6, 0.6, 0.3), 3.0, true)
		# Draw progress fill arc
		draw_arc(center, radius, -PI / 2, -PI / 2 + progress * PI * 2, 32, pen_color, 3.0, true)
		
		# Draw a hand-drawn look 'E' inside the circle
		var line_color = pen_color
		var e_left = center.x - 4
		var e_right = center.x + 4
		var e_top = center.y - 5
		var e_bottom = center.y + 5
		draw_line(Vector2(e_left, e_top), Vector2(e_left, e_bottom), line_color, 2.0) # spine
		draw_line(Vector2(e_left, e_top), Vector2(e_right, e_top), line_color, 2.0) # top bar
		draw_line(Vector2(e_left, center.y), Vector2(e_right - 2, center.y), line_color, 2.0) # middle bar
		draw_line(Vector2(e_left, e_bottom), Vector2(e_right, e_bottom), line_color, 2.0) # bottom bar
