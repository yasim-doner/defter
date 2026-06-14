extends Node2D

@onready var player1 = $Player1
@onready var player2 = $Player2
@onready var death_screen = $UI/DeathScreen
@onready var replay_button = $UI/DeathScreen/Panel/ReplayButton
@onready var drawing_canvas = $UI/DrawingCanvas
@onready var spawn_timer = $SpawnTimer

var is_game_paused: bool = false
var peer = ENetMultiplayerPeer.new()
var is_network_active: bool = false

# Network UI node references to prevent NodePath lookup crashes
var net_ui_panel: Panel = null
var ip_input_edit: LineEdit = null
var status_label_node: Label = null
var host_btn_node: Button = null
var join_btn_node: Button = null

# Track who is currently drawing (node name string, e.g. "Player1" or "Player2")
var drawing_player_name: String = ""

func _ready() -> void:
	# Hide default death screen since we are endless and respawn players immediately
	death_screen.hide()
	drawing_canvas.hide()
	
	# Disable player processing until network connection is made
	player1.set_physics_process(false)
	player2.set_physics_process(false)
	
	# Connect drawing canvas finished signal
	drawing_canvas.drawing_finished.connect(_on_drawing_finished)
	
	# Setup Network UI overlay programmatically at startup
	_create_network_ui()
	
	# Connect ENet signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)

func _create_network_ui() -> void:
	net_ui_panel = Panel.new()
	net_ui_panel.name = "NetworkUI"
	net_ui_panel.custom_minimum_size = Vector2(420, 240)
	
	# Stylized notebook ruled panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#fcfaf2")
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color("#323232")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	net_ui_panel.add_theme_stylebox_override("panel", style)
	
	$UI.add_child(net_ui_panel)
	net_ui_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	net_ui_panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Notebook Platformer Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#323232"))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)
	
	ip_input_edit = LineEdit.new()
	ip_input_edit.name = "IPInput"
	ip_input_edit.placeholder_text = "Enter Host IP (e.g. 127.0.0.1)"
	ip_input_edit.text = "127.0.0.1"
	ip_input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_input_edit.custom_minimum_size = Vector2(250, 36)
	vbox.add_child(ip_input_edit)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)
	
	host_btn_node = Button.new()
	host_btn_node.name = "HostButton"
	host_btn_node.text = "Host Game"
	host_btn_node.custom_minimum_size = Vector2(130, 40)
	hbox.add_child(host_btn_node)
	
	join_btn_node = Button.new()
	join_btn_node.name = "JoinButton"
	join_btn_node.text = "Join Game"
	join_btn_node.custom_minimum_size = Vector2(130, 40)
	hbox.add_child(join_btn_node)
	
	status_label_node = Label.new()
	status_label_node.name = "StatusLabel"
	status_label_node.text = "Start host or enter IP to join..."
	status_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label_node.add_theme_color_override("font_color", Color("#666666"))
	vbox.add_child(status_label_node)
	
	# Connect buttons
	host_btn_node.pressed.connect(_on_host_pressed)
	join_btn_node.pressed.connect(_on_join_pressed)

func _on_host_pressed() -> void:
	var err = peer.create_server(52000, 1) # Port 52000, 1 client max (2 players total)
	if err != OK:
		if is_instance_valid(status_label_node):
			status_label_node.text = "Failed to Host: %s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	is_network_active = true
	if is_instance_valid(status_label_node):
		status_label_node.text = "Hosting on port 52000... Waiting for player 2"
	if is_instance_valid(host_btn_node):
		host_btn_node.disabled = true
	if is_instance_valid(join_btn_node):
		join_btn_node.disabled = true

func _on_join_pressed() -> void:
	var ip = ""
	if is_instance_valid(ip_input_edit):
		ip = ip_input_edit.text.strip_edges()
	if ip.is_empty():
		if is_instance_valid(status_label_node):
			status_label_node.text = "Please enter a valid IP address"
		return
	
	var err = peer.create_client(ip, 52000)
	if err != OK:
		if is_instance_valid(status_label_node):
			status_label_node.text = "Failed to Connect: %s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	is_network_active = true
	if is_instance_valid(status_label_node):
		status_label_node.text = "Connecting to %s..." % ip
	if is_instance_valid(host_btn_node):
		host_btn_node.disabled = true
	if is_instance_valid(join_btn_node):
		join_btn_node.disabled = true

# Connection callbacks
func _on_peer_connected(_id: int) -> void:
	# Server starts the gameplay and notifies clients
	if multiplayer.is_server():
		_start_gameplay()

func _on_connected_ok() -> void:
	# Client notifies they are in
	if is_instance_valid(net_ui_panel):
		net_ui_panel.queue_free()
	player2.set_physics_process(true)
	player1.set_physics_process(true)

func _on_peer_disconnected(_id: int) -> void:
	# Stop everything if peer leaves
	is_network_active = false
	get_tree().quit()

func _on_connected_fail() -> void:
	if is_instance_valid(status_label_node):
		status_label_node.text = "Connection failed. Try hosting again."
	if is_instance_valid(host_btn_node):
		host_btn_node.disabled = false
	if is_instance_valid(join_btn_node):
		join_btn_node.disabled = false
	multiplayer.multiplayer_peer = null

