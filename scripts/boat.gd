class_name Boat
extends Node3D
## Boat entity (not terrain): the rowboat (kind 0) and the outrigger sailing skiff
## (kind 1). Floats on the tide plane, collides with terrain/docks via voxel queries and
## grounds itself in the shallows. The rowboat rows with pulsed strokes; the skiff sails
## on the weather's wind (see sail_efficiency) and can paddle when the wind is foul.
##
## Networking: exactly one peer simulates a boat at a time (its driver, or the host
## when nobody is rowing). Everyone else interpolates the snapshots BoatManager relays.
## Boat-local axes: +Z = bow (forward), +X = starboard... rotated by `yaw` about Y.

const VS := VoxelWorld.VS
const DRAFT := 0.08            # hull bottom below the waterline (m)
const HULL_PREFAB := 11        # "Rowboat" voxel grid (8 x 6 x 20)
const HALF_BEAM := 0.62
const HALF_LEN := 1.70
## Seat positions in boat space, at the character's feet origin. 0 = rower, 1 = passenger.
const SEATS := [Vector3(0.0, 0.01, 0.36), Vector3(0.0, 0.01, -0.72)]
const STROKES_PER_SEC := 1.1
const THRUST := 5.0
const TURN := 1.9
const KIND_ROWBOAT := 0
const KIND_SKIFF := 1
## Skiff: sail drive at full wind on a beam reach (m/s^2), paddle drive, seat layout.
const SAIL_ACCEL := 14.0
const PADDLE_ACCEL := 1.6
const SKIFF_SEATS := [Vector3(0.0, 0.01, -1.15), Vector3(0.0, 0.01, 0.55)]
## Tier-2 workboats. The Tide-Barge: flat-bottomed and beamy, rowed with long sweeps; it
## floats over tidal mud a skiff would ground on, wind barely moves it, it seats four, and
## its cargo hold carries 27 stacks between islands. The Coastal Sloop: a single big
## gaff sail on a deep keel; faster than the skiff and points higher (only ~30 degrees
## off the wind is "in irons"), with a little cuddy cabin forward. Seats three.
const KIND_BARGE := 2
const KIND_SLOOP := 3
const KIND_SCHOONER := 4
const BARGE_SEATS := [Vector3(0.0, 0.01, -1.9), Vector3(-0.55, 0.01, 0.3), Vector3(0.55, 0.01, 0.3), Vector3(0.0, 0.01, 1.4)]
const SLOOP_SEATS := [Vector3(0.0, 0.01, -2.05), Vector3(-0.4, 0.01, -1.1), Vector3(0.4, 0.01, -1.1)]
const SCHOONER_SEATS := [Vector3(0.0, 0.01, -3.2), Vector3(-0.6, 0.01, -1.8), Vector3(0.6, 0.01, -1.8), Vector3(-0.6, 0.01, 0.8), Vector3(0.6, 0.01, 0.8), Vector3(0.0, 0.01, 2.5)]
const HOLD_SLOTS := 27
const SCHOONER_HOLD_SLOTS := 36
const SLOOP_SAIL := 1.35        # sail force relative to the skiff
const SCHOONER_SAIL := 1.65     # powerful double-masted gaff rig

var id := 0
var kind := KIND_ROWBOAT
var is_world_spawn: bool = false
var half_beam := HALF_BEAM
var half_len := HALF_LEN
var yaw := 0.0
var vel := Vector2.ZERO        # xz, m/s
var yaw_vel := 0.0
var row_phase := 0.0
var row_power := 0.0
var occupants := [0, 0]        # peer id per seat (0 = empty)
var grounded := false
var world: VoxelWorld
var sky: SkyCycle

var visual: Node3D
var _oar_l: Node3D
var _oar_r: Node3D
var _t := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_vel := Vector2.ZERO
var _has_net := false
var _wake: CPUParticles3D
var _bow_spray: CPUParticles3D
var _sail: Node3D               # skiff: the yard + sail, swung about the mast
var sail_angle := 0.0           # skiff: boom angle the sail has swung to (radians)
var hold: Inventory = null      # barge: the cargo hold (authority's copy is the truth)
var moored := false             # empty and tied up at a mooring bollard: no drifting
var _moor_t := 0.0

var has_lantern := false
var lantern_lit := true
var _bow_lantern: OmniLight3D = null
var _lantern_mesh: MeshInstance3D = null
var small_hold: Inventory = null
var reinforced_hull := false
var has_reinforced_hull: bool:
	get: return reinforced_hull
	set(v): reinforced_hull = v
var outrigger_rigged := false
var _water_lap_cd := 0.0
var deck_fixtures: Dictionary = {}  # slot_idx: int -> Dictionary {"id": StringName, "node": Node3D, "hold": Inventory}
var max_hull_hp: float = 100.0
var hull_hp: float = 100.0
var leak_amount: float = 0.0
var has_gilded_wheel: bool = false
var has_sea_hawk: bool = false


func setup(p_id: int, p_world: VoxelWorld, p_sky: SkyCycle, pos: Vector3, p_yaw: float, p_kind := KIND_ROWBOAT) -> void:
	id = p_id
	kind = p_kind
	match kind:
		KIND_ROWBOAT: max_hull_hp = 100.0
		KIND_SKIFF: max_hull_hp = 150.0
		KIND_SLOOP: max_hull_hp = 200.0
		KIND_BARGE: max_hull_hp = 250.0
		KIND_SCHOONER: max_hull_hp = 350.0
	hull_hp = max_hull_hp
	leak_amount = 0.0
	if kind == KIND_SKIFF:
		half_beam = 1.15     # the outrigger float sits out to port
		half_len = 2.3
	elif kind == KIND_BARGE:
		half_beam = 1.15
		half_len = 2.6
		occupants = [0, 0, 0, 0]
		hold = Inventory.new(HOLD_SLOTS)
	elif kind == KIND_SLOOP:
		half_beam = 0.95
		half_len = 2.9
		occupants = [0, 0, 0]
	elif kind == KIND_SCHOONER:
		half_beam = 1.35
		half_len = 4.2
		occupants = [0, 0, 0, 0, 0, 0]
		hold = Inventory.new(SCHOONER_HOLD_SLOTS)
		reinforced_hull = true
	if kind == KIND_ROWBOAT or kind == KIND_SKIFF:
		small_hold = Inventory.new(6)
	world = p_world
	sky = p_sky
	position = pos
	yaw = p_yaw
	_net_pos = pos
	_net_yaw = p_yaw
	_build_visual()


func is_skiff() -> bool:
	return kind == KIND_SKIFF


func is_barge() -> bool:
	return kind == KIND_BARGE


## Skiff, sloop and schooner: driven by the wind (W/S work the sail).
func has_sail() -> bool:
	return kind == KIND_SKIFF or kind == KIND_SLOOP or kind == KIND_SCHOONER


func display_name() -> String:
	match kind:
		KIND_SKIFF: return "skiff"
		KIND_BARGE: return "Tide-Barge"
		KIND_SLOOP: return "Coastal Sloop"
		KIND_SCHOONER: return "Ocean Schooner"
	return "rowboat"


func seats_list() -> Array:
	match kind:
		KIND_SKIFF: return SKIFF_SEATS
		KIND_BARGE: return BARGE_SEATS
		KIND_SLOOP: return SLOOP_SEATS
		KIND_SCHOONER: return SCHOONER_SEATS
	return SEATS


func get_hold() -> Inventory:
	return hold if hold != null else small_hold


