extends Area2D

@export_file("*.tscn") var target_scene: String = ""
@export var set_mid_level_1: bool = false
@export var set_mid_level_2: bool = false
@export var set_mid_level_3: bool = false
@export var set_mid_level_4: bool = false
@export var set_mid_level_5: bool = false

@onready var sprite = $Sprite2D

var players_inside: Array = []
var closed_tex = preload("res://assets/door_closed.png")
var open_tex = preload("res://assets/door_open.png")

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	sprite.texture = closed_tex

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		if not players_inside.has(body):
			players_inside.append(body)
			
		var total_players = get_tree().get_nodes_in_group("players").size()
		
		# Open door if at least 1 player is inside
		if players_inside.size() >= 1:
			sprite.texture = open_tex
			
		# Transition if all players are inside
		if players_inside.size() >= total_players and total_players > 0:
			_transition_level()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("players"):
		if players_inside.has(body):
			players_inside.erase(body)
			
		# Close door if no players are inside
		if players_inside.size() == 0:
			sprite.texture = closed_tex

func _transition_level() -> void:
	var is_server = not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server and target_scene != "":
		if GameManager:
			var flags_to_set = []
			if set_mid_level_1: flags_to_set.append("mid_level_1_done")
			if set_mid_level_2: flags_to_set.append("mid_level_2_done")
			if set_mid_level_3: flags_to_set.append("mid_level_3_done")
			if set_mid_level_4: flags_to_set.append("mid_level_4_done")
			if set_mid_level_5: flags_to_set.append("mid_level_5_done")
			
			for flag in flags_to_set:
				if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
					GameManager.sync_set_flag.rpc(flag, true)
				else:
					GameManager.sync_set_flag(flag, true)
					
			if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				GameManager.sync_load_level.rpc(target_scene)
			else:
				GameManager.sync_load_level(target_scene)
