extends Node
## Verifies attribute calculation and the demo's attribute-to-Vital integration.

const ModifierType = GameplayAttributeModifier.ModifierType
const PLAYER_DATA_PATH: String = "res://data/player_data/barbarian.tres"
const ATTACK_GROWTH: ScalableValue = preload("res://data/attributes/attack_growth_scalable.tres")

var _failures: Array[String] = []

func run() -> Array[String]:
	_test_modifier_order_and_bounds()
	_test_modifier_sources_and_signals()
	_test_scalable_attribute()
	_test_player_configuration_and_isolation()
	_test_growth_and_derivation_order()
	_test_reinitialize()
	_test_individual_modifier_release()
	_test_vital_limits()
	return _failures

func _test_modifier_order_and_bounds() -> void:
	var instance: GameplayAttributeInstance = GameplayAttributeInstance.new(_make_attribute(&"test", 50.0), 20.0)
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 5.0, ModifierType.ADD))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 0.2, ModifierType.MULTIPLY))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 0.4, ModifierType.MULTIPLY))
	_expect_value(instance.get_value(), 40.0, "additions precede summed percentage bonuses")
	var override: GameplayAttributeModifier = GameplayAttributeModifier.new(&"test", 80.0, ModifierType.OVERRIDE)
	instance.add_modifier(override)
	_expect_value(instance.get_value(), 50.0, "override takes precedence and still clamps to maximum")
	instance.remove_modifier(override)
	_expect_value(instance.get_value(), 40.0, "removing override restores modifier calculation")
	instance.base_value = -10.0
	_expect_value(instance.get_value(), 0.0, "negative total clamps to minimum")

func _test_modifier_sources_and_signals() -> void:
	var instance: GameplayAttributeInstance = GameplayAttributeInstance.new(_make_attribute(&"test"), 10.0)
	var changes: Array[Vector2] = []
	instance.value_changed.connect(func(old: float, next: float) -> void: changes.append(Vector2(old, next)))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 4.0, ModifierType.ADD, &"gear"))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 3.0, ModifierType.ADD, &"talent"))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 0.0, ModifierType.ADD, &"gear"))
	instance.remove_modifiers_by_source(&"gear")
	instance.remove_modifiers_by_source(&"gear")
	_expect_value(instance.get_value(), 13.0, "removing one source preserves the other source")
	if changes != [Vector2(10.0, 14.0), Vector2(14.0, 17.0), Vector2(17.0, 13.0)]:
		_failures.append("only effective final-value changes emit accurate old and new values")

func _test_scalable_attribute() -> void:
	var definition: GameplayAttribute = _make_attribute(&"test")
	var set: GameplayAttributeSet = GameplayAttributeSet.new()
	set.attributes[definition] = 900.0
	set.scalable_attributes[definition] = ATTACK_GROWTH
	var component: GameplayAttributeComponent = GameplayAttributeComponent.new()
	component.set_level(10)
	component.initialize([set])
	_expect_value(component.get_value(&"test"), 50.0, "configured curve takes precedence and uses initial level")
	component.set_level(20)
	_expect_value(component.get_value(&"test"), 100.0, "level updates the sampled value")
	component.set_level(0)
	_expect_value(component.get_level(), 1.0, "level is clamped to one")
	_expect_value(component.get_value(&"test"), 10.0, "lower level restores the starting curve value")
	component.free()

func _test_player_configuration_and_isolation() -> void:
	var player_data: PlayerData = load(PLAYER_DATA_PATH) as PlayerData
	var first: GameplayAttributeComponent = GameplayAttributeComponent.new()
	var second: GameplayAttributeComponent = GameplayAttributeComponent.new()
	first.initialize(player_data.attribute_sets)
	second.initialize(player_data.attribute_sets)
	_expect_value(first.get_value(&"phy_attack"), 29.0, "player attack includes strength and agility")
	_expect_value(first.get_value(&"max_health"), 270.0, "player max health includes vitality and strength")
	var strength_bonus: GameplayAttributeModifier = GameplayAttributeModifier.new(&"strength", 10.0, ModifierType.ADD, &"test")
	first.add_modifier(strength_bonus)
	_expect_value(first.get_value(&"phy_attack"), 49.0, "strength modifier propagates to attack")
	_expect_value(first.get_value(&"max_health"), 290.0, "strength modifier propagates to max health")
	_expect_value(second.get_value(&"phy_attack"), 29.0, "other player retains initial attack")
	var fresh: GameplayAttributeComponent = GameplayAttributeComponent.new()
	fresh.initialize(player_data.attribute_sets)
	_expect_value(fresh.get_value(&"strength"), 10.0, "the original configuration remains intact")
	first.remove_modifiers_by_source(&"test")
	_expect_value(first.get_value(&"phy_attack"), 29.0, "removing strength modifier restores attack")
	first.free()
	second.free()
	fresh.free()

