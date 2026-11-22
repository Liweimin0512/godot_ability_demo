extends Node
## Hosts the cast protocol or displays snapshots from the host on a separate peer.

const CastRules = preload("cast_rules.gd")
const HOST_ID: int = 1
const LOCAL_ADDRESS: String = "127.0.0.1"
const RECEIPT_LIMIT: int = 32

var _is_host: bool
var _verify: bool
var _verify_reconnect: bool
var _verify_failure: String
var _port: int
var _rules: CastRules
var _client_id: int = 0
var _session: int = 0
var _request_id: int = 0
var _next_request_id: int = 0
var _highest_request_id: int = 0
var _version: int = 0
var _snapshot: Dictionary = {}
var _requests: Dictionary[int, Dictionary] = {}
var _received: Dictionary[int, Dictionary] = {}
var _last_receipt: Dictionary = {}
var _receipt_log: Array[Dictionary] = []
var _ignored_receipts: int = 0
var _phase: String = "connecting"
var _settlement: String = ""
var _accepted: int = 0
var _replayed_windup: int = 0
var _replayed_result: int = 0
var _ignored_snapshots: int = 0
var _displayed_snapshots: Array[Dictionary] = []
var _verified: bool = false
var _stale_requests: int = 0
var _cancelled_casts: int = 0
var _disconnect_checks: Array[Dictionary] = []
var _cleared_displays: int = 0
var _previous_session: int = 0

@onready var _display: Label = $Display

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["host", "client"] or not args[1].is_valid_int():
		_fail("Expected host or client followed by a UDP port")
		return
	_is_host = args[0] == "host"
	_verify_reconnect = args.has("--verify-reconnect")
	if args.size() >= 4 and args[2] == "--verify-failure":
		_verify_failure = args[3]
	_verify = args.has("--verify") or _verify_reconnect or not _verify_failure.is_empty()
	_port = args[1].to_int()
	if not _is_host:
		multiplayer.connection_failed.connect(_on_connection_lost)
		multiplayer.server_disconnected.connect(_on_connection_lost)
		_connect_client()
		return
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(LOCAL_ADDRESS)
	var error: Error = peer.create_server(_port, 1)
	if error != OK:
		_fail("Could not open peer: %s" % error_string(error))
		return
	_rules = CastRules.new()
	add_child(_rules)
	_rules.settled.connect(_on_cast_settled)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.multiplayer_peer = peer
	print("HOST_LISTENING")

func _process(_delta: float) -> void:
	if _rules == null or _phase not in ["settled", "expired"]:
		return
	var current: Dictionary = _rules.snapshot()
	if _phase == "settled" and _snapshot["status_active"] and not current["status_active"]:
		_publish("expired")
	if not current["cooldown_active"] and not current["status_active"]:
		_publish("ready")

func _unhandled_key_input(event: InputEvent) -> void:
	if _is_host or _verify:
		return
	if event.is_action_pressed("ui_accept") and _phase == "ready":
		_send_new_request()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _phase == "disconnected":
			_connect_client()
		else:
			_disconnect_client()

@rpc("any_peer", "call_remote", "reliable")
func request_cast(session: int, request_id: int, ability_id: StringName, target_id: int) -> void:
	if not _is_host or _client_id == 0 or multiplayer.get_remote_sender_id() != _client_id:
		return
	if session != _session:
		_stale_requests += 1
		return
	if request_id <= 0:
		return
	if _requests.has(request_id):
		var entry: Dictionary = _requests[request_id]
		if entry["ability_id"] != ability_id or entry["target_id"] != target_id:
			return
		var receipt: Dictionary = entry["receipt"]
		if receipt["phase"] == "accepted":
			_replayed_windup += 1
		elif receipt["phase"] == "finished":
			_replayed_result += 1
		receive_receipt.rpc_id(_client_id, receipt)
		return
	if request_id <= _highest_request_id:
		receive_receipt.rpc_id(_client_id, _make_receipt(request_id, "rejected", "REQUEST_EXPIRED"))
		return
	_highest_request_id = request_id
	_requests[request_id] = {"ability_id": ability_id, "target_id": target_id}
	if _requests.size() > RECEIPT_LIMIT:
		for old_id: int in _requests.keys():
			if old_id != _request_id:
				_requests.erase(old_id)
				break
	var reason: String = _activation_rejection(ability_id, target_id)
	if not reason.is_empty():
		_send_receipt(request_id, "rejected", reason)
		return
	if not _rules.activate():
		_send_receipt(request_id, "rejected", "REJECTED")
		return
	_request_id = request_id
	_settlement = ""
	_accepted += 1
	_rules.inject_failure(_verify_failure)
	_send_receipt(request_id, "accepted", "")
	_publish("windup")

