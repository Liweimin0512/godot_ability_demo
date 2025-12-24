extends Node

## 游戏提示管理器（单例）
## 负责执行 Cue，处理所有表现相关的脏活累活
## 采用组合模式，将具体表现处理交给 Cue 组件

## 执行 Cue（核心接口）
## [param] cue: GameplayCue Cue 资源
## [param] target: Node 目标节点（用于计算挂点位置）
## [param] context: Dictionary 上下文信息（可选，如伤害值、治疗值等）
func execute_cue(cue: GameplayCue, target: Node, context: Dictionary = {}) -> void:
	if not is_instance_valid(cue):
		return

	# 遍历所有 Cue 组件并执行
	for cue_component in cue.cues:
		if not is_instance_valid(cue_component):
			continue

		# 计算挂点位置（使用 AttachmentPointUtils 工具类）
		var location = _get_attachment_point_position(target, cue_component.attachment_point)
		
		# 应用偏移量（如果配置了）
		location += cue_component.offset

		# 执行 Cue 组件
		cue_component.execute(target, location, context)

## 获取挂点位置（使用 AttachmentPointUtils 工具类）
## [param] target: Node 目标节点
## [param] attachment_point: StringName 挂点名（如 "head", "foot", "weapon" 等）
## [return] Vector3 挂点位置（世界坐标）
func _get_attachment_point_position(target: Node, attachment_point: StringName) -> Vector3:
	if not is_instance_valid(target):
		return Vector3.INF
	
	# 如果目标实现了 get_attachment_point 方法，直接调用
	if target.has_method("get_attachment_point"):
		var point = target.get_attachment_point(attachment_point)
		if is_instance_valid(point) and point is Node3D:
			return (point as Node3D).global_position
	else:
		push_warning("target dont has method get_attachment_point!")

	return Vector3.INF