func hold_used() -> int:
	var h := get_hold()
	if h == null:
		return 0
	var n := 0
	for s: ItemSlot in h.slots:
		if not s.is_empty():
			n += 1
	return n


func install_lantern() -> void:
	if has_lantern:
		return
	has_lantern = true
	lantern_lit = true
	_build_lantern()


func toggle_lantern() -> void:
	if not has_lantern:
		return
	lantern_lit = not lantern_lit
	if _bow_lantern != null:
		_bow_lantern.visible = lantern_lit
	if _lantern_mesh != null:
		_lantern_mesh.visible = lantern_lit


func _build_lantern() -> void:
	if _bow_lantern != null or visual == null:
		return
	_lantern_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.35, 0.25)
	_lantern_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 2.0
	_lantern_mesh.material_override = mat
	_lantern_mesh.position = Vector3(0, 0.45, half_len - 0.25)
	visual.add_child(_lantern_mesh)

	_bow_lantern = OmniLight3D.new()
	_bow_lantern.light_color = Color(1.0, 0.88, 0.55)
	_bow_lantern.light_energy = 1.6
	_bow_lantern.omni_range = 14.0
	_bow_lantern.position = Vector3(0, 0.55, half_len - 0.2)
	visual.add_child(_bow_lantern)


# ---------------------------------------------------------------- modular deck fixtures

func get_deck_slots() -> Array[Dictionary]:
	match kind:
		KIND_SLOOP:
			return [
				{"index": 0, "name": "Bow Mount", "pos": Vector3(0.0, 0.45, 1.8), "allowed": [&"deck_lantern", &"harpoon_swivel", &"sea_hawk_perch"]},
				{"index": 1, "name": "Port Deck", "pos": Vector3(-0.6, 0.25, 0.2), "allowed": [&"cargo_crate", &"deck_lantern", &"diving_winch", &"gilded_ship_wheel"]},
				{"index": 2, "name": "Cuddy Cabin", "pos": Vector3(0.0, 0.25, 1.0), "allowed": [&"sea_cot", &"navigation_table", &"cargo_crate", &"gilded_ship_wheel"]}
			]
		KIND_SCHOONER:
			return [
				{"index": 0, "name": "Bow Pulpit", "pos": Vector3(0.0, 0.65, 3.4), "allowed": [&"deck_lantern", &"harpoon_swivel", &"sea_hawk_perch"]},
				{"index": 1, "name": "Foredeck Starboard", "pos": Vector3(0.7, 0.35, 1.6), "allowed": [&"cargo_crate", &"harpoon_swivel", &"diving_winch"]},
				{"index": 2, "name": "Foredeck Port", "pos": Vector3(-0.7, 0.35, 1.6), "allowed": [&"cargo_crate", &"deck_lantern", &"diving_winch"]},
				{"index": 3, "name": "Midship Deck", "pos": Vector3(0.0, 0.35, -0.4), "allowed": [&"navigation_table", &"cargo_crate", &"diving_winch", &"sea_hawk_perch"]},
				{"index": 4, "name": "Quarterdeck Cabin", "pos": Vector3(0.0, 0.45, -2.2), "allowed": [&"sea_cot", &"navigation_table", &"gilded_ship_wheel"]}
			]
		KIND_BARGE:
			return [
				{"index": 0, "name": "Bow Cleat Mount", "pos": Vector3(0.0, 0.35, 2.0), "allowed": [&"deck_lantern", &"gilded_ship_wheel", &"sea_hawk_perch"]},
				{"index": 1, "name": "Port Cargo Bay", "pos": Vector3(-0.7, 0.25, -0.5), "allowed": [&"cargo_crate", &"diving_winch"]},
				{"index": 2, "name": "Starboard Cargo Bay", "pos": Vector3(0.7, 0.25, -0.5), "allowed": [&"cargo_crate", &"diving_winch"]}
			]
		_:
			return [
				{"index": 0, "name": "Bow Stem", "pos": Vector3(0.0, 0.35, half_len - 0.3), "allowed": [&"deck_lantern", &"cargo_crate", &"gilded_ship_wheel", &"sea_hawk_perch"]}
			]


func can_install_fixture(slot_idx: int, fixture_id: StringName) -> bool:
	if deck_fixtures.has(slot_idx):
		return false
	var slots := get_deck_slots()
	for s in slots:
		if s["index"] == slot_idx:
			var allowed: Array = s["allowed"]
			return allowed.is_empty() or allowed.has(fixture_id)
	return false


func install_fixture(slot_idx: int, fixture_id: StringName, hold_data: Variant = null) -> bool:
	if deck_fixtures.has(slot_idx):
		return false
	var slots := get_deck_slots()
	var slot_def: Dictionary = {}
	for s in slots:
		if s["index"] == slot_idx:
			slot_def = s
			break
	if slot_def.is_empty():
		return false
	var allowed: Array = slot_def["allowed"]
	if not allowed.is_empty() and not allowed.has(fixture_id):
		return false

	var mount_pos: Vector3 = slot_def["pos"]
	var fixture_node := Node3D.new()
	fixture_node.name = "Fixture_%d_%s" % [slot_idx, fixture_id]
	fixture_node.position = mount_pos

	var inv: Inventory = null
	match fixture_id:
		&"deck_lantern":
			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.32, 0.22)
			mesh_inst.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.75, 0.3)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.85, 0.4)
			mat.emission_energy_multiplier = 2.0
			mesh_inst.material_override = mat
			fixture_node.add_child(mesh_inst)

			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.88, 0.55)
			light.light_energy = 1.6
			light.omni_range = 14.0
			light.position = Vector3(0, 0.1, 0)
			fixture_node.add_child(light)

		&"cargo_crate":
			inv = Inventory.new(9)
			var crate_hold = hold_data
			if hold_data is Dictionary and hold_data.has("hold"):
				crate_hold = hold_data["hold"]
			if crate_hold != null and crate_hold is Dictionary:
				inv.deserialize(crate_hold)
			var crate_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.42, 0.55)
			crate_mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.48, 0.34, 0.22)
			mat.roughness = 0.9
			crate_mesh.material_override = mat
			fixture_node.add_child(crate_mesh)

		&"harpoon_swivel":
			var mount_base := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.08
			cyl.bottom_radius = 0.12
			cyl.height = 0.35
			mount_base.mesh = cyl
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.3, 0.32)
			mount_base.material_override = mat
			fixture_node.add_child(mount_base)

			var barrel := MeshInstance3D.new()
			var b_cyl := CylinderMesh.new()
			b_cyl.top_radius = 0.04
			b_cyl.bottom_radius = 0.04
			b_cyl.height = 0.7
			barrel.mesh = b_cyl
			barrel.rotation.x = deg_to_rad(90)
			barrel.position = Vector3(0, 0.2, 0.25)
			barrel.material_override = mat
			fixture_node.add_child(barrel)

		&"sea_cot":
			var cot_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.65, 0.18, 1.35)
			cot_mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.6, 0.55, 0.45)
			cot_mesh.material_override = mat
			fixture_node.add_child(cot_mesh)

		&"navigation_table":
			var table_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.4, 0.45)
			table_mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.35, 0.24, 0.15)
			table_mesh.material_override = mat
			fixture_node.add_child(table_mesh)

		&"diving_winch":
			var frame := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.15
			cyl.height = 0.45
			frame.mesh = cyl
			var frame_mat := StandardMaterial3D.new()
			frame_mat.albedo_color = Color(0.25, 0.25, 0.28)
			frame.material_override = frame_mat
			fixture_node.add_child(frame)

			var spool := MeshInstance3D.new()
			var sp_cyl := CylinderMesh.new()
			sp_cyl.top_radius = 0.18
			sp_cyl.bottom_radius = 0.18
			sp_cyl.height = 0.25
			spool.mesh = sp_cyl
			spool.rotation.z = deg_to_rad(90)
			spool.position = Vector3(0, 0.28, 0)
			var brass_mat := StandardMaterial3D.new()
			brass_mat.albedo_color = Color(0.8, 0.65, 0.2)
			spool.material_override = brass_mat
			fixture_node.add_child(spool)

			var bell := MeshInstance3D.new()
			bell.name = "DivingBell"
			var sph := SphereMesh.new()
			sph.radius = 0.22
			sph.height = 0.35
			bell.mesh = sph
			bell.material_override = brass_mat
			bell.position = Vector3(0, -0.4, 0)
			fixture_node.add_child(bell)
		&"gilded_ship_wheel":
			has_gilded_wheel = true
			var wh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.32
			cyl.bottom_radius = 0.32
			cyl.height = 0.08
			wh.mesh = cyl
			var g_mat := StandardMaterial3D.new()
			g_mat.albedo_color = Color(0.95, 0.82, 0.25)
			wh.material_override = g_mat
			wh.rotation.x = PI * 0.5
			fixture_node.add_child(wh)
		&"sea_hawk_perch":
			has_sea_hawk = true
			var post := MeshInstance3D.new()
			var cpost := BoxMesh.new()
			cpost.size = Vector3(0.08, 0.8, 0.08)
			post.mesh = cpost
			fixture_node.add_child(post)
			var hawk := MeshInstance3D.new()
			var hmesh := SphereMesh.new()
			hmesh.radius = 0.12
			hmesh.height = 0.25
			hawk.mesh = hmesh
			hawk.position = Vector3(0, 0.45, 0)
			fixture_node.add_child(hawk)

	if visual != null:
		visual.add_child(fixture_node)
	else:
		add_child(fixture_node)

	var is_lowered := false
	if hold_data is Dictionary:
		is_lowered = hold_data.get("lowered", false)
		if is_lowered:
			var bell_node: Node3D = fixture_node.get_node_or_null("DivingBell")
			if bell_node != null:
				bell_node.position.y = -8.0

	deck_fixtures[slot_idx] = {
		"id": fixture_id,
		"node": fixture_node,
		"hold": inv,
		"lowered": is_lowered
	}
	return true


