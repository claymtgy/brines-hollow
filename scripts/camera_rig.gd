class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera and toggleable first-person camera.
## Mouse orbits, wheel zooms, V swaps shoulders, F5 / P toggles first-person view.

signal first_person_changed(enabled: bool)

var cam: Camera3D
var target: Node3D
var world: VoxelWorld

var yaw := 0.0
var pitch := -0.38
var dist := 5.5
var first_person := false
var sensitivity := 0.0026
var invert_y := false
var controller_look_speed := 2.6
var foliage_fade := true
var shoulder := 1.05        # metres to the side (positive = right shoulder)
var _cur_shoulder := 1.05
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


func set_first_person(enabled: bool) -> void:
	if first_person == enabled:
		return
	first_person = enabled
	if first_person:
		_cur_dist = 0.0
		_cur_shoulder = 0.0
	else:
		pitch = clampf(pitch, -1.35, 0.85)
		_cur_dist = dist
	if target is Player and (target as Player).model != null:
		(target as Player).model.set_first_person_view(first_person)
		(target as Player).model.visible = true if first_person else (_cur_dist > 1.0)
	first_person_changed.emit(first_person)


func toggle_first_person() -> void:
	set_first_person(not first_person)
	if target is Player and (target as Player).hud != null:
		(target as Player).hud.show_toast("Camera: First-Person View" if first_person else "Camera: Third-Person View")


func _unhandled_input(e: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		var max_up := 1.42 if first_person else 0.85
		var max_down := -1.48 if first_person else -1.35
		yaw -= e.relative.x * sensitivity
		pitch = clampf(pitch - e.relative.y * sensitivity * (-1.0 if invert_y else 1.0), max_down, max_up)
	elif e.is_action_pressed("toggle_first_person"):
		toggle_first_person()
	elif e is InputEventMouseButton and e.pressed and not first_person:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 0.6, 1.8, 16.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 0.6, 1.8, 16.0)
	elif e.is_action_pressed("swap_shoulder") and not first_person:
		shoulder = -shoulder


func view_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _process(delta: float) -> void:
	if target == null:
		return

	var max_up := 1.42 if first_person else 0.85
	var max_down := -1.48 if first_person else -1.35

	# Gamepad Right-Stick Camera Orbit
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	if look.length_squared() > 0.001:
		yaw -= look.x * controller_look_speed * delta
		pitch = clampf(pitch - look.y * controller_look_speed * delta * (-1.0 if invert_y else 1.0), max_down, max_up)

	var b := view_basis()
	if first_person:
		var eye_pos: Vector3 = target.global_position + Vector3(0.0, 1.56, 0.0)
		_pivot = eye_pos
		_snapped = true
		cam.global_transform = Transform3D(b, eye_pos)
		if world != null and world.terrain_mat != null:
			world.terrain_mat.set_shader_parameter("fade_enabled", false)
			world.terrain_mat.set_shader_parameter("view_pos", eye_pos)
		if target is Player and (target as Player).model != null:
			(target as Player).model.visible = true
			(target as Player).model.set_first_person_view(true)
		return

	var want: Vector3 = target.global_position + Vector3(0, 1.55, 0)
	if not _snapped or _pivot.distance_to(want) > 4.0:
		_pivot = want
		_snapped = true
	_pivot = _pivot.lerp(want, 1.0 - exp(-delta * 20.0))
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
	if world != null and world.terrain_mat != null:
		world.terrain_mat.set_shader_parameter("fade_enabled", foliage_fade)
		world.terrain_mat.set_shader_parameter("fade_eye", cam.global_position)
		world.terrain_mat.set_shader_parameter("view_pos", cam.global_position)
		world.terrain_mat.set_shader_parameter("fade_target", _pivot)
	# Hide the character when the camera is squeezed right up against it.
	if target is Player and (target as Player).model != null:
		(target as Player).model.set_first_person_view(false)
		(target as Player).model.visible = _cur_dist > 1.0
