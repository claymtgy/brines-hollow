class_name Player
extends Node3D
## Local player: voxel-AABB movement (with auto-step), swimming, and building tools.
## Edits are emitted as commands; Main routes them through the network host.

signal command_requested(cmd: Dictionary)

const VS := VoxelWorld.VS
const HW := 0.26            # half width (m)
const H := 1.62             # collision height (m)
const MAX_STEP := 3         # auto-step up to 3 voxels (0.54 m)
const REACH := 7.5
const BRUSHES := [0, 1, 2, 3, 5]
const TOOL_NAMES := ["Pickaxe (dig)", "Hammer (build)", "Blueprints (prefabs)", "Fishing Rod", "Farming & Hoe"]

var world: VoxelWorld
var rig: CameraRig
var model: CharacterModel
var sky: SkyCycle
var hud: Hud
var farm: FarmManager
var quests: QuestManager
var village: SettlementManager
var entities: EntityManager
var controller: ControllerManager

var inventory: Inventory = Inventory.new(24)
var customizer: CharacterCustomizer = CharacterCustomizer.new()
var fishing: FishingController = FishingController.new(1)
var vitality: VitalityController = VitalityController.new()
var fishing_cast_power: float = 0.0

var vel := Vector3.ZERO
var on_ground := false
var swimming := false
var facing := 0.0
var water_level := 0.0      # metres, set by Main
var input_enabled := true
var horizontal_speed := 0.0
var swing_count := 0

var tool := 0
var brush := 1
var mat_index := 0
var prefab_id := 5
var prefab_rot := 0
var snap := true
var target := {}
var _use_cd := 0.0
var _step_offset := 0.0

var _highlight: MeshInstance3D
var _hl_mat: ShaderMaterial
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_key := -1
var _ghost_cache := {}

## Rowboat the player is seated in (null when on foot) and which seat.
var boat: Boat = null
var seat := 0


func is_seated() -> bool:
	return boat != null and is_instance_valid(boat)


func board(b: Boat, seat_index: int) -> void:
	boat = b
	seat = seat_index
	vel = Vector3.ZERO
	on_ground = false
	swimming = false
	horizontal_speed = 0.0
	_highlight.visible = false
	_ghost.visible = false
	rig.extra_dist = 2.2


func unboard(stand_at: Vector3) -> void:
	boat = null
	position = stand_at
	vel = Vector3.ZERO
	_step_offset = 0.0
	rig.extra_dist = 0.0