func remove_fixture(slot_idx: int) -> StringName:
	if not deck_fixtures.has(slot_idx):
		return &""
	var f: Dictionary = deck_fixtures[slot_idx]
	var fid: StringName = f["id"]
	if fid == &"gilded_ship_wheel":
		has_gilded_wheel = false
	elif fid == &"sea_hawk_perch":
		has_sea_hawk = false
	var node: Node3D = f.get("node")
	if node != null and is_instance_valid(node):
		node.queue_free()
	deck_fixtures.erase(slot_idx)
	return fid


func interact_fixture(slot_idx: int, player: Node) -> void:
	if not deck_fixtures.has(slot_idx) or player == null:
		return
	var f: Dictionary = deck_fixtures[slot_idx]
	var fid: StringName = f["id"]
	match fid:
		&"deck_lantern":
			var node: Node3D = f.get("node")
			if node != null:
				for ch in node.get_children():
					if ch is OmniLight3D:
						ch.visible = not ch.visible
		&"cargo_crate":
			var h: Inventory = f.get("hold")
			if h != null and player.get("hud") != null:
				player.hud.open_container(h, "Ship Cargo Crate")
		&"sea_cot":
			if player.get("vitality") != null:
				player.vitality.current_hp = player.vitality.get_max_hp()
				player.vitality.current_stamina = player.vitality.get_max_stamina()
			if player.get("hud") != null and player.hud.has_method("show_toast"):
				player.hud.show_toast("Rested in Sailor's Cot. Senses revitalized.")
		&"navigation_table":
			if player.get("hud") != null and player.hud.has_method("show_banner"):
				var wind := wind_vec()
				var angle_deg := int(round(rad_to_deg(wind.angle())))
				player.hud.show_banner("Navigation Chart Desk", "Wind heading: %d° | Current vessel: %s" % [angle_deg, display_name()])
		&"harpoon_swivel":
			CombatAudio.play_sound("swing_heavy", position)
			if player.get("hud") != null and player.hud.has_method("show_toast"):
				player.hud.show_toast("Swivel Harpoon primed and armed.")
		&"diving_winch":
			var is_lowered: bool = not f.get("lowered", false)
			f["lowered"] = is_lowered
			var node: Node3D = f.get("node")
			if node != null:
				var bell_node: Node3D = node.get_node_or_null("DivingBell")
				if bell_node != null:
					bell_node.position.y = -8.0 if is_lowered else -0.4
			CombatAudio.play_sound("parry", position)
			if player.get("hud") != null and player.hud.has_method("show_toast"):
				if is_lowered:
					player.hud.show_toast("Diving Bell lowered 8m — underwater oxygen pocket active!")
				else:
					player.hud.show_toast("Diving Bell winched back up to surface.")


func take_hull_damage(dmg: float, _attacker = null) -> void:
	if dmg <= 0.0:
		return
	var eff_dmg := dmg * (0.65 if reinforced_hull else 1.0)
	hull_hp = maxf(0.0, hull_hp - eff_dmg)
	if hull_hp < max_hull_hp * 0.5:
		leak_amount = clampf(leak_amount + (eff_dmg / max_hull_hp) * 1.5, 0.0, 1.0)
	CombatAudio.play_sound("shield_block", position)


func repair_hull(amount: float) -> void:
	hull_hp = minf(max_hull_hp, hull_hp + amount)
	if hull_hp >= max_hull_hp * 0.75:
		leak_amount = maxf(0.0, leak_amount - 0.4)
	if hull_hp >= max_hull_hp:
		leak_amount = 0.0


func repair_at_sea(player_node: Node) -> bool:
	if player_node == null or not ("inventory" in player_node) or player_node.inventory == null:
		return false
	var inv: Inventory = player_node.inventory
	var repair_mat := &""
	if inv.has_item(&"dark_wood", 1):
		repair_mat = &"dark_wood"
	elif inv.has_item(&"wood_plank", 1):
		repair_mat = &"wood_plank"
	elif inv.has_item(&"pine_wood", 1):
		repair_mat = &"pine_wood"

	if repair_mat == &"":
		if "hud" in player_node and player_node.hud != null:
			player_node.hud.show_toast("Need wood planks or tarred wood to repair hull!")
		return false

	inv.remove_item(repair_mat, 1)
	repair_hull(40.0)
	leak_amount = maxf(0.0, leak_amount - 0.35)
	if "hud" in player_node and player_node.hud != null:
		player_node.hud.show_toast("Hull Patched with %s (%.0f%% Integrity)" % [ItemDB.get_item(repair_mat).name, get_hull_percent()])
	return true


func is_leaking() -> bool:
	return leak_amount > 0.0


func get_hull_percent() -> float:
	return (hull_hp / maxf(1.0, max_hull_hp)) * 100.0


