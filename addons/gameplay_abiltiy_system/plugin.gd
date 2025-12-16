@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("GameplayAbilitySystem", "scripts/singletons/gameplay_ability_system.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("GameplayAbilitySystem")
