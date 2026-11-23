extends Node3D
## Hosts RoomLobby, routes controller input and projects authoritative state for both peers.

const Arena = preload("cast_arena.gd")
const Rules = preload("cast_rules.gd")
const Ledger = preload("cast_request_ledger.gd")
const View = preload("lan_view.gd")
const Smoke = preload("lan_smoke.gd")
const ACTOR_SCENE: PackedScene = preload("cast_rules.tscn")
const HOST: int = 1
const WALKABLE: Rect2 = Rect2(1, 1, 26, 18)
const SPEED: float = 5.0
const UPDATE_INTERVAL: float = 0.05
const INPUT_TIMEOUT: float = 0.35
const RECONNECT_SECONDS: float = 30.0

var _hosting: bool
var _smoke: bool
var _probe: Smoke
var _address: String
var _port: int
var _arena: Arena
var _guest_peer: int = 0
var _guest_actor: int = 0
var _next_actor: int = 2
var _session: int = 0
var _owner: int = 0
var _ticket: String = ""
var _join_deadline: float = 0.0
var _guest_direction: Vector2 = Vector2.ZERO
var _steer_ttl: float = 0.0
var _probe_direction: Vector2 = Vector2.ZERO
var _ledgers: Dictionary[int, Ledger] = {}
var _next_request: int = 0
var _version: int = 0
var _snapshot: Dictionary = {}
var _update_elapsed: float = 0.0
var _connection: String = ""
var _smoke_complete: bool = false
var _smoke_departures: int = 0

@onready var _view: View = $LanView

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3 or args[0] not in ["host", "client"] or not args[2].is_valid_int():
		_fail("Expected host/client, bind or host address, and UDP port")
		return
	_hosting = args[0] == "host"
	_address = args[1]
	_port = args[2].to_int()
	_smoke = args.has("--verify-lan")
	if _hosting:
		_host_lobby()
	else:
		if _smoke:
			_probe = Smoke.new(_cast, _set_probe_direction, _reconnect_for_probe, _finish_probe, _fail)
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_lost.bind("Connection failed"))
		multiplayer.server_disconnected.connect(_on_connection_lost.bind("Host disconnected"))
		_connect_lobby()

func _physics_process(delta: float) -> void:
	_update_elapsed += delta
	var should_publish: bool = _update_elapsed >= UPDATE_INTERVAL
	if should_publish:
		_update_elapsed = 0.0
	if _hosting:
		if _arena == null:
			return
		_arena.move_actor(HOST, _input_direction() * SPEED * delta, WALKABLE)
		if _guest_peer != 0:
			_steer_ttl = maxf(0.0, _steer_ttl - delta)
			if _steer_ttl > 0.0:
				_arena.move_actor(_guest_actor, _guest_direction * SPEED * delta, WALKABLE)
		elif _guest_actor != 0:
			_join_deadline -= delta
			if _join_deadline <= 0.0:
				_arena.remove_actor(_guest_actor)
				_guest_actor = 0
				_ticket = ""
				_connection = "Host | waiting for guest"
				_publish(true)
		if should_publish:
			_publish()
	elif should_publish and _owner != 0:
		var direction: Vector2 = _probe_direction if _smoke else _input_direction()
		steer.rpc_id(HOST, _session, direction)

func _unhandled_key_input(event: InputEvent) -> void:
	if _smoke or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action_pressed("ui_accept"):
		_cast()
	elif not _hosting and event.keycode == KEY_R:
		if multiplayer.multiplayer_peer == null:
			_connect_lobby()
		else:
			_disconnect_lobby("Disconnected | press R to reconnect")