func scout_surroundings() -> String:
	if not has_sea_hawk:
		return ""
	var info := "Sea-Hawk takes flight and circles overhead, keeping vigilant watch over the brine."
	var m = get_parent().get_parent() if get_parent() != null else null
	if m != null and "world" in m and m.world != null and m.world.gen != null:
		var nearest_wreck_dist := INF
		var nearest_wreck_dir := "Ahead"
		for w in m.world.gen.wrecks:
			var wp := Vector2(w.chest.x * VoxelWorld.VS, w.chest.z * VoxelWorld.VS)
			var bp := Vector2(position.x, position.z)
			var d := bp.distance_to(wp)
			if d < nearest_wreck_dist:
				nearest_wreck_dist = d
				var diff := wp - bp
				var ang := rad_to_deg(atan2(diff.y, diff.x))
				if ang >= -45 and ang <= 45: nearest_wreck_dir = "East"
				elif ang > 45 and ang < 135: nearest_wreck_dir = "South"
				elif ang >= 135 or ang <= -135: nearest_wreck_dir = "West"
				else: nearest_wreck_dir = "North"
		if nearest_wreck_dist < 450.0:
			info = "🦅 Sea-Hawk screeches! Spots a shipwreck %.0fm to the %s!" % [nearest_wreck_dist, nearest_wreck_dir]
	return info



func serialize_fixtures() -> Array:
	var out: Array = []
	for s_idx in deck_fixtures:
		var f: Dictionary = deck_fixtures[s_idx]
		var hold_data = f.hold.serialize() if f.get("hold") != null else null
		out.append({
			"slot": s_idx,
			"id": String(f["id"]),
			"hold": hold_data,
			"lowered": f.get("lowered", false)
		})
	return out


func deserialize_fixtures(arr: Variant) -> void:
	if not (arr is Array):
		return
	for s_idx in deck_fixtures.keys():
		remove_fixture(s_idx)
	for rec in arr:
		if rec is Dictionary and rec.has("slot") and rec.has("id"):
			install_fixture(int(rec["slot"]), StringName(rec["id"]), rec)


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	if is_skiff():
		_build_skiff(mat)
		_build_wake()
		return
	if kind == KIND_SLOOP:
		_build_sloop(mat)
		_build_wake()
		return
	if kind == KIND_SCHOONER:
		_build_schooner(mat)
		_build_wake()
		return
	if kind == KIND_BARGE:
		_build_barge(mat)
		var u2 := VS * 0.5
		var sg := Prefabs.Grid.new(34, 1, 3)
		sg.box(0, 0, 1, 27, 0, 1, Palette.HANDLE)
		sg.box(0, 0, 1, 2, 0, 1, Palette.DARK_WOOD)
		sg.box(28, 0, 0, 33, 0, 2, Palette.PLANK)
		var sweep_mesh := Mesher.mesh_from_grid(sg.data, sg.sx, sg.sy, sg.sz, u2, mat, mat)
		_oar_r = _make_oar(sweep_mesh, u2, 1.0)
		_oar_l = _make_oar(sweep_mesh, u2, -1.0)
		_build_wake()
		return
	var pf := Prefabs.rotated(HULL_PREFAB, 0)
	var s: Vector3i = pf.size
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(pf.data, s.x, s.y, s.z, VS, mat, mat)
	hull.position = Vector3(-s.x * 0.5 * VS, -DRAFT, -s.z * 0.5 * VS)
	visual.add_child(hull)
	# Oars, built at character detail (2x terrain resolution).
	var u := VS * 0.5
	var g := Prefabs.Grid.new(26, 1, 3)
	g.box(0, 0, 1, 19, 0, 1, Palette.HANDLE)
	g.box(0, 0, 1, 2, 0, 1, Palette.DARK_WOOD)       # grip
	g.box(20, 0, 0, 25, 0, 2, Palette.PLANK)          # blade
	g.box(24, 0, 0, 25, 0, 2, Palette.ROOF_BLUE)      # painted tip
	var oar_mesh := Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, u, mat, mat)
	_oar_r = _make_oar(oar_mesh, u, 1.0)
	_oar_l = _make_oar(oar_mesh, u, -1.0)
	_build_wake()


## Outrigger skiff: a long narrow dugout, a float on two booms out to port, a mast with
## a striped lateen sail on a swinging yard. Built at terrain resolution like the rowboat.
func _build_skiff(mat: Material) -> void:
	var g := Prefabs.Grid.new(14, 4, 28)
	# hull: x 1..5 (centre 3), tapering to a point at both ends
	for z in range(0, 28):
		var w := 2 if z > 3 and z < 24 else 1
		if z == 0 or z == 27:
			w = 0
		g.box(3 - w, 0, z, 3 + w, 0, z, Palette.DARK_WOOD)              # keel / floor
		g.box(3 - w, 1, z, 3 - w, 2, z, Palette.PLANK)                   # sides
		g.box(3 + w, 1, z, 3 + w, 2, z, Palette.PLANK)
		if w > 0:
			g.box(3 - w + 1, 1, z, 3 + w - 1, 1, z, Palette.DARK_WOOD)   # inside floor boards
	g.box(1, 2, 4, 1, 2, 23, Palette.ROOF_BLUE)                          # painted gunwale
	g.box(5, 2, 4, 5, 2, 23, Palette.ROOF_BLUE)
	g.box(3, 2, 0, 3, 3, 0, Palette.DARK_WOOD)                           # stern post
	g.box(3, 2, 27, 3, 3, 27, Palette.DARK_WOOD)                         # bow post
	g.box(2, 1, 5, 4, 2, 7, Palette.KELP)                                # live-well (kelp-lined)
	# two booms out to the float (port = -x in boat space; the grid is offset so x=13 is port)
	for bz in [7, 20]:
		g.box(5, 3, bz, 11, 3, bz, Palette.HANDLE)
	g.box(11, 0, 4, 12, 1, 23, Palette.DRIFTWOOD)                        # outrigger float
	g.box(11, 1, 3, 12, 1, 3, Palette.DRIFTWOOD)
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	# grid x=3 is the hull's centreline; flip so the float lies to port (-x)
	hull.scale = Vector3(-1, 1, 1)
	hull.position = Vector3(3.5 * VS, -DRAFT, -14 * VS)
	visual.add_child(hull)
	# mast
	var mg := Prefabs.Grid.new(1, 30, 1)
	mg.box(0, 0, 0, 0, 29, 0, Palette.DARK_WOOD)
	var mast := MeshInstance3D.new()
	mast.mesh = Mesher.mesh_from_grid(mg.data, 1, 30, 1, VS, mat, mat)
	mast.position = Vector3(-0.5 * VS, 1 * VS - DRAFT, 3.5 * VS)
	visual.add_child(mast)
	# sail on a pivot at the mast: a triangle of canvas, striped, along the boat's length
	_sail = Node3D.new()
	_sail.position = Vector3(0, 3 * VS - DRAFT, 4 * VS)
	visual.add_child(_sail)
	var sg := Prefabs.Grid.new(1, 26, 18)
	for y in 26:
		var span := int(round(17.0 * (1.0 - float(y) / 26.0)))   # wide at the foot, a point at the top
		for z in range(0, span + 1):
			var c := Palette.WHITEWASH if (y / 4) % 2 == 0 else Palette.ROOF_RED
			sg.setv(0, y, 17 - z, c)
	var sail_mi := MeshInstance3D.new()
	sail_mi.mesh = Mesher.mesh_from_grid(sg.data, 1, 26, 18, VS, mat, mat)
	sail_mi.position = Vector3(-0.5 * VS, 0, -17 * VS)    # the sail's leading edge sits at the mast
	sail_mi.name = "Canvas"
	_sail.add_child(sail_mi)
	var yard := MeshInstance3D.new()
	var yg := Prefabs.Grid.new(1, 1, 20)
	yg.box(0, 0, 0, 0, 0, 19, Palette.HANDLE)
	yard.mesh = Mesher.mesh_from_grid(yg.data, 1, 1, 20, VS, mat, mat)
	yard.position = Vector3(-0.5 * VS, -1 * VS, -18 * VS)
	_sail.add_child(yard)


