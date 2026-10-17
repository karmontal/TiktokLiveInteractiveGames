extends Node
## Receives LiveBridge events over WebSocket and re-emits them as signals.
## Bridge address: env LIVEBRIDGE_WS / LIVEBRIDGE_TOKEN, or user args
## --bridge=ws://host:port/ws --token=... (defaults: ws://127.0.0.1:8765/ws, "test").
## In debug builds the number keys 1-8 inject fake events (see _unhandled_input).

signal event_received(ev: Dictionary)
signal connection_changed(connected: bool)

const RETRY_S := 2.0
const CONTROL_TYPES := ["hello", "ping"]

var url := ""
var connected := false

var _ws := WebSocketPeer.new()
var _retry := 0.0


func _ready() -> void:
	url = _build_url()
	_open()


func inject(ev: Dictionary) -> void:
	event_received.emit(ev)


func _build_url() -> String:
	var base := OS.get_environment("LIVEBRIDGE_WS")
	var token := OS.get_environment("LIVEBRIDGE_TOKEN")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bridge="):
			base = arg.trim_prefix("--bridge=")
		elif arg.begins_with("--token="):
			token = arg.trim_prefix("--token=")
	if base == "":
		base = "ws://127.0.0.1:8765/ws"
	if token == "":
		token = "test"
	return "%s?token=%s" % [base, token.uri_encode()]


func _open() -> void:
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url(url) != OK:
		_retry = RETRY_S


func _process(delta: float) -> void:
	if _retry > 0.0:
		_retry -= delta
		if _retry <= 0.0:
			_open()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				connection_changed.emit(true)
			while _ws.get_available_packet_count() > 0:
				var data = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if data is Dictionary and not (data.get("type", "") in CONTROL_TYPES):
					event_received.emit(data)
		WebSocketPeer.STATE_CLOSED:
			if connected:
				connected = false
				connection_changed.emit(false)
			_retry = RETRY_S


func _unhandled_input(e: InputEvent) -> void:
	if not OS.is_debug_build() or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var n := randi_range(1, 30)
	var user := {"id": "dbg%d" % n, "name": "Tester %d" % n, "avatar": ""}
	match e.keycode:
		KEY_1: inject({"type": "join", "user": user})
		KEY_2: inject({"type": "comment", "user": user, "text": "A"})
		KEY_3: inject({"type": "comment", "user": user, "text": "B"})
		KEY_4: inject({"type": "like", "user": user, "count": 10, "value": 10})
		KEY_5: inject({"type": "follow", "user": user})
		KEY_6: inject({"type": "share", "user": user})
		KEY_7: inject({"type": "gift", "user": user, "count": 1, "value": 1,
				"gift": {"id": 5655, "name": "Rose", "diamonds": 1, "tier": "small"}})
		KEY_8: inject({"type": "gift", "user": user, "count": 1, "value": 299,
				"gift": {"id": 6267, "name": "Corgi", "diamonds": 299, "tier": "large"}})
