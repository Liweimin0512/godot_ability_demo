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
