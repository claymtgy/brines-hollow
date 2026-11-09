class_name WaterSourceEntity
extends WorldEntity
## Fresh water: a spring bubbling up in a karst cavern (found, never runs dry), or a stone well
## (built: it seeps full again over time). F fills flasks of spring water: a drink that helps
## stamina recover, and what the furnace quenches fine sea-brass in.

const U := VoxelWorld.VS * 0.5
const WELL_MAX := 4
const WELL_SEEP_SEC := 90.0      # one flask's worth seeps back in this often
const SPRING_FILL := 3

var is_well := false
var stored := WELL_MAX           # wells only
var _seep := 0.0
var _water: MeshInstance3D
var _bob := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO, p_well := false) -> void:
	is_well = p_well
	if is_well:
		super._init(&"stone_well", "Stone Well", p_coord)
		size = Vector3(12, 22, 12) * U
	else:
		super._init(&"freshwater_spring", "Freshwater Spring", p_coord)
		size = Vector3(12, 3, 12) * U
	entity_type = EntityType.TRAP
	state_changed.connect(_refresh_visuals)


static func make_well(c: Vector3i) -> WaterSourceEntity:
	return WaterSourceEntity.new(c, true)


static func make_spring(c: Vector3i) -> WaterSourceEntity:
	return WaterSourceEntity.new(c, false)


func _build_visuals() -> void:
	if is_well:
		var g := Prefabs.Grid.new(12, 22, 12)
		for z in 12:
			for x in 12:
				var d := Vector2(x - 5.5, z - 5.5).length()
				if d <= 5.8 and d > 4.0:
					for y in 6:
						g.setv(x, y, z, Palette.COBBLE if (x + y + z) % 3 != 0 else Palette.STONE)
		for p: Vector2i in [Vector2i(1, 5), Vector2i(10, 5)]:
			g.box(p.x, 6, p.y, p.x, 17, p.y + 1, Palette.DARK_WOOD)
		g.box(1, 15, 5, 10, 15, 6, Palette.DARK_WOOD)             # windlass
		g.box(5, 11, 5, 6, 13, 6, Palette.PLANK)                  # the pail on its rope
		g.setv(5, 14, 5, Palette.METAL)
		for z in 12:                                              # a little pitched roof
			for x in 12:
				var r := 21 - absi(x * 2 - 11) / 2
				if r >= 18:
					g.setv(x, r, z, Palette.ROOF_RED)
		_mesh_instance = _voxel_model(g)
	else:
		var g := Prefabs.Grid.new(12, 2, 12)
		for z in 12:
			for x in 12:
				var d := Vector2(x - 5.5, z - 5.5).length()
				if d <= 5.8 and d > 4.2:
					g.setv(x, 0, z, Palette.STONE)
					if (x * 7 + z * 3) % 4 != 0:
						g.setv(x, 1, z, Palette.COBBLE if (x + z) % 2 == 0 else Palette.GLOW_TEAL)
				elif d <= 4.2:
					g.setv(x, 0, z, Palette.GRAVEL)
		_mesh_instance = _voxel_model(g)
	var w := Prefabs.Grid.new(9, 1, 9)
	for z in 9:
		for x in 9:
			if Vector2(x - 4, z - 4).length() <= 4.3:
				w.setv(x, 0, z, Palette.SHUTTER)
	_water = _voxel_model(w)
	_water.position.y = U * (4.2 if is_well else 1.1)
	_refresh_visuals()


func _refresh_visuals() -> void:
	if _water != null:
		_water.visible = not is_well or stored > 0


func _process(delta: float) -> void:
	if _water == null or is_well:
		return
	_bob += delta * 2.3
	_water.position.y = U * (1.1 + sin(_bob) * 0.12)   # the spring wells up


func get_interaction_prompt(_player: Player) -> String:
	if is_well:
		if stored <= 0:
			return "Stone Well: dry for now, the water seeps back in"
		return "F  Draw spring water (%d/%d)" % [stored, WELL_MAX]
	return "F  Fill flasks at the spring"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if is_well and stored <= 0:
		if player.hud:
			player.hud.show_toast(get_interaction_prompt(player))
		return
	manager.request_action(self, &"draw", {})


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action != &"draw":
		return {}
	if is_well:
		if stored <= 0:
			return {}
		var n := stored
		stored = 0
		_seep = 0.0
		_refresh_visuals()
		return {"changed": true, "grant": [[&"spring_water", n]], "toast": "Drew %d flasks of spring water." % n}
	return {"grant": [[&"spring_water", SPRING_FILL]], "toast": "Filled %d flasks of cold spring water." % SPRING_FILL}


func server_tick(delta: float, _env: Dictionary) -> bool:
	if not is_well or stored >= WELL_MAX:
		return false
	_seep += delta
	if _seep >= WELL_SEEP_SEC:
		_seep = 0.0
		stored += 1
		_refresh_visuals()
		return true
	return false


func serialize() -> Dictionary:
	var d := super.serialize()
	if is_well:
		d["water"] = stored
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if is_well:
		stored = int(data.get("water", WELL_MAX))
	_refresh_visuals()
