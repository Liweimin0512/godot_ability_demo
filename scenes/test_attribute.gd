extends Node3D

@export var player_data: PlayerData = null
@onready var attribute_component: GameplayAttributeComponent = $GameplayAttributeComponent

func _ready() -> void:
	if not is_instance_valid(player_data):
		push_error("PlayerData is not set")
		return
		
	# 使用 PlayerData 中的属性集初始化组件
	attribute_component.initialize(player_data.attribute_sets)

	# 监听属性变化
	attribute_component.attribute_value_changed.connect(_on_attribute_changed)

	# 测试：打印所有属性值
	_print_all_attributes()

	# 测试修改属性值
	await get_tree().create_timer(1.0).timeout
	print("\n=== Modifying Strength ===")
	attribute_component.set_base_value(&"strength", 15.0)
	await get_tree().process_frame
	print("Strength: ", attribute_component.get_value(&"strength"))  # 应该输出 15

func _on_attribute_changed(id: StringName, new_val: float) -> void:
	print("Attribute %s changed to %f" % [id, new_val])

func _print_all_attributes() -> void:
	print("=== Player Attributes ===")
	print("Strength: ", attribute_component.get_value(&"strength"))
	print("Agility: ", attribute_component.get_value(&"agility"))
	print("Intelligence: ", attribute_component.get_value(&"intelligence"))
	print("Vitality: ", attribute_component.get_value(&"vitality"))
