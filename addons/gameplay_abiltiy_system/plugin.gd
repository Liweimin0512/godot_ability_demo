@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("GameplayAbilitySystem", "scripts/singletons/gameplay_ability_system.gd")
	add_autoload_singleton("DamageCalculator", "scripts/singletons/damage_calculator.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("GameplayAbilitySystem")
	remove_autoload_singleton("DamageCalculator")
