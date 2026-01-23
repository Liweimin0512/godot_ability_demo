extends CharacterBody3D
class_name Player

const STAFF = preload("uid://c1bcskxvw3pvk")
const SWORD = preload("uid://cpfyqq8clupjn")

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
@onready var attribute_component: GameplayVitalAttributeComponent = $GameplayVitalAttributeComponent

var animation_state_machine: AnimationNodeStateMachinePlayback
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var attribute_points_manager: AttributePointsManager = AttributePointsManager.new(10)

# 当前正在瞄准的技能
var current_targeting_ability: GameplayAbilityInstance = null

# 存储每个装备槽位的属性修改器（slot_id -> Array[GameplayAttributeModifier]）
var _equipment_modifiers: Dictionary[StringName, Array] = {}
var _equipment_models: Dictionary[StringName, Node3D]

func _ready() -> void:
	animation_state_machine = animation_tree.get("parameters/StateMachine/playback")
	animation_state_machine.travel("movement")
	# 【测试福利】送 3 瓶药水
	var potion = load("res://data/items/potion_health_small.tres")
	if potion:
		for i in range(3):
			inventory_component.add_item(potion.duplicate())

	AbilityEventBus.game_event_occurred.connect(
		func(event_type: StringName, event_context: Dictionary) -> void:
			if event_type != "ability_button_pressed":
				return
			var ability_id : StringName = event_context.get("ability_id", "")
			if ability_id.is_empty():
				push_error("Player: ability id is empty, 无法预览！")
				return
			_request_ability_preview(ability_id)
	)

	vital_component.initialize(player_data.attribute_sets, player_data.vitals)
	ability_component.initialize(player_data.initial_abilities)

	inventory_component.equip_changed.connect(_on_equip_changed)

	inventory_component.add_item(STAFF.duplicate())
	inventory_component.add_item(SWORD.duplicate())
	
	await get_tree().create_timer(2).timeout
	ability_component.forget_ability(&"damage_reduction_shield_passive")

func _process(_delta):
	# 实时更新指示器位置
	var targeting_ability = ability_component.get_current_targeting_ability()
	if is_instance_valid(targeting_ability):
		var mouse_pos = get_mouse_world_pos()
		targeting_ability.update_targeting(mouse_pos)
		# 同步本地变量（用于其他逻辑）
		current_targeting_ability = targeting_ability

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

	# 获取所有已学会的技能，检查输入匹配
	var ability_id : StringName = ability_component.match_input(event)
	_request_ability_preview(ability_id)

	# 2. 鼠标左键：确认施法
	if event.is_action_pressed("mouse_left"):
		var targeting_ability = ability_component.get_current_targeting_ability()
		if is_instance_valid(targeting_ability):
			var mouse_pos = get_mouse_world_pos()
			# 确认预览，获取 Context 数据 (包含 position/direction)
			var context = targeting_ability.confirm_targeting(mouse_pos)
			context["targets"] = get_tree().get_nodes_in_group("Enemies")
			# 正式激活技能
			ability_component.try_activate_ability(
				targeting_ability.get_definition().ability_id, 
				context
			)
			# 清空当前预览技能（Component 内部会处理）
			current_targeting_ability = null
		get_viewport().set_input_as_handled() # 阻止点击移动

	# 3. 鼠标右键：取消施法
	if event.is_action_pressed("mouse_right"):
		var targeting_ability = ability_component.get_current_targeting_ability()
		if is_instance_valid(targeting_ability):
			ability_component.cancel_ability_preview()
			current_targeting_ability = null
			get_viewport().set_input_as_handled()

## 辅助函数：获取鼠标在 3D 世界的坐标
func get_mouse_world_pos() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# 简单的射线检测平面 (y=0)
	# 实际项目中建议使用 PhysicsRayQueryParameters3D 检测地表层
	var t = -ray_origin.y / ray_dir.y
	if t >= 0:
		return ray_origin + ray_dir * t
	return Vector3.ZERO

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

func get_visuals() -> Node3D:
	return visuals

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

func _request_ability_preview(ability_id: StringName) -> void:
	if ability_id.is_empty():
		return
	# 请求预览
	var ability = ability_component.request_ability_preview(ability_id)
	if ability  == null:
		# 返回 null 说明是智能施法或瞬发，立即执行
		var mouse_pos = get_mouse_world_pos()
		# 即使是智能施法，最好也让 Strategy 计算一下修正坐标，
		# 但为了简化，这里直接传位置，或者手动获取 strategy 计算
		var smart_context = {"target_position": mouse_pos, "facing_direction": _get_facing_direction()}
		var success = ability_component.try_activate_ability(ability_id, smart_context)
		if success:
			get_viewport().set_input_as_handled()
			print("技能释放成功: ", ability_id)

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

func _get_facing_direction() -> Vector3:
	return visuals.global_transform.basis * Vector3.FORWARD

