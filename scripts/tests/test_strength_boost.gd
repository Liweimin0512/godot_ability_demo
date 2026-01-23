extends Node

## 测试力量强化天赋

const STRENGTH_BOOST_TALENT = preload("uid://bb58mxy5g4f51")

func _ready() -> void:
	# 等待一帧，确保单例已加载
	await get_tree().process_frame

	# 获取玩家实体
	var player = get_tree().get_first_node_in_group("Player")
	if not is_instance_valid(player):
		push_error("TestStrengthBoost: Player not found")
		return

	# 获取属性组件
	var attr_comp = GameplayAbilitySystem.get_component_by_interface(
		player,
		"GameplayVitalAttributeComponent"
	)
	if not is_instance_valid(attr_comp):
		push_error("TestStrengthBoost: Player does not have GameplayVitalAttributeComponent")
		return
	
	# 检查力量属性是否存在
	if not attr_comp.has_attribute(&"strength"):
		push_error("TestStrengthBoost: Player does not have 'strength' attribute")
		return
	
	# 记录初始力量值
	var initial_strength = attr_comp.get_value(&"strength")
	print("TestStrengthBoost: Initial strength: %s" % initial_strength)

	# 加载天赋数据
	var talent_data = STRENGTH_BOOST_TALENT as TalentData
	if not is_instance_valid(talent_data):
		push_error("TestStrengthBoost: Failed to load talent data")
		return
	
	# 激活天赋
	print("TestStrengthBoost: Activating talent...")
	TalentSystem.activate_talent(talent_data.talent_id, talent_data, player)

	# 等待一帧，确保修改器已应用
	await get_tree().process_frame

	# 检查力量值是否增加
	var new_strength = attr_comp.get_value(&"strength")
	print("TestStrengthBoost: New strength: %s (expected: %s)" % [new_strength, initial_strength + 10.0])

	if abs(new_strength - (initial_strength + 10.0)) < 0.01:
		print("TestStrengthBoost: ✅ Test passed! Strength increased correctly.")
	else:
		push_error("TestStrengthBoost: ❌ Test failed! Strength did not increase correctly.")
	
	# 测试失效天赋
	print("TestStrengthBoost: Deactivating talent...")
	TalentSystem.deactivate_talent(talent_data.talent_id, player)

	# 等待一帧，确保修改器已移除
	await get_tree().process_frame

	# 检查力量值是否恢复
	var final_strength = attr_comp.get_value(&"strength")
	print("TestStrengthBoost: Final strength: %s (expected: %s)" % [final_strength, initial_strength])

	if abs(final_strength - initial_strength) < 0.01:
		print("TestStrengthBoost: ✅ Test passed! Strength restored correctly.")
	else:
		push_error("TestStrengthBoost: ❌ Test failed! Strength did not restore correctly.")
