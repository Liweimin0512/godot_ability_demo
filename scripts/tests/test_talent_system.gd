extends Node

func _ready() -> void:
	# 等待一帧，确保单例已加载
	await get_tree().process_frame

	# 获取玩家实体
	var player = get_tree().get_first_node_in_group("Player")
	if not is_instance_valid(player):
		push_error("TestTalentSystem: Player not found")
		return
	
	# 访问 TalentSystem 单例（AutoLoad 单例直接通过名称访问）
	# 注意：确保在 project.godot 的 [autoload] 中注册了 TalentSystem
	if not is_instance_valid(TalentSystem):
		push_error("TestTalentSystem: TalentSystem singleton not found")
		return
	
	# 测试：检查 TalentSystem 是否正常工作
	print("TestTalentSystem: TalentSystem is ready")
	print("TestTalentSystem: Entity talents count: ", TalentSystem._entity_talents.size())

	# 测试：查询玩家的天赋列表
	var player_talents = TalentSystem.get_entity_talents(player)
	print("TestTalentSystem: Player talents: ", player_talents)
