extends Node3D
## Presents a player snapshot without owning any gameplay state.

@export var host_material: Material
@export var guest_material: Material

@onready var _body: MeshInstance3D = $Body
@onready var _mark: MeshInstance3D = $Mark
@onready var _nameplate: Label3D = $Nameplate

func render_state(id: int, state: Dictionary, is_local: bool) -> void:
	global_position = state["position"]
	_body.material_override = host_material if state["faction"] == 1 else guest_material
	_mark.visible = state["status_active"]
	_nameplate.text = "%d%s" % [id, " (You)" if is_local else ""]
