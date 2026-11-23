extends RefCounted
## Drives the real LAN scene through movement, range validation and two reconnects.

enum Phase {
	INITIAL, FAR_CAST, MOVING, LEAVING_RANGE, RANGE_REJECTED, RETURNING,
	BEFORE_PAYMENT, RESUME_CANCELLED, CASTING, RESUME_COMMITTED, EXPIRY, DONE,
}

var _phase: Phase = Phase.INITIAL
var _cast: Callable
var _move: Callable
var _reconnect: Callable
var _finish: Callable
var _fail: Callable
var _entity: int = 0
var _session: int = 0
var _applied: bool = false
var _disconnect_position: Vector3

func _init(cast: Callable, move: Callable, reconnect: Callable, finish: Callable, fail: Callable) -> void:
	_cast = cast
	_move = move
	_reconnect = reconnect
	_finish = finish
	_fail = fail

func on_receipt(_id: int, phase: String, result: String) -> void:
	if _phase == Phase.FAR_CAST:
		if phase != "rejected" or result != "TARGET_INVALID":
			_fail.call("Out-of-range cast must be rejected")
			return
		_phase = Phase.MOVING
		_move.call(Vector2.LEFT)
	elif _phase == Phase.LEAVING_RANGE:
		if phase == "accepted":
			_move.call(Vector2.RIGHT)
		elif phase == "finished" and result == "TARGET_INVALID":
			_phase = Phase.RANGE_REJECTED
		else:
			_fail.call("Moving out of range during windup must invalidate the cast at commit")
	elif _phase == Phase.CASTING and phase == "finished":
		if result != "APPLIED":
			_fail.call("In-range cast must apply the mark")
			return
		_applied = true

func on_snapshot(session: int, owner: int, entities: Dictionary) -> void:
	if entities.size() != 2 or not entities.has(owner) or not entities.has(1) or owner == 1:
		_fail.call("Expected the host and assigned guest entities")
		return
	var guest: Dictionary = entities[owner]
	var host: Dictionary = entities[1]
	var guest_position: Vector3 = guest["position"]
	var host_position: Vector3 = host["position"]
	match _phase:
		Phase.INITIAL:
			_entity = owner
			_session = session
			if guest_position.distance_to(host_position) <= 5.0 or guest["mana"] != 10.0:
				_fail.call("Expected an out-of-range spawn with full Mana")
				return
			_phase = Phase.FAR_CAST
			_cast.call()
		Phase.MOVING:
			if guest_position.distance_to(host_position) <= 4.0:
				_move.call(Vector2.ZERO)
				_phase = Phase.LEAVING_RANGE
				_cast.call()
		Phase.RANGE_REJECTED:
			if guest_position.distance_to(host_position) <= 5.0 or guest["mana"] != 10.0 \
				or guest["cast_active"] or guest["cooldown_active"] or host["status_active"]:
				_fail.call("Range rejection must leave Mana, cooldown and mark unchanged")
				return
			_phase = Phase.RETURNING
			_move.call(Vector2.LEFT)
		Phase.RETURNING:
			if guest_position.distance_to(host_position) <= 4.0:
				_move.call(Vector2.ZERO)
				_phase = Phase.BEFORE_PAYMENT
				_cast.call()
		Phase.BEFORE_PAYMENT:
			if guest["cast_active"]:
				_disconnect_position = guest_position
				_phase = Phase.RESUME_CANCELLED
				_reconnect.call_deferred()
		Phase.RESUME_CANCELLED:
			if session == _session:
				return
			if owner != _entity or guest["mana"] != 10.0 or guest["cast_active"] \
				or guest["cooldown_active"] or host["status_active"] \
				or guest_position.distance_to(_disconnect_position) >= 2.0:
				_fail.call("Windup disconnect must retain identity and position without committing")
				return
			_session = session
			_phase = Phase.CASTING
			_cast.call()
		Phase.CASTING:
			if _applied and host["status_active"] and guest["mana"] == 6.0 and guest["cooldown_active"]:
				_disconnect_position = guest_position
				_phase = Phase.RESUME_COMMITTED
				_reconnect.call_deferred()
		Phase.RESUME_COMMITTED:
			if session == _session:
				return
			if owner != _entity or guest["mana"] != 6.0 or not guest["cooldown_active"] \
				or not host["status_active"] or guest_position != _disconnect_position:
				_fail.call("Committed reconnect must preserve positions, Mana, cooldown and mark")
				return
			_phase = Phase.EXPIRY
		Phase.EXPIRY:
			if not guest["cooldown_active"] and not host["status_active"]:
				_phase = Phase.DONE
				_finish.call()
