extends Node
class_name GameplayAttributeComponent

## 游戏性属性组件
## 管理角色的属性系统（攻击力、防御力等）

## 如果传入的属性集不为空，则使用传入的属性集
@export var _active_sets: Array[GameplayAttributeSet] = []
# ID -> Instance（运行时实例）
var _attributes: Dictionary[StringName, GameplayAttributeInstance] = {}

# 信号：当属性值发生变化时发出
signal attribute_value_changed(id: StringName, new_val: float)

## 初始化属性组件
## [param] sets: Array[GameplayAttributeSet] 属性集数组
func initialize(sets: Array[GameplayAttributeSet] = []) -> void:
	if not sets.is_empty():
		_active_sets = sets.duplicate(true)
	
	# 遍历所有属性集，批量创建实例
	for attr_set in _active_sets:
		var new_instances : Dictionary[StringName, GameplayAttributeInstance] = attr_set.instantiate_attributes()
		for id in new_instances:
			_register_instance(id, new_instances[id])

	# 注意：依赖处理会在后续章节中添加

## 获取属性值
## [param] id: StringName 属性ID
## [param] default: float 默认值（如果属性不存在）
## [return] float 属性值
func get_value(id: StringName, default: float = 0.0) -> float:
	if not has_attribute(id):
		push_warning("GameplayAttributeComponent: Attribute with id %s not found" % id)
		return default
	return _attributes[id].get_value()

## 获取属性实例
## [param] id: StringName 属性ID
## [return] GameplayAttributeInstance 属性实例（如果不存在返回 null）
func get_attribute(id: StringName) -> GameplayAttributeInstance:
	return _attributes.get(id, null)

## 设置基础值
## [param] id: StringName 属性ID
## [param] val: float 新的基础值
func set_base_value(id: StringName, val: float) -> bool:
	if has_attribute(id):
		_attributes[id].base_value = val
		return true
	push_warning("AttributeComponent: can not set base value: %s" %id)
	return false

## 检查属性是否存在
## [param] id: StringName 属性ID
## [return] bool 是否存在
func has_attribute(id: StringName) -> bool:
	return _attributes.has(id)

## 注册属性实例（内部方法）
## [param] id: StringName 属性ID
## [param] instance: GameplayAttributeInstance 属性实例
func _register_instance(id: StringName, instance: GameplayAttributeInstance) -> bool:
	if has_attribute(id):
		push_warning("Attribute with id %s already registered" % id)
		return false
	_attributes[id] = instance
	# 转发信号：当实例值变化时，组件也发出信号
	instance.value_changed.connect(func(old, new) -> void: attribute_value_changed.emit(id, new))
	return true
