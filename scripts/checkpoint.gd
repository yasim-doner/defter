extends Area2D
class_name Checkpoint

@onready var marker_p1: Marker2D = $MarkerP1
@onready var marker_p2: Marker2D = $MarkerP2

var is_active: bool = false
var players_inside: Array = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("players") and not is_active:
		if not players_inside.has(body):
			players_inside.append(body)
			
		var total_players = get_tree().get_nodes_in_group("players").size()
		if players_inside.size() >= total_players and total_players > 0:
			activate_checkpoint()

func _on_body_exited(body: Node2D) -> void:
	pass # Do not decrease the counter on exit, it resets on death when scene reloads

func activate_checkpoint() -> void:
	is_active = true
	if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		sync_activate_checkpoint.rpc()
	else:
		_apply_checkpoint()

@rpc("any_peer", "call_local", "reliable")
func sync_activate_checkpoint() -> void:
	is_active = true
	_apply_checkpoint()

func _apply_checkpoint() -> void:
	if marker_p1 and marker_p2:
		GameManager.checkpoint_active = true
		GameManager.checkpoint_p1_pos = marker_p1.global_position
		GameManager.checkpoint_p2_pos = marker_p2.global_position

	for player in get_tree().get_nodes_in_group("players"):
		if player.get("player_id") == 1 and marker_p1:
			player.spawn_position = marker_p1.global_position
		elif player.get("player_id") == 2 and marker_p2:
			player.spawn_position = marker_p2.global_position
