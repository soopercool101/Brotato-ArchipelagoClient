extends MarginContainer

signal back_button_pressed

onready var _connect_button: Button = $"VBoxContainer/ConnectButton"
onready var _disconnect_button: Button = $"VBoxContainer/DisconnectButton"
onready var _connect_status_label: Label = $"VBoxContainer/ConnectStatusLabel"
onready var _connect_error_label: Label = $"VBoxContainer/ConnectionErrorLabel"
onready var _host_edit: LineEdit = $"VBoxContainer/CenterContainer/GridContainer/HostEdit"
onready var _player_edit: LineEdit = $"VBoxContainer/CenterContainer/GridContainer/PlayerEdit"
onready var _password_edit: LineEdit = $"VBoxContainer/CenterContainer/GridContainer/PasswordEdit"

onready var _ap_session

func init():
	# Needed to make the scene switch in title_screen_menus happy.
	pass

func _ready():
	var mod_node = get_node("/root/ModLoader/RampagingHippy-Archipelago")
	_ap_session = mod_node.ap_player_session
	_ap_session.connect("connection_state_changed", self, "_on_connection_state_changed")

#func _input(_event):
#	if get_tree().current_scene.name == self.name && Input.is_key_pressed(KEY_ENTER):
#		_on_ConnectButton_pressed()

func _on_connection_state_changed(new_state: int, error: int = 0):
	# See ConnectState enum in ap_player_session.gd
	match new_state:
		0:
			# Disconnected
			_connect_status_label.text = "Disconnected"
		1:
			# Connecting
			_connect_status_label.text = "Connecting"
		2:
			# Disconnecting
			_connect_status_label.text = "Disconnecting"
		3:
			# Connected to server
			_connect_status_label.text = "Connected to server"
		4:
			# Connected to multiworld
			_connect_status_label.text = "Connected to multiworld"

	# Allow connecting if disconnected or connected to the server but not the multiworld
	_connect_button.disabled = not(
		new_state == ApPlayerSession.ConnectState.DISCONNECTED or
		new_state == ApPlayerSession.ConnectState.CONNECTED_TO_MULTIWORLD
	)
	if _connect_button.disabled and _connect_button.has_focus():
		# Disabled buttons having focus look bad and don't make sense.
		_connect_button.release_focus()

	# Allow disconnecting if connected to the server and/or multiworld
	_disconnect_button.disabled = not(
		new_state == ApPlayerSession.ConnectState.CONNECTED_TO_SERVER or
		new_state == ApPlayerSession.ConnectState.CONNECTED_TO_MULTIWORLD
	)

	if _disconnect_button.disabled and _disconnect_button.has_focus():
		_disconnect_button.release_focus()

	if error != 0:
		_set_error(error)
	else:
		_clear_error()

func _set_error(error_reason: int):
	# See ConnectResult enum in ap_player_session.gd
	var error_text: String
	match error_reason:
		1:
			error_text = "Failed to connect to the server"
		2:
			error_text = "Need to set player name before connecting"
		3:
			error_text = "Client needs to set game name before connecting"
		4:
			error_text = "Invalid server name"
		5:
			error_text = "AP: Invalid player name"
		6:
			error_text = "AP: Invalid game"
		7:
			error_text = "AP: Incompatible versions"
		8:
			error_text = "AP: Invalid or missing password"
		9:
			error_text = "AP: Invalid items handling"
		9:
			error_text = "AP: Failed to connect (unknown error)"
		_:
			error_text = "Unknown error"

	_connect_error_label.visible = true
	_connect_error_label.text = error_text

func _clear_error():
	_connect_error_label.visible = false
	_connect_error_label.text = ""

func _on_ConnectButton_pressed():
	_ap_session.server = _host_edit.text
	_ap_session.player = _player_edit.text

	# _connect_status_label.text = "Connecting"
	# _connect_error_label.visible = false
	# _connect_button.visible = false
	# _disconnect_button.visible = true

	# Fire and forget this coroutine call, signal handlers will take care of the rest.
	_ap_session.connect_to_multiworld(_password_edit.text)

func _on_BackButton_pressed():
	emit_signal("back_button_pressed")

func _on_DisconnectButton_pressed():
	_ap_session.disconnect_from_multiworld()
