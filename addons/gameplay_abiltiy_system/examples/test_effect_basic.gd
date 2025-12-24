extends Node3D

@onready var player: Node3D = $Player
@onready var enemy: Node3D = $Enemy
@onready var player_vital_component: GameplayVitalAttributeComponent = $Player/GameplayVitalAttributeComponent
@onready var enemy_vital_component: GameplayVitalAttributeComponent = $Enemy/GameplayVitalAttributeComponent

@export var player_data: PlayerData = null
@export var damage_effect_res: GE_ApplyDamage = null
@export var heal_effect_res: GE_ModifyVital = null

func _ready() -> void:
	if not is_instance_valid(player_data):
		push_error("PlayerData is not set")
		return

	player_vital_component.initialize(player_data.attribute_sets, player_data.vitals)
	enemy_vital_component.initialize(player_data.attribute_sets, player_data.vitals)
	var tag_team_enemy : GameplayTag = GameplayTag.new()
	tag_team_enemy.id = "Team.Enemy"
	tag_team_enemy.display_name = "敌方队伍"
	TagManager.initialize(tag_team_enemy)
	TagManager.add_tag(enemy, "Team.Enemy")
	
	await get_tree().create_timer(0.5).timeout
	_run_tests()

func _run_tests() -> void:
	print("\n=== Day 13: Testing Basic Effects ===")

	# 测试 1：伤害效果
	_test_damage_effect()
	await get_tree().create_timer(1.0).timeout

	# 测试 2：治疗效果
	_test_heal_effect()
	await get_tree().create_timer(1.0).timeout

	# 测试 1：标签过滤（target_blocked_tags）
	_test_tag_filter()
	await get_tree().create_timer(1.0).timeout

## 测试 1：伤害效果
func _test_damage_effect() -> void:
	print("\n--- Test 1: Damage Effect ---")
	var health_vital = enemy_vital_component.get_vital(&"health")
	if not is_instance_valid(health_vital):
		return

	var initial_health = health_vital.current_value
	print("Enemy initial health: %.1f" % initial_health)

	# 创建上下文
	var context = {}
	context["instigator"] = player
	context["damage_multiplier_modifier"] = 2

	# 应用效果
	damage_effect_res.apply(enemy, player, context)
	await get_tree().process_frame

	var final_health = health_vital.current_value
	print("Enemy final health: %.1f" % final_health)

	assert(final_health < initial_health, "Damage effect test failed: Health should decrease")
	print("✅ Damage effect test passed: %.1f -> %.1f" % [initial_health, final_health])

## 测试 2：治疗效果
func _test_heal_effect() -> void:
	print("\n--- Test 2: Heal Effect ---")
	var health_vital = player_vital_component.get_vital(&"health")
	if not is_instance_valid(health_vital):
		return
		
	# 先扣血
	health_vital.modify_value(-30.0)
	var initial_health = health_vital.current_value
	print("Player initial health: %.1f" % initial_health)

	# 创建上下文
	var context = {}

	# 应用效果
	heal_effect_res.apply(player, player, context)
	await get_tree().process_frame

	var final_health = health_vital.current_value
	print("Player final health: %.1f" % final_health)

	assert(final_health > initial_health, "Heal effect test failed: Health should increase")
	print("✅ Heal effect test passed: %.1f -> %.1f" % [initial_health, final_health])

## 测试 3：标签过滤
func _test_tag_filter() -> void:
	print("\n--- Test 3: Tag Filter (target_blocked_tags) ---")

	var health_vital_player = player_vital_component.get_vital(&"health")
	var health_vital_enemy = enemy_vital_component.get_vital(&"health")

	if not is_instance_valid(health_vital_player) or not is_instance_valid(health_vital_enemy):
		return
		
	var initial_health_player = health_vital_player.current_value
	var initial_health_enemy = health_vital_enemy.current_value

	print("Player initial health: %.1f" % initial_health_player)
	print("Enemy initial health: %.1f" % initial_health_enemy)
	

	var damage_effect = damage_effect_res.duplicate()
	var filter_target_by_tags = FilterTargetByTags.new()
	filter_target_by_tags.required_tags.append(
		"Team.Enemy"
	)
	damage_effect.filters.append(
		filter_target_by_tags
	)
	# 对玩家应用（不应该生效）
	damage_effect.apply(player, player, {})
	await get_tree().process_frame

	# 对敌人应用（应该生效）
	damage_effect.apply(enemy, player, {})
	await get_tree().process_frame
	
	var final_health_player = health_vital_player.current_value
	var final_health_enemy = health_vital_enemy.current_value

	print("Player final health: %.1f" % final_health_player)
	print("Enemy final health: %.1f" % final_health_enemy)
	
	# 验证：两个目标都应该受到伤害
	assert(final_health_player == initial_health_player, "Player not should take damage")
	assert(final_health_enemy < initial_health_enemy, "Enemy should take damage")
	print("✅ Tag filter test passed: Both targets took damage")	
