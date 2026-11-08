class_name LivestockAnimal
extends Node3D
## Domestic livestock animal: Salt-Goat, Shore-Sheep, and Shore-Duck.
## Simulates needs (hunger, thirst, happiness), yields (milk, wool, eggs),
## herding (follows held wheat / shepherd's whistle), and interactive care (petting, shearing, milking).

enum Species { SALT_GOAT, SHORE_SHEEP, SHORE_DUCK }
enum State { IDLE, WANDER, GRAZE, SEEK_TROUGH, FOLLOW, SLEEP }

const U := VoxelWorld.VS * 0.5

const FEED_ITEMS: Array[StringName] = [&"shore_wheat", &"seed_shore_wheat", &"tide_kale", &"samphire", &"kelp_frond"]
const HERD_BAIT_ITEMS: Array[StringName] = [&"shore_wheat", &"seed_shore_wheat", &"tide_kale"]

const YIELD_INTERVAL_GOAT := 180.0    # 3 mins for fresh milk
const YIELD_INTERVAL_SHEEP := 180.0   # 3 mins for full wool regrowth
const YIELD_INTERVAL_DUCK := 120.0    # 2 mins for egg / down feather

var animal_id: int = 0
var species: StringName = &"salt_goat"
var animal_name: String = "Salt-Goat"

# Needs (0 to 100)
var hunger: float = 85.0
var thirst: float = 85.0
var happiness: float = 65.0

# Yield & care state
var yield_timer: float = 0.0          # <= 0 means ready
var wool_grown: bool = true           # Shore-Sheep fleece visible
var pet_cooldown: float = 0.0

# AI & movement
var state: State = State.IDLE
var state_t: float = 0.0
var yaw: float = 0.0
var vel: Vector3 = Vector3.ZERO
var target_player: Node3D = null
var target_trough: Node3D = null

# Visual articulated parts
var visual_root: Node3D
var body_node: Node3D
var head_node: Node3D
var leg_fl: Node3D
var leg_fr: Node3D
var leg_bl: Node3D
var leg_br: Node3D
var wing_l: Node3D
var wing_r: Node3D
var wool_mesh: MeshInstance3D

var _emote_label: Label3D
var _emote_timer: float = 0.0
var _walk_phase: float = 0.0
var _graze_y_offset: float = 0.0
var _main_ref: Node = null
# Co-op clients: the host's latest pose for this animal (we glide toward it).
var _net_pos: Variant = null
var _net_yaw: float = 0.0

static var _mat_standard: StandardMaterial3D
static var _mat_glow: StandardMaterial3D


static func _get_mats() -> Array[StandardMaterial3D]:
	if _mat_standard == null:
		_mat_standard = StandardMaterial3D.new()
		_mat_standard.vertex_color_use_as_albedo = true
		_mat_standard.vertex_color_is_srgb = true
		_mat_standard.roughness = 0.8
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.vertex_color_use_as_albedo = true
		_mat_glow.vertex_color_is_srgb = true
		_mat_glow.emission_enabled = true
		_mat_glow.emission = Color(1.0, 0.9, 0.4)
		_mat_glow.emission_energy_multiplier = 1.5
	return [_mat_standard, _mat_glow]


func _init(p_species: StringName = &"salt_goat", p_name: String = "") -> void:
	species = p_species
	if p_name != "":
		animal_name = p_name
	else:
		animal_name = _default_name_for_species(p_species)
	visual_root = Node3D.new()
	add_child(visual_root)
	_build_visuals()
	_setup_emote()


func _ready() -> void:
	if visual_root == null:
		visual_root = Node3D.new()
		add_child(visual_root)
		_build_visuals()
		_setup_emote()


