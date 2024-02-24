extends Node
class_name ApWebSocketConnection

enum State {
	STATE_CONNECTING = 0
	STATE_OPEN = 1
	STATE_CLOSING = 2
	STATE_CLOSED = 3
}

# Hard-code mod name to avoid cyclical dependency
const LOG_NAME = "RampagingHippy-Archipelago/ap_websocket_connection"
const _DEFAULT_PORT = 38281

# The client handles connecting to the server, and the peer handles sending/receiving
# data after connecting. We set the peer in the "_on_connection_established" callback,
# and clear it in the "_on_connection_closed" callback.
var _client: WebSocketClient = WebSocketClient.new()
var _peer: WebSocketPeer
var _url: String
var _connection_factory = ApWebSocketConnectionFactory.new()

var connection_state = State.STATE_CLOSED

signal connection_state_changed
signal on_room_info(RoomInfo)
signal on_received_items
signal on_location_info
signal on_room_update
signal on_print_json
signal on_data_package
signal on_bounced
signal on_invalid_packet
signal on_retrieved
signal on_set_reply

signal _stop_waiting_to_connect(success)

func _ready():
	self.add_child(_connection_factory)
	# Connect base signals to get notified of connection open, close, and errors.
	# _client.connect("connection_closed", self, "_on_connection_closed")
	# _client.connect("data_received", self, "_on_data_received")
	# _client.connect("connection_established", self, "_on_connection_established")
	# _client.connect("connection_error", self, "_on_connection_error")
	# # Increase max buffer size to accommodate AP's larger payloads. The defaults are:
	#   - Max in/out buffer = 64 KB
	#   - Max in/out packets = 1024 
	# We increase the in buffer to 256 KB because some messages we receive are too large
	# for 64. The other defaults are fine though.
	# _client.set_buffers(256, 1024, 64, 1024)
	
	# Always process so we don't disconnect if the game is paused for too long.
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(false)
	
# Public API
func connect_to_server(multiworld_url: String):
	if connection_state == State.STATE_OPEN:
		return
	_set_connection_state(State.STATE_CONNECTING)
	# Try to connect with SSL first. If this doesn't work then the _on_connection_error
	# callback will try again without SSL.
	_url = "ws://%s" % multiworld_url
	ModLoaderLog.info("Connecting to %s" % _url, LOG_NAME)
	var err = _client.connect_to_url(_url)
	if not err:
		# Start processing to poll the connection for data
		set_process(true)

func connect_to_server_new(server: String) -> bool:
	if connection_state == State.STATE_OPEN:
		return true
	_set_connection_state(State.STATE_CONNECTING)

	# Use the default Archipelago port if not included in the URL
	var port_check_pattern = RegEx.new()
	port_check_pattern.compile(":(\\d+)$")
	var server_has_port = port_check_pattern.search(server)
	if not server_has_port:
		server = "%s:%d" % [server, _DEFAULT_PORT]

	# Try to connect with SSL first
	var wss_url = "wss://%s" % [server]
	var wss_connect_state = _connection_factory.try_create_connection(wss_url)
	var wss_connect_result = yield(wss_connect_state, "completed")	

	var connect_info = null
	if not wss_connect_result["success"]:
		# We don't have any info on why the connection failed (thanks Godot), so we
		# assume it was because the server doesn't support SSL. So, try connecting using
		# "ws://" instead.
		ModLoaderLog.info("Connecting with WSS failed, trying WS.", LOG_NAME)
		var ws_url = "ws://%s" % [server]
		var ws_connect_state = _connection_factory.try_create_connection(ws_url)
		var ws_connect_result = yield(ws_connect_state, "completed")
		if ws_connect_result["success"]:
			connect_info = ws_connect_result
			_url = ws_url
	else:
		_url = wss_url

	if connect_info != null:
		_client = connect_info["client"]
		var _status = _client.connect("connection_closed", self, "_on_connection_closed")
		_status = _client.connect("data_received", self, "_on_data_received")
		_peer = connect_info["peer"]
		set_process(true)
		_set_connection_state(State.STATE_OPEN)
	else:
		_set_connection_state(State.STATE_CLOSED)

	return connect_info != null

func connected_to_multiworld() -> bool:
	return connection_state == State.STATE_OPEN
	
func disconnect_from_server():
	if connection_state == State.STATE_CLOSED:
		return
	_set_connection_state(State.STATE_CLOSING)
	# The "connection_closed" signal handler will take care of cleanup
	_client.disconnect_from_host()

func send_connect(game: String, user: String, password: String = "", slot_data: bool = true):
	_send_command({
		"cmd": "Connect", 
		"game": game, 
		"name": user,
		"password": password,
		"uuid": "Godot %s: %s" % [game, user], # TODO: What do we need here? We can't generate an actual UUID in 3.5
		"version": {"major": 0, "minor": 4, "build": 2, "class": "Version"},
		"items_handling": 0b111, # TODO: argument
		"tags": [],
		"slot_data": slot_data
	})