@rpc("authority", "call_remote", "reliable")
func receive_receipt(receipt: Dictionary) -> void:
	if receipt["session"] != _session or _phase in ["connecting", "disconnected"]:
		return
	if _verify:
		_receipt_log.append(receipt)
	var id: int = receipt["request_id"]
	if _received.has(id) and (_received[id] == receipt or _received[id]["phase"] != "accepted"):
		_ignored_receipts += 1
		return
	_received[id] = receipt
	if _received.size() > RECEIPT_LIMIT:
		_received.erase(_received.keys()[0])
	_last_receipt = receipt
	_show_snapshot()

@rpc("authority", "call_remote", "reliable")
func receive_snapshot(data: Dictionary) -> void:
	var incoming_session: int = data["session"]
	var incoming_version: int = data["version"]
	if incoming_session < _session or incoming_version <= _version \
		or (_phase == "connecting" and incoming_session == _session) or _phase == "disconnected":
		_ignored_snapshots += 1
		return
	_session = incoming_session
	_version = incoming_version
	_request_id = data["request_id"]
	_phase = data["phase"]
	_snapshot = data
	_show_snapshot()
	if not _verify:
		return
	_displayed_snapshots.append(data)
	if _verify_reconnect:
		_exercise_reconnect()
		return
	if _request_id == 0:
		_send_new_request()
	elif _verify_failure.is_empty() and _phase in ["windup", "settled"]:
		_send_request_for_session(_session, _request_id)
		_send_new_request()
	elif _phase == "ready":
		acknowledge_final.rpc_id(HOST_ID, _session, _version)

@rpc("any_peer", "call_remote", "reliable")
func acknowledge_final(session: int, version: int) -> void:
	if not _verify or not _is_host or _client_id == 0 or multiplayer.get_remote_sender_id() != _client_id:
		return
	if _phase != "ready" or session != _session or version != _version \
		or (_verify_reconnect and _session != 3) or (not _verify_reconnect and _settlement.is_empty()):
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
		"cancelled_casts": _cancelled_casts,
		"stale_requests": _stale_requests,
		"disconnects": _disconnect_checks,
	}
	print("HOST_REPORT ", JSON.stringify(report))
	confirm_final.rpc_id(_client_id)

@rpc("authority", "call_remote", "reliable")
func confirm_final() -> void:
	print("CLIENT_REPORT ", JSON.stringify({
		"snapshot": _snapshot,
		"displayed_snapshots": _displayed_snapshots,
		"ignored_snapshots": _ignored_snapshots,
		"ignored_receipts": _ignored_receipts,
		"receipts": _receipt_log,
		"rules_nodes": _count_rule_nodes(get_tree().root),
		"cleared_displays": _cleared_displays,
	}))
	get_tree().quit()

func _on_peer_connected(id: int) -> void:
	_client_id = id
	_session += 1
	_publish("ready" if _phase == "connecting" else _phase)

func _on_peer_disconnected(id: int) -> void:
	if id != _client_id:
		return
	if _verify and _verified:
		get_tree().quit()
		return
	_client_id = 0
	var before: Dictionary = _rules.snapshot()
	var windup: bool = _phase == "windup"
	# Clear the request and its replay before cancellation can notify observers.
	_request_id = 0
	_highest_request_id = 0
	_requests.clear()
	_settlement = ""
	if windup:
		_rules.cancel_pending_cast()
	_publish("ready" if windup else _phase)
	if _verify_reconnect:
		_disconnect_checks.append({
			"session": _session, "before": before, "after": _rules.snapshot(),
			"payments": _rules.payments, "cooldown_starts": _rules.cooldown_starts,
			"applications": _rules.applications,
		})
	elif _verify:
		_fail("Client disconnected before acknowledging its final snapshot")