func _test_growth_and_derivation_order() -> void:
	var data: PlayerData = load(PLAYER_DATA_PATH) as PlayerData
	var first: GameplayAttributeComponent = GameplayAttributeComponent.new()
	var second: GameplayAttributeComponent = GameplayAttributeComponent.new()
	first.initialize(data.attribute_sets)
	second.set_level(10)
	second.initialize(data.attribute_sets)
	first.set_level(10)
	_expect_value(first.get_value(&"phy_attack"), 69.0, "level 10 combines the +40 curve growth and existing derived attack")
	first.set_base_value(&"strength", 11.0)
	second.set_base_value(&"strength", 11.0)
	_expect_value(first.get_value(&"phy_attack"), 71.0, "strength change preserves curve growth")
	_expect_value(second.get_value(&"phy_attack"), 71.0, "initializing at level 10 produces the same result")
	second.set_level(1)
	second.set_level(10)
	_expect_value(second.get_value(&"phy_attack"), 71.0, "changing level preserves the strength bonus")
	first.free()
	second.free()

func _test_reinitialize() -> void:
	var strength: GameplayAttribute = _make_attribute(&"strength")
	var original: GameplayAttributeSet = GameplayAttributeSet.new()
	original.attributes[strength] = 10.0
	original.attributes[_make_attribute(&"defense")] = 5.0
	var replacement: GameplayAttributeSet = GameplayAttributeSet.new()
	replacement.attributes[strength] = 30.0
	var component: GameplayAttributeComponent = GameplayAttributeComponent.new()
	component.initialize([original])
	var old_strength: GameplayAttributeInstance = component.get_attribute(&"strength")
	var changes: Array[float] = []
	component.attribute_value_changed.connect(func(id: StringName, value: float) -> void:
		if id == &"strength":
			changes.append(value)
	)
	component.initialize([replacement])
	_expect_value(component.get_value(&"strength"), 30.0, "reinitialization replaces the old value")
	if component.has_attribute(&"defense"):
		_failures.append("reinitialization removes attributes absent from the new set")
	old_strength.base_value = 11.0
	component.set_base_value(&"strength", 31.0)
	if changes != [31.0]:
		_failures.append("only the replacement attribute forwards signals")
	component.free()

func _test_individual_modifier_release() -> void:
	var instance: GameplayAttributeInstance = GameplayAttributeInstance.new(_make_attribute(&"test"), 10.0)
	var removed: GameplayAttributeModifier = GameplayAttributeModifier.new(&"test", 3.0, ModifierType.ADD, &"gear")
	var reference: WeakRef = weakref(removed)
	instance.add_modifier(removed)
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 2.0, ModifierType.ADD, &"gear"))
	instance.add_modifier(GameplayAttributeModifier.new(&"test", 4.0, ModifierType.ADD, &"talent"))
	instance.remove_modifier(removed)
	removed = null
	if reference.get_ref() != null:
		_failures.append("single removal releases the modifier from its source index")
	instance.remove_modifiers_by_source(&"gear")
	_expect_value(instance.get_value(), 14.0, "source cleanup still removes its remaining modifier only")

func _test_vital_limits() -> void:
	var player_data: PlayerData = load(PLAYER_DATA_PATH) as PlayerData
	var component: GameplayVitalAttributeComponent = GameplayVitalAttributeComponent.new()
	component.initialize(player_data.attribute_sets, player_data.vitals)
	_expect_value(component.get_vital_value(&"health"), 270.0, "health starts at the derived maximum")
	component.set_base_value(&"vitality", 16.0)
	_expect_value(component.get_vital_value(&"health"), 270.0, "increasing maximum preserves current health")
	var snapshots: Array[Vector3] = []
	component.vital_value_changed.connect(func(id: StringName, current: float, maximum: float, percent: float, _regen: bool) -> void:
		if id == &"health":
			snapshots.append(Vector3(current, maximum, percent))
	)
	component.set_base_value(&"vitality", 12.0)
	_expect_value(component.get_vital_value(&"health"), 240.0, "decreasing maximum clamps current health")
	if snapshots != [Vector3(240.0, 240.0, 1.0)]:
		_failures.append("maximum decrease emits exactly one consistent health snapshot")
	component.modify_vital(&"mana", -5.0)
	var mana: GameplayVital = component.get_vital(&"mana")
	mana.process_regen(2.0)
	_expect_value(component.get_vital_value(&"mana"), 97.0, "mana regeneration respects elapsed time")
	component.free()

func _make_attribute(id: StringName, maximum: float = 1000.0) -> GameplayAttribute:
	var definition: GameplayAttribute = GameplayAttribute.new()
	definition.attribute_id = id
	definition.min_value = 0.0
	definition.max_value = maximum
	return definition

func _expect_value(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (expected %s, got %s)" % [label, expected, actual])
