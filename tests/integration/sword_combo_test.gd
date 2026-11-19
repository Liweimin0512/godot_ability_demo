extends Node
## Drives the demo's sword combo through its input, physics and status components.

const BLEED_ID: StringName = &"heavy_attack_bleed"
const TALENT_PATH: String = "res://data/talents/combo_mastery_talent.tres"

var _failures: Array[String] = []
var _applications: int = 0
var _removals: int = 0
var _health_deltas: Array[float] = []
var _previous_health: float = 0.0

func run() -> Array[String]:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if not _expect(scene != null, "main scene loads"):
		return _failures
	var demo: Node = scene.instantiate()
	add_child(demo)
	var debug_panel: Window = demo.get_node("BtDebugPanel") as Window
	_expect(not debug_panel.visible, "the behavior-tree debugger starts hidden")
	var player: Player = demo.get_node("RoomLobby/Player") as Player
	var enemy: CharacterBody3D = demo.get_node("RoomDungeon/Enemies/Enemy") as CharacterBody3D
	var combo: GameplayAbilityInstance = await _equip_and_learn_combo(player)
	var runtime_refs: Array[WeakRef] = []
	if combo != null:
		var failures_before_combo: int = _failures.size()
		await _verify_combo(player, enemy, combo)
		# Leave an active cast in the scene to exercise teardown during gameplay.
		if _failures.size() == failures_before_combo:
			_expect(player.ability_component.try_activate_ability(&"attack"), "combo can start again before teardown")
		runtime_refs.assign([weakref(combo), weakref(combo.get_bt_instance()), weakref(combo.get_blackboard())])
		combo = null
	demo.queue_free()
	await get_tree().process_frame
	for reference: WeakRef in runtime_refs:
		_expect(reference.get_ref() == null, "scene teardown releases the active skill, tree and blackboard")
	_test_early_player_teardown()
	return _failures

func _test_early_player_teardown() -> void:
	var player_scene: PackedScene = load("res://prefabs/player.tscn") as PackedScene
	var player: Player = player_scene.instantiate() as Player
	add_child(player)
	var startup_timer: Timer = player.get_node_or_null("StartupChecks") as Timer
	var pending: WeakRef = null
	if _expect(startup_timer != null and not startup_timer.is_stopped(), "startup check is pending on a player-owned timer"):
		pending = weakref(startup_timer)
	player.free()
	if pending != null:
		_expect(pending.get_ref() == null, "early player removal releases the pending startup timer")

func _equip_and_learn_combo(player: Player) -> GameplayAbilityInstance:
	var inventory: C_Inventory = player.get_inventory()
	for item: Item in inventory.items:
		if item is Equip and item.name == "大剑":
			inventory.equip_item(item as Equip)
			var original: WeakRef = weakref(player.ability_component.get_ability_instance(&"attack"))
			ConsoleCommands.apply_talent("Player", TALENT_PATH)
			# The old ability button releases its reference when its queued free runs.
			await get_tree().process_frame
			_expect(original.get_ref() == null, "talent replacement releases the forgotten skill")
			var combo: GameplayAbilityInstance = player.ability_component.get_ability_instance(&"attack")
			if _expect(combo != null and combo.get_definition() is ComboAbilityDefinition, "talent replaces the equipped sword attack"):
				return combo
			return null
	_expect(false, "sword is available in the player inventory")
	return null

func _verify_combo(player: Player, enemy: CharacterBody3D, combo: GameplayAbilityInstance) -> void:
	var status: GameplayStatusComponent = enemy.get_node("GameplayStatusComponent") as GameplayStatusComponent
	var vitals: GameplayVitalAttributeComponent = enemy.get_node("GameplayVitalAttributeComponent") as GameplayVitalAttributeComponent
	var health: GameplayVital = vitals.get_vital(&"health")
	_previous_health = health.current_value
	health.value_changed.connect(_on_health_changed)
	status.status_applied.connect(_on_status_applied)
	status.status_removed.connect(_on_status_removed)

	await get_tree().physics_frame
	if not await _perform_combo(combo, false):
		return
	if not _expect(_applications == 0 and not status.has_status(BLEED_ID) and _health_deltas.is_empty(),
			"third-stage whiff neither applies bleed nor changes health"):
		return
	print("Sword combo: whiff caused no damage or bleed")
	await get_tree().create_timer(1.25).timeout

	# Put the actual enemy's hit area in range and let physics register the move.
	var facing: Vector3 = player.get_visuals().global_transform.basis * Vector3.FORWARD
	enemy.global_position = player.global_position + facing.normalized() * 1.1
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not await _perform_combo(combo, true):
		return
	if not _expect(_applications == 1 and status.has_status(BLEED_ID),
			"third strike applies bleed once"):
		return
	_expect(_health_deltas.all(func(delta: float) -> bool: return delta < 0.0),
			"each direct strike deducts health before the first bleed tick")
	print("Sword combo: three direct hits %s" % str(_health_deltas))
	await get_tree().create_timer(4.5).timeout
	_expect(_removals == 1 and not status.has_status(BLEED_ID), "bleed expires exactly once")
	_expect(_health_deltas.size() == 6 and _health_deltas.slice(3) == [-3.0, -3.0, -3.0],
			"exactly three bleed ticks deduct three health each, with no late tick")
	print("Sword combo: HP deltas after expiry %s" % str(_health_deltas))

func _perform_combo(combo: GameplayAbilityInstance, expect_hits: bool) -> bool:
	var cooldown: CooldownFeature = combo.get_feature("CooldownFeature") as CooldownFeature
	if not _expect(cooldown != null, "combo has a cooldown feature"):
		return false
	for step: int in range(3):
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		event.position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.25)
		event.global_position = event.position
		get_viewport().push_input(event, true)
		var release: InputEventMouseButton = event.duplicate() as InputEventMouseButton
		release.pressed = false
		get_viewport().push_input(release, true)
		await get_tree().create_timer(1.15).timeout
		var index: int = combo.get_blackboard_var("combo_index", 0) as int
		var finished: bool = step == 2
		if not _expect(index == step and combo.is_active != finished,
				"input reaches combo stage %d" % (step + 1)):
			return false
		if not _expect((cooldown.get_cooldown_remaining(combo) > 0.0) == finished,
				"whole-combo cooldown starts after the third stage"):
			return false
		if not _expect(_health_deltas.size() == (step + 1 if expect_hits else 0),
				"stage %d has the expected number of direct hits" % (step + 1)):
			return false
	return true

func _on_health_changed(current: float, _maximum: float, _percent: float, _regen: bool) -> void:
	_health_deltas.append(current - _previous_health)
	_previous_health = current

func _on_status_applied(id: StringName, _instance: GameplayStatusInstance) -> void:
	if id == BLEED_ID:
		_applications += 1

func _on_status_removed(id: StringName) -> void:
	if id == BLEED_ID:
		_removals += 1

func _expect(condition: bool, label: String) -> bool:
	if not condition:
		_failures.append("%s (HP deltas: %s)" % [label, _health_deltas])
	return condition
