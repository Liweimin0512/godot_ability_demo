extends Resource
class_name TalentMechanicModifier

## 天赋机制修改器（业务层）
## 用于定义天赋如何修改技能机制
## 例如：冷却时间 -20%、消耗 -30%、技能范围 +50%

## 影响的技能ID（如果为空或 "*"，影响所有技能）
@export var ability_id: StringName = &""

## 冷却时间倍率（乘法叠加）
## 例如：0.8 表示冷却时间减少 20%（1.0 - 0.8 = 0.2）
@export var cooldown_multiplier: float = 1.0

## 消耗倍率（乘法叠加）
## 例如：0.7 表示消耗减少 30%（1.0 - 0.7 = 0.3）
@export var cost_multiplier: float = 1.0

## 范围倍率（乘法叠加）
## 例如：1.5 表示范围增加 50%
@export var range_multiplier: float = 1.0

## 施法时间倍率（乘法叠加）
## 例如：0.67 表示施法时间减少 33%（速度提升 50%）
@export var cast_time_multiplier: float = 1.0

@export var payload_status_replacements: Dictionary[StringName, GameplayStatusData] = {}
