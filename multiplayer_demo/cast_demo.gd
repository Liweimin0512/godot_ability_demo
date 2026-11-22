extends Node
## Hosts the cast protocol or displays snapshots from the host on a separate peer.

const CastRules = preload("cast_rules.gd")
const HOST_ID: int = 1
const LOCAL_ADDRESS: String = "127.0.0.1"

var _is_host: bool
var _verify: bool
var _rules: CastRules
var _client_id: int = 0
var _request_id: int = 0
var _version: int = 0
var _snapshot: Dictionary = {}
var _last_result: Dictionary = {}
var _phase: String = "connecting"
var _settlement: String = ""
var _accepted: int = 0
var _replayed_windup: int = 0
var _replayed_result: int = 0
var _ignored_snapshots: int = 0
var _displayed_snapshots: Array[Dictionary] = []
var _verified: bool = false

@onready var _display: Label = $Display

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["host", "client"] or not args[1].is_valid_int():
		_fail("Expected host or client followed by a UDP port")
		return
	_is_host = args[0] == "host"
	_verify = args.has("--verify")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var port: int = args[1].to_int()
	var error: Error
	if _is_host:
		peer.set_bind_ip(LOCAL_ADDRESS)
		error = peer.create_server(port, 1)
	else:
		error = peer.create_client(LOCAL_ADDRESS, port)
	if error != OK:
		_fail("Could not open peer: %s" % error_string(error))
		return
	if _is_host:
		_rules = CastRules.new()
		add_child(_rules)
		_rules.settled.connect(_on_cast_settled)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		multiplayer.connection_failed.connect(func() -> void: _fail("Connection failed"))
		multiplayer.server_disconnected.connect(func() -> void: _fail("Host disconnected"))
	multiplayer.multiplayer_peer = peer
	if _is_host:
		print("HOST_LISTENING")

func _process(_delta: float) -> void:
	if _rules == null or _client_id == 0 or _phase not in ["settled", "expired"]:
		return
	var current: Dictionary = _rules.snapshot()
	if _phase == "settled" and _snapshot["status_active"] and not current["status_active"]:
		_publish("expired")
	if not current["cooldown_active"] and not current["status_active"]:
		_publish("ready")

func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_host and not _verify and event.is_action_pressed("ui_accept") and _phase == "ready":
		_send_new_request()

@rpc("any_peer", "call_remote", "reliable")
func request_cast(request_id: int, ability_id: StringName, target_id: int) -> void:
	if not _is_host or _client_id == 0 or multiplayer.get_remote_sender_id() != _client_id:
		return
	if ability_id != CastRules.ABILITY_ID or target_id != CastRules.TARGET_ID or request_id <= 0:
		return
	if request_id == _request_id:
		if _last_result["phase"] == "windup":
			_replayed_windup += 1
		else:
			_replayed_result += 1
		receive_snapshot.rpc_id(_client_id, _last_result)
		return
	if request_id < _request_id or _phase != "ready":
		return
	_request_id = request_id
	_settlement = ""
	if not _rules.activate():
		_settlement = "REJECTED"
		_publish("ready", true)
		return
	_accepted += 1
	_publish("windup", true)

@rpc("authority", "call_remote", "reliable")
func receive_snapshot(data: Dictionary) -> void:
	var incoming_version: int = data["version"]
	if incoming_version <= _version:
		_ignored_snapshots += 1
		return
	_version = incoming_version
	_request_id = data["request_id"]
	_phase = data["phase"]
	_snapshot = data
	_show_snapshot()
	if not _verify:
		return
	_displayed_snapshots.append(data)
	if _request_id == 0:
		_send_new_request()
	elif _phase in ["windup", "settled"]:
		_send_request()
	elif _phase == "ready":
		acknowledge_final.rpc_id(HOST_ID, _version)

@rpc("any_peer", "call_remote", "reliable")
func acknowledge_final(version: int) -> void:
	if not _verify or not _is_host or _client_id == 0 or multiplayer.get_remote_sender_id() != _client_id:
		return
	if _phase != "ready" or _settlement != "APPLIED" or version != _version:
		_fail("Final acknowledgment must match a completed cast")
		return
	_verified = true
	var report: Dictionary = {
		"snapshot": _snapshot,
		"rules": _rules.snapshot(),
		"accepted": _accepted,
		"replayed_windup": _replayed_windup,
		"replayed_result": _replayed_result,
		"payments": _rules.payments,
		"cooldown_starts": _rules.cooldown_starts,
		"applications": _rules.applications,
		"removals": _rules.removals,
	}
	print("HOST_REPORT ", JSON.stringify(report))
	confirm_final.rpc_id(_client_id)

@rpc("authority", "call_remote", "reliable")
func confirm_final() -> void:
	print("CLIENT_REPORT ", JSON.stringify({
		"snapshot": _snapshot,
		"displayed_snapshots": _displayed_snapshots,
		"ignored_snapshots": _ignored_snapshots,
		"rules_nodes": _count_rule_nodes(get_tree().root),
	}))
	get_tree().quit()

func _on_peer_connected(id: int) -> void:
	if _version != 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_client_id = id
	_publish("ready")

func _on_peer_disconnected(_id: int) -> void:
	if _verify:
		if _verified:
			get_tree().quit()
		else:
			_fail("Client disconnected before acknowledging its final snapshot")
		return
	_client_id = 0
	_display.text = "Client disconnected. Restart the demo to start a new session."

func _on_cast_settled(result: TargetedStatusAbilityDefinition.Result) -> void:
	_settlement = str(TargetedStatusAbilityDefinition.Result.keys()[result])
	_publish("settled", true)

func _publish(phase: String, cache_result: bool = false) -> void:
	_phase = phase
	_version += 1
	_snapshot = _rules.snapshot()
	_snapshot.merge({
		"version": _version,
		"request_id": _request_id,
		"phase": _phase,
		"result": _settlement,
	})
	if cache_result:
		_last_result = _snapshot
	_show_snapshot()
	if _client_id != 0:
		receive_snapshot.rpc_id(_client_id, _snapshot)

func _show_snapshot() -> void:
	_display.text = "%s\nRequest %d  |  %s %s\nMana: %s\nCooldown: %s\nTarget mark: %s" % [
		"Host" if _is_host else "Client  |  Enter or Space to cast",
		_request_id, _phase, _snapshot["result"], _snapshot["mana"],
		"active" if _snapshot["cooldown_active"] else "ready",
		"active" if _snapshot["status_active"] else "absent",
	]

func _send_new_request() -> void:
	_request_id += 1
	_send_request()

func _send_request() -> void:
	request_cast.rpc_id(HOST_ID, _request_id, CastRules.ABILITY_ID, CastRules.TARGET_ID)

func _count_rule_nodes(node: Node) -> int:
	var count: int = int(node is GameplayAbilityComponent or node is GameplayVitalAttributeComponent
		or node is GameplayStatusComponent)
	for child: Node in node.get_children():
		count += _count_rule_nodes(child)
	return count

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
