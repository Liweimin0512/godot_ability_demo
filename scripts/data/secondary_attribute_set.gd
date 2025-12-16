extends GameplayAttributeSet
class_name SecondaryAttributeSet

## 二级属性集 (Derived Attributes)
## 负责维护：一级属性 -> 二级属性 的动态映射

# 配置：{ 二级属性ID: { 一级属性ID: 倍率 } }
@export var attribute_mappings : Dictionary[StringName, Dictionary] = {
	# 生存资源类
	&"max_health": {
		&"vitality": 10.0,  # 1点体质 = 10点生命
		&"strength": 2.0    # 1点力量 = 2点生命（副加成）
	},
	&"max_mana": {
		&"intelligence": 10.0 # 1点智力 = 10点法力
	},
	
	# 进攻输出类
	&"phy_attack": {
		&"strength": 2.0,   # 1点力量 = 2点物理攻击
		&"agility": 0.5      # 1点敏捷 = 0.5点物理攻击（副加成）
	},
	&"spell_power": {
		&"intelligence": 2.0 # 1点智力 = 2点法术强度
	},
	
	# 攻速与暴击
	&"crit_rate": {
		&"agility": 0.005   # 1点敏捷 = 0.5% 暴击
	},
	&"attack_speed": {
		&"agility": 0.01    # 1点敏捷 = 1% 攻速
	},
	
	# 防御抗性类
	&"defense": {
		&"vitality": 0.5,   # 1点体质 = 0.5点防御
		&"strength": 0.2    # 1点力量 = 0.2点防御
	}
}
# 格式：{ 一级属性ID: [受影响的二级属性ID, ...] }
var _dependency_cache: Dictionary[StringName, Array] = {}

func instantiate_attributes() -> Dictionary:
	_init_cache()  # 初始化缓存
	return super()

## 解析依赖关系（在组件初始化时调用）
func resolve_dependencies(comp: GameplayAttributeComponent) -> void:
	# 遍历所有配置的二级属性，强制重算一次
	for sec_id in attribute_mappings:
		_recalculate_derived_attribute(comp, sec_id)

## 响应属性变化（实时更新）
func on_attribute_changed(comp: GameplayAttributeComponent, attr_id: StringName, _new_val: float) -> void:
	# 检查缓存：当前变化的属性是否是一级属性？
	if not _dependency_cache.has(attr_id): return
	
	# 获取所有受影响的二级属性列表
	var affected_secondaries = _dependency_cache[attr_id]

	# 逐个重算
	for sec_id in affected_secondaries:
		_recalculate_derived_attribute(comp, sec_id)
	
## 计算衍生属性
## [param] comp: GameplayAttributeComponent 属性组件
## [param] sec_id: StringName 二级属性ID
func _recalculate_derived_attribute(comp: GameplayAttributeComponent, sec_id: StringName) -> void:
	# A. 获取该属性在 Resource 配置中的原始初始值
	var initial_base := 0.0
	for attr_res in attributes:
		if attr_res.attribute_id == sec_id:
			initial_base = attributes[attr_res]
			break

	# B. 计算所有一级属性的加成
	var bonus = 0.0
	var mapping : Dictionary = attribute_mappings[sec_id]  # { strength: 10.0, ... }
	
	for prim_id in mapping:
		var multiplier = mapping[prim_id]
		# 获取一级属性的最终值
		var prim_val = comp.get_value(prim_id)
		bonus += prim_val * multiplier
	
	# C. 设置新的基础值 (NewBase = ConfigBase + Bonus)
	comp.set_base_value(sec_id, initial_base + bonus)

## 初始化依赖缓存
func _init_cache() -> void:
	_dependency_cache.clear()
	for sec_id in attribute_mappings:
		var primaries : Dictionary = attribute_mappings[sec_id]
		for prim_id in primaries:
			if not _dependency_cache.has(prim_id):
				_dependency_cache[prim_id] = []
			_dependency_cache[prim_id].append(sec_id)
