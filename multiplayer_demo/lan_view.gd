extends Node3D
## Draws the lobby's replicated player positions and the local controller's receipts.

const Avatar = preload("lan_avatar.gd")
const AVATAR_SCENE: PackedScene = preload("lan_avatar.tscn")

var _avatars: Dictionary[int, Avatar] = {}
var _owner_id: int = 0
var _entities: Dictionary = {}
var _receipt: String = ""
var _connection: String = ""

@onready var _avatar_root: Node3D = $Avatars
@onready var _readout: Label = $HUD/Panel/Readout

func render_state(entities: Dictionary, owner_id: int, connection: String) -> void:
	_entities = entities
	_owner_id = owner_id
	_connection = connection
	for id: int in _avatars.keys():
		if not entities.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
	for id: int in entities:
		if not _avatars.has(id):
			var avatar: Avatar = AVATAR_SCENE.instantiate() as Avatar
			_avatar_root.add_child(avatar)
			_avatars[id] = avatar
		_avatars[id].render_state(id, entities[id], id == owner_id)
	_update_text()

func show_receipt(phase: String, result: String) -> void:
	_receipt = phase if result.is_empty() else result
	_update_text()

func clear_receipt() -> void:
	_receipt = ""
	_update_text()

func _update_text() -> void:
	var lines: PackedStringArray = [_connection, "WASD: move   Space / Enter: mark the other player", "Guest: R to disconnect / reconnect"]
	if not _receipt.is_empty():
		lines.append("Last cast: %s" % _receipt)
	for id: int in _entities:
		var state: Dictionary = _entities[id]
		var activity: String = "Windup" if state["cast_active"] else ("Cooldown" if state["cooldown_active"] else "Ready")
		lines.append("%d%s   Mana %.1f   %s%s" % [id, " (You)" if id == _owner_id else "", state["mana"],
			activity, "   Marked" if state["status_active"] else ""])
	_readout.text = "\n".join(lines)