func _default_name_for_species(sp: StringName) -> String:
	match sp:
		&"salt_goat":
			return ["Bramble", "Barnaby", "Clover", "Gulliver", "Pebble", "Finley"].pick_random()
		&"shore_sheep":
			return ["Daisy", "Woolsey", "Cotton", "Floss", "Mallow", "Snowdrop"].pick_random()
		&"shore_duck":
			return ["Pip", "Quigley", "Waddles", "Drake", "Puddle", "Splash"].pick_random()
		_:
			return "Animal"


func species_display_name() -> String:
	match species:
		&"salt_goat": return "Salt-Goat"
		&"shore_sheep": return "Shore-Sheep"
		&"shore_duck": return "Shore-Duck"
		_: return "Livestock"


func _setup_emote() -> void:
	_emote_label = Label3D.new()
	_emote_label.text = "♥"
	_emote_label.font_size = 64
	_emote_label.outline_size = 12
	_emote_label.modulate = Color(1.0, 0.35, 0.55, 0.0)
	_emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_label.no_depth_test = true
	_emote_label.pixel_size = 0.005
	_emote_label.position = Vector3(0, 1.4, 0)
	add_child(_emote_label)


func pop_emote(text: String = "♥", color: Color = Color(1.0, 0.35, 0.55)) -> void:
	if _emote_label != null:
		_emote_label.text = text
		_emote_label.modulate = color
		_emote_label.position.y = 1.35
		_emote_timer = 1.6


# ---------------------------------------------------------------- Visual Construction

func _create_part(parent: Node3D, grid: Prefabs.Grid, offset_u: Vector3) -> MeshInstance3D:
	var mats := _get_mats()
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(grid.data, grid.sx, grid.sy, grid.sz, U, mats[0], mats[1])
	mi.position = offset_u * U
	parent.add_child(mi)
	return mi


