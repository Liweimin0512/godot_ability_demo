extends DamageLogicStrategy
class_name ARPGDamageLogic

## ARPG 伤害计算策略
## 公式：(攻击力 - 防御力) * (1 + 暴击倍数 * 暴击率)

@export var attack_attribute: StringName = &"phy_attack"  ## 攻击力属性
@export var defense_attribute: StringName = &"defense"   ## 防御力属性
@export var crit_rate_attribute: StringName = &"crit_rate"  ## 暴击率属性
@export var crit_multiplier: float = 2.0  ## 暴击倍数

func calculate(damage_info: DamageInfo, target_attributes: GameplayAttributeComponent) -> float:
	# 1. 获取攻击者的攻击力（从 damage_info 中获取，或从 instigator 获取）
	var attacker_comp : GameplayAttributeComponent = GameplayAbilitySystem.get_component_by_interface(damage_info.instigator, "GameplayVitalAttributeComponent")
	var base_attack : float = 0.0
	if not attacker_comp:
		# 如果没有攻击者组件，使用基础伤害
		base_attack = damage_info.base_damage
	else:
		base_attack = attacker_comp.get_value(attack_attribute)
	
	# 2. 获取防御者的防御力
	var defense = target_attributes.get_value(defense_attribute)
	
	# 3. 计算基础伤害（减法公式）
	var base_damage = max(1.0, base_attack - defense)
	
	# 4. 计算暴击（如果配置了暴击率属性）
	var final_damage = base_damage
	if crit_rate_attribute != &"" and attacker_comp:
		var crit_rate = attacker_comp.get_value(crit_rate_attribute)
		if damage_info.is_crit or randf() < crit_rate:
			final_damage = base_damage * crit_multiplier
			damage_info.is_crit = true

	return final_damage
