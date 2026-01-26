extends Node

## 天赋系统单例（AutoLoad）
## 职责：
## - 管理所有天赋的激活/失效
## - 将天赋效果应用到指定实体
## - 提供天赋查询接口
## - 支持多实体场景，每个实体独立管理天赋

## 实体天赋映射 {entity_id: {talent_id: TalentData}}
## 支持多实体场景，每个实体独立管理自己的天赋列表
var _entity_talents: Dictionary[int, Dictionary] = {}

## 修改器存储 {entity_id: {talent_id: {modifier_type: Array[Modifier]}}}
## 存储每个修改器的引用，用于精确移除
var _entity_modifiers: Dictionary[int, Dictionary] = {}

## 天赋激活信号
signal talent_activated(talent_id: StringName, talent_data: TalentData, entity: Node)
## 天赋失效信号
signal talent_deactivated(talent_id: StringName, entity: Node)

## 激活天赋
## [param] talent_id: StringName 天赋ID
## [param] talent_data: TalentData 天赋数据
## [param] target_entity: Node 目标实体（通常是玩家）
func activate_talent(talent_id: StringName, talent_data: TalentData, target_entity: Node) -> void:
	if not is_instance_valid(talent_data):
		push_error("TalentSystem: Talent data is not valid")
		return
	if not is_instance_valid(target_entity):
		push_error("TalentSystem: Target entity is not valid")
		return
	var entity_id = target_entity.get_instance_id()

	# 初始化实体天赋字典
	if not _entity_talents.has(entity_id):
		_entity_talents[entity_id] = {}
		_entity_modifiers[entity_id] = {}
		## 监听实体销毁信号，自动清理
		#if not target_entity.tree_exiting.is_connected(_on_entity_exiting):
			#target_entity.tree_exiting.connect(_on_entity_exiting.bind(entity_id))

	# 检查该实体是否已激活此天赋
	if _entity_talents[entity_id].has(talent_id):
		push_warning("TalentSystem: Talent %s already activated for entity %d" % [talent_id, entity_id])
		return

	_entity_talents[entity_id][talent_id] = talent_data

	# 应用属性修改
	for attr_mod in talent_data.attribute_modifiers:
		if is_instance_valid(attr_mod):
			_apply_attribute_modifier(target_entity, attr_mod, talent_id)

	# 应用技能效果修改
	for effect_mod in talent_data.effect_modifiers:
		if is_instance_valid(effect_mod):
			_apply_effect_modifier(target_entity, effect_mod, talent_id)

	# 应用技能机制修改
	for mechanic_mod in talent_data.mechanic_modifiers:
		if is_instance_valid(mechanic_mod):
			_apply_mechanic_modifier(target_entity, mechanic_mod, talent_id)

	talent_activated.emit(talent_id, talent_data, target_entity)
	print("TalentSystem: Activated talent '%s' for entity %d" % [talent_id, entity_id])

## 失效天赋
## [param] talent_id: StringName 天赋ID
## [param] target_entity: Node 目标实体
func deactivate_talent(talent_id: StringName, target_entity: Node) -> void:
	if not is_instance_valid(target_entity):
		return

	var entity_id = target_entity.get_instance_id()
	if not _entity_talents.has(entity_id):
		return

	if not _entity_talents[entity_id].has(talent_id):
		return

	#var talent_data = _entity_talents[entity_id][talent_id]

	# 移除属性修改
	_remove_attribute_modifier(target_entity, talent_id)
	# 移除技能效果修改
	_remove_effect_modifier(target_entity, talent_id)
	# 移除技能机制修改
	_remove_mechanic_modifier(target_entity, talent_id)

	_entity_talents[entity_id].erase(talent_id)

	# 如果实体没有天赋了，清理字典
	if _entity_talents[entity_id].is_empty():
		_entity_talents.erase(entity_id)
		_entity_modifiers.erase(entity_id)

	talent_deactivated.emit(talent_id, target_entity)
	print("TalentSystem: Deactivated talent '%s' for entity %d" % [talent_id, entity_id])

## 检查天赋是否已激活（全局，任意实体&特定实体）
## [param] talent_id: StringName 天赋ID
## [return] bool 是否已激活
func is_talent_active(talent_id: StringName, entity: Node = null) -> bool:
	if is_instance_valid(entity):
		var entity_id = entity.get_instance_id()
		if not _entity_talents.has(entity_id):
			return false
		return _entity_talents[entity_id].has(talent_id)
	else:
		for entity_talents in _entity_talents.values():
			if entity_talents.has(talent_id):
				return true
	return false