func _create_pivot(parent: Node3D, pos_u: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos_u * U
	parent.add_child(n)
	return n


func _build_visuals() -> void:
	match species:
		&"salt_goat":
			_build_salt_goat()
		&"shore_sheep":
			_build_shore_sheep()
		&"shore_duck":
			_build_shore_duck()


func _build_salt_goat() -> void:
	# Goat body: ~10 long, 6 wide, 6 high
	body_node = _create_pivot(visual_root, Vector3(0, 5, 0))
	var body_grid := Prefabs.Grid.new(6, 6, 11)
	body_grid.box(0, 0, 0, 5, 5, 10, Palette.SANDSTONE_A) # Warm sandy coat
	body_grid.box(1, 0, 2, 4, 1, 9, Palette.WHITEWASH)   # Light underbelly
	_create_part(body_node, body_grid, Vector3(-3, -3, -5.5))

	# Neck and head
	head_node = _create_pivot(body_node, Vector3(0, 2, 5))
	var head_grid := Prefabs.Grid.new(4, 5, 6)
	head_grid.box(0, 0, 0, 3, 4, 5, Palette.SANDSTONE_A)
	head_grid.box(1, 0, 4, 2, 2, 5, Palette.SANDSTONE_B) # Muzzle
	head_grid.setv(0, 3, 3, Palette.EYE)                  # Eyes
	head_grid.setv(3, 3, 3, Palette.EYE)
	# Chin beard
	head_grid.box(1, -1, 3, 2, 0, 4, Palette.WHITEWASH)
	# Curled salt horns
	head_grid.box(0, 4, 1, 0, 6, 1, Palette.STONE)
	head_grid.box(3, 4, 1, 3, 6, 1, Palette.STONE)
	head_grid.setv(0, 6, 0, Palette.WHITEWASH)           # Salt tips
	head_grid.setv(3, 6, 0, Palette.WHITEWASH)
	_create_part(head_node, head_grid, Vector3(-2, -1, 0))

	# 4 legs
	leg_fl = _create_pivot(body_node, Vector3(-2.2, -3, 3.5))
	leg_fr = _create_pivot(body_node, Vector3(2.2, -3, 3.5))
	leg_bl = _create_pivot(body_node, Vector3(-2.2, -3, -4))
	leg_br = _create_pivot(body_node, Vector3(2.2, -3, -4))
	for leg in [leg_fl, leg_fr, leg_bl, leg_br]:
		var leg_grid := Prefabs.Grid.new(2, 5, 2)
		leg_grid.box(0, 1, 0, 1, 4, 1, Palette.SANDSTONE_A)
		leg_grid.box(0, 0, 0, 1, 0, 1, Palette.DARK_WOOD) # Hoof
		_create_part(leg, leg_grid, Vector3(-1, -5, -1))


func _build_shore_sheep() -> void:
	# Core shorn body
	body_node = _create_pivot(visual_root, Vector3(0, 5, 0))
	var inner_grid := Prefabs.Grid.new(6, 6, 10)
	inner_grid.box(0, 0, 0, 5, 5, 9, Palette.SANDSTONE_B) # Bare skin tone
	_create_part(body_node, inner_grid, Vector3(-3, -3, -5))

	# Wool fleece coat (thick exterior layer)
	var wool_grid := Prefabs.Grid.new(8, 8, 12)
	wool_grid.box(0, 0, 0, 7, 7, 11, Palette.WHITEWASH)
	wool_mesh = _create_part(body_node, wool_grid, Vector3(-4, -4, -6))
	wool_mesh.visible = wool_grown

	# Head (dark coastal face)
	head_node = _create_pivot(body_node, Vector3(0, 1, 5))
	var head_grid := Prefabs.Grid.new(4, 5, 5)
	head_grid.box(0, 0, 0, 3, 4, 4, Palette.BEDROCK)
	head_grid.setv(0, 3, 2, Palette.EYE)
	head_grid.setv(3, 3, 2, Palette.EYE)
	# Floppy sheep ears
	head_grid.box(-1, 3, 1, -1, 4, 2, Palette.BEDROCK)
	head_grid.box(4, 3, 1, 4, 4, 2, Palette.BEDROCK)
	_create_part(head_node, head_grid, Vector3(-2, -1, 0))

	# 4 legs
	leg_fl = _create_pivot(body_node, Vector3(-2, -3, 3))
	leg_fr = _create_pivot(body_node, Vector3(2, -3, 3))
	leg_bl = _create_pivot(body_node, Vector3(-2, -3, -3.5))
	leg_br = _create_pivot(body_node, Vector3(2, -3, -3.5))
	for leg in [leg_fl, leg_fr, leg_bl, leg_br]:
		var leg_grid := Prefabs.Grid.new(2, 5, 2)
		leg_grid.box(0, 0, 0, 1, 4, 1, Palette.BEDROCK)
		_create_part(leg, leg_grid, Vector3(-1, -5, -1))


func _build_shore_duck() -> void:
	# Duck body
	body_node = _create_pivot(visual_root, Vector3(0, 3, 0))
	var body_grid := Prefabs.Grid.new(5, 4, 8)
	body_grid.box(0, 0, 0, 4, 3, 7, Palette.WHITEWASH) # Sea-duck plumage
	body_grid.box(1, 1, 0, 3, 3, 2, Palette.DARK_WOOD)  # Tail feathers
	_create_part(body_node, body_grid, Vector3(-2.5, -2, -4))

	# Head & Neck
	head_node = _create_pivot(body_node, Vector3(0, 1.5, 3.5))
	var head_grid := Prefabs.Grid.new(3, 4, 4)
	head_grid.box(0, 0, 0, 2, 3, 3, Palette.DIRT)       # Mallard / shore head
	head_grid.setv(0, 2, 2, Palette.EYE)
	head_grid.setv(2, 2, 2, Palette.EYE)
	# Flat yellow bill
	head_grid.box(0, 0, 3, 2, 1, 5, Palette.FLOWER_Y)
	_create_part(head_node, head_grid, Vector3(-1.5, -1, 0))

	# Wings
	wing_l = _create_pivot(body_node, Vector3(-2.6, 0, 0))
	wing_r = _create_pivot(body_node, Vector3(2.6, 0, 0))
	var wing_grid := Prefabs.Grid.new(1, 3, 6)
	wing_grid.box(0, 0, 0, 0, 2, 5, Palette.SANDSTONE_B)
	_create_part(wing_l, wing_grid, Vector3(-0.5, -1.5, -3))
	_create_part(wing_r, wing_grid, Vector3(-0.5, -1.5, -3))

	# Webbed feet
	leg_fl = _create_pivot(body_node, Vector3(-1.5, -2, 0))
	leg_fr = _create_pivot(body_node, Vector3(1.5, -2, 0))
	for leg in [leg_fl, leg_fr]:
		var foot_grid := Prefabs.Grid.new(2, 3, 3)
		foot_grid.box(0, 1, 1, 1, 2, 1, Palette.FLOWER_Y)
		foot_grid.box(0, 0, 0, 1, 0, 2, Palette.FLOWER_Y)
		_create_part(leg, foot_grid, Vector3(-1, -3, -1))


# ---------------------------------------------------------------- Needs & Yields

func is_milk_ready() -> bool:
	return species == &"salt_goat" and yield_timer <= 0.0 and hunger >= 30.0 and thirst >= 30.0


func is_shear_ready() -> bool:
	return species == &"shore_sheep" and wool_grown


func is_egg_ready() -> bool:
	return species == &"shore_duck" and yield_timer <= 0.0 and hunger >= 30.0


func can_pet() -> bool:
	return pet_cooldown <= 0.0


# ---------------------------------------------------------------- Interaction API

func get_interaction_prompt(player: Node) -> String:
	if player == null or player.get("inventory") == null:
		return "%s (%s)" % [animal_name, species_display_name()]

	var slot: ItemSlot = player.inventory.get_active_item()
	var held_id: StringName = slot.item_id if (slot != null and not slot.is_empty()) else &""

	if species == &"shore_sheep" and held_id == &"shearing_shears":
		if wool_grown:
			return "F  Shear %s" % animal_name
		else:
			return "%s: Wool Regrowing (%d%%)" % [animal_name, int((1.0 - yield_timer / YIELD_INTERVAL_SHEEP) * 100)]

	if species == &"salt_goat" and held_id == &"wooden_bucket":
		if is_milk_ready():
			return "F  Milk %s" % animal_name
		else:
			return "%s: Not Ready to Milk" % animal_name

	if held_id in FEED_ITEMS:
		if hunger >= 95.0:
			return "%s: Well Fed (100%%)" % animal_name
		return "F  Hand-feed %s (%s)" % [animal_name, held_id]

	if can_pet():
		return "F  Pet %s ♥" % animal_name

	return "%s (Happy: %d%%, Fed: %d%%)" % [animal_name, int(happiness), int(hunger)]


func interact(player: Node) -> Dictionary:
	if player == null or player.get("inventory") == null:
		return {"ok": false}

	var slot: ItemSlot = player.inventory.get_active_item()
	var held_id: StringName = slot.item_id if (slot != null and not slot.is_empty()) else &""

	# 1. Shearing
	if species == &"shore_sheep" and held_id == &"shearing_shears":
		if wool_grown:
			wool_grown = false
			if wool_mesh != null:
				wool_mesh.visible = false
			yield_timer = YIELD_INTERVAL_SHEEP
			var count: int = randi_range(2, 3)
			player.inventory.add_item(&"sea_wool", count)
			happiness = minf(100.0, happiness + 10.0)
			pop_emote("✂ ♥", Color(0.85, 0.95, 1.0))
			return {"ok": true, "msg": "Sheared %s! Obtained %d Shore-Sheep Wool." % [animal_name, count]}
		else:
			return {"ok": false, "msg": "%s has not regrown its wool yet." % animal_name}

	# 2. Milking
	if species == &"salt_goat" and held_id == &"wooden_bucket":
		if is_milk_ready():
			yield_timer = YIELD_INTERVAL_GOAT
			player.inventory.remove_item(&"wooden_bucket", 1)
			player.inventory.add_item(&"salt_milk", 1)
			happiness = minf(100.0, happiness + 15.0)
			pop_emote("🥛 ♥", Color(1.0, 1.0, 0.8))
			return {"ok": true, "msg": "Milked %s! Obtained Salt-Goat Milk." % animal_name}
		else:
			return {"ok": false, "msg": "%s is not ready for milking yet." % animal_name}

	# 3. Hand-feeding
	if held_id in FEED_ITEMS:
		if hunger < 95.0:
			player.inventory.remove_item(held_id, 1)
			hunger = minf(100.0, hunger + 35.0)
			thirst = minf(100.0, thirst + 10.0)
			happiness = minf(100.0, happiness + 18.0)
			pop_emote("♥", Color(1.0, 0.4, 0.6))
			return {"ok": true, "msg": "Hand-fed %s with %s!" % [animal_name, held_id]}
		else:
			return {"ok": false, "msg": "%s is full and not hungry right now." % animal_name}

	# 4. Petting
	if can_pet():
		pet_cooldown = 45.0
		happiness = minf(100.0, happiness + 20.0)
		pop_emote("♥", Color(1.0, 0.35, 0.55))
		return {"ok": true, "msg": "Petted %s! ♥" % animal_name}

	return {"ok": false, "msg": "%s is feeling content." % animal_name}


# ---------------------------------------------------------------- Simulation & AI

## Head-room an animal needs to pass (see TerrainStep): ducks slip under a rail fence's
## bottom rail, goats and sheep don't. Pen Fence and closed Pen Gates hold everything.
func clearance_voxels() -> int:
	return 3 if species == &"shore_duck" else 5


## Moves by `step` unless a fence, wall, closed gate or drop-off is in the way.
func _try_move(step: Vector3, main: Node) -> bool:
	if main == null or main.get("world") == null or main.world.store == null:
		position += step
		return true
	var nxt := position + step
	var g := TerrainStep.step(main.world.get_voxel, position, nxt, clearance_voxels(), 3, 8)
	if is_nan(g):
		return false
	if TerrainStep.entity_blocked(Vector3(nxt.x, g, nxt.z), 0.18, clearance_voxels() * VoxelWorld.VS * 0.8):
		return false
	position.x = nxt.x
	position.z = nxt.z
	return true


func simulate(dt: float, main: Node) -> void:
	_main_ref = main
	# Cooldowns & Needs
	if pet_cooldown > 0.0:
		pet_cooldown -= dt

	# Needs degradation
	hunger = maxf(0.0, hunger - (dt / 12.0))
	thirst = maxf(0.0, thirst - (dt / 15.0))

	# Happiness tracks needs
	if hunger < 25.0 or thirst < 25.0:
		happiness = maxf(0.0, happiness - (dt / 8.0))
	elif hunger > 60.0 and thirst > 60.0:
		happiness = minf(100.0, happiness + (dt / 25.0))

	# Yield production progress
	if yield_timer > 0.0:
		var happy_mult: float = 1.0 + (happiness / 200.0)
		if hunger > 30.0 and thirst > 30.0:
			yield_timer = maxf(0.0, yield_timer - dt * happy_mult)
		if yield_timer <= 0.0:
			if species == &"shore_sheep":
				wool_grown = true
				if wool_mesh != null:
					wool_mesh.visible = true

	# Check for player herding (holding wheat or sounded whistle)
	_check_herding(main)

	# State execution
	state_t -= dt
	match state:
		State.FOLLOW:
			_process_follow(dt)
		State.SEEK_TROUGH:
			_process_seek_trough(dt, main)
		State.GRAZE:
			_process_graze(dt)
		State.WANDER:
			_process_wander(dt)
		State.IDLE:
			_process_idle(dt, main)

	# Ground snapping / terrain adherence
	_snap_to_ground(main)

	# Animate articulated parts
	_animate_parts(dt)


## True if this player node is holding herd bait (wheat, kale) or the whistle.
static func holds_herd_bait(p: Node) -> bool:
	if p == null or not ("inventory" in p) or p.inventory == null:
		return false
	var slot: ItemSlot = p.inventory.get_active_item()
	return slot != null and not slot.is_empty() 			and (slot.item_id in HERD_BAIT_ITEMS or slot.item_id == &"animal_whistle")


func _check_herding(main: Node) -> void:
	# Every player who can lead animals: the host's own player plus co-op players
	# (the manager tracks what remote players hold). Nearest herder wins.
	var herders: Array = []
	if main != null and main.get("livestock_mgr") != null and main.livestock_mgr.has_method("herders"):
		herders = main.livestock_mgr.herders()
	else:
		var lp = main.get("player") if main != null else null
		if lp != null and holds_herd_bait(lp):
			herders.append(lp)
	var p: Node3D = null
	var d: float = INF
	for h: Node3D in herders:
		if is_instance_valid(h):
			var hd := position.distance_to(h.position)
			if hd < d:
				d = hd
				p = h
	if p == null and target_player != null and is_instance_valid(target_player):
		p = target_player
		d = position.distance_to(p.position)
	if p == null:
		if state == State.FOLLOW and state_t <= 0.0:
			state = State.IDLE
			state_t = 2.0
		return
	var is_holding_bait: bool = herders.has(p)

	if is_holding_bait and d <= 12.0:
		target_player = p
		state = State.FOLLOW
		state_t = 5.0
	elif state == State.FOLLOW and (not is_holding_bait or d > 16.0):
		target_player = null
		state = State.IDLE
		state_t = 3.0


func _process_follow(dt: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		state = State.IDLE
		state_t = 2.0
		return

	var to_player: Vector3 = target_player.position - position
	to_player.y = 0.0
	var dist: float = to_player.length()

	if dist > 2.0:
		var dir: Vector3 = to_player.normalized()
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * dt))
		var speed := 1.8 if species != &"shore_duck" else 1.2
		_try_move(dir * speed * dt, _main_ref)
		_walk_phase += dt * 8.0
	else:
		_walk_phase = 0.0


