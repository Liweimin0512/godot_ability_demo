extends Equip
class_name GameplayEquip

@export var equip_model_scene : PackedScene
@export var attachment_point : StringName = "hand_r"

@export var abilities : Array[GameplayAbilityDefinition]