## 获取实体的所有天赋ID列表
## [param] entity: Node 目标实体
## [return] Array[StringName] 天赋ID列表
func get_entity_talents(entity: Node) -> Array[StringName]:
	var final_talent_ids : Array[StringName] = []
	if not is_instance_valid(entity):
		return final_talent_ids
	
	var entity_id = entity.get_instance_id()
	if not _entity_talents.has(entity_id):
		return final_talent_ids
	
	for talent_id in _entity_talents[entity_id].keys():
		final_talent_ids.append(talent_id)
	return final_talent_ids

func get_entity_talent(entity: Node, talent_id : StringName) -> TalentData:
	var talents := get_entity_talents(entity)
	if talents.is_empty():
		return null
	return _entity_talents[entity.get_instance_id()].get(talent_id)

### 实体销毁时自动清理
### [param] entity_id: int 实体ID
#func _on_entity_exiting(entity_id: int) -> void:
	#if _entity_talents.has(entity_id):
		## 清理该实体的所有天赋
		#var talents = _entity_talents[entity_id].duplicate()
		#for talent_id in talents.keys():
			## 注意：此时实体可能已经部分销毁，通过 source_id 批量清理
			#_cleanup_entity_talent(entity_id, talent_id)
#
		#_entity_talents.erase(entity_id)
		#_entity_modifiers.erase(entity_id)
		#print("TalentSystem: Cleaned up talents for entity %d" % entity_id)

## 清理实体的天赋（实体销毁时调用）
## [param] entity_id: int 实体ID
## [param] talent_id: StringName 天赋ID
func _cleanup_entity_talent(entity_id: int, talent_id: StringName) -> void:
	# 通过 source_id 批量清理修改器
	# 注意：此时实体可能已经部分销毁，需要特殊处理
	if _entity_modifiers.has(entity_id) and _entity_modifiers[entity_id].has(talent_id):
		_entity_modifiers[entity_id].erase(talent_id)

## 应用属性修改器
## [param] entity: Node 目标实体
## [param] modifier: TalentAttributeModifier 属性修改器
## [param] talent_id: StringName 天赋ID（用于 source_id）
func _apply_attribute_modifier(entity: Node, modifier: TalentAttributeModifier, talent_id: StringName) -> void:
	var attr_comp = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayVitalAttributeComponent")
	
	if not is_instance_valid(attr_comp):
		push_warning("TalentSystem: Entity does not have GameplayVitalAttributeComponent")
		return

	# 创建属性修改器
	var attr_mod = GameplayAttributeModifier.new(
		modifier.attribute_id,
		modifier.value,
		modifier.modifier_type,
		"talent." + String(talent_id)  # source_id
	)
	
	attr_comp.add_modifier(attr_mod)

	# 存储修改器引用，用于精确移除
	var entity_id = entity.get_instance_id()
	if not _entity_modifiers[entity_id].has(talent_id):
		_entity_modifiers[entity_id][talent_id] = {}
	if not _entity_modifiers[entity_id][talent_id].has("attribute"):
		_entity_modifiers[entity_id][talent_id]["attribute"] = []
	_entity_modifiers[entity_id][talent_id]["attribute"].append(attr_mod)

	print("TalentSystem: Applied attribute modifier '%s' = %s (type: %s)" % [
		modifier.attribute_id,
		modifier.value,
		GameplayAttributeModifier.ModifierType.keys()[modifier.modifier_type]
	])

## 移除属性修改器
## [param] entity: Node 目标实体
## [param] talent_id: StringName 天赋ID
func _remove_attribute_modifier(entity: Node, talent_id: StringName) -> void:
	if not is_instance_valid(entity):
		return

	var entity_id = entity.get_instance_id()
	if not _entity_modifiers.has(entity_id):
		return

	if not _entity_modifiers[entity_id].has(talent_id):
		return

	if not _entity_modifiers[entity_id][talent_id].has("attribute"):
		return
	
	var attr_comp = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayVitalAttributeComponent")
	
	if is_instance_valid(attr_comp):
		# 精确移除每个修改器
		for modifier in _entity_modifiers[entity_id][talent_id]["attribute"]:
			if is_instance_valid(modifier):
				attr_comp.remove_modifier(modifier)

	# 清除存储的修改器引用
	_entity_modifiers[entity_id][talent_id].erase("attribute")
	print("TalentSystem: Removed attribute modifiers for talent '%s'" % talent_id)

