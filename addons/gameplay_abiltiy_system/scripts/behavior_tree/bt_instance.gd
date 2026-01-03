extends RefCounted
class_name BTInstance

var agent: Node
var tree_root: BTNode
var blackboard: BTBlackboard

# 当前正在运行的节点路径（用于判断优先级）
var active_nodes: Array[BTNode] = []

# 已注册的观察者列表
var _observers: Array[BTNode] = []

# 节点状态记录（用于判断节点是否在运行）
var _node_status: Dictionary = {}

# 节点执行记录（用于调试面板）
var execution_history: Array[Dictionary] = []
var _max_history_size: int = 100
var _current_frame: int = 0

func _init(p_agent: Node, p_tree_root: BTNode, p_blackboard: BTBlackboard = null) -> void:
	agent = p_agent
	tree_root = p_tree_root
	blackboard = p_blackboard if is_instance_valid(p_blackboard) else BTBlackboard.new()
	blackboard.value_changed.connect(_on_blackboard_changed)

func tick(delta: float) -> int:
	if not tree_root or not is_instance_valid(agent):
		return BTNode.Status.FAILURE

	_current_frame += 1

	# 从 Root 开始 Tick
	var result = tree_root.tick(self, delta)

	return result

func set_node_status(node: BTNode, status: int) -> void:
	_node_status[node] = status

func get_node_status(node: BTNode, default: int = -1) -> int:
	return _node_status.get(node, default)

func has_node_status(node: BTNode) -> bool:
	return _node_status.has(node)

func erase_node_status(node: BTNode) -> void:
	_node_status.erase(node)

func clear_node_status() -> void:
	_node_status.clear()

## 记录节点执行（由 BTNode.tick 调用）
func record_node_execution(node: BTNode, status: int) -> void:
	_record_execution(node, status)

## 内部方法：记录执行历史
func _record_execution(node: BTNode, status: int) -> void:
	if not is_instance_valid(node):
		return

	var timestamp = Time.get_ticks_msec() / 1000.0  # 转换为秒

	# 检查是否与上一条记录相同（避免重复记录）
	if execution_history.size() > 0:
		var last_record = execution_history[-1]
		if last_record.get("node") == node and last_record.get("status") == status:
			# 相同节点相同状态，只更新时间戳
			last_record["timestamp"] = timestamp
			last_record["frame"] = _current_frame
			return

	# 添加新记录
	execution_history.append({
		"node": node,
		"status": status,
		"timestamp": timestamp,
		"frame": _current_frame
	})

	# 限制历史记录大小
	if execution_history.size() > _max_history_size:
		execution_history.pop_front()

func _on_blackboard_changed(key: String, value: Variant) -> void:
	pass
