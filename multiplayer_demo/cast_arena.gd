extends Node3D
## Owns the authoritative arena and resolves entity IDs into local gameplay components.

signal settled(entity_id: int, result: TargetedStatusAbilityDefinition.Result)

const CastRules = preload("cast_rules.gd")
const HOST_ACTOR: int = 1
const CLIENT_ACTOR: int = 2
const PRACTICE_TARGET: int = 3
const CAST_RANGE_SQUARED: float = 25.0

var _actors: Dictionary[int, CastRules] = {}
var _detached_fixture_target: CastRules
var long_status_actor_id: int = 0

func _enter_tree() -> void:
	if long_status_actor_id != 0:
		var actor: CastRules = $HostActor if long_status_actor_id == HOST_ACTOR else $ClientActor
		actor.status_seconds = 5.0

func _ready() -> void:
	for child: Node in get_children():
		if child is CastRules:
			_register_actor(child)

func _exit_tree() -> void:
	if is_instance_valid(_detached_fixture_target):
		_detached_fixture_target.free()

func try_cast(actor_id: int, ability_id: StringName, target_id: int) -> String:
	if ability_id != CastRules.ABILITY_ID:
		return "UNKNOWN_ABILITY"
	if not _valid_target(actor_id, target_id):
		return "TARGET_INVALID"
	var caster: CastRules = _actors[actor_id]
	var state: Dictionary = caster.snapshot()
	if state["cast_active"]:
		return "BUSY"
	if state["cooldown_active"]:
		return "COOLDOWN"
	if not caster.can_pay():
		return "INSUFFICIENT_MANA"
	var target: CastRules = _actors[target_id]
	if not caster.activate(target.status_component(), _check_target.bind(actor_id, target_id)):
		return "REJECTED"
	return ""

func cancel_cast(actor_id: int) -> void:
	if is_instance_valid(_actors.get(actor_id)):
		_actors[actor_id].cancel_pending_cast()

func add_actor(actor: CastRules) -> void:
	add_child(actor)
	_register_actor(actor)

func set_actor_present(actor_id: int, present: bool) -> void:
	_actors[actor_id].present = present

func remove_actor(actor_id: int) -> void:
	var actor: CastRules = _actors[actor_id]
	_actors.erase(actor_id)
	actor.queue_free()

## Advances a present actor on the host within the lobby's walkable bounds.
func move_actor(actor_id: int, offset: Vector2, bounds: Rect2) -> void:
	var actor: CastRules = _actors.get(actor_id)
	if not is_instance_valid(actor) or not actor.present or not actor.alive:
		return
	var next_position: Vector2 = (Vector2(actor.position.x, actor.position.z) + offset).clamp(bounds.position, bounds.end)
	actor.position = Vector3(next_position.x, actor.position.y, next_position.y)

func inject_failure(mode: String, target_id: int) -> void:
	match mode:
		"target":
			_actors[target_id].position.x += 10.0
		"leave":
			# Keep the fixture allocated to verify detachment alone removes it from replication.
			_detached_fixture_target = _actors[target_id]
			remove_child(_detached_fixture_target)
		_:
			_actors[CLIENT_ACTOR].inject_failure(mode)

func snapshot() -> Dictionary:
	var entities: Dictionary = {}
	for id: int in _actors:
		var actor: CastRules = _actors[id]
		if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion() or not actor.present:
			continue
		var data: Dictionary = actor.snapshot()
		data["alive"] = actor.alive
		data["faction"] = actor.faction
		data["x"] = actor.position.x
		data["position"] = actor.global_position
		entities[id] = data
	return entities

func counters() -> Dictionary:
	var data: Dictionary = {}
	for id: int in _actors:
		var actor: CastRules = _actors[id]
		if is_instance_valid(actor):
			data[id] = {"payments": actor.payments, "cooldowns": actor.cooldown_starts,
				"applications": actor.applications, "removals": actor.removals}
	return data

func _valid_target(actor_id: int, target_id: int) -> bool:
	var actor: CastRules = _actors.get(actor_id)
	var target: CastRules = _actors.get(target_id)
	return is_instance_valid(actor) and is_instance_valid(target) and actor != target \
		and actor.is_inside_tree() and target.is_inside_tree() \
		and not actor.is_queued_for_deletion() and not target.is_queued_for_deletion() \
		and actor.present and target.present and actor.alive and target.alive and actor.faction != target.faction \
		and actor.global_position.distance_squared_to(target.global_position) <= CAST_RANGE_SQUARED

func _check_target(component: GameplayStatusComponent, actor_id: int, target_id: int) -> bool:
	return _valid_target(actor_id, target_id) and _actors[target_id].status_component() == component

func _on_actor_settled(result: TargetedStatusAbilityDefinition.Result, entity_id: int) -> void:
	settled.emit(entity_id, result)

func _register_actor(actor: CastRules) -> void:
	assert(actor.entity_id > 0 and not _actors.has(actor.entity_id))
	_actors[actor.entity_id] = actor
	actor.settled.connect(_on_actor_settled.bind(actor.entity_id))