func _process_seek_trough(dt: float, main: Node) -> void:
	if target_trough == null or not is_instance_valid(target_trough):
		state = State.IDLE
		state_t = 2.0
		return

	var to_trough: Vector3 = target_trough.position - position
	to_trough.y = 0.0
	var dist: float = to_trough.length()

	if dist > 1.4:
		var dir: Vector3 = to_trough.normalized()
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * dt))
		if not _try_move(dir * 1.3 * dt, main):
			state = State.IDLE   # fenced off from the trough
			state_t = 3.0
			target_trough = null
		_walk_phase += dt * 6.0
	else:
		# Arrived at trough! Feed or drink
		_walk_phase = 0.0
		if target_trough.has_method("consume_feed") and hunger < 80.0 and target_trough.has_feed():
			target_trough.consume_feed()
			hunger = minf(100.0, hunger + 40.0)
			pop_emote("🌾", Color(0.9, 0.9, 0.3))
		elif target_trough.has_method("consume_water") and thirst < 80.0 and target_trough.has_water():
			target_trough.consume_water()
			thirst = minf(100.0, thirst + 40.0)
			pop_emote("💧", Color(0.4, 0.8, 1.0))
		state = State.IDLE
		state_t = 4.0
		target_trough = null


func _process_graze(dt: float) -> void:
	_walk_phase = 0.0
	_graze_y_offset = sin(state_t * 2.0) * 0.15
	if state_t <= 0.0:
		hunger = minf(100.0, hunger + 8.0)
		state = State.IDLE
		state_t = randf_range(3.0, 6.0)


