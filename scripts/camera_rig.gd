class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera: behind, above, and offset to one side.
## Mouse orbits, wheel zooms, V swaps shoulders, pulls in when terrain is in the way.

var cam: Camera3D
var target: Node3D
var world: VoxelWorld

var yaw := 0.0
var pitch := -0.38
var dist := 5.5
var sensitivity := 0.0026
var shoulder := 0.65        # metres to the side (positive = right shoulder)
var _cur_shoulder := 0.65
var extra_dist := 0.0       # added distance (e.g. pulled back while rowing)
var _cur_extra := 0.0
var _cur_dist := 5.5
var _pivot := Vector3.ZERO
var _snapped := false


func _ready() -> void:
	top_level = true
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.05
	cam.far = 700.0
	add_child(cam)
	cam.current = true


func _unhandled_input(e: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		yaw -= e.relative.x * sensitivity
		pitch = clampf(pitch - e.relative.y * sensitivity, -1.35, 0.85)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 0.6, 1.8, 16.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 0.6, 1.8, 16.0)
	elif e.is_action_pressed("swap_shoulder"):
		shoulder = -shoulder


func view_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _process(delta: float) -> void:
	if target == null:
		return
	var want: Vector3 = target.global_position + Vector3(0, 1.55, 0)
	if not _snapped or _pivot.distance_to(want) > 4.0:
		_pivot = want
		_snapped = true
	_pivot = _pivot.lerp(want, 1.0 - exp(-delta * 20.0))
	var b := view_basis()
	var back := b.z
	# Side offset: shrink it when a wall is beside the player's head.
	var side := Basis(Vector3.UP, yaw).x
	var want_side := shoulder
	if world != null:
		var sh := world.raycast(_pivot, side * signf(shoulder), absf(shoulder) + 0.3, true)
		if not sh.is_empty():
			want_side = signf(shoulder) * maxf(0.0, sh.dist - 0.3)
	_cur_shoulder = lerpf(_cur_shoulder, want_side, 1.0 - exp(-delta * 10.0))
	var origin := _pivot + side * _cur_shoulder
	_cur_extra = lerpf(_cur_extra, extra_dist, 1.0 - exp(-delta * 3.0))
	var full := dist + _cur_extra
	var d := full
	if world != null:
		var hit := world.raycast(origin, back, full + 0.3, true)
		if not hit.is_empty():
			d = maxf(0.5, hit.dist - 0.3)
	if d < _cur_dist:
		_cur_dist = d
	else:
		_cur_dist = lerpf(_cur_dist, d, 1.0 - exp(-delta * 5.0))
	cam.global_transform = Transform3D(b, origin + back * _cur_dist)
	# Hide the character when the camera is squeezed right up against it.
	if target is Player:
		(target as Player).model.visible = _cur_dist > 1.0