func _start_gameplay() -> void:
	if is_instance_valid(net_ui_panel):
		net_ui_panel.queue_free()
	
	# Enable physics process loop
	player1.set_physics_process(true)
	player2.set_physics_process(true)
	
	# Server spawns initial platform enemies
	if multiplayer.is_server():
		_spawn_enemies()
		
		# Start spawn timer for pens (8 seconds after game start)
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)
		spawn_timer.start(8.0)

func _process(_delta: float) -> void:
	if not is_network_active:
		return
		
	# Viewport check: if local player falls off, trigger respawn locally
	var viewport_size = get_viewport_rect().size
	if multiplayer.is_server():
		if player1.position.y > viewport_size.y + 80.0:
			player1.die()
	else:
		if player2.position.y > viewport_size.y + 80.0:
			player2.die()

@rpc("any_peer", "call_local", "reliable")
func sync_pause(paused: bool) -> void:
	is_game_paused = paused
	# Lock player velocities
	if paused:
		player1.velocity = Vector2.ZERO
		player2.velocity = Vector2.ZERO
	else:
		# If unpaused and we are the host, restart the pen spawn timer (15s cooldown)
		if multiplayer.is_server():
			spawn_timer.start(15.0)

@rpc("any_peer", "call_local", "reliable")
func sync_pen_collected(by_player: String) -> void:
	# Pause physics for both players
	sync_pause(true)
	
	drawing_player_name = by_player
	
	# Delete the pen node on all peers
	if has_node("Pen"):
		get_node("Pen").queue_free()
	
	# Open drawing screen locally ONLY on the client who touched the pen
	var local_player_node_name = "Player1" if multiplayer.is_server() else "Player2"
	if by_player == local_player_node_name:
		drawing_canvas.start_drawing()

func _on_drawing_finished(lines: Array) -> void:
	# Feed lines to player and resume game state
	var local_player = player1 if multiplayer.is_server() else player2
	local_player.set_weapon_lines(lines)
	
	# Unpause the game across the network
	sync_pause.rpc(false)

# Pen Spawning (Host authoritative)
func _on_spawn_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if is_game_paused:
		# Check again in 3 seconds
		spawn_timer.start(3.0)
		return
	if has_node("Pen"):
		# Check again in 5 seconds
		spawn_timer.start(5.0)
		return
		
	# Select platform index randomly and sync
	var platforms = $Platforms.get_children()
	if platforms.size() > 0:
		var valid_indices = []
		for i in range(platforms.size()):
			var p = platforms[i]
			# Avoid Platform 2/3 where enemies are patrolling
			if p.name == "Platform1" or p.name == "Platform4":
				valid_indices.append(i)
		
		var idx = valid_indices[randi() % valid_indices.size()] if valid_indices.size() > 0 else randi() % platforms.size()
		sync_spawn_pen.rpc(idx)

@rpc("any_peer", "call_local", "reliable")
func sync_spawn_pen(platform_idx: int) -> void:
	# Spawn a pen on the platform
	var platforms = $Platforms.get_children()
	if platform_idx < platforms.size():
		var target_platform = platforms[platform_idx]
		var pen_script = preload("res://pen.gd")
		var pen = Area2D.new()
		pen.set_script(pen_script)
		pen.name = "Pen"
		pen.position = target_platform.position + Vector2(0, -32)
		add_child(pen)
		
		# Connect collision collection signal
		pen.collected.connect(_on_pen_collected)

func _on_pen_collected(body: Node2D) -> void:
	# Only triggers on the collector machine to start the RPC chain
	if body.has_method("is_local") and body.is_local():
		sync_pen_collected.rpc(body.name)

# Enemy spawning (Host authoritative)
func _spawn_enemies() -> void:
	# Platform 2 (550, 378) and Platform 3 (850, 474)
	sync_spawn_enemy.rpc("Enemy_Platform2", Vector2(550, 378), 60.0)
	sync_spawn_enemy.rpc("Enemy_Platform3", Vector2(850, 474), 80.0)


@rpc("any_peer", "call_local", "reliable")
func sync_spawn_enemy(enemy_name: String, pos: Vector2, patrol_range: float) -> void:
	var enemy_script = preload("res://enemy.gd")
	
	# Verify Enemies container
	if not has_node("Enemies"):
		var container = Node2D.new()
		container.name = "Enemies"
		add_child(container)
		
	var enemy = CharacterBody2D.new()
	enemy.set_script(enemy_script)
	enemy.name = enemy_name
	enemy.position = pos
	enemy.patrol_range = patrol_range
	$Enemies.add_child(enemy)

func _on_enemy_died(enemy_name: String, pos: Vector2, patrol_range: float) -> void:
	if not multiplayer.is_server():
		return
		
	# Endless enemy loop: respawn the enemy on its platform after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_network_active:
		sync_spawn_enemy.rpc(enemy_name, pos, patrol_range)

func _clear_bullets() -> void:
	if has_node("Bullets"):
		for b in $Bullets.get_children():
			b.queue_free()