func _ready() -> void:
	model = CharacterModel.new()
	add_child(model)
	model.setup(Palette.COAT_A, Palette.HAT_A, customizer)

	customizer.appearance_changed.connect(func() -> void:
		if model:
			model.apply_customizer(customizer)
	)

	inventory.equipment_changed.connect(func(slot_name: StringName, slot: ItemSlot) -> void:
		if model == null:
			return
		if slot_name == &"backpack":
			model.set_backpack_visible(not slot.is_empty())
		elif slot_name == &"head":
			var is_helm: bool = not slot.is_empty() and (slot.item_id == &"deep_diving_helmet" or slot.item_id == &"diving_rebreather")
			model.set_diving_helmet_visible(is_helm)
	)

	vitality.player_defeated.connect(func(pos: Vector3) -> void:
		if hud:
			hud.show_toast("Defeated! Awakening safely ashore...")
		if world and world.gen:
			var respawn: Dictionary = world.gen.get_spawn_for_player(1)
			position = respawn.get("pos", position)
			vel = Vector3.ZERO
			vitality.revive(position)
	)

	_hl_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform vec3 size = vec3(0.18);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 d = size * 0.5 - abs(lp);
	float t = 0.014;
	float n = step(d.x, t) + step(d.y, t) + step(d.z, t);
	ALBEDO = color.rgb;
	ALPHA = n >= 2.0 ? color.a : 0.07;
}
"""
	_hl_mat.shader = sh
	_highlight = MeshInstance3D.new()
	_highlight.mesh = BoxMesh.new()
	_highlight.material_override = _hl_mat
	_highlight.top_level = true
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_highlight)

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.vertex_color_use_as_albedo = true
	_ghost_mat.vertex_color_is_srgb = true
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.85, 1.0, 0.9, 0.55)
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)

	# Starter inventory setup
	ItemDB.init_db()
	inventory.add_item(&"driftwood_pickaxe", 1)
	inventory.add_item(&"whittle_rod", 1)
	inventory.add_item(&"seed_shore_wheat", 5)
	inventory.add_item(&"seed_samphire", 3)
	inventory.add_item(&"driftwood", 15)

	fishing.fish_landed.connect(func(fish: FishDef, weight: float) -> void:
		inventory.add_item(fish.item_id, 1)
		if controller:
			controller.pulse_catch()
		if hud:
			hud.show_toast("Caught %s (%.1f kg)!" % [fish.name, weight])
		if quests:
			quests.notify_event(QuestDef.ObjectiveType.CATCH_FISH, fish.id, 1, inventory)
	)
	fishing.fish_escaped.connect(func(reason: String) -> void:
		if controller:
			controller.pulse_tension_warning()
		if hud:
			hud.show_toast("Lost fish: %s" % reason)
	)
	fishing.nibble_telegraphed.connect(func() -> void:
		if controller:
			controller.pulse_nibble()
	)
	fishing.hook_window_opened.connect(func(_dur: float) -> void:
		if controller:
			controller.pulse_bite()
		if hud:
			var btn: String = controller.get_glyph(&"use") if controller else "LMB"
			hud.show_toast(">> BITE! Click [%s] to hook! <<" % btn)
	)

	bind_quest_signals()


func bind_quest_signals() -> void:
	if quests and not quests.quest_progressed.is_connected(_on_quest_progressed):
		quests.quest_progressed.connect(_on_quest_progressed)
		quests.quest_completed.connect(_on_quest_completed)


func _on_quest_progressed(q: QuestDef, step: QuestDef.QuestStep) -> void:
	if hud:
		hud.show_toast("[%s] %s (%d/%d)" % [q.title, step.description, step.current_count, step.target_count])


func _on_quest_completed(q: QuestDef) -> void:
	if hud:
		hud.show_toast("Quest Completed: %s!" % q.title)


# ---------------------------------------------------------------- movement

func _collides(p: Vector3) -> bool:
	# Box shrunk by EPS so resting exactly on a voxel boundary doesn't count as overlap.
	const EPS := 0.002
	return world.aabb_collides(Vector3(p.x - HW + EPS, p.y + EPS, p.z - HW + EPS),
			Vector3(p.x + HW - EPS, p.y + H - EPS, p.z + HW - EPS))


func _move_horizontal(axis: int, amount: float) -> bool:
	if amount == 0.0:
		return false
	var p := position
	p[axis] += amount
	if not _collides(p):
		position = p
		return false
	# Try auto-stepping up onto a ledge.
	if on_ground or swimming:
		var base := floori(position.y / VS + 0.02)
		for k in range(1, MAX_STEP + 1):
			var lifted := p
			lifted.y = (base + k) * VS
			var up_only := position
			up_only.y = lifted.y
			if not _collides(up_only) and not _collides(lifted):
				_step_offset -= lifted.y - position.y
				position = lifted
				return false
	# Blocked: snap flush against the wall.
	if amount > 0.0:
		var edge := floori((p[axis] + HW) / VS)
		p[axis] = edge * VS - HW - 0.0005
	else:
		var edge := floori((p[axis] - HW) / VS)
		p[axis] = (edge + 1) * VS + HW + 0.0005
	if not _collides(p):
		position[axis] = p[axis]
	return true


func _move_vertical(amount: float) -> bool:
	if amount == 0.0:
		return false
	var p := position
	p.y += amount
	if not _collides(p):
		position = p
		return false
	if amount < 0.0:
		p.y = (floori((p.y + 0.002) / VS) + 1) * VS
	else:
		p.y = floori((p.y + H) / VS) * VS - H - 0.0005
	if not _collides(p):
		position.y = p.y
	return true


func _physics_process(delta: float) -> void:
	if world == null or not world.ready_for_play:
		return
	if is_seated():
		position = boat.seat_position(seat)
		facing = boat.yaw
		return
	# Get unstuck if something was built inside us.
	if _collides(position):
		position.y += VS
		return

	var b := Basis(Vector3.UP, rig.yaw)
	var fwd := -b.z
	var right := b.x
	var wish := Vector3.ZERO
	if input_enabled:
		wish = fwd * Input.get_axis("move_back", "move_forward") + right * Input.get_axis("move_left", "move_right")
	if wish.length() > 1.0:
		wish = wish.normalized()

	swimming = position.y + 0.75 < water_level
	var is_submerged: bool = position.y + 1.2 < water_level
	var sprint := input_enabled and Input.is_action_pressed("sprint")
	var is_sprinting: bool = sprint and wish.length_squared() > 0.01 and not vitality.is_exhausted and vitality.current_stamina > 0.0

	if is_sprinting:
		vitality.drain_stamina_continuous(10.0, delta)
	elif swimming and wish.length_squared() > 0.01:
		vitality.drain_stamina_continuous(4.0, delta)

	vitality.tick(delta, is_submerged, is_sprinting or (swimming and wish.length_squared() > 0.01))

	var swim_mult := inventory.get_swim_speed_multiplier() * vitality.get_swim_speed_multiplier()
	if vitality.is_exhausted:
		swim_mult *= 0.65

	var speed := (3.2 * swim_mult) if swimming else (7.2 if is_sprinting else 4.4)
	var accel := 6.0 if swimming else (14.0 if on_ground else 5.0)
	var target_v := wish * speed
	vel.x = lerpf(vel.x, target_v.x, 1.0 - exp(-accel * delta))
	vel.z = lerpf(vel.z, target_v.z, 1.0 - exp(-accel * delta))

	if swimming:
		var buoyancy_off := inventory.get_buoyancy_offset()
		vel.y = lerpf(vel.y, 0.0, 1.0 - exp(-3.0 * delta))
		vel.y -= (2.0 - buoyancy_off * 3.0) * delta
		if input_enabled and Input.is_action_pressed("jump"):
			vel.y = minf(vel.y + 14.0 * delta, 2.8)
			# Hop out at the waterline onto ledges.
			if position.y + 1.0 > water_level:
				vel.y = maxf(vel.y, 4.5)
	else:
		vel.y -= 24.0 * delta
		if on_ground and input_enabled and Input.is_action_just_pressed("jump"):
			if not vitality.is_exhausted:
				vitality.consume_stamina(6.0)
				vel.y = 7.6
			else:
				vel.y = 4.2
	vel.y = maxf(vel.y, -30.0)

	# Substepped axis-separated movement.
	var motion := vel * delta
	var steps := int(ceil(motion.length() / (VS * 0.45))) + 1
	var sub := motion / steps
	var landed := false
	for s in steps:
		if _move_horizontal(0, sub.x):
			vel.x = 0.0; sub.x = 0.0
		if _move_horizontal(2, sub.z):
			vel.z = 0.0; sub.z = 0.0
		if _move_vertical(sub.y):
			if sub.y < 0.0:
				landed = true
			vel.y = 0.0
			sub.y = 0.0
	if not landed and vel.y <= 0.0:
		# Still standing on something directly below?
		var probe := position
		probe.y -= 0.02
		landed = _collides(probe)
	on_ground = landed

	# Keep inside the island bounds.
	var lim := VoxelWorld.WX * VS
	position.x = clampf(position.x, 0.5, lim - 0.5)
	position.z = clampf(position.z, 0.5, lim - 0.5)
	if position.y < -5.0:
		position.y = 30.0

	horizontal_speed = Vector2(vel.x, vel.z).length()
	if wish.length() > 0.1:
		facing = lerp_angle(facing, atan2(wish.x, wish.z), 1.0 - exp(-12.0 * delta))


# ---------------------------------------------------------------- tools

func current_material() -> int:
	return Palette.BUILDABLE[mat_index]


func _set_tool(new_tool: int) -> void:
	if tool == 3 and new_tool != 3 and fishing != null:
		fishing.reset()
	if controller:
		controller.reset_triggers()
	tool = new_tool
	model.set_tool(tool)


func _unhandled_input(e: InputEvent) -> void:
	if not input_enabled or is_seated():
		return
	if e.is_action_pressed("interact"):
		if entities != null:
			var ent: WorldEntity = entities.get_closest_interactable(position)
			if ent != null and ent.can_interact(self):
				ent.interact(self)
				return
	if e.is_action_pressed("tool_1"): _set_tool(0)
	elif e.is_action_pressed("tool_2"): _set_tool(1)
	elif e.is_action_pressed("tool_3"): _set_tool(2)
	elif e.is_action_pressed("tool_4"): _set_tool(3)
	elif e.is_action_pressed("tool_5"): _set_tool(4)
	elif e.is_action_pressed("cycle_tool_next"): _set_tool(posmod(tool + 1, 5))
	elif e.is_action_pressed("cycle_tool_prev"): _set_tool(posmod(tool - 1, 5))
	elif e.is_action_pressed("next_item"): _cycle(1)
	elif e.is_action_pressed("prev_item"): _cycle(-1)
	elif e.is_action_pressed("brush_up"): brush = mini(brush + 1, BRUSHES.size() - 1)
	elif e.is_action_pressed("brush_down"): brush = maxi(brush - 1, 0)
	elif e.is_action_pressed("rotate"): prefab_rot = (prefab_rot + 1) % 4
	elif e.is_action_pressed("snap"): snap = not snap
	elif e.is_action_pressed("pick") and not target.is_empty():
		var c: Vector3i = target.cell
		var m := world.get_voxel(c.x, c.y, c.z)
		var idx := Palette.BUILDABLE.find(m)
		if idx >= 0:
			mat_index = idx
			_set_tool(1)
	elif tool == 4 and e.is_action_pressed("alt_use"):
		if not _try_eat_active_food():
			_plant_seed_at_target()
	elif tool == 3:
		_handle_fishing_input(e)


func _try_eat_active_food() -> bool:
	var active: ItemSlot = inventory.get_active_item()
	if active and not active.is_empty():
		var item_id: StringName = active.item_id
		if vitality.can_eat_food(item_id):
			if vitality.eat_food(item_id, inventory):
				if hud:
					var def: ItemDef = ItemDB.get_item(item_id)
					var meal_name: String = def.name if def != null else String(item_id)
					hud.show_toast("Ate %s. Satiety: %d/3 meals" % [meal_name, vitality.get_active_meals().size()])
				return true
	return false


func _cycle(d: int) -> void:
	if tool == 2:
		prefab_id = posmod(prefab_id + d, Prefabs.count())
	elif tool == 4:
		inventory.active_hotbar_index = posmod(inventory.active_hotbar_index + d, 8)
		var active := inventory.get_active_item()
		if active and not active.is_empty():
			var item := ItemDB.get_item(active.item_id)
			if hud and item:
				hud.show_toast("Selected: %s (x%d)" % [item.name, active.count])
	else:
		mat_index = posmod(mat_index + d, Palette.BUILDABLE.size())


func _handle_fishing_input(e: InputEvent) -> void:
	if fishing == null:
		return
	if e.is_action_pressed("use"):
		match fishing.current_state:
			FishingController.State.IDLE, FishingController.State.CAUGHT, FishingController.State.LOST:
				fishing_cast_power = 0.0
				fishing.start_cast()
				if controller:
					controller.apply_fishing_cast(0.0)
			FishingController.State.NIBBLING, FishingController.State.HOOK_WINDOW:
				var hooked := fishing.strike_hook()
				if hooked:
					if controller:
						controller.apply_fishing_bite()
					if hud:
						hud.show_toast("HOOKED! Hold and pulse [LMB] to reel!")
			FishingController.State.WAITING_FOR_BITE:
				fishing.strike_hook()
	elif e.is_action_released("use"):
		if fishing.current_state == FishingController.State.CASTING:
			var tide_frac: float = 0.5
			var daylight: bool = true
			if sky:
				tide_frac = (sky.water_level_vox - (VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP)) / (2.0 * VoxelWorld.TIDE_AMP)
				daylight = sky.is_day()
			fishing.release_cast(fishing_cast_power, tide_frac, daylight, false, false)
			if controller:
				controller.reset_triggers()
			if hud:
				hud.show_toast("Cast line! Watching for nibbles...")


func _process(delta: float) -> void:
	if world == null or not world.ready_for_play:
		return
	if is_seated():
		# Ride the boat: follow the seat every frame (it bobs and rolls).
		var st := boat.seat_transform(seat)
		position = st.origin
		facing = boat.yaw
		model.position = Vector3.ZERO
		model.rotation = st.basis.get_euler()
		model.animate_seated(delta, boat.row_phase, boat.row_power if seat == 0 else 0.0)
		target = {}
		_highlight.visible = false
		_ghost.visible = false
		return
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-delta * 16.0))
	model.position = Vector3(0, _step_offset, 0)
	model.rotation = Vector3(0, facing, 0)
	model.animate(delta, horizontal_speed, on_ground, swimming)
	_update_target()
	_use_cd -= delta

	if tool == 3 and fishing != null:
		if fishing.current_state == FishingController.State.CASTING:
			fishing_cast_power = clampf(fishing_cast_power + delta * 1.5, 0.0, 1.0)
			if controller:
				controller.apply_fishing_cast(fishing_cast_power)
		elif fishing.current_state == FishingController.State.REELING:
			var is_reeling := Input.is_action_pressed("use")
			fishing.tick_reeling(is_reeling, 0.6, delta)
			if controller:
				controller.apply_fishing_reeling(fishing.line_tension, fishing.fish_stamina_left > 0.0)
				if fishing.line_tension > 0.85:
					controller.pulse_tension_warning()
		else:
			fishing.tick(delta)

	var can_input: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (controller != null and controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE)
	if input_enabled and can_input and Input.is_action_pressed("use") and _use_cd <= 0.0 and tool != 3 and not target.is_empty():
		_use_tool()


func _update_target() -> void:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var origin := rig.cam.project_ray_origin(center)
	var dir := rig.cam.project_ray_normal(center)
	target = {}
	var hit := world.raycast(origin, dir, 40.0)
	var head := position + Vector3(0, 1.4, 0)
	if not hit.is_empty():
		var hp := (Vector3(hit.cell) + Vector3.ONE * 0.5) * VS
		if hp.distance_to(head) <= REACH:
			target = hit
	_highlight.visible = false
	_ghost.visible = false
	if target.is_empty():
		return
	var cell: Vector3i = target.cell
	if tool == 0 or tool == 1:
		var c := cell if tool == 0 else cell + (target.normal as Vector3i)
		var r: int = BRUSHES[brush]
		var sz := Vector3.ONE * (2 * r + 1) * VS * 1.02
		(_highlight.mesh as BoxMesh).size = sz
		_hl_mat.set_shader_parameter("size", sz)
		_hl_mat.set_shader_parameter("color", Color(1, 0.55, 0.4, 0.95) if tool == 0 else Color(0.6, 1, 0.75, 0.95))
		_highlight.global_position = (Vector3(c) + Vector3.ONE * 0.5) * VS
		_highlight.visible = true
	elif tool == 4:
		var sz := Vector3.ONE * VS * 1.02
		(_highlight.mesh as BoxMesh).size = sz
		_hl_mat.set_shader_parameter("size", sz)
		_hl_mat.set_shader_parameter("color", Color(0.4, 0.85, 0.3, 0.95))
		_highlight.global_position = (Vector3(cell) + Vector3.ONE * 0.5) * VS
		_highlight.visible = true
	elif tool == 2:
		var o := prefab_origin()
		var key := prefab_id * 4 + prefab_rot
		if key != _ghost_key:
			_ghost_key = key
			if not _ghost_cache.has(key):
				var pf := Prefabs.rotated(prefab_id, prefab_rot)
				var s: Vector3i = pf.size
				_ghost_cache[key] = Mesher.mesh_from_grid(pf.data, s.x, s.y, s.z, VS, _ghost_mat, _ghost_mat)
			_ghost.mesh = _ghost_cache[key]
		var pf2 := Prefabs.rotated(prefab_id, prefab_rot)
		_ghost.global_position = Vector3(o - (pf2.anchor as Vector3i)) * VS
		_ghost.visible = true


func prefab_origin() -> Vector3i:
	var o: Vector3i = (target.cell as Vector3i) + (target.normal as Vector3i)
	if (target.normal as Vector3i).y == 0:
		o.y = (target.cell as Vector3i).y  # side hit: sit level with the face
	if snap:
		o.x = int(round(o.x / 6.0)) * 6
		o.z = int(round(o.z / 6.0)) * 6
	return o


func _use_tool() -> void:
	var cell: Vector3i = target.cell
	match tool:
		0:
			var mat := world.get_voxel(cell.x, cell.y, cell.z)
			if controller:
				controller.apply_mining(mat)
			command_requested.emit({"t": "dig", "p": cell, "r": BRUSHES[brush]})
			_use_cd = 0.16 + BRUSHES[brush] * 0.03
		1:
			var c: Vector3i = cell + (target.normal as Vector3i)
			var r: int = BRUSHES[brush]
			if _brush_hits_self(c, r):
				return
			# Survival: placing costs materials (1 item per 4 voxels, like digging yields).
			var cost := BuildCosts.brush_cost(world, c, r, current_material())
			if not _pay_or_warn(cost):
				_use_cd = 0.4
				return
			command_requested.emit({"t": "place", "p": c, "r": r, "m": current_material()})
			if controller:
				controller.pulse_place()
			_use_cd = 0.16 + r * 0.03
		2:
			if not _pay_or_warn(BuildCosts.prefab_cost(prefab_id, prefab_rot)):
				_use_cd = 0.6
				return
			command_requested.emit({"t": "prefab", "p": prefab_origin(), "r": prefab_rot, "id": prefab_id})
			_use_cd = 0.45
		4:
			_use_farm_tool(cell)
			_use_cd = 0.25
	model.swing()
	swing_count += 1
	facing = rig.yaw + PI


func _use_farm_tool(cell: Vector3i) -> void:
	if farm == null:
		return
	# 1. Salt pan harvest
	if farm.salt_pans.has(cell):
		var harvested_salt := farm.harvest_salt_to_inventory(cell, inventory)
		if harvested_salt > 0:
			if hud:
				hud.show_toast("Harvested %d Sea Salt!" % harvested_salt)
			if quests:
				quests.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"sea_salt", harvested_salt, inventory)
		else:
			if hud:
				hud.show_toast("Salt pan is still evaporating...")
		return

	# 2. Crop plot harvest or water
	if farm.plots.has(cell):
		var plot: CropPlot = farm.get_plot(cell)
		if plot.is_mature():
			var crop_id: StringName = plot.crop_id
			if farm.harvest_to_inventory(cell, inventory):
				if hud:
					hud.show_toast("Harvested mature %s!" % crop_id)
				if quests:
					quests.notify_event(QuestDef.ObjectiveType.HARVEST_CROP, crop_id, 1, inventory)
		elif not plot.is_empty():
			farm.water_plot(cell, 0.5, 0.0)
			if hud:
				hud.show_toast("Watered %s (Hydration: %.0f%%, Salinity: %.0f%%)" % [
					plot.crop_id, plot.hydration * 100.0, plot.salinity * 100.0
				])
		else:
			if hud:
				hud.show_toast("Plot ready for planting. Right-click [RMB] to sow seeds.")
		return

	# 3. Till untilled soil
	var new_plot := farm.till_plot(cell)
	if controller:
		controller.apply_farming_till()
	if hud:
		var sal_pct := int(new_plot.salinity * 100.0)
		hud.show_toast("Tilled soil! Salinity: %d%%. Right-click [RMB] with seeds to plant." % sal_pct)


func _plant_seed_at_target() -> void:
	if farm == null or target.is_empty():
		return
	var cell: Vector3i = target.cell
	if not farm.plots.has(cell):
		farm.till_plot(cell)
	var planted := farm.plant_from_inventory(cell, inventory)
	if planted:
		if controller:
			controller.apply_farming_sow()
		var plot := farm.get_plot(cell)
		if hud:
			hud.show_toast("Planted %s (Soil Salinity: %.0f%%)!" % [plot.crop_id, plot.salinity * 100.0])
	else:
		if hud:
			hud.show_toast("Cannot plant here (Need seeds in inventory or plot is occupied).")


## Survival build costs: pays from the inventory, or shows what's missing and refuses.
func _pay_or_warn(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	if not BuildCosts.can_afford(inventory, cost):
		if hud:
			hud.show_toast("Need " + BuildCosts.describe_missing(inventory, cost))
		return false
	BuildCosts.pay(inventory, cost)
	return true


func _brush_hits_self(c: Vector3i, r: int) -> bool:
	var lo := Vector3(c - Vector3i.ONE * r) * VS
	var hi := Vector3(c + Vector3i.ONE * (r + 1)) * VS
	var plo := position - Vector3(HW, 0, HW)
	var phi := position + Vector3(HW, H, HW)
	return lo.x < phi.x and hi.x > plo.x and lo.y < phi.y and hi.y > plo.y and lo.z < phi.z and hi.z > plo.z