## 应用装备的属性修改器
## [param] equip: Equip 装备实例（实际应为 GameplayEquip）
## [param] equip_slot_name: StringName 装备槽名称
func _apply_equipment_modifiers(equip: Equip, equip_slot_name: StringName) -> void:
	if not is_instance_valid(equip) or not is_instance_valid(attribute_component):
		push_error("Player: equip or attribute_component is not valid!")
		return

	# 获取装备的属性字典
	var attributes = equip.attributes
	if attributes.is_empty():
		return
		
	# 存储该装备的所有修改器
	var modifiers: Array[GameplayAttributeModifier] = []

	# 遍历装备的所有属性，创建修改器
	for attr_name in attributes.keys():
		var attr_value = attributes[attr_name]
		if attr_value == 0.0:
			continue

		# 创建属性修改器（使用 ADD 类型，直接加到基础值上）
		var modifier := GameplayAttributeModifier.new()
		modifier.attribute_id = StringName(attr_name)
		modifier.value = attr_value
		modifier.modifier_type = GameplayAttributeModifier.ModifierType.ADD
		modifier.source_id = str(equip.get_instance_id())

		# 检查属性是否存在
		if not attribute_component.has_attribute(modifier.attribute_id):
			push_warning("Player: Attribute '%s' not found in attribute_component, skipping equipment modifier" % attr_name)
			continue

		# 应用修改器
		attribute_component.add_modifier(modifier)
		modifiers.append(modifier)

		print("Player: Applied equipment modifier - %s: +%.1f (from %s)" % [attr_name, attr_value, equip.name])

	# 存储修改器（使用装备槽名称作为键，因为同一槽位只能有一个装备）
	if not modifiers.is_empty():
		_equipment_modifiers[equip_slot_name] = modifiers

func _remove_equipment_modifiers(equip_slot_name: StringName) -> void:
	if not _equipment_modifiers.has(equip_slot_name):
		return

	if not is_instance_valid(attribute_component):
		# 如果属性组件已销毁，直接清除记录
		_equipment_modifiers.erase(equip_slot_name)
		return

	# 获取该装备槽的所有修改器
	var modifiers = _equipment_modifiers[equip_slot_name]

	# 移除所有修改器
	for modifier in modifiers:
		if is_instance_valid(modifier):
			attribute_component.remove_modifier(modifier)
			print("Player: Removed equipment modifier - %s: %.1f" % [modifier.attribute_id, modifier.value])

	# 清除记录
	_equipment_modifiers.erase(equip_slot_name)

## 应用装备模型
## [param] equip: Equip 装备实例（实际应为 GameplayEquip）
## [param] equip_slot_name: StringName 装备槽名称
func _apply_equipment_model(equip: Equip, equip_slot_name: StringName) -> void:
	# 检查是否为 GameplayEquip 实例（业务层装备类）
	if not equip is GameplayEquip:
		# 如果不是 GameplayEquip，说明没有装备模型配置，直接返回
		return

	var gameplay_equip = equip as GameplayEquip

	# 获取装备的挂点名称（默认为 hand_right）
	var attachment_point : StringName = gameplay_equip.attachment_point
	if attachment_point.is_empty():
		return

	if not is_instance_valid(gameplay_equip) or not is_instance_valid(gameplay_equip.equip_model_scene):
		return

	# 根据挂点名称获取对应的 BoneAttachment3D 节点
	var attachment_node: BoneAttachment3D = get_attachment_point(attachment_point)
	if not is_instance_valid(attachment_node):
		push_warning("Player: Attachment point '%s' not found for equipment '%s'" % [attachment_point, equip.name])
		return

	# 实例化装备模型
	var model_instance = gameplay_equip.equip_model_scene.instantiate()
	if not is_instance_valid(model_instance):
		push_warning("Player: Failed to instantiate equipment model for '%s'" % gameplay_equip.name)
		return

	# 添加到挂点节点
	attachment_node.add_child(model_instance)
	_equipment_models[equip_slot_name] = model_instance

	print("Player: Applied equipment model '%s' to attachment point '%s'" % [gameplay_equip.name, attachment_point])

## 移除装备模型
## [param] equip_slot_name: StringName 装备槽名称
func _remove_equipment_model(equip_slot_name: StringName) -> void:
	if not _equipment_models.has(equip_slot_name):
		return
	var model_instance = _equipment_models[equip_slot_name]
	if is_instance_valid(model_instance):
		model_instance.queue_free()
		print("Player: Removed equipment model from slot '%s'" % equip_slot_name)
	# 清除记录
	_equipment_models.erase(equip_slot_name)

## 装备变化回调
func _on_equip_changed(equip_slot_name: StringName, equip: Equip) -> void:
	if not is_instance_valid(attribute_component):
		return

	# 如果是卸下装备（equip 为 null），移除旧装备的属性修改器
	if equip == null:
		_remove_equipment_modifiers(equip_slot_name)
		_remove_equipment_model(equip_slot_name)
		return
		
	# 如果是替换装备，先移除旧装备的属性修改器
	_remove_equipment_modifiers(equip_slot_name)
	_remove_equipment_model(equip_slot_name)

	# 应用新装备的属性修改器
	_apply_equipment_modifiers(equip, equip_slot_name)
	_apply_equipment_model(equip,equip_slot_name)