## Tide-Barge: a broad, flat-bottomed scow with low sides, square ends, a cargo well of
## crates amidships and a pair of long sweeps.
func _build_barge(mat: Material) -> void:
	var g := Prefabs.Grid.new(14, 4, 30)
	for z in 30:
		var end := z == 0 or z == 29
		for x in 14:
			g.setv(x, 0, z, Palette.DARK_WOOD)
			if x == 0 or x == 13 or end:
				g.setv(x, 1, z, Palette.PLANK)
				g.setv(x, 2, z, Palette.DARK_WOOD if end else Palette.PLANK)
		g.setv(0, 3, z, Palette.ROOF_BLUE if z % 6 == 0 else Palette.AIR)
		g.setv(13, 3, z, Palette.ROOF_BLUE if z % 6 == 0 else Palette.AIR)
	g.box(1, 1, 1, 12, 1, 28, Palette.PLANK)                 # deck boards
	for c: Vector3i in [Vector3i(3, 2, 11), Vector3i(8, 2, 11), Vector3i(3, 2, 16), Vector3i(8, 2, 16)]:
		g.box(c.x, c.y, c.z, c.x + 2, c.y + 1, c.z + 3, Palette.TRUNK if (c.x + c.z) % 2 == 0 else Palette.DRIFTWOOD)
	g.box(6, 2, 27, 7, 3, 28, Palette.METAL)                 # a mooring cleat on the bow
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	hull.position = Vector3(-7 * VS, -DRAFT * 0.5, -15 * VS)
	visual.add_child(hull)


## Coastal Sloop: a deep-keeled day-sailer, cuddy cabin forward, one tall mast with a big
## striped gaff sail that swings on its boom.
func _build_sloop(mat: Material) -> void:
	var g := Prefabs.Grid.new(11, 6, 32)
	for z in 32:
		var t := float(z) / 31.0
		var w := int(round(5.0 * sin(clampf(t * 1.15, 0.05, 1.0) * PI * 0.95)))
		if z >= 30:
			w = maxi(0, 31 - z)
		w = maxi(w, 1)
		g.box(5 - w + 1, 0, z, 5 + w - 1, 0, z, Palette.DARK_WOOD)
		for y in range(1, 4):
			g.setv(5 - w, y, z, Palette.WHITEWASH if y < 3 else Palette.ROOF_BLUE)
			g.setv(5 + w, y, z, Palette.WHITEWASH if y < 3 else Palette.ROOF_BLUE)
		g.box(5 - w + 1, 1, z, 5 + w - 1, 1, z, Palette.PLANK)
	g.box(3, 2, 20, 7, 4, 27, Palette.PLANK)                 # the cuddy cabin
	g.box(3, 5, 20, 7, 5, 27, Palette.ROOF_RED)
	g.setv(3, 3, 23, Palette.SHUTTER)
	g.setv(7, 3, 23, Palette.SHUTTER)
	g.box(5, 1, 0, 5, 3, 0, Palette.DARK_WOOD)               # rudder post
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	hull.position = Vector3(-5.5 * VS, -DRAFT, -16 * VS)
	visual.add_child(hull)
	var mg := Prefabs.Grid.new(1, 40, 1)
	mg.box(0, 0, 0, 0, 39, 0, Palette.DARK_WOOD)
	var mast := MeshInstance3D.new()
	mast.mesh = Mesher.mesh_from_grid(mg.data, 1, 40, 1, VS, mat, mat)
	mast.position = Vector3(-0.5 * VS, 1 * VS - DRAFT, 2.5 * VS)
	visual.add_child(mast)
	_sail = Node3D.new()
	_sail.position = Vector3(0, 3 * VS - DRAFT, 3 * VS)
	visual.add_child(_sail)
	var sg := Prefabs.Grid.new(1, 34, 22)
	for y in 34:
		var span := int(round(21.0 * (1.0 - float(y) / 40.0)))   # a gaff: the head stays wide
		for z in range(0, span + 1):
			sg.setv(0, y, 21 - z, Palette.WHITEWASH if (y / 5) % 2 == 0 else Palette.ROOF_BLUE)
	var sail_mi := MeshInstance3D.new()
	sail_mi.mesh = Mesher.mesh_from_grid(sg.data, 1, 34, 22, VS, mat, mat)
	sail_mi.position = Vector3(-0.5 * VS, 0, -21 * VS)
	sail_mi.name = "Canvas"
	_sail.add_child(sail_mi)
	var boom := MeshInstance3D.new()
	var bg := Prefabs.Grid.new(1, 1, 24)
	bg.box(0, 0, 0, 0, 0, 23, Palette.HANDLE)
	boom.mesh = Mesher.mesh_from_grid(bg.data, 1, 1, 24, VS, mat, mat)
	boom.position = Vector3(-0.5 * VS, -1 * VS, -22 * VS)
	_sail.add_child(boom)


## Ocean Schooner: deep-sea double-masted flagship, raised helm quarterdeck, captain's cabin,
## crab pot davit winch, and powerful twin gaff sails.
func _build_schooner(mat: Material) -> void:
	var g := Prefabs.Grid.new(15, 7, 46)
	for z in 46:
		var t := float(z) / 45.0
		var w := int(round(6.5 * sin(clampf(t * 1.12, 0.05, 1.0) * PI * 0.96)))
		if z >= 43:
			w = maxi(0, 45 - z)
		w = maxi(w, 1)
		g.box(7 - w + 1, 0, z, 7 + w - 1, 0, z, Palette.DARK_WOOD)
		for y in range(1, 5):
			var c := Palette.WHITEWASH if y < 4 else Palette.ROOF_BLUE
			g.setv(7 - w, y, z, c)
			g.setv(7 + w, y, z, c)
		g.box(7 - w + 1, 1, z, 7 + w - 1, 1, z, Palette.PLANK)

	# Aft quarterdeck & captain's cabin
	g.box(3, 2, 6, 11, 4, 16, Palette.PLANK)
	g.box(3, 5, 6, 11, 5, 16, Palette.DARK_WOOD)
	# Ship's steering wheel at helm
	g.box(7, 3, 4, 7, 5, 4, Palette.METAL)

	# Forward companionway & crab pot davit on starboard gunwale
	g.box(13, 2, 22, 14, 5, 24, Palette.METAL)
	g.box(11, 5, 23, 14, 5, 23, Palette.HANDLE)

	# Bowsprit
	g.box(7, 4, 44, 7, 5, 45, Palette.DARK_WOOD)

	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	hull.position = Vector3(-7.5 * VS, -DRAFT * 1.2, -23 * VS)
	visual.add_child(hull)

	# Twin masts: Mainmast (aft) & Foremast (forward)
	for m_z: float in [-1.5 * VS, 14.0 * VS]:
		var mg := Prefabs.Grid.new(1, 46, 1)
		mg.box(0, 0, 0, 0, 45, 0, Palette.DARK_WOOD)
		var mast := MeshInstance3D.new()
		mast.mesh = Mesher.mesh_from_grid(mg.data, 1, 46, 1, VS, mat, mat)
		mast.position = Vector3(-0.5 * VS, 1 * VS - DRAFT, m_z)
		visual.add_child(mast)

	# Gaff sail rig on mainmast
	_sail = Node3D.new()
	_sail.position = Vector3(0, 3 * VS - DRAFT, -1.0 * VS)
	visual.add_child(_sail)
	var sg := Prefabs.Grid.new(1, 38, 26)
	for y in 38:
		var span := int(round(25.0 * (1.0 - float(y) / 44.0)))
		for z in range(0, span + 1):
			sg.setv(0, y, 25 - z, Palette.WHITEWASH if (y / 5) % 2 == 0 else Palette.ROOF_RED)
	var sail_mi := MeshInstance3D.new()
	sail_mi.mesh = Mesher.mesh_from_grid(sg.data, 1, 38, 26, VS, mat, mat)
	sail_mi.position = Vector3(-0.5 * VS, 0, -25 * VS)
	sail_mi.name = "Canvas"
	_sail.add_child(sail_mi)
	var boom := MeshInstance3D.new()
	var bg := Prefabs.Grid.new(1, 1, 28)
	bg.box(0, 0, 0, 0, 0, 27, Palette.HANDLE)
	boom.mesh = Mesher.mesh_from_grid(bg.data, 1, 1, 28, VS, mat, mat)
	boom.position = Vector3(-0.5 * VS, -1 * VS, -26 * VS)
	_sail.add_child(boom)


