class_name CharacterModel
extends Node3D
## Chunky voxel fisherfolk, built from voxels at 2x the terrain resolution.
## Rigid-part animation: legs, arms, head swing on pivots.

const U := VoxelWorld.VS * 0.5  # character voxel size

var coat := Palette.COAT_A
var hat := Palette.HAT_A

var body: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var tool_pick: Node3D
var tool_hammer: Node3D
var tool_plan: Node3D

var _phase := 0.0
var _swing := 0.0
var _mat: StandardMaterial3D


static func _grid(sx: int, sy: int, sz: int) -> Prefabs.Grid:
	return Prefabs.Grid.new(sx, sy, sz)


func setup(coat_mat: int, hat_mat: int) -> void:
	coat = coat_mat
	hat = hat_mat
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.8
	body = Node3D.new()
	add_child(body)

	# Torso 6w x 6h x 4d, hips at 5u.
	var t := _grid(6, 6, 4)
	t.box(0, 0, 0, 5, 5, 3, coat)
	t.box(0, 0, 0, 5, 0, 3, Palette.DARK_WOOD)      # belt
	t.setv(2, 0, 3, Palette.METAL)                   # buckle
	t.setv(3, 0, 3, Palette.METAL)
	t.box(2, 2, 3, 2, 2, 3, Palette.BUTTON)
	t.box(2, 4, 3, 2, 4, 3, Palette.BUTTON)
	t.box(0, 5, 0, 5, 5, 3, Palette.HAT_B if coat == Palette.COAT_A else Palette.WHITEWASH)  # scarf
	t.setv(4, 4, 3, Palette.HAT_B if coat == Palette.COAT_A else Palette.WHITEWASH)
	_part(body, t, Vector3(-3, 5, -2))

	# Head (with sou'wester hat): pivot at neck.
	head = Node3D.new()
	head.position = Vector3(0, 11, 0) * U
	body.add_child(head)
	var h := _grid(10, 10, 10)
	h.box(1, 0, 1, 8, 6, 7, Palette.SKIN)
	h.box(1, 1, 1, 8, 5, 1, Palette.HANDLE)        # hair at the back
	h.box(3, 3, 7, 3, 4, 7, Palette.EYE)
	h.box(6, 3, 7, 6, 4, 7, Palette.EYE)
	h.setv(2, 2, 7, Palette.CHEEK)
	h.setv(7, 2, 7, Palette.CHEEK)
	h.box(1, 6, 1, 8, 8, 7, hat)             # crown
	h.box(0, 6, 0, 9, 6, 9, hat)             # brim
	h.box(0, 5, 0, 9, 5, 0, hat)             # back flap
	h.box(2, 9, 2, 7, 9, 6, hat)
	_part(head, h, Vector3(-5, 0, -4))

	# Arms: pivot at shoulder.
	arm_l = _limb(body, Vector3(-4, 10.5, 0), coat, Palette.SKIN, 2, 6, 2, 1)
	arm_r = _limb(body, Vector3(4, 10.5, 0), coat, Palette.SKIN, 2, 6, 2, 1)
	# Legs: pivot at hip.
	leg_l = _limb(body, Vector3(-1.5, 5, 0), Palette.TROUSER, Palette.BOOT, 3, 5, 3, 2)
	leg_r = _limb(body, Vector3(1.5, 5, 0), Palette.TROUSER, Palette.BOOT, 3, 5, 3, 2)

	# Tools held in the right hand (forward = +Z).
	var pk := _grid(5, 9, 1)
	pk.box(2, 0, 0, 2, 7, 0, Palette.HANDLE)
	pk.box(0, 7, 0, 4, 7, 0, Palette.METAL)
	pk.setv(0, 6, 0, Palette.METAL)
	pk.setv(4, 6, 0, Palette.METAL)
	tool_pick = _tool(pk)
	var hm := _grid(4, 8, 2)
	hm.box(1, 0, 0, 1, 6, 0, Palette.HANDLE)
	hm.box(0, 6, 0, 3, 7, 1, Palette.METAL)
	tool_hammer = _tool(hm)
	var pl := _grid(4, 5, 1)
	pl.box(0, 0, 0, 3, 4, 0, Palette.WHITEWASH)
	pl.box(1, 1, 0, 2, 3, 0, Palette.ROOF_BLUE)
	tool_plan = _tool(pl)
	set_tool(0)


