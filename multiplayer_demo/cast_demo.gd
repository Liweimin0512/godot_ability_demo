extends Node
## Hosts the cast protocol or displays snapshots from the host on a separate peer.

const CastRules = preload("cast_rules.gd")
const CastArena = preload("cast_arena.gd")
const ARENA_SCENE: PackedScene = preload("cast_arena.tscn")
const HOST_ID: int = 1
const LOCAL_ADDRESS: String = "127.0.0.1"
const RECEIPT_LIMIT: int = 32

var _is_host: bool
var _verify: bool
var _verify_reconnect: bool
var _verify_failure: String
var _verify_actors: bool
var _port: int
var _arena: CastArena
var _owner_by_peer: Dictionary[int, int] = {}
var _selected_target: int = CastArena.HOST_ACTOR
var _client_id: int = 0
var _session: int = 0
var _request_id: int = 0
var _next_request_id: int = 0
var _version: int = 0
var _snapshot: Dictionary = {}
var _ledgers: Dictionary[int, RequestLedger] = {}
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

class RequestLedger extends RefCounted:
	var highest_id: int = 0
	var last_cast_id: int = 0
	var entries: Dictionary[int, Dictionary] = {}

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["host", "client"] or not args[1].is_valid_int():
		_fail("Expected host or client followed by a UDP port")
		return
	_is_host = args[0] == "host"
	_verify_reconnect = args.has("--verify-reconnect")
	_verify_actors = args.has("--verify-actors")
	if args.size() >= 4 and args[2] == "--verify-failure":
		_verify_failure = args[3]
	_verify = args.has("--verify") or _verify_reconnect or _verify_actors or not _verify_failure.is_empty()
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
	_arena = ARENA_SCENE.instantiate() as CastArena
	add_child(_arena)
	_arena.settled.connect(_on_cast_settled)
	_owner_by_peer[HOST_ID] = CastArena.HOST_ACTOR
	_ledgers[HOST_ID] = RequestLedger.new()
	_selected_target = CastArena.CLIENT_ACTOR
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.multiplayer_peer = peer
	print("HOST_LISTENING")

func _process(_delta: float) -> void:
	if _arena == null or _phase not in ["settled", "expired"]:
		return
	var current: Dictionary = _rule_snapshot()
	if _phase == "settled" and _snapshot["status_active"] and not current["status_active"]:
		_publish("expired")
	if not current["cooldown_active"] and not current["status_active"]:
		_publish("ready")

func _unhandled_key_input(event: InputEvent) -> void:
	if _verify:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		if _is_host:
			_submit_request(HOST_ID, _ledgers[HOST_ID].highest_id + 1, CastRules.ABILITY_ID, _selected_target)
		elif _phase not in ["connecting", "disconnected"]:
			_send_new_request(_selected_target)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode in [KEY_1, KEY_2, KEY_3]:
		_selected_target = int(event.keycode - KEY_1) + 1
		if not _snapshot.is_empty():
			_show_snapshot()
	elif not _is_host and event.keycode == KEY_R:
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
	_submit_request(_client_id, request_id, ability_id, target_id)

