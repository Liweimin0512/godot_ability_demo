extends Resource
class_name TalentEffectModifier

## 天赋效果修改器（业务层）
## 用于定义天赋如何修改技能效果
## 例如：火球术伤害 +30%、治疗量 +50%、状态持续时间 +2秒

## 影响的技能ID（如果为空，影响所有技能）
@export var ability_id: StringName = &""

## 伤害倍率（乘法叠加）
## 例如：1.3 表示伤害增加 30%
@export var damage_multiplier: float = 1.0

## 治疗倍率（乘法叠加）
## 例如：1.5 表示治疗量增加 50%
@export var heal_multiplier: float = 1.0

## 持续时间倍率（乘法叠加）
## 例如：1.2 表示持续时间增加 20%
@export var duration_multiplier: float = 1.0

## 持续时间增加值（固定增加，单位：秒）
## 例如：2.0 表示持续时间增加 2 秒
@export var duration_add: float = 0.0

## 范围倍率（乘法叠加）
## 例如：1.5 表示范围增加 50%
@export var range_multiplier: float = 1.0

## 应用修改到 context（由 Feature 调用）
## [param] context: Dictionary 技能上下文（可修改）
func apply_to_context(context: Dictionary) -> void:
	# 修改伤害倍率（累乘）
	if damage_multiplier != 1.0:
		var current_multiplier = context.get("damage_multiplier", 1.0)
		context["damage_multiplier"] = current_multiplier * damage_multiplier

	# 修改治疗倍率（累乘）
	if heal_multiplier != 1.0:
		var current_heal_multiplier = context.get("heal_multiplier", 1.0)
		context["heal_multiplier"] = current_heal_multiplier * heal_multiplier

	# 修改持续时间倍率（累乘）
	if duration_multiplier != 1.0:
		var current_duration_multiplier = context.get("duration_multiplier", 1.0)
		context["duration_multiplier"] = current_duration_multiplier * duration_multiplier

	# 修改持续时间增加值（累加）
	if duration_add != 0.0:
		var current_duration_add = context.get("duration_add", 0.0)
		context["duration_add"] = current_duration_add + duration_add

	# 修改范围倍率（累乘）
	if range_multiplier != 1.0:
		var current_range_multiplier = context.get("range_multiplier", 1.0)
		context["range_multiplier"] = current_range_multiplier * range_multiplier

## 检查是否影响指定技能
## [param] ability_id: StringName 技能ID
## [return] bool 是否影响此技能
func affects_ability(id: StringName) -> bool:
	# 如果未设置过滤条件，默认影响所有技能
	if ability_id.is_empty():
		return true

	# 检查 ID 匹配
	return ability_id == id
