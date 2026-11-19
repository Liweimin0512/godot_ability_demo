extends Node
## Exercises skill input, blackboard state and status rules without a game scene.

const BLEED: GameplayStatusData = preload("res://data/ability_status/heavy_attack_bleed.tres")

var _failures: Array[String] = []

func run() -> Array[String]:
	_test_input_binding()
	_test_blackboard()
	_test_wait_uses_tree_delta()
	_test_duration()
	_test_refresh()
	_test_periodic_effect()
	_test_vital_cost()
	return _failures

func _test_input_binding() -> void:
	var input_feature: AbilityInputFeature = AbilityInputFeature.new()
	input_feature.input_action = &"attack_right"
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	_expect(input_feature.match_input(event), "right press matches the combo binding")
	event.pressed = false
	_expect(not input_feature.match_input(event), "right release does not match")
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	_expect(not input_feature.match_input(event), "left press does not match")

func _test_blackboard() -> void:
	var board: BTBlackboard = BTBlackboard.new()
	var other: BTBlackboard = BTBlackboard.new()
	var node: BTWait = BTWait.new()
	var changes: Array[String] = []
	board.value_changed.connect(func(key: String, _value: Variant) -> void: changes.append(key))
	board.set_var("combo_index", 1)
	board.set_var("combo_index", 1)
	board.set_node_data(node, 0.5)
	_expect(changes == ["combo_index"], "only changed public values emit a signal")
	_expect(other.get_var("combo_index", 0) == 0, "blackboards do not share values")
	_expect(other.get_node_data(node, 0.0) == 0.0, "blackboards do not share node memory")
	board.clear()
	_expect(not board.has_var("combo_index"), "clear removes public values")
	_expect(board.get_node_data(node, 0.0) == 0.0, "clear removes node memory")

func _test_wait_uses_tree_delta() -> void:
	var wait: BTWait = BTWait.new()
	wait.duration = 0.5
	wait.duration_key = "cast_delay"
	var first: BTInstance = BTInstance.new(self, wait)
	var second: BTInstance = BTInstance.new(self, wait)
	second.blackboard.set_var("cast_delay", 0.75)
	_expect(first.tick(0.25) == BTNode.Status.RUNNING, "wait stays active before its duration")
	_expect(first.tick(0.0) == BTNode.Status.RUNNING, "a paused tree does not advance a wait")
	_expect(first.tick(0.25) == BTNode.Status.SUCCESS, "wait completes on elapsed tree time")
	_expect(second.tick(0.5) == BTNode.Status.RUNNING, "the second instance uses its own wait override")
	second.reset_tree()
	_expect(second.tick(0.5) == BTNode.Status.RUNNING, "reset restarts the wait")
	_expect(second.tick(0.25) == BTNode.Status.SUCCESS, "the reset wait completes at its duration")

func _test_duration() -> void:
	var policy: DurationNaturalTime = DurationNaturalTime.new()
	var instance: GameplayStatusInstance = GameplayStatusInstance.new(BLEED, null, null, 1)
	policy.initialize(instance, BLEED.duration)
	_expect(not policy.update(instance, 3.0), "bleed is active at three seconds")
	_expect(policy.update(instance, 0.5), "bleed expires at exactly 3.5 seconds")
	policy.initialize(instance, -1.0)
	_expect(not policy.update(instance, 100.0), "permanent duration does not expire")

func _test_refresh() -> void:
	var instance: GameplayStatusInstance = GameplayStatusInstance.new(BLEED, null, null, 1)
	instance.apply()
	instance.update(2.0)
	var policy: StackingRefreshDuration = BLEED.stacking_policy as StackingRefreshDuration
	if not _expect(policy != null and BLEED.max_stacks == 1, "bleed uses single-layer refresh"):
		return
	_expect(policy.handle_stacking(instance, BLEED, 1, {}), "refresh policy handles reapplication")
	_expect(instance.stacks == 1, "refresh leaves one stack")
	_expect(is_equal_approx(instance.remaining_duration, BLEED.duration), "refresh restores full duration")
	instance.remove()

func _test_periodic_effect() -> void:
	var target: Node = _make_health_target()
	var status: GameplayStatusComponent = GameplayStatusComponent.new()
	target.add_child(status)
	var vitals: GameplayVitalAttributeComponent = target.get_node("GameplayVitalAttributeComponent") as GameplayVitalAttributeComponent

	if not _expect(BLEED.features.size() == 1, "bleed has exactly one feature"):
		target.free()
		return
	var feature: FeaturePeriodicEffects = BLEED.features[0] as FeaturePeriodicEffects
	if not _expect(feature != null, "bleed uses a periodic effect"):
		target.free()
		return
	var first: GameplayStatusInstance = GameplayStatusInstance.new(BLEED, status, null, 1)
	var second: GameplayStatusInstance = GameplayStatusInstance.new(BLEED, status, null, 1)
	feature.apply_feature(first, {})
	feature.apply_feature(second, {})
	feature.update_feature(first, 0.75)
	feature.update_feature(second, 0.25)
	_expect(vitals.get_vital_value(&"health") == 20.0, "shared feature keeps timers separate")
	feature.update_feature(first, 0.25)
	_expect(vitals.get_vital_value(&"health") == 17.0, "first tick deducts three health")
	feature.update_feature(second, 0.75)
	_expect(vitals.get_vital_value(&"health") == 14.0, "second instance reaches its own first tick")
	feature.update_feature(first, 1.25)
	feature.update_feature(first, 0.75)
	_expect(vitals.get_vital_value(&"health") == 8.0, "periodic updates preserve fractional time")
	vitals.modify_vital(&"health", -6.0)
	feature.update_feature(first, 1.0)
	_expect(vitals.get_vital_value(&"health") == 0.0, "a bleed tick depletes health below three")
	target.free()

func _test_vital_cost() -> void:
	var target: Node = _make_health_target()
	var vitals: GameplayVitalAttributeComponent = target.get_node("GameplayVitalAttributeComponent") as GameplayVitalAttributeComponent
	var cost: VitalCost = VitalCost.new()
	cost.vital_id = &"health"
	cost.amount = 7.0
	_expect(cost.can_pay(null, target) and vitals.get_vital_value(&"health") == 20.0,
			"checking a cost does not pay it")
	_expect(cost.try_pay(null, target) and vitals.get_vital_value(&"health") == 13.0,
			"a valid payment deducts exactly the cost")
	cost.amount = 14.0
	_expect(not cost.try_pay(null, target) and vitals.get_vital_value(&"health") == 13.0,
			"an unaffordable cost leaves the balance intact")
	target.free()

func _make_health_target() -> Node:
	var target: Node = Node.new()
	var vitals: GameplayVitalAttributeComponent = GameplayVitalAttributeComponent.new()
	vitals.name = "GameplayVitalAttributeComponent"
	target.add_child(vitals)
	var max_health: GameplayAttribute = GameplayAttribute.new()
	max_health.attribute_id = &"max_health"
	var attributes: GameplayAttributeSet = GameplayAttributeSet.new()
	attributes.attributes[max_health] = 20.0
	var health: GameplayVital = GameplayVital.new()
	health.vital_id = &"health"
	health.max_value_attribute = &"max_health"
	vitals.initialize([attributes], [health])
	return target

func _expect(condition: bool, label: String) -> bool:
	if not condition:
		_failures.append(label)
	return condition
