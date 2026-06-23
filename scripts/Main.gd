extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/ButtonHBox/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/ButtonHBox/JoinButton
@onready var ip_input: LineEdit = $CenterContainer/VBoxContainer/IPInput
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var peer = ENetMultiplayerPeer.new()
var is_network_active: bool = false

func _ready() -> void:
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	# Connect ENet signals safely
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
	if not multiplayer.connection_failed.is_connected(_on_connected_fail):
		multiplayer.connection_failed.connect(_on_connected_fail)

func _on_host_pressed() -> void:
	var err = peer.create_server(52000, 1) # Port 52000, 1 client max (2 players total)
	if err != OK:
		status_label.text = "Failed to Host: %s" % error_string(err)
		return
	
	multiplayer.multiplayer_peer = peer
	is_network_active = true
	status_label.text = "Hosting on port 52000... Waiting for player 2"
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Please enter a valid IP address"
		return
	
	var err = peer.create_client(ip, 52000)
	if err != OK:
		status_label.text = "Failed to Connect: %s" % error_string(err)
		return
		
	multiplayer.multiplayer_peer = peer
	is_network_active = true
	status_label.text = "Connecting to %s..." % ip
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false

# ENet Callbacks
func _on_peer_connected(_id: int) -> void:
	status_label.text = "Peer connected! Starting game..."
	if multiplayer.is_server():
		# Wait a short moment to ensure connection is solid, then switch scene
		await get_tree().create_timer(1.0).timeout
		start_game.rpc()

@rpc("any_peer", "call_local", "reliable")
func start_game() -> void:
	get_tree().change_scene_to_file("res://Level1.tscn")

func _on_connected_ok() -> void:
	status_label.text = "Connected to host!"

func _on_connected_fail() -> void:
	status_label.text = "Connection failed. Resetting..."
	reset_lobby()

func _on_peer_disconnected(_id: int) -> void:
	status_label.text = "Peer disconnected."
	reset_lobby()

func reset_lobby() -> void:
	multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	is_network_active = false
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