func _build_wake() -> void:
	# Little wake while moving.
	_wake = CPUParticles3D.new()
	_wake.amount = 24
	_wake.lifetime = 1.2
	_wake.emitting = false
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VS * 0.35
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.95, 0.97, 0.95)
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = wm
	_wake.mesh = bm
	_wake.position = Vector3(0, 0.02, -half_len)
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(minf(half_beam, 0.62), 0.01, 0.1)
	_wake.direction = Vector3(0, 0.3, -1)
	_wake.spread = 25.0
	_wake.initial_velocity_min = 0.2
	_wake.initial_velocity_max = 0.6
	_wake.gravity = Vector3(0, -1.5, 0)
	_wake.scale_amount_min = 0.5
	_wake.scale_amount_max = 1.0
	visual.add_child(_wake)

	# Foaming bow spray cutting through waves at speed
	_bow_spray = CPUParticles3D.new()
	_bow_spray.amount = 28
	_bow_spray.lifetime = 0.8
	_bow_spray.emitting = false
	var spm := BoxMesh.new()
	spm.size = Vector3.ONE * VS * 0.28
	var sp_mat := StandardMaterial3D.new()
	sp_mat.albedo_color = Color(0.92, 0.98, 1.0, 0.9)
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.material = sp_mat
	_bow_spray.mesh = spm
	_bow_spray.position = Vector3(0, 0.08, half_len - 0.1)
	_bow_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bow_spray.emission_box_extents = Vector3(minf(half_beam * 0.45, 0.4), 0.02, 0.15)
	_bow_spray.direction = Vector3(0, 0.65, 0.8)
	_bow_spray.spread = 45.0
	_bow_spray.initial_velocity_min = 1.8
	_bow_spray.initial_velocity_max = 3.6
	_bow_spray.gravity = Vector3(0, -5.5, 0)
	_bow_spray.scale_amount_min = 0.4
	_bow_spray.scale_amount_max = 0.85
	visual.add_child(_bow_spray)


func _make_oar(mesh: Mesh, u: float, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * 0.74, 4 * VS - DRAFT, SEATS[0].z + 0.15)
	if kind == KIND_BARGE:
		pivot.position = Vector3(side * 1.22, 3 * VS - DRAFT, BARGE_SEATS[0].z + 0.4)
	visual.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(-7 * u, -0.5 * u, -1.5 * u)   # oarlock ~0.63 m from the grip
	pivot.add_child(mi)
	pivot.set_meta("side", side)
	return pivot


# ---------------------------------------------------------------- queries

func forward2() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func water_y() -> float:
	# [weather] the hull rides the same swell the water shader draws
	return (sky.water_level_m() + sky.wave_offset_at(position)) if sky != null else VoxelWorld.SEA_MID * VS


func seat_transform(i: int) -> Transform3D:
	var seats: Array = seats_list()
	return visual.global_transform * Transform3D(Basis(), seats[clampi(i, 0, seats.size() - 1)])


func seat_position(i: int) -> Vector3:
	return seat_transform(i).origin


func free_seat() -> int:
	for i in occupants.size():
		if occupants[i] == 0:
			return i
	return -1


func seat_of(peer: int) -> int:
	return occupants.find(peer)


func authority() -> int:
	return occupants[0] if occupants[0] != 0 else 1


func _solid(p: Vector3) -> bool:
	if world.has_method("is_loaded_at") and not world.call("is_loaded_at", p):
		# Not streamed in yet (a fast skiff can outrun streaming): use the generator's
		# height map, which matches unedited terrain. With no generator, treat it as solid.
		if world.gen == null:
			return true
		return float(world.gen.col_h(floori(p.x / VS), floori(p.z / VS))) * VS > p.y
	var m := world.get_voxel(floori(p.x / VS), floori(p.y / VS), floori(p.z / VS))
	if m != 0 and not Palette.is_foliage(m):
		return true
	# Entities (Agent A): placed entities and other boats are obstacles too.
	return EntityManager.current != null and EntityManager.current.point_solid(p, self)


## Number of hull sample points overlapping terrain at a candidate pose.
## Samples the keel (grounding), the gunwale (docks, cliffs) and seated-head height.
func blocked_count(pos: Vector3, p_yaw: float, water: float) -> int:
	var f := Vector3(sin(p_yaw), 0, cos(p_yaw))
	var r := Vector3(cos(p_yaw), 0, -sin(p_yaw))
	var n := 0
	for zi in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var half := HALF_BEAM * (0.55 if absf(zi) == 1.0 else 1.0)  # tapered bow/stern
		for xi in [-1.0, 0.0, 1.0]:
			var side := half
			if is_skiff():
				side = half_beam if xi < 0.0 and absf(zi) < 1.0 else 0.45   # float to port
			elif kind != KIND_ROWBOAT:
				side = half_beam * (0.7 if absf(zi) == 1.0 and kind == KIND_SLOOP else 1.0)
			var base: Vector3 = Vector3(pos.x, 0, pos.z) + f * (zi * half_len) + r * (xi * side)
			# the barge's flat bottom floats over mud a keel would ground on
			var keel := (0.04 if kind == KIND_BARGE else -DRAFT - 0.03)
			for h in [keel, 0.3, 1.25]:
				if _solid(base + Vector3(0, water + h, 0)):
					n += 1
	return n


## Where a seated player can step off: a nearby spot with floor under it and room above.
func find_exit_spot() -> Variant:
	var water := water_y()
	var top := floori((water + 1.8) / VS)
	var bottom := floori((water - 0.25) / VS)
	for r in [1.1, 1.5, 1.9, 2.4, 3.0, 3.6]:
		for k in 20:
			var a := TAU * k / 20.0
			var p := Vector3(position.x + cos(a) * r, 0, position.z + sin(a) * r)
			for vy in range(top, bottom - 1, -1):
				var y := vy * VS
				var lo := Vector3(p.x - Player.HW + 0.002, y + 0.002, p.z - Player.HW + 0.002)
				var hi := Vector3(p.x + Player.HW - 0.002, y + Player.H, p.z + Player.HW - 0.002)
				# Entities (Agent A): ignore=world (nothing) so the spot also clears this boat's own hull.
				if world.aabb_collides(lo, hi) or (EntityManager.current != null and EntityManager.current.blocks(lo, hi, world)):
					continue
				if world.aabb_collides(Vector3(p.x - 0.18, y - 0.06, p.z - 0.18), Vector3(p.x + 0.18, y - 0.01, p.z + 0.18)):
					if y >= water - 0.2:
						return Vector3(p.x, y, p.z)
					break
	return null


