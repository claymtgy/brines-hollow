class_name GuardAnimalEntity
extends WorldEntity
## A farm guardian that lives at a placed home:
##   dog_kennel  Guard Dog Kennel: the dog dozes by its kennel and sees off foxes, stoats and
##               shore rats that come within GUARD_RADIUS, barking so everyone hears.
##   cat_basket  Dock Cat's Basket: the cat naps in its basket and chases off shore rats (and
##               nosy stoats) near stores and coops.
## The animals never hurt anything: raiders just bolt. Press F to give them a fuss.

const U := VoxelWorld.VS * 0.5
const RADIUS := {&"dog_kennel": 16.0, &"cat_basket": 12.0}
const GUARDS := {&"dog_kennel": [&"fox", &"stoat", &"rat"], &"cat_basket": [&"rat", &"stoat"]}
const CHASE_TIME := 3.5

var pet_name := ""
var _animal: Node3D
var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _bark_label: Label3D
var _chase_to := Vector3.INF    # world point the animal is dashing toward
var _chase_t := 0.0
var _phase := 0.0


func _init(p_id: StringName = &"dog_kennel", p_coord: Vector3i = Vector3i.ZERO) -> void:
	var nm := "Guard Dog Kennel" if p_id == &"dog_kennel" else "Dock Cat's Basket"
	super._init(p_id, nm, p_coord)
	entity_type = EntityType.DECOR
	item_id = p_id
	size = (Vector3(10, 9, 10) if p_id == &"dog_kennel" else Vector3(7, 3, 7)) * U
	pet_name = "Skipper" if p_id == &"dog_kennel" else "Barnacle"


static func make_kennel(c: Vector3i) -> GuardAnimalEntity:
	return GuardAnimalEntity.new(&"dog_kennel", c)


static func make_cat_basket(c: Vector3i) -> GuardAnimalEntity:
	return GuardAnimalEntity.new(&"cat_basket", c)


func is_dog() -> bool:
	return entity_id == &"dog_kennel"


func guard_radius() -> float:
	return RADIUS.get(entity_id, 12.0)


func guards_against(kind: StringName) -> bool:
	return (GUARDS.get(entity_id, []) as Array).has(kind)


func species_word() -> String:
	return "dog" if is_dog() else "cat"


## Authority: dash at an intruder. Everyone sees it (state broadcast).
func chase(at: Vector3) -> void:
	_chase_to = at
	_chase_t = CHASE_TIME
	if manager != null:
		manager._broadcast_state(self)


func is_chasing() -> bool:
	return _chase_t > 0.0


# ---------------------------------------------------------------- visuals

func _build_visuals() -> void:
	var g: Prefabs.Grid
	if is_dog():
		g = Prefabs.Grid.new(10, 9, 10)
		g.box(0, 0, 0, 9, 0, 9, Palette.DARK_WOOD)       # floor
		g.box(0, 1, 0, 0, 6, 9, Palette.PLANK)           # walls
		g.box(9, 1, 0, 9, 6, 9, Palette.PLANK)
		g.box(0, 1, 0, 9, 6, 0, Palette.PLANK)           # back
		g.box(1, 7, 0, 8, 7, 9, Palette.ROOF_RED)        # roof
		g.box(3, 8, 0, 6, 8, 9, Palette.ROOF_RED)
		g.box(0, 1, 9, 2, 6, 9, Palette.PLANK)           # front, with a door hole
		g.box(7, 1, 9, 9, 6, 9, Palette.PLANK)
		g.box(3, 6, 9, 6, 6, 9, Palette.PLANK)
	else:
		g = Prefabs.Grid.new(7, 3, 7)
		for z in 7:
			for x in 7:
				var r := Vector2(x - 3, z - 3).length()
				if r <= 3.3:
					g.setv(x, 0, z, Palette.GRASS_DRY)  # wicker base
				if r <= 3.3 and r > 2.2:
					g.box(x, 1, z, x, 2, z, Palette.GRASS_DRY)
		g.box(2, 1, 2, 4, 1, 4, Palette.ROOF_BLUE)       # cushion
	_mesh_instance = _voxel_model(g)
	_animal = Node3D.new()
	add_child(_animal)
	_body = Node3D.new()
	_animal.add_child(_body)
	if is_dog():
		_build_dog()
		_animal.position = Vector3(0, 0, 8.0 * U)
	else:
		_build_cat()
		_animal.position = Vector3(0, 1.0 * U, 0)
	_bark_label = Label3D.new()
	_bark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark_label.font_size = 40
	_bark_label.outline_size = 8
	_bark_label.position = Vector3(0, 1.0, 0)
	_bark_label.visible = false
	_animal.add_child(_bark_label)


func _part(parent: Node3D, g: Prefabs.Grid, at: Vector3) -> MeshInstance3D:
	var mi := _voxel_model(g)
	mi.reparent(parent, false)
	mi.position = at * U
	return mi


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at * U
	parent.add_child(n)
	return n


