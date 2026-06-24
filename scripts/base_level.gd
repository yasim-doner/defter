extends Node2D
class_name BaseLevel

@export var spawn_p1: Vector2 = Vector2(250, 400)
@export var spawn_p2: Vector2 = Vector2(400, 400)
@export var fall_limit: float = 3550.0

@onready var player1 = $Player1
@onready var player2 = $Player2
@onready var drawing_canvas = $UI/DrawingCanvas
@onready var death_screen = $UI/DeathScreen

var drawing_player_name: String = ""

func _ready() -> void:
	# Enable processing
	player1.set_physics_process(true)
	player2.set_physics_process(true)
	
	# Configure player camera focus
	player1.setup_camera()
	player2.setup_camera()
	
	# Assign level-specific spawn positions to player scripts
	player1.spawn_position = spawn_p1
	player2.spawn_position = spawn_p2
	
	# Position players at starts
	player1.position = spawn_p1
	player2.position = spawn_p2
	
	# Hide overlay screens
	death_screen.hide()
	drawing_canvas.hide()
	
	# Connect drawing canvas finished signal
	drawing_canvas.drawing_finished.connect(_on_drawing_finished)
	
	# Connect all existing Pens in the level
	if has_node("Pens"):
		for pen in $Pens.get_children():
			pen.collected.connect(func(body): _on_pen_collected(body, pen))
			
	# Create offscreen indicators for players
	var indicator_script = preload("res://scripts/offscreen_indicator.gd")
	var indicator = Control.new()
	indicator.set_script(indicator_script)
	indicator.name = "OffscreenIndicator"
	$UI.add_child(indicator)
			
	# Monitor network disconnect to clean up safely
	if multiplayer:
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(_delta: float) -> void:
	# Fall limit check for player respawning
	var is_host = not multiplayer or not multiplayer.multiplayer_peer or multiplayer.is_server()
	if is_host:
		if player1.position.y > fall_limit:
			player1.die()
	else:
		if player2.position.y > fall_limit:
			player2.die()

@rpc("any_peer", "call_local", "reliable")
func sync_pen_collected(by_player: String, pen_path: NodePath) -> void:
	GameManager.sync_pause(true)
	drawing_player_name = by_player
	
	# Delete the pen node on all peers
	if has_node(pen_path):
		get_node(pen_path).queue_free()
		
	# Open drawing screen locally ONLY on the client who touched the pen
	var is_host = not multiplayer or not multiplayer.multiplayer_peer or multiplayer.is_server()
	var local_player_node_name = "Player1" if is_host else "Player2"
	if by_player == local_player_node_name:
		drawing_canvas.start_drawing()

func _on_drawing_finished(lines: Array) -> void:
	var is_host = not multiplayer or not multiplayer.multiplayer_peer or multiplayer.is_server()
	var local_player = player1 if is_host else player2
	local_player.set_weapon_lines(lines)
	GameManager.sync_pause.rpc(false)

func _on_pen_collected(body: Node2D, pen_node: Area2D) -> void:
	if body.has_method("is_local") and body.is_local():
		sync_pen_collected.rpc(body.name, pen_node.get_path())

func _on_peer_disconnected(_id: int) -> void:
	GameManager.is_network_active = false
	if multiplayer:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_enemy_died(enemy_name: String, pos: Vector2, patrol_range: float) -> void:
	if multiplayer and multiplayer.multiplayer_peer and not multiplayer.is_server():
		return
	# Wait 5 seconds, then respawn the enemy using RPC
	await get_tree().create_timer(5.0).timeout
	if GameManager.is_network_active:
		sync_spawn_enemy.rpc(enemy_name, pos, patrol_range)

@rpc("any_peer", "call_local", "reliable")
func sync_spawn_enemy(enemy_name: String, pos: Vector2, patrol_range: float) -> void:
	var enemy_script = preload("res://scripts/enemy.gd")
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

@rpc("any_peer", "call_local", "reliable")
func sync_level_finished() -> void:
	GameManager.sync_pause(true) # Pause player physics/inputs
	
	# Show level finished screen
	if not $UI.has_node("FinishedScreen"):
		var finished_script = preload("res://scripts/finished_screen.gd")
		var finished_screen = Control.new()
		finished_screen.set_script(finished_script)
		finished_screen.name = "FinishedScreen"
		$UI.add_child(finished_screen)
	else:
		$UI/FinishedScreen.show()
