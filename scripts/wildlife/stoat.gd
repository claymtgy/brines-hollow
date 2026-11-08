class_name Stoat
extends Raider
## Stoat: tiny, quick and bold. Slips through gaps a fox can't (it needs barely two voxels
## of head-room), steals one egg from a coop or a laying duck, and is gone. It never harms
## the animals. Same answers as the fox: light, Pen Fences and gates, chasing, live traps.

var body: Node3D
var _phase := 0.0


func _init() -> void:
	super()
	kind = &"stoat"
	max_hp = 6.0
	hp = 6.0
	radius = 0.2
	clearance = 2
	body_width = 0.0
	stalk_speed = 3.0
	flee_speed = 6.8
	carry_speed = 5.0
	track_size = 0.045


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(2, 3, 9)
	g.box(0, 1, 0, 1, 2, 6, Palette.TRUNK)           # long brown body
	g.box(0, 0, 1, 1, 0, 6, Palette.WHITEWASH)       # cream belly
	g.box(0, 1, 7, 1, 2, 8, Palette.TRUNK)           # head
	g.setv(0, 2, 8, Palette.EYE)
	g.setv(1, 2, 8, Palette.EYE)
	g.box(0, 0, 7, 1, 0, 8, Palette.WHITEWASH)
	part(body, g, Vector3(-1, 0, -4.5))
	var tg := Prefabs.Grid.new(1, 1, 4)
	tg.box(0, 0, 0, 0, 0, 2, Palette.TRUNK)
	tg.setv(0, 0, 0, Palette.BEDROCK)                # black tail tip
	part(body, tg, Vector3(-0.5, 1.5, -8.5))


func telegraph_height() -> float:
	return 0.4


func hint() -> String:
	return "A stoat after eggs! It squeezes through small gaps; light, Pen Fences and a baited live trap stop it."


func animate(dt: float) -> void:
	var moving := is_moving_state()
	_phase += dt * 18.0 * (1.0 if moving else 0.0)
	# The bounding, humped run of a weasel.
	body.position.y = absf(sin(_phase)) * 0.06 if moving else 0.0
	body.rotation.x = sin(_phase) * 0.25 if moving else 0.0
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI * 0.5, 1.0 - exp(-dt * 8.0))
