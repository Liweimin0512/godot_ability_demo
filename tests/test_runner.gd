extends Node
## Runs the named suites and returns a process status for automated checks.

const UNIT_TEST = preload("res://tests/unit/ability_rules_test.gd")
const COMBO_TEST = preload("res://tests/integration/sword_combo_test.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().create_timer(40.0).timeout.connect(_on_timeout)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var suite: String = args[0] if not args.is_empty() else "all"
	if args.size() > 1 or suite not in ["all", "unit", "integration"]:
		push_error("Usage: test_runner.tscn -- [all|unit|integration]")
		get_tree().quit(2)
		return

	var failures: Array[String] = []
	if suite != "integration":
		var unit: UNIT_TEST = UNIT_TEST.new()
		add_child(unit)
		var unit_failures: Array[String] = unit.run()
		failures.append_array(unit_failures)
		if unit_failures.is_empty():
			print("PASS unit: ability rules")
	if suite != "unit":
		var integration: COMBO_TEST = COMBO_TEST.new()
		add_child(integration)
		var combo_failures: Array[String] = await integration.run()
		failures.append_array(combo_failures)
		if combo_failures.is_empty():
			print("PASS integration: sword combo")
	for failure: String in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS Godot demo tests (%s)" % suite)
	get_tree().quit(0 if failures.is_empty() else 1)

func _on_timeout() -> void:
	push_error("Godot demo tests timed out")
	get_tree().quit(1)