func _process_wander(dt: float) -> void:
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var speed := 0.9 if species != &"shore_duck" else 0.6
	if not _try_move(forward * speed * dt, _main_ref):
		yaw += PI * randf_range(0.5, 1.0)   # hit the fence: turn back into the pen
	_walk_phase += dt * 5.0
	if state_t <= 0.0:
		state = State.IDLE
		state_t = randf_range(2.0, 5.0)


func _process_idle(dt: float, main: Node) -> void:
	_walk_phase = 0.0
	if state_t <= 0.0:
		# Check if hungry/thirsty and seek a trough
		if (hunger < 45.0 or thirst < 45.0) and main != null and main.get("entities") != null:
			var nearest_t: Node3D = _find_nearest_trough(main)
			if nearest_t != null:
				target_trough = nearest_t
				state = State.SEEK_TROUGH
				state_t = 15.0
				return

		# Randomly decide to wander or graze
		if randf() < 0.4:
			state = State.GRAZE
			state_t = randf_range(3.0, 5.0)
		else:
			state = State.WANDER
			yaw += randf_range(-PI * 0.5, PI * 0.5)
			state_t = randf_range(2.5, 5.0)


func _find_nearest_trough(main: Node) -> Node3D:
	var ents: EntityManager = main.entities
	if ents == null:
		return null
	var best: Node3D = null
	var best_d := 22.0
	for ent in ents.entities.values():
		if ent != null and ent.entity_id == &"feed_trough":
			if (hunger < 45.0 and ent.has_method("has_feed") and ent.has_feed()) or (thirst < 45.0 and ent.has_method("has_water") and ent.has_water()):
				var d := position.distance_to(ent.position)
				if d < best_d:
					best = ent
					best_d = d
	return best