## Open water beside the hull to slip into and swim from, when there is no floor nearby.
func find_swim_exit_spot() -> Variant:
	var water := water_y()
	var y := water - Player.H * 0.6   # head and shoulders above the surface
	for r in [1.4, 1.8, 2.3, 2.9]:
		# Starboard and port first (over the gunwale), working round to bow and stern.
		for k in [0, 8, 1, 15, 7, 9, 2, 14, 6, 10, 3, 13, 5, 11, 4, 12]:
			var d: Vector2 = Vector2(cos(yaw), -sin(yaw)).rotated(TAU * float(k) / 16.0) * float(r)
			var p := Vector3(position.x + d.x, y, position.z + d.y)
			var lo := Vector3(p.x - Player.HW, y, p.z - Player.HW)
			var hi := Vector3(p.x + Player.HW, y + Player.H, p.z + Player.HW)
			if world.aabb_collides(lo, hi):
				continue
			if EntityManager.current != null and EntityManager.current.blocks(lo, hi, world):
				continue
			return p
	return null


# ---------------------------------------------------------------- simulation

## Wind over the boat (metres/second-ish, xz): the weather's direction, never quite calm.
func wind_vec() -> Vector2:
	if sky == null or sky.weather == null:
		return Vector2(1, 0) * 0.3
	var w: float = sky.weather.params.wind
	var d: Vector2 = sky.weather.params.wind_dir
	return d.normalized() * clampf(w, 0.22, 1.0)


## How well a sail drives a boat pointing along `heading` with the wind blowing towards
## `wind_to`: nothing head to wind ("in irons", within ~40 degrees), best across the wind
## (a beam reach), a bit less dead downwind (a run).
static func sail_efficiency(heading: Vector2, wind_to: Vector2, irons := 140.0) -> float:
	if wind_to.length() < 0.001:
		return 0.0
	var off := rad_to_deg(heading.normalized().angle_to(wind_to.normalized()))
	off = absf(off)                      # 0 = running downwind, 180 = head to wind
	if off <= 90.0:
		return lerpf(0.7, 1.0, off / 90.0)
	return clampf((irons - off) / (irons - 90.0), 0.0, 1.0)


static func point_of_sail(heading: Vector2, wind_to: Vector2) -> String:
	var off := absf(rad_to_deg(heading.normalized().angle_to(wind_to.normalized())))
	if off < 30.0:
		return "Running"
	if off < 70.0:
		return "Broad reach"
	if off < 110.0:
		return "Beam reach"
	if off < 140.0:
		return "Close-hauled"
	return "In irons"


## Skiff drive: W/S raise and lower the sail (row_power holds how far it's up), A/D steer
## with the rudder (needs way on), Shift paddles.
func _sail_drive(delta: float, f: float, t: float, hard: bool) -> void:
	if f > 0.1:
		row_power = minf(1.0, row_power + delta * 0.8)
	elif f < -0.1:
		row_power = maxf(0.0, row_power - delta * 1.2)
	var fwd := forward2()
	var wind := wind_vec()
	var sloop := kind == KIND_SLOOP
	var schooner := kind == KIND_SCHOONER
	var eff := sail_efficiency(fwd, wind, 155.0 if (sloop or schooner) else 140.0)
	var mult: float = SCHOONER_SAIL if schooner else (SLOOP_SAIL if sloop else 1.0)
	var wheel_speed_mult: float = 1.15 if has_gilded_wheel else 1.0
	var leak_speed_mult: float = maxf(0.3, 1.0 - leak_amount * 0.45)
	vel += fwd * row_power * eff * wind.length() * SAIL_ACCEL * mult * wheel_speed_mult * leak_speed_mult * delta
	if hard:
		row_phase += delta * TAU * 1.2
		vel += fwd * maxf(0.0, sin(row_phase)) * PADDLE_ACCEL * 2.0 * wheel_speed_mult * leak_speed_mult * delta
	var speed := absf(vel.dot(fwd))
	var wheel_turn_mult: float = 1.30 if has_gilded_wheel else 1.0
	yaw_vel += t * TURN * wheel_turn_mult * (0.35 + minf(speed, 6.0) * 0.18) * delta
	# The boom swings out to leeward, further off the wind.
	var rel := fwd.angle_to(wind)        # signed
	var want := clampf(PI - absf(rel), 0.15, 1.35) * (1.0 if rel > 0.0 else -1.0) * 0.8
	sail_angle = lerp_angle(sail_angle, want, 1.0 - exp(-delta * 2.0))


## Authority-side physics step. f: -1..1 row, t: -1..1 turn (+ = left), hard: Shift.
func simulate(delta: float, f: float, t: float, hard: bool) -> void:
	var water := water_y()
	if has_sail():
		_sail_drive(delta, f, t, hard)
		_integrate(delta, water)
		return
	var rowing := absf(f) > 0.01 or absf(t) > 0.01
	var cadence := STROKES_PER_SEC * (1.45 if hard else 1.0)
	row_power = lerpf(row_power, 1.0 if rowing else 0.0, 1.0 - exp(-delta * 4.0))
	if rowing or sin(row_phase) > 0.05:
		row_phase += delta * TAU * cadence * maxf(row_power, 0.35)
	var pulse := maxf(0.0, sin(row_phase))
	var fwd := forward2()
	var heavy := 0.8 if kind == KIND_BARGE else 1.0        # the barge's sweeps: slow but steady
	var wheel_speed_mult: float = 1.15 if has_gilded_wheel else 1.0
	var leak_speed_mult: float = maxf(0.3, 1.0 - leak_amount * 0.45)
	var wheel_turn_mult: float = 1.30 if has_gilded_wheel else 1.0
	vel += fwd * f * pulse * THRUST * heavy * (1.45 if hard else 1.0) * wheel_speed_mult * leak_speed_mult * delta
	yaw_vel += t * (0.45 + pulse) * TURN * (0.75 if kind == KIND_BARGE else 1.0) * wheel_turn_mult * delta
	_integrate(delta, water)


## Drag, drift, terrain collision and grounding (shared by both kinds of boat).
func _integrate(delta: float, water: float) -> void:
	if leak_amount > 0.0:
		water += leak_amount * 0.18
	var fwd := forward2()
	# Drag: keel resists sideways motion far more than forward motion.
	var along := vel.dot(fwd)
	var lat := vel - fwd * along
	along *= exp(-0.5 * delta)
	along -= signf(along) * along * along * 0.09 * delta
	lat *= exp(-3.5 * delta)
	vel = fwd * along + lat
	yaw_vel *= exp(-2.4 * delta)
	# A lazy current so an empty boat drifts a little.
	var drift := Vector2(sin(_t * 0.05 + id * 1.7), cos(_t * 0.037 + id)) * 0.04
	if sky != null and not (has_sail() and row_power > 0.05):
		drift += sky.wind_drift() * (0.2 if kind == KIND_BARGE else 1.0)  # [weather] storms push boats downwind
	_moor_t -= delta
	if _moor_t <= 0.0:
		_moor_t = 0.5
		moored = occupants.max() == 0 and near_bollard()
	if moored:
		drift = Vector2.ZERO
		vel *= exp(-4.0 * delta)
		yaw_vel *= exp(-4.0 * delta)
	vel += (drift - vel * 0.02) * delta

	# Dynamic ocean hazards: whirlpool current & torque
	if not WhirlpoolHazard.active_whirlpools.is_empty():
		var vortex: Dictionary = WhirlpoolHazard.get_vortex_effect(position)
		if not vortex.is_empty():
			vel += (vortex.get("force", Vector2.ZERO) as Vector2) * delta
			yaw_vel += float(vortex.get("torque", 0.0)) * delta

	var old_blocked := blocked_count(position, yaw, water)
	grounded = old_blocked > 0
	var new_pos := position + Vector3(vel.x, 0, vel.y) * delta
	var new_yaw := yaw + yaw_vel * delta
	var nb := blocked_count(new_pos, new_yaw, water)
	if nb == 0 or nb < old_blocked:
		position = new_pos
		yaw = new_yaw
	elif blocked_count(position, new_yaw, water) <= old_blocked and old_blocked == 0:
		yaw = new_yaw
		vel *= -0.2  # bump
	else:
		# Try sliding along each axis before giving up.
		var px := position + Vector3(vel.x * delta, 0, 0)
		var pz := position + Vector3(0, 0, vel.y * delta)
		if blocked_count(px, yaw, water) <= old_blocked and blocked_count(px, yaw, water) == 0:
			position = px
			vel.y *= 0.3
		elif blocked_count(pz, yaw, water) == 0:
			position = pz
			vel.x *= 0.3
		else:
			vel *= -0.2
			yaw_vel *= 0.3
	if grounded:
		vel *= exp(-6.0 * delta)
		yaw_vel *= exp(-6.0 * delta)
	position.y = water
	_clamp_to_world()


