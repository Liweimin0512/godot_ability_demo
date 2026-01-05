extends CharacterBody3D
class_name Player

@export var player_data : PlayerData
@export var _attachment_points : Dictionary[StringName, BoneAttachment3D]

@export_group("Movement")
@export var speed: float = 5.0
@export var acceleration: float = 20.0 # 加速度：决定起步快慢
@export var rotation_speed: float = 12.0 # 转身速度

@onready var visuals: Node3D = $Visuals
@onready var animation_tree: AnimationTree = $Visuals/Barbarian/AnimationTree
@onready var interaction_area: Area3D = $Visuals/InteractionArea
@onready var inventory_component: C_Inventory = $InventoryComponent
@onready var vital_component: GameplayVitalAttributeComponent = $GameplayVitalAttributeComponent
@onready var ability_component: GameplayAbilityComponent = $GameplayAbilityComponent

var animation_state_machine: AnimationNodeStateMachinePlayback
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var attribute_points_manager: AttributePointsManager = AttributePointsManager.new(10)

func _ready() -> void:
	animation_state_machine = animation_tree.get("parameters/StateMachine/playback")
	animation_state_machine.travel("movement")
	# 【测试福利】送 3 瓶药水
	var potion = load("res://data/items/potion_health_small.tres")
	if potion:
		for i in range(3):
			inventory_component.add_item(potion.duplicate())

	vital_component.initialize(player_data.attribute_sets, player_data.vitals)
	ability_component.initialize(player_data.initial_abilities)

	# 测试1：学习技能
	ability_component.ability_completed.connect(
		func(ability: GameplayAbilityInstance) -> void:
			print("%s 技能执行完成！" %ability.get_definition().ability_name)
	)
	ability_component.ability_learned.connect(
		func(ability: GameplayAbilityInstance) -> void:
			print("%s 技能学习完成！" %ability.get_definition().ability_name)
	)
	
	var fireball_ability = preload("res://data/abilities/fireball_ability.tres")
	ability_component.learn_ability(fireball_ability)
	print("火球术已学习")

	# 测试2：检查技能是否可用
	assert(ability_component.can_activate_ability("attack"), "技能应该可用")

	# 测试3：激活技能
	var success = ability_component.try_activate_ability("attack", {})
	assert(success, "技能应该成功激活")

	print("✅ 技能组件测试通过")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	# 【标签系统】检查是否被眩晕或定身（无法移动）
	if TagManager.has_tag(self, &"state.stunned") or TagManager.has_tag(self, &"state.rooted"):
		# 眩晕/定身状态：停止移动，但保持重力
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		_set_movement_blend_position(velocity.length())
		move_and_slide()
		return
		
	# 1. 获取输入 (2D向量)
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 2. 转换为 3D 方向 (X/Z 平面)
	var direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	if direction:
		# 3. 移动逻辑：利用 move_toward 实现平滑加速
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
		
		# 4. 旋转逻辑：让 Visuals 平滑转向移动方向
		# 注意：模型朝向 -Z（Godot 默认前方）
		# - input_dir.x 是左右（对应 3D 的 X 轴，正值为右）
		# - input_dir.y 是前后（对应 3D 的 Z 轴，正值为前，但在 2D 输入映射中是 Y）
		# 当 input_dir.y = 1（向上键，向前）时，应该朝向 -Z
		# 由于模型从 +Z 改为 -Z（旋转了 180 度），角度需要加 π
		var base_angle = atan2(input_dir.x, input_dir.y)
		var target_angle = base_angle + PI
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)
	else:
		# 停止逻辑：利用 move_toward 实现平滑减速 (惯性停车)
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		
	_set_movement_blend_position(velocity.length())
	# 6. 应用移动
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
	#elif event.is_action_pressed("attack"):
		#_play_anim("attack")

	elif event.is_action_pressed("ui_accept"):
		_test_damage()
	
	# 过滤非按下和重复事件
	if not event.is_pressed() or event.is_echo():
		return

	# 获取所有已学会的技能
	var ability_id : StringName = ability_component.match_input(event)
	if not ability_id.is_empty():
		var success = ability_component.try_activate_ability(ability_id)
		if success:
			get_viewport().set_input_as_handled()
			print("技能释放成功: ", ability_id)

func _test_damage() -> void:
	if not is_instance_valid(vital_component):
		return

	var health_vital = vital_component.get_vital(&"health")
	if not is_instance_valid(health_vital) or not health_vital is HealthVital:
		return
	
	# 创建简单的伤害信息
	var damage_info = DamageInfo.new(self, null, 10.0)
	
	# 应用伤害
	health_vital.apply_damage(damage_info, self)
	print("Test: Applied 10 damage")

func get_inventory() -> C_Inventory:
	return inventory_component

func get_attachment_point(attachment_point: StringName) -> Node3D:
	return _attachment_points.get(attachment_point, null)

func get_facing_angle() -> float:
	if is_instance_valid(visuals) and visuals is Node3D:
		return visuals.rotation.y
	return 0.0

func play_animation(anim_name : StringName, anim_speed: float = 1.0) -> void:
	_play_anim(anim_name, anim_speed)

func _play_anim(anim_name: String, anim_speed: float = 1.0) -> void:
	if not is_instance_valid(animation_state_machine):
		animation_state_machine = animation_tree.get("parameters/StateMachine/playback")
	if not is_instance_valid(animation_state_machine): return
	animation_state_machine.travel(anim_name)
	animation_tree.set("parameters/TimeScale/scale", anim_speed)
	
func _set_movement_blend_position(blend_position: float) -> void:
	animation_tree.set("parameters/StateMachine/movement/blend_position", blend_position)

func _try_interact() -> void:
	# 获取探测区域内所有的物体
	var bodies = interaction_area.get_overlapping_areas() # 假设交互物也是Area3D
	if bodies.size() > 0:
		# 找到最近的一个 (简单处理：取第一个)
		var target = bodies[0]
		# 检查目标是否有 interact 方法
		if target.has_method("interact"):
			target.interact()