func _snap_to_ground(main: Node) -> void:
	if main == null or main.get("world") == null:
		return
	var store: VoxelStore = main.world.store
	if store == null:
		return
	var vx := int(floor(position.x / VoxelWorld.VS))
	var vz := int(floor(position.z / VoxelWorld.VS))
	# Ground near our feet first (so passing under a rail doesn't pop us onto the fence),
	# then the column top as a fallback (fresh spawns, big drops).
	var g := TerrainStep.ground_at(main.world.get_voxel, position.x, position.z, position.y, 3, 8)
	if is_nan(g):
		# Column top: scan down for the first solid voxel (only for fresh spawns / big drops).
		var gy := -1
		for y in range(VoxelWorld.WY - 1, 0, -1):
			var gm: int = main.world.get_voxel(vx, y, vz)
			if gm != 0 and not Palette.is_plant(gm):
				gy = y + 1
				break
		if gy <= 0:
			return   # column not streamed in yet: try again next frame
		g = float(gy) * VoxelWorld.VS
	position.y = lerpf(position.y, g + 0.1, 0.2)


func _animate_parts(dt: float) -> void:
	if visual_root != null:
		visual_root.rotation.y = yaw

	# Leg swinging walk cycle
	var swing := sin(_walk_phase) * 0.45
	if leg_fl != null: leg_fl.rotation.x = swing
	if leg_fr != null: leg_fr.rotation.x = -swing
	if leg_bl != null: leg_bl.rotation.x = -swing
	if leg_br != null: leg_br.rotation.x = swing

	# Head bobbing / grazing
	if head_node != null:
		if state == State.GRAZE:
			head_node.rotation.x = lerp_angle(head_node.rotation.x, 0.7, 1.0 - exp(-6.0 * dt))
		else:
			head_node.rotation.x = lerp_angle(head_node.rotation.x, sin(_walk_phase * 0.5) * 0.1, 1.0 - exp(-6.0 * dt))

	# Duck wing flapping
	if wing_l != null and wing_r != null:
		if _walk_phase > 0.0 or state == State.FOLLOW:
			var flap := absf(sin(_walk_phase * 2.0)) * 0.5
			wing_l.rotation.z = flap
			wing_r.rotation.z = -flap
		else:
			wing_l.rotation.z = 0.0
			wing_r.rotation.z = 0.0

	# Emote float & fade
	if _emote_timer > 0.0 and _emote_label != null:
		_emote_timer -= dt
		_emote_label.position.y += dt * 0.35
		var alpha := clampf(_emote_timer / 0.8, 0.0, 1.0)
		_emote_label.modulate.a = alpha


