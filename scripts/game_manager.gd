extends Node

var is_game_paused: bool = false
var is_network_active: bool = true
var is_reloading: bool = false

var player1_weapon_lines: Array = []
var player2_weapon_lines: Array = []

var checkpoint_active: bool = false
var checkpoint_p1_pos: Vector2 = Vector2.ZERO
var checkpoint_p2_pos: Vector2 = Vector2.ZERO

var level_flags: Dictionary = {
	"mid_level_1_done": false,
	"mid_level_2_done": false,
	"mid_level_3_done": false,
	"mid_level_4_done": false,
	"mid_level_5_done": false
}

var levels: Array[String] = [
	"res://scenes/levels/Level_1.tscn",
	"res://scenes/levels/Level2.tscn"
]

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

@rpc("any_peer", "call_local", "reliable")
func sync_pause(paused: bool) -> void:
	is_game_paused = paused
	if paused:
		var tree = get_tree()
		var current_scene = tree.current_scene if tree else null
		if current_scene:
			var p1 = current_scene.get_node_or_null("Player1")
			if is_instance_valid(p1):
				p1.velocity = Vector2.ZERO
			var p2 = current_scene.get_node_or_null("Player2")
			if is_instance_valid(p2):
				p2.velocity = Vector2.ZERO

@rpc("any_peer", "call_local", "reliable")
func sync_global_death() -> void:
	if is_reloading or not is_inside_tree() or get_tree() == null:
		return
	is_reloading = true
	
	sync_pause(true)
	
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
			enemy.set_process(false)
			
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			player.set_physics_process(false)
			player.set_process(false)
			
	for letter in get_tree().get_nodes_in_group("letters"):
		if is_instance_valid(letter):
			letter.set_physics_process(false)
			letter.set_process(false)
			
	await get_tree().create_timer(0.2).timeout
	
	is_reloading = false
	is_game_paused = false
	player1_weapon_lines.clear()
	player2_weapon_lines.clear()
	var tree = get_tree()
	if tree and tree.current_scene:
		var current_path = tree.current_scene.scene_file_path
		tree.call_deferred("change_scene_to_file", current_path)

func get_next_level() -> String:
	var tree = get_tree()
	var current_scene = tree.current_scene if tree else null
	if not current_scene:
		return ""
	var current_path = current_scene.scene_file_path
	var idx = levels.find(current_path)
	if idx != -1 and idx + 1 < levels.size():
		return levels[idx + 1]
	return ""

@rpc("any_peer", "call_local", "reliable")
func sync_set_flag(flag_name: String, value: bool) -> void:
	level_flags[flag_name] = value

@rpc("any_peer", "call_local", "reliable")
func sync_load_level(level_path: String) -> void:
	is_game_paused = false
	checkpoint_active = false
	get_tree().change_scene_to_file(level_path)

func load_next_level() -> void:
	var next = get_next_level()
	if next != "":
		if multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			if multiplayer.is_server():
				sync_load_level.rpc(next)
		else:
			sync_load_level(next)