func _build_dog() -> void:
	var g := Prefabs.Grid.new(4, 4, 8)
	g.box(0, 1, 0, 3, 3, 7, Palette.TRUNK)               # brown and white collie
	g.box(1, 1, 5, 2, 3, 7, Palette.WHITEWASH)           # white chest
	for x in [0, 3]:
		g.box(x, 0, 1, x, 0, 1, Palette.TRUNK)
		g.box(x, 0, 6, x, 0, 6, Palette.WHITEWASH)
	_part(_body, g, Vector3(-2, 0, -4))
	_head = _pivot(_body, Vector3(0, 3, 4))
	var hg := Prefabs.Grid.new(4, 4, 4)
	hg.box(0, 0, 0, 3, 2, 2, Palette.TRUNK)
	hg.box(1, 0, 3, 2, 1, 3, Palette.WHITEWASH)         # muzzle
	hg.setv(1, 1, 3, Palette.BEDROCK)
	hg.setv(0, 2, 2, Palette.EYE)
	hg.setv(3, 2, 2, Palette.EYE)
	hg.setv(0, 3, 0, Palette.TRUNK)
	hg.setv(3, 3, 0, Palette.TRUNK)
	hg.setv(1, 0, 0, Palette.ROOF_RED)                   # collar
	hg.setv(2, 0, 0, Palette.ROOF_RED)
	_part(_head, hg, Vector3(-2, -1, -0.5))
	_tail = _pivot(_body, Vector3(0, 3, -4))
	var tg := Prefabs.Grid.new(1, 1, 4)
	tg.box(0, 0, 0, 0, 0, 3, Palette.TRUNK)
	tg.setv(0, 0, 0, Palette.WHITEWASH)
	_part(_tail, tg, Vector3(-0.5, 0, -4))


func _build_cat() -> void:
	var g := Prefabs.Grid.new(3, 3, 6)
	g.box(0, 0, 0, 2, 2, 5, Palette.BUOY)                # ginger tom
	g.box(1, 0, 3, 1, 1, 5, Palette.WHITEWASH)
	_part(_body, g, Vector3(-1.5, 0, -3))
	_head = _pivot(_body, Vector3(0, 2, 3))
	var hg := Prefabs.Grid.new(3, 3, 3)
	hg.box(0, 0, 0, 2, 2, 2, Palette.BUOY)
	hg.setv(0, 1, 2, Palette.EYE)
	hg.setv(2, 1, 2, Palette.EYE)
	hg.setv(1, 0, 2, Palette.FLOWER_P)
	hg.setv(0, 3 - 1, 0, Palette.BUOY)
	_part(_head, hg, Vector3(-1.5, -0.5, -0.5))
	var ears := Prefabs.Grid.new(3, 1, 1)
	ears.setv(0, 0, 0, Palette.BUOY)
	ears.setv(2, 0, 0, Palette.BUOY)
	_part(_head, ears, Vector3(-1.5, 2.5, 0.5))
	_tail = _pivot(_body, Vector3(0, 2, -3))
	var tg := Prefabs.Grid.new(1, 1, 5)
	tg.box(0, 0, 0, 0, 0, 4, Palette.BUOY)
	_part(_tail, tg, Vector3(-0.5, 0, -5))


func _process(dt: float) -> void:
	if _animal == null:
		return
	_phase += dt
	var home := Vector3(0, 0, 8.0 * U) if is_dog() else Vector3(0, 1.0 * U, 0)
	if _chase_t > 0.0:
		_chase_t -= dt
		# Dash out toward the intruder (local space), then trot back.
		var local := to_local(_chase_to) if _chase_to != Vector3.INF else home
		local.y = home.y
		var out := local.limit_length(guard_radius() * 0.6)
		var want := out if _chase_t > CHASE_TIME * 0.4 else home
		var step := want - _animal.position
		_animal.position += step.limit_length((9.0 if is_dog() else 7.0) * dt)
		if step.length() > 0.05:
			_animal.rotation.y = lerp_angle(_animal.rotation.y, atan2(step.x, step.z), 1.0 - exp(-12.0 * dt))
		_body.position.y = absf(sin(_phase * 18.0)) * 0.06
		_tail.rotation.y = sin(_phase * 20.0) * 0.6
		_bark_label.visible = true
		_bark_label.text = "WOOF!" if is_dog() else "HSSS!"
		_bark_label.modulate = Color(1, 0.95, 0.7) if is_dog() else Color(1, 0.7, 0.5)
		_bark_label.position.y = 1.0 + absf(sin(_phase * 6.0)) * 0.1
	else:
		_animal.position = _animal.position.lerp(home, 1.0 - exp(-4.0 * dt))
		_body.position.y = 0.0
		_bark_label.visible = false
		# Dozing: slow breathing, a lazy tail.
		_body.scale.y = 1.0 + sin(_phase * 1.6) * 0.03
		_tail.rotation.y = sin(_phase * (3.0 if is_dog() else 1.2)) * 0.3
		_head.rotation.y = sin(_phase * 0.3) * 0.4


# ---------------------------------------------------------------- interaction

func get_interaction_prompt(_player: Player) -> String:
	var does := "keeps foxes, stoats and rats off" if is_dog() else "keeps rats out of the stores"
	return "F  Give %s a fuss (%s within %d m)  ·  hold F to pick up" % [pet_name, does, int(guard_radius())]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if player != null and player.hud != null:
		if is_dog():
			player.hud.show_toast("%s thumps its tail and rolls over for a belly rub." % pet_name)
		else:
			player.hud.show_toast("%s purrs and kneads the cushion." % pet_name)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["pet"] = pet_name
	if _chase_t > 0.0 and _chase_to != Vector3.INF:
		d["chase"] = _chase_to
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	pet_name = String(data.get("pet", pet_name))
	if data.get("chase") is Vector3:
		_chase_to = data.chase
		_chase_t = CHASE_TIME