# ---------------------------------------------------------------- Co-op mirroring

## Compact state the host streams to clients a few times a second.
func net_pack() -> Array:
	return [animal_id, species, animal_name, position, yaw, int(state), wool_grown,
			yield_timer, hunger, thirst, happiness, pet_cooldown]


## Client: take the host's state. Pose is smoothed in net_update.
func net_apply(a: Array) -> void:
	_net_pos = a[3]
	_net_yaw = float(a[4])
	state = int(a[5]) as State
	if bool(a[6]) != wool_grown:
		wool_grown = bool(a[6])
		if wool_mesh != null:
			wool_mesh.visible = wool_grown
	yield_timer = float(a[7])
	hunger = float(a[8])
	thirst = float(a[9])
	happiness = float(a[10])
	pet_cooldown = float(a[11])


## Client frame: glide to the host's pose and animate as if walking.
func net_update(dt: float) -> void:
	if pet_cooldown > 0.0:
		pet_cooldown -= dt
	if _net_pos is Vector3:
		var target: Vector3 = _net_pos
		if position.distance_to(target) > 4.0:
			position = target   # teleported / just joined
		var before := position
		position = position.lerp(target, 1.0 - exp(-10.0 * dt))
		var moved := Vector2(position.x - before.x, position.z - before.z).length()
		if moved > 0.0005:
			_walk_phase += dt * 7.0
		else:
			_walk_phase = 0.0
	yaw = lerp_angle(yaw, _net_yaw, 1.0 - exp(-10.0 * dt))
	if state == State.GRAZE:
		_graze_y_offset = sin(Time.get_ticks_msec() * 0.002) * 0.15
	_animate_parts(dt)


