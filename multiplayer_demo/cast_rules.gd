extends Node3D
## Owns one authoritative actor's GAS instances. All target resolution is supplied by the host.

signal settled(result: TargetedStatusAbilityDefinition.Result)

const ABILITY_ID: StringName = &"targeted_mark"
@export var entity_id: int = 0
@export var faction: int = 0
@export var status_seconds: float = 2.0
var alive: bool = true

var payments: int = 0
var cooldown_starts: int = 0
var applications: int = 0
var removals: int = 0

var _ability: GameplayAbilityInstance
var _cooldown: CooldownFeature
var _cast: TargetedStatusAbilityDefinition.Cast
var _target_available: bool = true
var _invalidate_after_payment: bool = false
var _fixture_spending: bool = false
@onready var _abilities: GameplayAbilityComponent = $Abilities
@onready var _vitals: GameplayVitalAttributeComponent = $Vitals
@onready var _statuses: GameplayStatusComponent = $Statuses

func _ready() -> void:
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
	definition.status.duration = status_seconds
	_abilities.learn_ability(definition)
	_ability = _abilities.get_ability_instance(ABILITY_ID)
	_cooldown = _ability.get_feature("CooldownFeature") as CooldownFeature

	_vitals.vital_value_changed.connect(_on_vital_changed)
	_ability.get_blackboard().value_changed.connect(_on_ability_data_changed)
	_statuses.status_applied.connect(func(_id: StringName, _status: GameplayStatusInstance) -> void: applications += 1)
	_statuses.status_removed.connect(func(_id: StringName) -> void: removals += 1)
	_abilities.ability_completed.connect(_on_ability_completed)

func status_component() -> GameplayStatusComponent:
	return _statuses

func can_pay() -> bool:
	var definition: TargetedStatusAbilityDefinition = _ability.get_definition() as TargetedStatusAbilityDefinition
	return _vitals.can_spend(definition.vital_id, definition.cost)

func activate(target: GameplayStatusComponent, validate_target: Callable) -> bool:
	var cast: TargetedStatusAbilityDefinition.Cast = TargetedStatusAbilityDefinition.Cast.new(
		_vitals, target, _is_target.bind(validate_target))
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

## Injects one failure at a controlled point in the headless verification fixture.
func inject_failure(mode: String) -> void:
	match mode:
		"payment":
			_fixture_spending = true
			_vitals.try_spend(&"mana", 7.0)
			_fixture_spending = false
		"effect":
			_invalidate_after_payment = true

func _is_target(target: GameplayStatusComponent, validate_target: Callable) -> bool:
	return _target_available and validate_target.call(target) == true

func _on_vital_changed(id: StringName, _value: float, _max_value: float, _percent: float, is_regen: bool) -> void:
	if id == &"mana" and not is_regen and not _fixture_spending:
		payments += 1
		if _invalidate_after_payment:
			_target_available = false

func _on_ability_data_changed(key: String, value: Variant) -> void:
	# Cooldown writes its configured full duration only when it starts.
	if key == "CooldownFeature_cooldown_timer" and value == _cooldown.cooldown_duration:
		cooldown_starts += 1

func _on_ability_completed(_instance: GameplayAbilityInstance) -> void:
	var result: TargetedStatusAbilityDefinition.Result = _cast.result
	_cast = null
	settled.emit(result)
