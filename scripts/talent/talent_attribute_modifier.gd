extends Resource
class_name TalentAttributeModifier

## 天赋属性修改器（业务层）
## 用于定义天赋如何修改角色属性
## 例如：力量 +10、攻击力 +50%、移速 -20%

## 要修改的属性ID
@export var attribute_id: StringName = &""
## 修改值
@export var value: float = 0.0
## 修改类型（ADD、MULTIPLY、OVERRIDE）
@export var modifier_type: GameplayAttributeModifier.ModifierType = GameplayAttributeModifier.ModifierType.ADD