func _part(parent: Node3D, g: Prefabs.Grid, offset_u: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, _mat, _mat)
	mi.position = offset_u * U
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot_u: Vector3, upper: int, lower: int, w: int, hgt: int, d: int, lower_h: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_u * U
	parent.add_child(pivot)
	var g := _grid(w, hgt, d)
	g.box(0, 0, 0, w - 1, hgt - 1, d - 1, upper)
	g.box(0, 0, 0, w - 1, lower_h - 1, d - 1, lower)
	_part(pivot, g, Vector3(-w * 0.5, -hgt, -d * 0.5))
	return pivot


func _tool(g: Prefabs.Grid) -> Node3D:
	var n := Node3D.new()
	# Hand is at the bottom of the arm; tool points forward out of the fist.
	n.position = Vector3(0, -5.5, 0.5) * U
	n.rotation = Vector3(PI * 0.5, 0, 0)
	arm_r.add_child(n)
	_part(n, g, Vector3(-g.sx * 0.5, -1, -g.sz * 0.5))
	return n


func set_tool(i: int) -> void:
	if tool_pick == null:
		return
	tool_pick.visible = i == 0
	tool_hammer.visible = i == 1
	tool_plan.visible = i == 2


func swing() -> void:
	_swing = 1.0


## speed: horizontal m/s. Call every frame.
func animate(delta: float, speed: float, on_ground: bool, swimming: bool) -> void:
	var moving := clampf(speed / 4.5, 0.0, 1.4)
	_phase += delta * (4.0 + speed * 1.9)
	var s := sin(_phase)
	var target_leg := s * 0.75 * moving
	var bob := absf(cos(_phase)) * 0.05 * moving
	var arm_l_x := -s * 0.6 * moving
	var arm_r_x := s * 0.6 * moving
	var arm_spread := 0.08
	if swimming:
		target_leg = s * 0.35
		arm_l_x = -1.6 + sin(_phase * 0.7) * 0.6
		arm_r_x = -1.6 - sin(_phase * 0.7) * 0.6
		arm_spread = 0.5
		bob = sin(_phase * 0.5) * 0.04
	elif not on_ground:
		target_leg = 0.35
		arm_l_x = -0.5
		arm_r_x = -0.5
		arm_spread = 0.5
	elif moving < 0.05:
		bob = sin(_phase * 0.35) * 0.012  # idle breathing
	# action swing overrides the right arm
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta * 4.0)
		var k := _swing
		arm_r_x = -0.3 - 2.2 * sin(k * PI) * (0.6 + 0.4 * k)
	var f := 1.0 - exp(-delta * 14.0)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, target_leg, f)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -target_leg, f)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, arm_l_x, f)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_r_x, f * (2.0 if _swing > 0.0 else 1.0))
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -arm_spread, f)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, arm_spread, f)
	body.position.y = bob
	head.rotation.x = lerpf(head.rotation.x, 0.15 if swimming else 0.0, f)
	body.rotation.x = lerpf(body.rotation.x, 0.9 if swimming else 0.06 * moving, f)


## Seated pose for boats: thighs forward, arms reaching for the oars.
## row_phase drives the stroke; row_power 0..1 blends from resting to full rowing.
func animate_seated(delta: float, row_phase: float, row_power: float) -> void:
	var f := 1.0 - exp(-delta * 12.0)
	var pull := sin(row_phase)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.45, f)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.45, f)
	var arm := -1.25 + pull * 0.45 * row_power
	arm_l.rotation.x = lerpf(arm_l.rotation.x, lerpf(-0.9, arm, row_power), f)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, lerpf(-0.9, arm, row_power), f)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.25, f)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.25, f)
	body.position.y = 0.0
	body.rotation.x = lerpf(body.rotation.x, -pull * 0.16 * row_power, f)
	head.rotation.x = lerpf(head.rotation.x, pull * 0.08 * row_power, f)
	set_tool(-1)