## 应用技能效果修改（占位，后续章节实现）
## [param] entity: Node 目标实体
## [param] modifier: TalentEffectModifier 效果修改器
## [param] talent_id: StringName 天赋ID
func _apply_effect_modifier(entity: Node, modifier: TalentEffectModifier, talent_id: StringName) -> void:
	var ability_comp : GameplayAbilityComponent = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayAbilityComponent")
	if not is_instance_valid(ability_comp):
		push_warning("TalentSystem: Entity does not have GameplayAbilityComponent")
		return
	# 检查是否影响所有技能（ability_id 为空）
	if modifier.ability_id.is_empty():
		# 影响所有技能：为每个技能实例添加 Feature
		for ability_id in ability_comp.get_all_ability_ids():
			_apply_effect_modifier_to_ability(ability_comp, ability_id, modifier, talent_id)
	else:
		# 只影响指定技能
		_apply_effect_modifier_to_ability(ability_comp, modifier.ability_id, modifier, talent_id)

## 移除技能效果修改（占位，后续章节实现）
## [param] entity: Node 目标实体
## [param] talent_id: StringName 天赋ID
func _remove_effect_modifier(entity: Node, talent_id: StringName) -> void:
	var ability_comp : GameplayAbilityComponent = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayAbilityComponent")
	if not is_instance_valid(ability_comp):
		push_warning("TalentSystem: Entity does not have GameplayAbilityComponent")
		return

	# 移除所有技能的效果修改 Feature
	var feature_name = _get_feature_name(talent_id)
	for ability_id in ability_comp.get_all_ability_ids():
		var ability_instance : GameplayAbilityInstance = ability_comp.get_ability_instance(ability_id)
		if is_instance_valid(ability_instance) and ability_instance.has_feature(feature_name):
			var ok := ability_instance.remove_feature(feature_name)
			if not ok:
				push_warning("TalentSystem: remove %s feature is not ok!" % feature_name)
			print("TalentSystem: Removed effect modifiers for talent '%s' (ability: %s)" % [talent_id, ability_id])

## 应用技能机制修改（占位，后续章节实现）
## [param] entity: Node 目标实体
## [param] modifier: TalentMechanicModifier 机制修改器
## [param] talent_id: StringName 天赋ID
func _apply_mechanic_modifier(entity: Node, modifier: TalentMechanicModifier, talent_id: StringName) -> void:
	if not modifier.payload_status_replacements.is_empty():
		_apply_projectile_payload_replacement(entity, modifier.ability_id, modifier.payload_status_replacements, talent_id )
	if not modifier.replace_abilities.is_empty():
		for old_ability_id in modifier.replace_abilities:
			var new_ability_data := modifier.replace_abilities[old_ability_id]
			_replace_ability(entity, old_ability_id, new_ability_data, talent_id)

## 移除技能机制修改（占位，后续章节实现）
## [param] entity: Node 目标实体
## [param] talent_id: StringName 天赋ID
func _remove_mechanic_modifier(entity: Node, talent_id: StringName) -> void:
	_restore_ability(entity, talent_id) 

func _apply_projectile_payload_replacement(
		entity: Node,
		ability_id: StringName,
		replacements: Dictionary,
		talent_id: StringName
		) -> void:
	var ability_comp = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayAbilityComponent")
	if not is_instance_valid(ability_comp):
		push_warning("TalentSystem: Entity does not have GameplayAbilityComponent")
		return

	var ability_instance = ability_comp.get_ability_instance(ability_id)
	if not is_instance_valid(ability_instance):
		push_warning("TalentSystem: Ability instance '%s' not found" % ability_id)
		return
		
	# 获取或创建 Feature
	var feature_name = "talent_projectile_payload_" + String(talent_id)
	var feature = ability_instance.get_feature(feature_name) as ProjectilePayloadModifierFeature
	if not is_instance_valid(feature):
		# 创建新 Feature
		feature = ProjectilePayloadModifierFeature.new()
		feature.payload_status_replacements = {} as Dictionary[StringName, GameplayStatusData]
		ability_instance.add_feature(feature_name, feature)
	# 合并替换映射
	for old_status_id in replacements:
		var new_status = replacements[old_status_id] as GameplayStatusData
		if is_instance_valid(new_status):
			feature.payload_status_replacements[old_status_id] = new_status

	print("TalentSystem: Applied projectile payload replacement for ability '%s' (talent: %s, replacements: %d)" % [
		ability_id,
		talent_id,
		feature.payload_status_replacements.size()
	])

