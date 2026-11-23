extends RefCounted
## Keeps one controller's replay window. The latest accepted cast remains available through settlement.

const LIMIT: int = 32

var highest_id: int = 0
var last_cast_id: int = 0
var entries: Dictionary[int, Dictionary] = {}

func register(request_id: int, ability_id: StringName, target_id: int) -> void:
	highest_id = request_id
	entries[request_id] = {"ability_id": ability_id, "target_id": target_id}
	if entries.size() <= LIMIT:
		return
	for id: int in entries.keys():
		if id != last_cast_id:
			entries.erase(id)
			return