@rpc("any_peer", "call_remote", "reliable")
func request_join(ticket: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _hosting or sender <= HOST or _guest_peer != 0:
		return
	if _guest_actor != 0 and ticket != _ticket:
		join_denied.rpc_id(sender)
		return
	if _guest_actor == 0:
		_guest_actor = _next_actor
		_next_actor += 1
		_ticket = Crypto.new().generate_random_bytes(16).hex_encode()
		_spawn_actor(_guest_actor, 2, Vector3(19, 0.15, 10))
	else:
		_arena.set_actor_present(_guest_actor, true)
	_guest_peer = sender
	_session += 1
	_ledgers[_guest_actor] = Ledger.new()
	_connection = "Host | guest connected"
	joined.rpc_id(sender, _session, _guest_actor, _ticket)
	_publish(true)

@rpc("authority", "call_remote", "reliable")
func joined(session: int, actor_id: int, ticket: String) -> void:
	if _hosting or _owner != 0:
		return
	_session = session
	_owner = actor_id
	_ticket = ticket
	_connection = "Guest | connected to %s:%d" % [_address, _port]

@rpc("authority", "call_remote", "reliable")
func join_denied() -> void:
	_disconnect_lobby("Slot reserved for the previous guest | retry with R")
	if _smoke:
		_fail("Rejoin rejected")

@rpc("any_peer", "call_remote", "unreliable_ordered")
func steer(session: int, direction: Vector2) -> void:
	if not _is_current_guest(session) or not direction.is_finite():
		return
	_guest_direction = direction.limit_length(1.0)
	_steer_ttl = INPUT_TIMEOUT

@rpc("any_peer", "call_remote", "reliable")
func request_cast(session: int, request_id: int, target_id: int) -> void:
	if _is_current_guest(session):
		_submit_cast(_guest_actor, request_id, target_id)

@rpc("authority", "call_remote", "reliable")
func receive_receipt(session: int, request_id: int, phase: String, result: String) -> void:
	if _owner == 0 or session != _session:
		return
	_view.show_receipt(phase, result)
	if _probe != null:
		_probe.on_receipt(request_id, phase, result)

@rpc("authority", "call_remote", "reliable")
func receive_snapshot(session: int, version: int, entities: Dictionary) -> void:
	if _owner == 0 or session != _session or version <= _version:
		return
	_version = version
	_snapshot = entities
	_view.render_state(entities, _owner, _connection)
	if _probe != null:
		_probe.on_snapshot(session, _owner, entities)

@rpc("any_peer", "call_remote", "reliable")
func acknowledge_probe(session: int, version: int) -> void:
	if not _smoke or not _is_current_guest(session) or version != _version:
		return
	var counts: Dictionary = _arena.counters()
	var guest: Dictionary = counts[_guest_actor]
	var host: Dictionary = counts[HOST]
	if _smoke_departures != 2 or guest["payments"] != 1 or guest["cooldowns"] != 1 \
		or host["applications"] != 1 or host["removals"] != 1:
		_fail("LAN smoke observed unexpected host writes")
		return
	_smoke_complete = true
	print("PASS LAN host authoritative writes")
	probe_done.rpc_id(_guest_peer)

@rpc("authority", "call_remote", "reliable")
func probe_done() -> void:
	if _smoke:
		print("PASS LAN guest movement, range, expiry and reconnect")
		get_tree().quit()

func _host_lobby() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(_address)
	var error: Error = peer.create_server(_port, 1)
	if error != OK:
		_fail("Cannot host lobby: %s" % error_string(error))
		return
	_arena = Arena.new()
	add_child(_arena)
	_arena.settled.connect(_on_cast_settled)
	_spawn_actor(HOST, 1, Vector3(8, 0.15, 10))
	_ledgers[HOST] = Ledger.new()
	_owner = HOST
	multiplayer.peer_disconnected.connect(_on_guest_left)
	multiplayer.multiplayer_peer = peer
	_connection = "Host | waiting for guest (UDP %d)" % _port
	_publish(true)
	print("HOST_LISTENING")

func _connect_lobby() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(_address, _port)
	if error != OK:
		_on_connection_lost(error_string(error))
		return
	_connection = "Connecting to %s:%d" % [_address, _port]
	_view.render_state({}, 0, _connection)
	multiplayer.multiplayer_peer = peer

func _disconnect_lobby(message: String) -> void:
	_owner = 0
	_snapshot = {}
	_version = 0
	_next_request = 0
	_probe_direction = Vector2.ZERO
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
	_view.clear_receipt()
	_view.render_state({}, 0, message)

func _spawn_actor(id: int, faction: int, spawn: Vector3) -> void:
	var actor: Rules = ACTOR_SCENE.instantiate() as Rules
	actor.entity_id = id
	actor.faction = faction
	actor.position = spawn
	_arena.add_actor(actor)

func _cast() -> void:
	if _owner == 0:
		return
	var target_id: int = 0
	for id: int in _snapshot:
		if id != _owner:
			target_id = id
			break
	_next_request += 1
	if _hosting:
		_submit_cast(HOST, _next_request, target_id)
	else:
		request_cast.rpc_id(HOST, _session, _next_request, target_id)

func _submit_cast(actor_id: int, request_id: int, target_id: int) -> void:
	if request_id <= 0:
		return
	var ledger: Ledger = _ledgers[actor_id]
	if ledger.entries.has(request_id):
		var entry: Dictionary = ledger.entries[request_id]
		if entry["target_id"] == target_id:
			_reply(actor_id, request_id, entry["phase"], entry["result"])
		return
	if request_id <= ledger.highest_id:
		_reply(actor_id, request_id, "rejected", "REQUEST_EXPIRED")
		return
	ledger.register(request_id, Rules.ABILITY_ID, target_id)
	var result: String = _arena.try_cast(actor_id, Rules.ABILITY_ID, target_id)
	if result.is_empty():
		ledger.last_cast_id = request_id
		_record_receipt(actor_id, request_id, "accepted", "")
		_publish()
	else:
		_record_receipt(actor_id, request_id, "rejected", result)

func _record_receipt(actor_id: int, request_id: int, phase: String, result: String) -> void:
	var entry: Dictionary = _ledgers[actor_id].entries[request_id]
	entry["phase"] = phase
	entry["result"] = result
	_reply(actor_id, request_id, phase, result)

func _reply(actor_id: int, request_id: int, phase: String, result: String) -> void:
	if actor_id == HOST:
		_view.show_receipt(phase, result)
	elif _guest_peer != 0:
		receive_receipt.rpc_id(_guest_peer, _session, request_id, phase, result)

func _publish(force: bool = false) -> void:
	var entities: Dictionary = _arena.snapshot()
	if not force and entities == _snapshot:
		return
	_snapshot = entities
	_version += 1
	_view.render_state(entities, HOST, _connection)
	if _guest_peer != 0:
		receive_snapshot.rpc_id(_guest_peer, _session, _version, entities)

func _is_current_guest(session: int) -> bool:
	return _hosting and _guest_peer != 0 and session == _session \
		and multiplayer.get_remote_sender_id() == _guest_peer

func _input_direction() -> Vector2:
	if not get_window().has_focus() or _smoke:
		return Vector2.ZERO
	return Vector2(
		int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	).limit_length(1.0)

func _on_connected() -> void:
	request_join.rpc_id(HOST, _ticket)

func _on_connection_lost(message: String) -> void:
	_disconnect_lobby.call_deferred("%s | press R to reconnect" % message)
	if _smoke:
		_fail(message)

func _on_guest_left(peer_id: int) -> void:
	if peer_id != _guest_peer:
		return
	if _smoke_complete:
		get_tree().quit()
		return
	_guest_peer = 0
	_steer_ttl = 0.0
	_arena.set_actor_present(_guest_actor, false)
	_arena.cancel_cast(_guest_actor)
	_arena.cancel_cast(HOST)
	_ledgers.erase(_guest_actor)
	if _smoke:
		if _arena.snapshot().has(_guest_actor):
			_fail("Disconnected guest must leave live snapshots")
			return
		_smoke_departures += 1
	_join_deadline = RECONNECT_SECONDS
	_connection = "Host | guest slot reserved for 30 seconds"
	_publish(true)

func _on_cast_settled(actor_id: int, result: TargetedStatusAbilityDefinition.Result) -> void:
	var ledger: Ledger = _ledgers[actor_id]
	_record_receipt(actor_id, ledger.last_cast_id, "finished", str(TargetedStatusAbilityDefinition.Result.keys()[result]))
	_publish()

func _set_probe_direction(direction: Vector2) -> void:
	_probe_direction = direction

func _reconnect_for_probe() -> void:
	_disconnect_lobby("Reconnect probe")
	get_tree().create_timer(0.25).timeout.connect(_connect_lobby, CONNECT_ONE_SHOT)

func _finish_probe() -> void:
	acknowledge_probe.rpc_id(HOST, _session, _version)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
