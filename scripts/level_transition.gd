extends Area2D

@export var target_scene: PackedScene
@export var hold_required_time: float = 2.0

var players_inside: Array = []
var players_progress: Dictionary = {"Player1": 0.0, "Player2": 0.0}
var prompt_text: String = "Hold E to Leave"

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func get_player_progress(player_name: String) -> float:
	return players_progress.get(player_name, 0.0)

func _process(delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.get("is_game_paused") == true:
		return

	# Only local player updates their progress and sends it
	var local_player = _get_local_player()
	if is_instance_valid(local_player) and players_inside.has(local_player):
		var is_holding = Input.is_action_pressed("interact")
		var player_name = local_player.name
		var current_prog = players_progress.get(player_name, 0.0)
		var new_prog = current_prog
		
		if is_holding:
			new_prog = min(hold_required_time, current_prog + delta)
		else:
			new_prog = max(0.0, current_prog - delta * 2.0)
			
		if current_prog != new_prog:
			players_progress[player_name] = new_prog
			if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				sync_progress.rpc(player_name, new_prog)

	# In singleplayer/multiplayer, calculate prompt text for local player
	if is_instance_valid(local_player) and players_inside.has(local_player):
		var my_prog = players_progress.get(local_player.name, 0.0)
		var total_players = get_tree().get_nodes_in_group("players").size()
		
		if my_prog >= hold_required_time:
			# I am fully loaded!
			if total_players <= 1:
				prompt_text = "Leaving..."
			else:
				# Check other player's progress
				var other_name = "Player2" if local_player.name == "Player1" else "Player1"
				var other_prog = players_progress.get(other_name, 0.0)
				if other_prog >= hold_required_time:
					prompt_text = "Leaving..."
				else:
					prompt_text = "Two players are needed to leave"
		else:
			prompt_text = "Hold E to Leave"

	# Server check for level transition trigger
	var is_server = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server and target_scene:
		var all_players = get_tree().get_nodes_in_group("players")
		if not all_players.is_empty():
			var all_ready = true
			for player in all_players:
				if is_instance_valid(player):
					if players_progress.get(player.name, 0.0) < hold_required_time:
						all_ready = false
						break
			if all_ready:
				# Reset progress values so they don't loop
				for player in all_players:
					players_progress[player.name] = 0.0
					if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
						sync_progress.rpc(player.name, 0.0)
						
				if GameManager:
					if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
						GameManager.sync_load_level.rpc(target_scene.resource_path)
					else:
						GameManager.sync_load_level(target_scene.resource_path)

@rpc("any_peer", "call_local", "reliable")
func sync_progress(player_name: String, progress_val: float) -> void:
	players_progress[player_name] = progress_val
	var tree = get_tree()
	if tree and tree.current_scene:
		var player = tree.current_scene.get_node_or_null(player_name)
		if player and player.has_method("queue_redraw"):
			player.queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		if not players_inside.has(body):
			players_inside.append(body)
			if "active_interactables" in body:
				if not body.active_interactables.has(self):
					body.active_interactables.append(self)
			body.set("active_level_transition", self)
			if body.has_method("is_local") and body.is_local():
				body.set("is_near_level_transition", true)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("players"):
		if players_inside.has(body):
			players_inside.erase(body)
			if "active_interactables" in body:
				body.active_interactables.erase(self)
			body.set("active_level_transition", null)
			if body.has_method("is_local") and body.is_local():
				body.set("is_near_level_transition", false)
			
			# Reset progress for exiting player
			players_progress[body.name] = 0.0
			if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				sync_progress.rpc(body.name, 0.0)
				
			if body.has_method("queue_redraw"):
				body.queue_redraw()

func _get_local_player() -> CharacterBody2D:
	for player in get_tree().get_nodes_in_group("players"):
		if player.has_method("is_local") and player.is_local():
			return player
	return null