func send_sync():
	_send_command({"cmd": "Sync"})

func send_location_checks(locations: Array):
	_send_command(
		{
			"cmd": "LocationChecks",
			"locations": locations,
		}
	)

# TODO: create_as_hint Enum
func send_location_scouts(locations: Array, create_as_int: int):
	_send_command({
		"cmd": "LocationScouts",
		"locations": locations,
		"create_as_int": create_as_int
	})

func status_update(status: int):
	_send_command({
		"cmd": "StatusUpdate",
		"status": status,
	})

func say(text: String):
	_send_command({
		"cmd": "Say",
		"text": text,
	})

func get_data_package(games: Array):
	_send_command({
		"cmd": "GetDataPackage",
		"games": games,
	})

func bounce(games: Array, slots: Array, tags: Array, data: Dictionary):
	_send_command({
		"cmd": "Bounce",
		"games": games,
		"slots": slots,
		"tags": tags,
		"data": data,
	})

# TODO: Extra custom arguments
func get_value(keys: Array):
	# This is Archipelago's "Get" command, we change the name 
	# since "get" is already taken by "Object.get".
	_send_command({
		"cmd": "Get",
		"keys": keys,
	})

# TODO: DataStorageOperation data type
func set_value(key: String, default, want_reply: bool, operations: Array):
	_send_command({
		"cmd": "Set",
		"key": key,
		"default": default,
		"want_reply": want_reply,
		"operations": operations,
	})

func set_notify(keys: Array):
	_send_command({
		"cmd": "SetNotify",
		"keys": keys,
	})

# WebSocketClient callbacks
func _send_command(args: Dictionary):
	ModLoaderLog.info("Sending %s command" % args["cmd"], LOG_NAME)
	var command_str = JSON.print([args])
	var _result = _peer.put_packet(command_str.to_ascii())

func _on_connection_closed(was_clean = false):
	_set_connection_state(State.STATE_CLOSED)
	ModLoaderLog.info("AP connection closed, clean: %s." % was_clean, LOG_NAME)
	_peer = null
	set_process(false)

func _on_data_received():
	var received_data_str = _peer.get_packet().get_string_from_utf8()
	var received_data = JSON.parse(received_data_str)
	if received_data.result == null:
		ModLoaderLog.error("Failed to parse JSON for %s" % received_data_str, LOG_NAME)
		return
	for command in received_data.result:
		_handle_command(command)

# Internal plumbing
func _set_connection_state(state):
	var state_name = State.keys()[state]
	ModLoaderLog.info("AP connection state changed to: %s." % state_name, LOG_NAME)
	connection_state = state
	emit_signal("connection_state_changed", connection_state)

func _handle_command(command: Dictionary):
	match command["cmd"]:
		"RoomInfo":
			ModLoaderLog.debug("Received RoomInfo cmd.", LOG_NAME)
			emit_signal("on_room_info", command)
		"ConnectionRefused":
			ModLoaderLog.debug("Received ConnectionRefused cmd.", LOG_NAME)
			emit_signal("on_connection_refused", command)
		"Connected":
			ModLoaderLog.debug("Received Connected cmd.", LOG_NAME)
			emit_signal("on_connected", command)
		"ReceivedItems":
			ModLoaderLog.debug("Received ReceivedItems cmd.", LOG_NAME)
			emit_signal("on_received_items", command)
		"LocationInfo":
			ModLoaderLog.debug("Received LocationInfo cmd.", LOG_NAME)
			emit_signal("on_location_info", command)
		"RoomUpdate":
			ModLoaderLog.debug("Received RoomUpdate cmd.", LOG_NAME)
			emit_signal("on_room_update", command)
		"PrintJSON":
			ModLoaderLog.debug("Received PrintJSON cmd.", LOG_NAME)
			emit_signal("on_print_json", command)
		"DataPackage":
			ModLoaderLog.debug("Received DataPackage cmd.", LOG_NAME)
			emit_signal("on_data_package", command)
		"Bounced":
			ModLoaderLog.debug("Received Bounced cmd.", LOG_NAME)
			emit_signal("on_bounced", command)
		"InvalidPacket":
			ModLoaderLog.debug("Received InvalidPacket cmd.", LOG_NAME)
			emit_signal("on_invalid_packet", command)
		"Retrieved":
			ModLoaderLog.debug("Received Retrieved cmd.", LOG_NAME)
			emit_signal("on_retrieved", command)
		"SetReply":
			ModLoaderLog.debug("Received SetReply cmd.", LOG_NAME)
			emit_signal("on_set_reply", command)
		_:
			ModLoaderLog.warning("Received Unknown Command %s" % command["cmd"], LOG_NAME)

func _process(_delta):
	# Only run when the connection the the server is not closed.
	_client.poll()