func _submit_request(peer_id: int, request_id: int, ability_id: StringName, target_id: int) -> void:
	if request_id <= 0 or not _owner_by_peer.has(peer_id):
		return
	var ledger: RequestLedger = _ledgers[peer_id]
	if ledger.entries.has(request_id):
		var entry: Dictionary = ledger.entries[request_id]
		if entry["ability_id"] != ability_id or entry["target_id"] != target_id:
			return
		var receipt: Dictionary = entry["receipt"]
		if receipt["phase"] == "accepted":
			_replayed_windup += 1
		elif receipt["phase"] == "finished":
			_replayed_result += 1
		_reply(peer_id, receipt)
		return
	if request_id <= ledger.highest_id:
		_reply(peer_id, _make_receipt(peer_id, request_id, "rejected", "REQUEST_EXPIRED"))
		return
	ledger.highest_id = request_id
	ledger.entries[request_id] = {"ability_id": ability_id, "target_id": target_id}
	if ledger.entries.size() > RECEIPT_LIMIT:
		for old_id: int in ledger.entries.keys():
			if old_id != ledger.last_cast_id:
				ledger.entries.erase(old_id)
				break
	var reason: String = _arena.try_cast(_owner_by_peer[peer_id], ability_id, target_id)
	if not reason.is_empty():
		_send_receipt(peer_id, request_id, "rejected", reason)
		return
	ledger.last_cast_id = request_id
	_send_receipt(peer_id, request_id, "accepted", "")
	if peer_id == HOST_ID:
		_publish("ready" if _phase == "connecting" else _phase)
		return
	_request_id = request_id
	_settlement = ""
	_accepted += 1
	_arena.inject_failure(_verify_failure, target_id)
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
	if _verify_actors:
		if _next_request_id == 0:
			_send_new_request(CastArena.PRACTICE_TARGET)
		elif _phase == "ready" and _request_id != 0:
			acknowledge_final.rpc_id(HOST_ID, _session, _version)
		return
	if _request_id == 0:
		_send_new_request(CastArena.PRACTICE_TARGET if _verify_failure == "leave" else CastArena.HOST_ACTOR)
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
	var counts: Dictionary = _arena.counters()
	var remote_counts: Dictionary = counts[CastArena.CLIENT_ACTOR]
	var target_counts: Dictionary = counts[CastArena.HOST_ACTOR]
	var report: Dictionary = {
		"snapshot": _snapshot,
		"rules": _rule_snapshot(),
		"accepted": _accepted,
		"replayed_windup": _replayed_windup,
		"replayed_result": _replayed_result,
		"payments": remote_counts["payments"],
		"cooldown_starts": remote_counts["cooldowns"],
		"applications": target_counts["applications"],
		"removals": target_counts["removals"],
		"entity_counters": counts,
		"host_receipt": _last_receipt,
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
	_owner_by_peer[id] = CastArena.CLIENT_ACTOR
	_ledgers[id] = RequestLedger.new()
	_session += 1
	_publish("ready" if _phase == "connecting" else _phase)
	if _verify_actors:
		_submit_request(HOST_ID, 1, CastRules.ABILITY_ID, CastArena.CLIENT_ACTOR)

func _on_peer_disconnected(id: int) -> void:
	if id != _client_id:
		return
	if _verify and _verified:
		get_tree().quit()
		return
	_client_id = 0
	_owner_by_peer.erase(id)
	_ledgers.erase(id)
	var before: Dictionary = _rule_snapshot()
	var windup: bool = _phase == "windup"
	# Clear the request and its replay before cancellation can notify observers.
	_request_id = 0
	_settlement = ""
	if windup:
		_arena.cancel_cast(CastArena.CLIENT_ACTOR)
	_publish("ready" if windup else _phase)
	if _verify_reconnect:
		var counts: Dictionary = _arena.counters()
		_disconnect_checks.append({
			"session": _session, "before": before, "after": _rule_snapshot(),
			"payments": counts[CastArena.CLIENT_ACTOR]["payments"],
			"cooldown_starts": counts[CastArena.CLIENT_ACTOR]["cooldowns"],
			"applications": counts[CastArena.HOST_ACTOR]["applications"],
		})
	elif _verify:
		_fail("Client disconnected before acknowledging its final snapshot")

func _on_cast_settled(actor_id: int, result: TargetedStatusAbilityDefinition.Result) -> void:
	var outcome: String = str(TargetedStatusAbilityDefinition.Result.keys()[result])
	if actor_id == CastArena.HOST_ACTOR:
		_send_receipt(HOST_ID, _ledgers[HOST_ID].last_cast_id, "finished", outcome)
		_publish(_phase)
		return
	if result == TargetedStatusAbilityDefinition.Result.CANCELLED:
		_cancelled_casts += 1
	if _client_id == 0:
		return
	_settlement = outcome
	_send_receipt(_client_id, _request_id, "finished", _settlement)
	_publish("settled")

func _publish(phase: String) -> void:
	_phase = phase
	_version += 1
	_snapshot = _rule_snapshot()
	_snapshot["entities"] = _arena.snapshot()
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
	var outcome: String = str(_last_receipt.get("result", ""))
	var actor_id: int = CastArena.HOST_ACTOR if _is_host else CastArena.CLIENT_ACTOR
	var actor: Dictionary = _snapshot["entities"][actor_id]
	var target: Dictionary = _snapshot["entities"].get(_selected_target, {})
	_display.text = "%s\n1/2/3 to select target   |   Enter to cast\nTarget: %d\nRequest %d  |  %s %s\nMana: %s\nCooldown: %s\nTarget mark: %s" % [
		("Host  |  waiting for client" if _client_id == 0 else "Host") if _is_host
			else "Client  |  R to disconnect",
		_selected_target, int(_last_receipt.get("request_id", 0)), str(_last_receipt.get("phase", "")),
		outcome, actor["mana"], "active" if actor["cooldown_active"] else "ready",
		"active" if target.get("status_active", false) else "absent",
	]

func _send_new_request(target_id: int = CastArena.HOST_ACTOR) -> void:
	_next_request_id += 1
	_send_request_for_session(_session, _next_request_id, target_id)

func _send_request_for_session(session: int, request_id: int, target_id: int = CastArena.HOST_ACTOR) -> void:
	request_cast.rpc_id(HOST_ID, session, request_id, CastRules.ABILITY_ID, target_id)

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

func _rule_snapshot() -> Dictionary:
	var entities: Dictionary = _arena.snapshot()
	var remote: Dictionary = entities[CastArena.CLIENT_ACTOR]
	return {"mana": remote["mana"], "cast_active": remote["cast_active"],
		"cooldown_active": remote["cooldown_active"], "status_active": entities[CastArena.HOST_ACTOR]["status_active"]}

func _make_receipt(peer_id: int, request_id: int, phase: String, result: String) -> Dictionary:
	return {"session": 0 if peer_id == HOST_ID else _session, "request_id": request_id, "phase": phase, "result": result}

func _send_receipt(peer_id: int, request_id: int, phase: String, result: String) -> void:
	var receipt: Dictionary = _make_receipt(peer_id, request_id, phase, result)
	_ledgers[peer_id].entries[request_id]["receipt"] = receipt
	_reply(peer_id, receipt)

func _reply(peer_id: int, receipt: Dictionary) -> void:
	if peer_id != HOST_ID:
		receive_receipt.rpc_id(peer_id, receipt)
	else:
		_last_receipt = receipt
		if not _snapshot.is_empty():
			_show_snapshot()

func _count_rule_nodes(node: Node) -> int:
	var count: int = int(node is GameplayAbilityComponent or node is GameplayVitalAttributeComponent
		or node is GameplayStatusComponent)
	for child: Node in node.get_children():
		count += _count_rule_nodes(child)
	return count

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