## A mooring bollard within a boat length: an empty boat here is tied up and won't drift.
func near_bollard() -> bool:
	var em := EntityManager.current
	if em == null:
		return false
	for e: WorldEntity in em.entities.values():
		if e.entity_id == &"mooring_bollard" and Vector2(e.position.x - position.x, e.position.z - position.z).length() < half_len + 2.5:
			return true
	return false


func _clamp_to_world() -> void:
	var lim := Vector2(VoxelWorld.WX, VoxelWorld.WZ) * VS
	if "store" in world and world.store != null:
		var sz: Vector3i = world.store.get_size()
		lim = Vector2(sz.x, sz.z) * VS
	position.x = clampf(position.x, 2.0, lim.x - 2.0)
	position.z = clampf(position.z, 2.0, lim.y - 2.0)


## Non-authority side: ease toward the last snapshot (dead-reckoned by its velocity).
func interpolate(delta: float) -> void:
	if not _has_net:
		position.y = water_y()
		return
	_net_pos += Vector3(_net_vel.x, 0, _net_vel.y) * delta
	var k := 1.0 - exp(-delta * 10.0)
	position = position.lerp(Vector3(_net_pos.x, water_y(), _net_pos.z), k)
	if position.distance_to(_net_pos) > 6.0:
		position = Vector3(_net_pos.x, water_y(), _net_pos.z)
	yaw = lerp_angle(yaw, _net_yaw, k)
	vel = _net_vel


## Snapshots carry the sail state for remote viewers; the swing is recomputed locally.
var _local_auth := true


func is_authority_local() -> bool:
	return _local_auth


func apply_snapshot(pos: Vector3, p_yaw: float, p_vel: Vector2, phase: float, power: float) -> void:
	_net_pos = pos
	_net_yaw = p_yaw
	_net_vel = p_vel
	row_phase = phase
	row_power = power
	_has_net = true


var _diving_winch_cd := 0.0


func _process(delta: float) -> void:
	_t += delta
	rotation = Vector3(0, yaw, 0)

	_diving_winch_cd -= delta
	if _diving_winch_cd <= 0.0:
		_diving_winch_cd = 0.5
		_tick_diving_winches()
	# Bob, roll and speed-dependent pitch (bow lifts when moving).
	var speed := vel.length()
	var bob := sin(_t * 1.3 + id) * 0.035
	var roll := sin(_t * 0.9 + id * 2.0) * 0.035 - yaw_vel * 0.08
	var pitch := -clampf(vel.dot(forward2()), -1.0, 3.0) * 0.025 + sin(_t * 1.1) * 0.015
	# [weather] pitch/roll follow the swell slope under the hull
	if sky != null and not grounded:
		var fw := Vector3(sin(yaw), 0, cos(yaw))
		var rt := Vector3(fw.z, 0, -fw.x)
		pitch += (sky.wave_offset_at(position - fw * 1.6) - sky.wave_offset_at(position + fw * 1.6)) * 0.3
		roll += (sky.wave_offset_at(position - rt * 0.7) - sky.wave_offset_at(position + rt * 0.7)) * 0.5
		bob *= 1.0 + sky.sea_roughness() * 2.0
	if grounded:
		bob *= 0.2
		roll = 0.06
	visual.position.y = bob
	visual.rotation = Vector3(pitch, 0, roll)

	# Dynamic water hull sound
	if speed > 0.7 and not grounded and occupants.max() > 0:
		_water_lap_cd -= delta
		if _water_lap_cd <= 0.0:
			_water_lap_cd = randf_range(1.2, 2.0)
			CombatAudio.play_sound("water_lap", position, -4.0)
	if has_sail():
		if _sail != null:
			if not is_authority_local():
				var rel := forward2().angle_to(wind_vec())
				sail_angle = lerp_angle(sail_angle, clampf(PI - absf(rel), 0.15, 1.35) * (1.0 if rel > 0.0 else -1.0) * 0.8, 1.0 - exp(-delta * 2.0))
			_sail.rotation = Vector3(0, sail_angle, 0)
			_sail.scale = Vector3(1, maxf(0.08, row_power), 1)   # furled down to the yard
			_sail.visible = row_power > 0.02
		_wake.emitting = speed > 0.6 and not grounded
		if _bow_spray != null:
			_bow_spray.emitting = speed > 2.4 and not grounded
		return
	# Oars: sweep fore/aft on the stroke, lift the blade on the recovery.
	for o: Node3D in [_oar_l, _oar_r]:
		var side: float = o.get_meta("side")
		var sweep := cos(row_phase) * 0.55 * row_power
		var lift := maxf(0.0, -sin(row_phase)) * 0.28 * row_power
		var rest := (1.0 - row_power) * 0.55  # tucked alongside when idle
		var ry := -sweep + rest
		o.rotation = Vector3(0, ry if side > 0 else PI - ry, -0.38 + lift - (1.0 - row_power) * 0.1)
	_wake.emitting = speed > 0.6 and not grounded
	if _bow_spray != null:
		_bow_spray.emitting = speed > 2.4 and not grounded


func _tick_diving_winches() -> void:
	for slot_idx in deck_fixtures:
		var f: Dictionary = deck_fixtures[slot_idx]
		if f.get("id") == &"diving_winch" and f.get("lowered", false):
			var node: Node3D = f.get("node")
			if node != null:
				var bell: Node3D = node.get_node_or_null("DivingBell")
				if bell != null:
					var bell_world_pos: Vector3
					if bell.is_inside_tree():
						bell_world_pos = bell.global_position
					else:
						var vis_pos := visual.position if visual != null else Vector3.ZERO
						bell_world_pos = position + vis_pos + node.position + bell.position
					var em := EntityManager.current
					var main_node: Node = em.main if em != null else null
					var p: Player = null
					if main_node != null:
						if "player" in main_node and main_node.player is Player:
							p = main_node.player
						elif main_node.has_meta("player"):
							p = main_node.get_meta("player")
						elif main_node.get("player") is Player:
							p = main_node.get("player")

					if p != null and p.vitality != null:
						var p_pos: Vector3 = p.global_position if p.is_inside_tree() else p.position
						if p_pos.distance_to(bell_world_pos) <= 5.5:
							if "current_breath" in p.vitality:
								p.vitality.current_breath = p.vitality.get_max_breath()