## 替换技能
## [param] entity: Node 目标实体
## [param] old_ability_id: StringName 旧技能ID
## [param] new_ability_definition: GameplayAbilityDefinition 新技能定义
## [param] talent_id: StringName 天赋ID
func _replace_ability(
		entity: Node,
		old_ability_id: StringName,
		new_ability_definition: GameplayAbilityDefinition,
		talent_id: StringName
	) -> void:
	var ability_comp : GameplayAbilityComponent = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayAbilityComponent")
	if not is_instance_valid(ability_comp):
		push_warning("TalentSystem: Entity does not have GameplayAbilityComponent")
		return
	# 检查旧技能是否存在
	if not ability_comp.has_ability(old_ability_id):
		push_warning("TalentSystem: Old ability '%s' not found" % old_ability_id)
		return
	# 检查新技能定义是否有效
	if not is_instance_valid(new_ability_definition):
		push_error("TalentSystem: New ability definition is not valid")
		return
	
	# 保存旧技能定义（用于恢复）
	var old_ability_instance = ability_comp.get_ability_instance(old_ability_id)
	var old_ability_definition = old_ability_instance.get_definition()

	# 存储替换信息（用于恢复）
	var entity_id = entity.get_instance_id()
	if not _entity_modifiers.has(entity_id):
		_entity_modifiers[entity_id] = {}
	if not _entity_modifiers[entity_id].has(talent_id):
		_entity_modifiers[entity_id][talent_id] = {}
	_entity_modifiers[entity_id][talent_id]["ability_replacement"] = {
		"old_ability_id": old_ability_id,
		"old_ability_definition": old_ability_definition
	}

	# 遗忘旧技能
	ability_comp.forget_ability(old_ability_id)

	# 学习新技能
	# 将新技能实例存储到旧技能ID的位置
	new_ability_definition.ability_id = old_ability_id
	ability_comp.learn_ability(new_ability_definition)

	print("TalentSystem: Replaced ability '%s' with '%s' (talent: %s)" % [
		old_ability_id,
		new_ability_definition.ability_id,
		talent_id
	])

## 恢复技能
## [param] entity: Node 目标实体
## [param] talent_id: StringName 天赋ID
func _restore_ability(entity: Node, talent_id: StringName) -> void:
	var entity_id = entity.get_instance_id()
	if not _entity_modifiers.has(entity_id):
		return
	if not _entity_modifiers[entity_id].has(talent_id):
		return
	if not _entity_modifiers[entity_id][talent_id].has("ability_replacement"):
		return

	var replacement_info = _entity_modifiers[entity_id][talent_id]["ability_replacement"]
	var old_ability_id = replacement_info.get("old_ability_id", &"")
	var old_ability_definition = replacement_info.get("old_ability_definition", null)

	if old_ability_id.is_empty() or not is_instance_valid(old_ability_definition):
		return

	var ability_comp = GameplayAbilitySystem.get_component_by_interface(entity, "GameplayAbilityComponent")
	if not is_instance_valid(ability_comp):
		return

	# 遗忘新技能（使用旧技能ID存储的）
	if ability_comp.has_ability(old_ability_id):
		ability_comp.forget_ability(old_ability_id)

	# 恢复旧技能
	ability_comp.learn_ability(old_ability_definition)

	# 清理替换信息
	_entity_modifiers[entity_id][talent_id].erase("ability_replacement")
	print("TalentSystem: Restored ability '%s' (talent: %s)" % [old_ability_id, talent_id])

## 为指定技能应用效果修改器
## [param] ability_comp: GameplayAbilityComponent 技能组件
## [param] ability_id: StringName 技能ID
## [param] modifier: TalentEffectModifier 效果修改器
## [param] talent_id: StringName 天赋ID
func _apply_effect_modifier_to_ability(
		ability_comp: GameplayAbilityComponent,
		ability_id: StringName,
		modifier: TalentEffectModifier,
		talent_id: StringName
	) -> void:
	var ability_instance = ability_comp.get_ability_instance(ability_id)
	if not is_instance_valid(ability_instance):
		push_warning("TalentSystem: Ability instance '%s' not found" % ability_id)
		return

	# 获取或创建 Feature
	var feature_name = _get_feature_name(talent_id)
	var feature = ability_instance.get_feature(feature_name) as EffectModifierFeature

	if not is_instance_valid(feature):
		# 创建新 Feature
		feature = EffectModifierFeature.new()
		feature.effect_modifiers = [] as Array[TalentEffectModifier]
		ability_instance.add_feature(feature_name, feature)

	# 添加修改器到 Feature
	if modifier not in feature.effect_modifiers:
		feature.effect_modifiers.append(modifier)
		print("TalentSystem: Applied effect modifier to ability '%s' (talent: %s)" % [ability_id, talent_id])

func _get_feature_name(talent_id : StringName) -> StringName:
	return "talent_effect_" + String(talent_id)
