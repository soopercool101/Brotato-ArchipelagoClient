extends Node
class_name ApWebSocketConnectionFactory

const LOG_NAME = "RampagingHippy-Archipelago/ap_websocket_connection_factory"
const CONNECT_TIMEOUT = 5.0 # 5 8/3 # Seconds

var _waiting_to_connect_to_server = false


signal _stop_waiting_to_connect(success)

func _init():
	pause_mode = Node.PAUSE_MODE_PROCESS

func try_create_connection(url: String) -> Dictionary:
	## Configure and establish a WebSocket connection to a server.
	##
	## Creates a WebSocketClient with settings configured for an Archipelago connection,
	## then tries to connect to the given URL with the client.
	##
	## This function does no validation of the input URL, and will try to blindly 
	## connect.
	##
	## Returns a dictionary with three keys:
	##	* "success" (bool): Indicates whether the connection was successfull.
	##	* "client": (WebSocketClient): The WebSocket client used to make the conneciton.
	##	* "peer': (WebSocketPeer): The peer on the client, configured for Archipelago.
	##
	##	If "success" is false (the connection failed), the latter two keys will be null.
	ModLoaderLog.debug("Attempting to connect to %s." % url, LOG_NAME)
	var client = WebSocketClient.new()
	client.connect("connection_established", self, "_on_connection_established")
	client.connect("connection_error", self, "_on_connection_error")
	# Increase max buffer size to accommodate AP's larger payloads. The defaults are:
	#   - Max in/out buffer = 64 KB
	#   - Max in/out packets = 1024 
	# We increase the in buffer to 256 KB because some messages we receive are too large
	# for 64. The other defaults are fine though.
	client.set_buffers(256, 1024, 64, 1024)

	# Create a timeout to trigger the done waiting signal if we take too long
	_waiting_to_connect_to_server = true
	timeout()
	client.connect_to_url(url)
	
	# The signal is emitted by the first to complete of the following:
	#	* The "connection_established" signal handler.
	#	* The "connection_error" signal handler.
	#	* The timeout.
	var success = yield(self, "_stop_waiting_to_connect")
	
	# Tell the timeout function not to emit the signal a second time if we succeeded.
	_waiting_to_connect_to_server = false

	var peer = null
	if success:
		peer = client.get_peer(1)
		peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	else:
		client = null

	return {"success": success, "client": client, "peer": peer}

func timeout():
	yield(get_tree().create_timer(CONNECT_TIMEOUT), "timeout")
	if _waiting_to_connect_to_server:
		# We took to long, stop waiting and tell the called we failed.
		_waiting_to_connect_to_server = false
		ModLoaderLog.debug("Timed out trying to connect.", LOG_NAME)
		emit_signal("_stop_waiting_to_connect", false)

func _on_connection_established(_proto = ""):
	# We succeeded, stop waiting and tell the caller.
	ModLoaderLog.debug("Successfully connected.", LOG_NAME)
	emit_signal("_stop_waiting_to_connect", true)

func _on_connection_error():
	# We failed, stop waiting and tell the caller.
	ModLoaderLog.debug("Error connecting.", LOG_NAME)
	emit_signal("_stop_waiting_to_connect", false)
