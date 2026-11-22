extends Node
## Owns the GAS instances used by the host's two actors.

signal settled(result: TargetedStatusAbilityDefinition.Result)

const ABILITY_ID: StringName = &"targeted_mark"
const TARGET_ID: int = 1

var payments: int = 0
var cooldown_starts: int = 0
var applications: int = 0
var removals: int = 0

var _abilities: GameplayAbilityComponent
var _vitals: GameplayVitalAttributeComponent
var _statuses: GameplayStatusComponent
var _ability: GameplayAbilityInstance
var _cooldown: CooldownFeature
var _cast: TargetedStatusAbilityDefinition.Cast

func _ready() -> void:
	var caster: Node = Node.new()
	var target: Node = Node.new()
	add_child(caster)
	add_child(target)
	_abilities = GameplayAbilityComponent.new()
	_vitals = GameplayVitalAttributeComponent.new()
	_statuses = GameplayStatusComponent.new()
	caster.add_child(_abilities)
	caster.add_child(_vitals)
	target.add_child(_statuses)

	var maximum: GameplayAttribute = GameplayAttribute.new()
	maximum.attribute_id = &"max_mana"
	var attributes: GameplayAttributeSet = GameplayAttributeSet.new()
	attributes.attributes = {maximum: 10.0}
	var mana: GameplayVital = GameplayVital.new()
	mana.vital_id = &"mana"
	mana.max_value_attribute = &"max_mana"
	_vitals.initialize([attributes], [mana])

	var definition: TargetedStatusAbilityDefinition = TargetedStatusAbilityDefinition.new()
	definition.ability_id = ABILITY_ID
	definition.status = GameplayStatusData.new()
	definition.status.status_id = ABILITY_ID
	definition.status.duration = 2.0
	_abilities.learn_ability(definition)
	_ability = _abilities.get_ability_instance(ABILITY_ID)
	_cooldown = _ability.get_feature("CooldownFeature") as CooldownFeature

	_vitals.vital_value_changed.connect(_on_vital_changed)
	_ability.get_blackboard().value_changed.connect(_on_ability_data_changed)
	_statuses.status_applied.connect(func(_id: StringName, _status: GameplayStatusInstance) -> void: applications += 1)
	_statuses.status_removed.connect(func(_id: StringName) -> void: removals += 1)
	_abilities.ability_completed.connect(_on_ability_completed)

func activate() -> bool:
	var cast: TargetedStatusAbilityDefinition.Cast = TargetedStatusAbilityDefinition.Cast.new(
		_vitals, _statuses, _is_target)
	if not _abilities.try_activate_ability(ABILITY_ID, {TargetedStatusAbilityDefinition.CAST_KEY: cast}):
		return false
	_cast = cast
	return true

func snapshot() -> Dictionary:
	return {
		"mana": _vitals.get_vital_value(&"mana"),
		"cooldown_active": _cooldown.get_cooldown_remaining(_ability) > 0.0,
		"status_active": _statuses.has_status(ABILITY_ID),
		"cast_active": _cast != null or _ability.is_active,
	}

func cancel_pending_cast() -> void:
	if _cast != null:
		_abilities.cancel_ability(ABILITY_ID)

func _is_target(target: GameplayStatusComponent) -> bool:
	return target == _statuses

func _on_vital_changed(id: StringName, _value: float, _max_value: float, _percent: float, is_regen: bool) -> void:
	if id == &"mana" and not is_regen:
		payments += 1

func _on_ability_data_changed(key: String, value: Variant) -> void:
	# Cooldown writes its configured full duration only when it starts.
	if key == "CooldownFeature_cooldown_timer" and value == _cooldown.cooldown_duration:
		cooldown_starts += 1

func _on_ability_completed(_instance: GameplayAbilityInstance) -> void:
	var result: TargetedStatusAbilityDefinition.Result = _cast.result
	_cast = null
	settled.emit(result)
