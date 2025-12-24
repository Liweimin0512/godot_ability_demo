extends GameplayCueBase
class_name CueAttachedParticle

## 附加粒子特效 Cue
## 用于播放附加到目标节点的持续特效（如光环、Buff 特效、飘字等）

@export var particle_scene: PackedScene = null  ## 粒子特效场景
@export var attach_to_target: bool = true  ## 是否附加到目标节点

func _execute(target: Node, location: Vector3, context: Dictionary) -> void:
	if not is_instance_valid(particle_scene):
		return

	var particle = particle_scene.instantiate()
	if not is_instance_valid(particle):
		return
		
	# 附加到目标节点（通过目标的 get_attachment_point 方法）
	if attach_to_target and is_instance_valid(target):
		if target.has_method("get_attachment_point"):
			var attachment_node = target.get_attachment_point(attachment_point)
			if is_instance_valid(attachment_node):
				attachment_node.add_child(particle)
				particle.position = offset  # 应用偏移量
			else:
				push_error("CueAttachedParticle：挂点无效！")
		else:
			push_error("CueAttachedParticle: 目标没有方法：get_attachment_point！")
	
	else:
		# 在指定位置生成（不附加）
		target.get_tree().current_scene.add_child(particle)
		particle.global_position = location
	
	if particle.has_method("setup_from_context"):
		particle.call("setup_from_context", context)
