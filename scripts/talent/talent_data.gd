extends Resource
class_name TalentData

## 天赋数据（业务层）
## 描述一个可学习的天赋：消耗点数、前置条件、应用的修改器等

## 天赋ID（唯一标识）
@export var talent_id: StringName = &""
## 天赋名称（显示用）
@export var talent_name: String = ""
## 天赋描述（显示用）
@export_multiline var description: String = ""
## 天赋图标（显示用）
@export var icon: Texture2D = null

@export_group("Attribute Modifiers")
## 属性修改器列表
## 用于修改角色属性（如力量 +10）
@export var attribute_modifiers: Array[TalentAttributeModifier] = []

@export_group("Effect Modifiers")
## 效果修改器列表
## 用于修改技能效果（如伤害 +30%）
@export var effect_modifiers: Array[TalentEffectModifier] = []

@export_group("Mechanic Modifiers")
## 机制修改器列表
## 用于修改技能机制（如冷却 -20%）
@export var mechanic_modifiers: Array[TalentMechanicModifier] = []
