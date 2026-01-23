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