## The fields a player's interaction can change, reported to the host by clients.
func interact_state() -> Dictionary:
	return {"wool": wool_grown, "yield_t": yield_timer, "hunger": hunger,
			"thirst": thirst, "happy": happiness, "pet_cd": pet_cooldown}


func apply_interact_state(d: Dictionary) -> void:
	wool_grown = bool(d.get("wool", wool_grown))
	if wool_mesh != null:
		wool_mesh.visible = wool_grown
	yield_timer = float(d.get("yield_t", yield_timer))
	hunger = float(d.get("hunger", hunger))
	thirst = float(d.get("thirst", thirst))
	happiness = float(d.get("happy", happiness))
	pet_cooldown = float(d.get("pet_cd", pet_cooldown))


# ---------------------------------------------------------------- Serialization

func serialize() -> Dictionary:
	return {
		"id": animal_id,
		"sp": species,
		"name": animal_name,
		"pos": position,
		"yaw": yaw,
		"hunger": hunger,
		"thirst": thirst,
		"happy": happiness,
		"yield_t": yield_timer,
		"wool": wool_grown,
	}


func deserialize(data: Dictionary) -> void:
	animal_id = int(data.get("id", animal_id))
	species = StringName(data.get("sp", species))
	animal_name = String(data.get("name", animal_name))
	position = data.get("pos", position)
	yaw = float(data.get("yaw", yaw))
	hunger = float(data.get("hunger", hunger))
	thirst = float(data.get("thirst", thirst))
	happiness = float(data.get("happy", happiness))
	yield_timer = float(data.get("yield_t", yield_timer))
	wool_grown = bool(data.get("wool", wool_grown))
	if wool_mesh != null:
		wool_mesh.visible = wool_grown
