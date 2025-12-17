extends Node3D

@export var player_data: PlayerData = null

@onready var attribute_component: GameplayAttributeComponent = $GameplayAttributeComponent

## HealthVital 和 ManaVital 资源
@export var health_vital_res: HealthVital = null
@export var mana_vital_res: ManaVital = null

## Vital 实例
var health_vital: HealthVital
var mana_vital: ManaVital

func _ready() -> void:
	if not is_instance_valid(player_data):
		push_error("PlayerData is not set")
		return

	# 初始化属性系统
	attribute_component.initialize(player_data.attribute_sets)

	# 创建 Vital 实例
	_setup_vitals()

	# 运行测试
	await get_tree().create_timer(0.5).timeout
	_run_tests()

## 设置 Vital 实例
func _setup_vitals() -> void:
	# 创建 HealthVital 实例
	if is_instance_valid(health_vital_res):
		health_vital = health_vital_res.duplicate(true)
		health_vital._owner_comp = attribute_component
		health_vital._update_cached_max()
		health_vital.current_value = health_vital._cached_max

		# 连接信号
		health_vital.value_changed.connect(_on_health_changed)
		health_vital.depleted.connect(_on_health_depleted)
		health_vital.full.connect(_on_health_full)

	# 创建 ManaVital 实例
	if is_instance_valid(mana_vital_res):
		mana_vital = mana_vital_res.duplicate(true)
		mana_vital._owner_comp = attribute_component
		mana_vital._update_cached_max()
		mana_vital.current_value = mana_vital._cached_max

		# 连接信号
		mana_vital.value_changed.connect(_on_mana_changed)

func _run_tests() -> void:
	print("\n=== Day 07: Testing Vital System (Basic) ===")
	# 测试 1：初始状态
	_test_initial_state()
	
	await get_tree().create_timer(1.0).timeout
	
	# 测试 2：修改 Vital 值
	_test_modify_value()
	
	await get_tree().create_timer(1.0).timeout
	
	# 测试 3：属性变化时 Vital 上限更新
	_test_attribute_change()

## 测试 1：初始状态
func _test_initial_state() -> void:
	print("\n--- Test 1: Initial State ---")
	if is_instance_valid(health_vital):
		print("Health: %.1f / %.1f (%.1f%%)" % [
			health_vital.current_value,
			health_vital._cached_max,
			health_vital.get_percent() * 100.0
		])
	if is_instance_valid(mana_vital):
		print("Mana: %.1f / %.1f (%.1f%%)" % [
			mana_vital.current_value,
			mana_vital._cached_max,
			mana_vital.get_percent() * 100.0
		])

## 测试 2：修改 Vital 值
func _test_modify_value() -> void:
	print("\n--- Test 2: Modify Value ---")
	if is_instance_valid(health_vital):
		print("Before: %.1f / %.1f" % [health_vital.current_value, health_vital._cached_max])
		health_vital.apply_damage(DamageInfo.new(30.0), self)
		print("After -30 HP: %.1f / %.1f" % [health_vital.current_value, health_vital._cached_max])
	
		# 测试治疗
		health_vital.heal(20.0, self)
		print("After +20 HP: %.1f / %.1f" % [health_vital.current_value, health_vital._cached_max])

## 测试 3：属性变化时 Vital 上限更新
func _test_attribute_change() -> void:
	print("\n--- Test 3: Attribute Change ---")
	if not is_instance_valid(health_vital): return

	var old_max = health_vital._cached_max
	var old_current = health_vital.current_value

	print("Before: %.1f / %.1f" % [old_current, old_max])
	
	# 增加体质属性（应该增加最大生命值）
	var current_vitality = attribute_component.get_value(&"vitality")
	attribute_component.set_base_value(&"vitality", current_vitality + 10.0)
	health_vital._update_cached_max()

	await get_tree().process_frame
	print("After +10 Vitality:")
	print("  Max Health: %.1f (was %.1f)" % [health_vital._cached_max, old_max])
	print("  Current Health: %.1f (should remain %.1f)" % [health_vital.current_value, old_current])
	
	# 验证：当前值应该保持不变，最大值应该增加
	assert(health_vital.current_value == old_current, "Current HP should remain unchanged")
	assert(health_vital._cached_max > old_max, "Max HP should increase")

func _on_health_changed(current: float, max: float, percent: float) -> void:
	print("Health changed: %.1f / %.1f (%.1f%%)" % [current, max, percent * 100.0])

func _on_health_depleted() -> void:
	print("⚠️ Health depleted!")
	
func _on_health_full() -> void:
	print("✓ Health full!")

func _on_mana_changed(current: float, max: float, percent: float) -> void:
	print("Mana changed: %.1f / %.1f (%.1f%%)" % [current, max, percent * 100.0])
