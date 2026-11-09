extends GameplayEffect
class_name GE_ModifyVital

## 修改 Vital

@export var vital_id: StringName = &""  ## Vital ID
@export var amount: float = 0.0  ## 修改量（正数为增加，负数为减少）
@export var vital_comp_name: StringName = &"GameplayVitalAttributeComponent"  ## Vital 组件名称

func _apply(target: Node, _instigator: Node, context: Dictionary) -> void:
	var vital_comp: GameplayVitalAttributeComponent = GameplayAbilitySystem.get_component_by_interface(target, vital_comp_name)
	if not vital_comp:
		push_error("GE_ModifyVital: Target %s has no %s component" % [target.name, vital_comp_name])
		return
	
	var vital: GameplayVital = vital_comp.get_vital(vital_id)
	if not is_instance_valid(vital):
		return

	var stacks: int = context.get("stacks", 1)
	# Effects clamp at zero, even when the target has less health than the tick amount.
	vital.modify_value(amount * stacks)
