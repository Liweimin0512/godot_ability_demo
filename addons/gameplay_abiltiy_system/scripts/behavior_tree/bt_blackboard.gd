extends RefCounted
class_name BTBlackboard

# 只有这部分数据的变化会触发信号 / 中断逻辑
var _data: Dictionary = {}
# 这部分数据变化 **静默处理**，不发信号，专门给 BTNode 存中间状态用
# Key 是 BTNode 引用 (Object)，不是 String
var _node_memory: Dictionary = {}

## 信号：当某个 Key 的值改变时发出
signal value_changed(key: String, value: Variant)
signal value_cleared()

func set_var(key: String, value: Variant) -> void:
	var old_value = _data.get(key)
	# 只有值真的改变了才发信号，避免死循环和性能浪费
	if old_value != value:
		_data[key] = value
		value_changed.emit(key, value)

func get_var(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)

func has_var(key: String) -> Variant:
	return _data.has(key)

func erase_var(key: String) -> Variant:
	return _data.erase(key)

func set_node_data(node: BTNode, value: Variant) -> void:
	_node_memory[node] = value

func get_node_data(node: BTNode, default: Variant = null) -> Variant:
	return _node_memory.get(node, default)

func erase_node_data(node: BTNode) -> void:
	_node_memory.erase(node)
