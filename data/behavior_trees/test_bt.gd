extends Node3D

@onready var bt_runner: BTRunner = $BTRunner

var mana : int = 100
var has_mana: bool = true
var blackboard : BTBlackboard

func _ready() -> void:
	blackboard = bt_runner.get_blackboard()
	blackboard.value_changed.connect(_on_blackboard_value_changed)
	#blackboard.set_var("has_mana", has_mana)
	#blackboard.set_var("mana", mana)
	# 初始没有敌人，执行巡逻
	blackboard.set_var("has_enemy", false)
	# 3 秒后出现敌人，应该中断巡逻，执行攻击
	await get_tree().create_timer(3.0).timeout
	blackboard.set_var("has_enemy", true)
	
	await get_tree().create_timer(3.0).timeout
	blackboard.set_var("has_enemy", false)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		blackboard.set_var("event_input_received", true)

func _on_blackboard_value_changed(key: String, value: Variant) -> void:
	if key == "mana":
		mana = value
		if mana <= 0:
			has_mana = false
			blackboard.set_var("has_mana", has_mana)
