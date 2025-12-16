extends RefCounted
class_name GameplayAttributeInstance

## 属性运行时实例
## 核心职责：维护 BaseValue，管理 Modifiers，计算 FinalValue
## 注意：当前版本是简化版，只包含基础值。Modifier 系统会在后续章节中添加

var attribute_def: GameplayAttribute  # 属性定义（资源）
var base_value: float = 0.0 : set = _set_base_value  # 基础值

var _cached_final_value: float = 0.0
var _dirty : bool = true

signal value_changed(old_val: float, new_value: float)

func _init(attr_res: GameplayAttribute = null, init_val: float = 0.0) -> void:
	attribute_def = attr_res
	base_value = init_val

## 获取最终值（当前实现：直接返回基础值，后续会加入 Modifier 计算）
## [return] float 最终值
func get_value() -> float:
	if _dirty:
		_recalculate_value()
	return _cached_final_value

## 重新计算最终值（当前版本：只处理基础值和范围限制）
func _recalculate_value() -> void:
	var final = base_value
	
	# 限制范围
	if is_instance_valid(attribute_def):
		final = clampf(final, attribute_def.min_value, attribute_def.max_value)
	else:
		push_warning("AttributeInstance: attribute def is not valid!")
	
	_cached_final_value = final
	_dirty = false

## 设置基础值（会触发重新计算）
func _set_base_value(val: float) -> void:
	if base_value == val:
		return
	
	var old_val = _cached_final_value
	base_value = val
	_dirty = true
	var new_value = get_value()
	
	# 如果属性发生改变，那么发出信号
	if not is_equal_approx(old_val, new_value):
		value_changed.emit(old_val, new_value)
