class_name RemotePlayer
extends Node3D
## Another co-op player, driven by network state snapshots with interpolation.

var model: CharacterModel
var peer_id := 0
var player_name: String = ""
var label: Label3D = null
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _speed := 0.0
var _on_ground := true
var _swimming := false
var _swing_seen := 0
var _has_state := false

## Set by BoatManager while this player sits in a boat.
var seat_boat: Boat = null
var seat_index := 0


func setup(id: int) -> void:
	peer_id = id
	model = CharacterModel.new()
	add_child(model)
	model.setup(Palette.COAT_B, Palette.HAT_B)
	label = Label3D.new()
	label.text = player_name if player_name != "" else ("Player %d" % id if id != 1 else "Host")
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1, 0.97, 0.9)
	label.pixel_size = 0.004
	label.no_depth_test = true
	add_child(label)


func set_player_name(p_name: String) -> void:
	player_name = p_name
	if label != null:
		label.text = player_name


func apply_state(pos: Vector3, yaw: float, speed: float, flags: int, tool: int, swings: int) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_speed = speed
	_on_ground = flags & 1 != 0
	_swimming = flags & 2 != 0
	model.crouching = flags & 4 != 0
	model.set_tool(tool)
	if swings != _swing_seen:
		_swing_seen = swings
		model.swing()
	if not _has_state or seat_boat != null:
		position = pos
		_has_state = true


func _process(delta: float) -> void:
	if seat_boat != null and is_instance_valid(seat_boat):
		var st := seat_boat.seat_transform(seat_index)
		position = st.origin
		model.rotation = st.basis.get_euler()
		model.animate_seated(delta, seat_boat.row_phase, seat_boat.row_power if seat_index == 0 else 0.0)
		return
	model.rotation.x = 0.0
	model.rotation.z = 0.0
	position = position.lerp(_target_pos, 1.0 - exp(-delta * 14.0))
	model.rotation.y = lerp_angle(model.rotation.y, _target_yaw, 1.0 - exp(-delta * 14.0))
	model.animate(delta, _speed, _on_ground, _swimming)
