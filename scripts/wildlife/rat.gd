class_name ShoreRat
extends Raider
## Shore rat: comes up off the tideline on the nights after a storm, looking for open food
## stores (chests and crates with food in them), and makes off with a bite or two.
## Answers: keep food in a sealed barrel (rats can't get in), a dock cat or guard dog nearby,
## light, chasing it, or a baited live trap. Never harms animals or players.

var body: Node3D
var tail: Node3D
var _phase := 0.0


func _init() -> void:
	super()
	kind = &"rat"
	max_hp = 4.0
	hp = 4.0
	radius = 0.16
	clearance = 2
	body_width = 0.0
	stalk_speed = 2.4
	flee_speed = 6.0
	carry_speed = 4.5
	track_size = 0.035


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(3, 3, 6)
	g.box(0, 0, 0, 2, 2, 4, Palette.GRAVEL)            # grey-brown body
	g.box(1, 0, 5, 1, 1, 5, Palette.GRAVEL)            # pointed snout
	g.setv(0, 2, 4, Palette.EYE)
	g.setv(2, 2, 4, Palette.EYE)
	g.setv(1, 1, 5, Palette.CHEEK)                     # pink nose
	g.setv(0, 3 - 1, 3, Palette.CHEEK)                 # ears
	g.setv(2, 3 - 1, 3, Palette.CHEEK)
	part(body, g, Vector3(-1.5, 0, -3))
	tail = pivot(body, Vector3(0, 0.5, -3))
	var tg := Prefabs.Grid.new(1, 1, 5)
	tg.box(0, 0, 0, 0, 0, 4, Palette.CHEEK)            # long bare tail
	part(tail, tg, Vector3(-0.5, 0, -5))


func telegraph_height() -> float:
	return 0.3


func hint() -> String:
	return "A shore rat after your stores! Sealed barrels keep food safe; a dock cat or a guard dog sees it off."


func animate(dt: float) -> void:
	var moving := is_moving_state()
	_phase += dt * 22.0 * (1.0 if moving else 0.0)
	body.position.y = absf(sin(_phase)) * 0.03 if moving else 0.0
	tail.rotation.y = sin(_phase * 0.4 + 0.5) * 0.5
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI * 0.5, 1.0 - exp(-dt * 8.0))