func _on_cast_settled(result: TargetedStatusAbilityDefinition.Result) -> void:
	if result == TargetedStatusAbilityDefinition.Result.CANCELLED:
		_cancelled_casts += 1
	if _client_id == 0:
		return
	_settlement = str(TargetedStatusAbilityDefinition.Result.keys()[result])
	_send_receipt(_request_id, "finished", _settlement)
	_publish("settled")

func _publish(phase: String) -> void:
	_phase = phase
	_version += 1
	_snapshot = _rules.snapshot()
	_snapshot.merge({
		"version": _version,
		"session": _session,
		"request_id": _request_id,
		"phase": _phase,
	})
	_show_snapshot()
	if _client_id != 0:
		receive_snapshot.rpc_id(_client_id, _snapshot)

func _show_snapshot() -> void:
	var outcome: String = _settlement if _is_host else str(_last_receipt.get("result", ""))
	_display.text = "%s\nRequest %d  |  %s %s\nMana: %s\nCooldown: %s\nTarget mark: %s" % [
		("Host  |  waiting for client" if _client_id == 0 else "Host") if _is_host
			else "Client  |  Enter or Space to cast  |  R to disconnect",
		_request_id if _is_host else int(_last_receipt.get("request_id", 0)), _phase, outcome, _snapshot["mana"],
		"active" if _snapshot["cooldown_active"] else "ready",
		"active" if _snapshot["status_active"] else "absent",
	]

func _send_new_request() -> void:
	_next_request_id += 1
	_send_request_for_session(_session, _next_request_id)

func _send_request_for_session(session: int, request_id: int) -> void:
	request_cast.rpc_id(HOST_ID, session, request_id, CastRules.ABILITY_ID, CastRules.TARGET_ID)

func _connect_client() -> void:
	_phase = "connecting"
	_display.text = "Connecting..."
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(LOCAL_ADDRESS, _port)
	if error != OK:
		_on_connection_lost()
		return
	multiplayer.multiplayer_peer = peer

func _disconnect_client() -> void:
	_phase = "disconnected"
	_snapshot = {}
	_request_id = 0
	_next_request_id = 0
	_received.clear()
	_last_receipt = {}
	_display.text = "Disconnected  |  R to reconnect"
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null

func _on_connection_lost() -> void:
	if _phase == "disconnected":
		return
	_disconnect_client.call_deferred()
	if _verify:
		_fail("Unexpected connection loss")

func _exercise_reconnect() -> void:
	if _session == 1 and _phase == "ready":
		_send_new_request()
	elif (_session == 1 and _phase == "windup") or (_session == 2 and _phase == "settled"):
		_previous_session = _session
		_disconnect_client.call_deferred()
		var delay: float = 1.25 if _session == 1 else 0.15
		get_tree().create_timer(delay).timeout.connect(_resume_verification)
	elif _session == 2 and _phase == "ready":
		_send_request_for_session(_previous_session, 1)
		_send_new_request()
	elif _session == 3 and _phase == "ready":
		_send_request_for_session(_previous_session, 1)
		acknowledge_final.rpc_id(HOST_ID, _session, _version)

func _resume_verification() -> void:
	if _phase != "disconnected" or not _snapshot.is_empty() or not _display.text.begins_with("Disconnected"):
		_fail("Disconnect left a snapshot or windup presentation")
		return
	_cleared_displays += 1
	_connect_client()

func _activation_rejection(ability_id: StringName, target_id: int) -> String:
	if ability_id != CastRules.ABILITY_ID:
		return "UNKNOWN_ABILITY"
	if target_id != CastRules.TARGET_ID:
		return "TARGET_INVALID"
	var state: Dictionary = _rules.snapshot()
	if state["cast_active"]:
		return "BUSY"
	if state["cooldown_active"]:
		return "COOLDOWN"
	return ""

func _make_receipt(request_id: int, phase: String, result: String) -> Dictionary:
	return {"session": _session, "request_id": request_id, "phase": phase, "result": result}

func _send_receipt(request_id: int, phase: String, result: String) -> void:
	var receipt: Dictionary = _make_receipt(request_id, phase, result)
	_requests[request_id]["receipt"] = receipt
	receive_receipt.rpc_id(_client_id, receipt)

func _count_rule_nodes(node: Node) -> int:
	var count: int = int(node is GameplayAbilityComponent or node is GameplayVitalAttributeComponent
		or node is GameplayStatusComponent)
	for child: Node in node.get_children():
		count += _count_rule_nodes(child)
	return count

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
