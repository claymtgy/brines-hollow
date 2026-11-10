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
var recipes := RecipeBook.new()   # known recipes (saved in the player profile)
var village: SettlementManager
var entities: EntityManager
var placement: PlacementController   # Entities (Agent A): place / use / pick up
var controller: ControllerManager
var inventory_ui: InventoryUI
var build_menu_ui: BuildMenuUI

var inventory: Inventory = Inventory.new(24)
var customizer: CharacterCustomizer = CharacterCustomizer.new()
var fishing: FishingController = FishingController.new(1)
var vitality: VitalityController = VitalityController.new()
var combat: PlayerCombat = null   # Agent C: attached by CreatureNet
var fishing_cast_power: float = 0.0
var player_name: String = "Captain"
var nameplate: Label3D = null

var vel := Vector3.ZERO
var on_ground := false
var swimming := false
var creative_mode := false
var facing := 0.0
var water_level := 0.0      # metres, set by Main
var input_enabled := true
var horizontal_speed := 0.0
var is_sprinting := false
var swing_count := 0

var tool := 0
var tool_wheel: ToolWheelUI
var _told_use_hatchet := false   # one nudge per session when a pick hits a trunk
var hammer_build_mode := 1  # 0 = Fabricated Pieces (Prefabs), 1 = Individual Blocks, 2 = Furniture
var brush := 0
var mat_index := 0
var pickaxe_flatten_mode: bool = false
var _line_anchor := Vector3i(-99999, -99999, -99999)
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
var hovered_entity: WorldEntity = null
var _last_ray_origin := Vector3.ZERO
var _last_ray_dir := Vector3.FORWARD
var _last_ray_hit := {}
var _bobber: Node3D
var _fishing_line: MeshInstance3D
var _fishing_line_mesh: ImmediateMesh
var _bobber_start := Vector3.ZERO
var _bobber_target := Vector3.ZERO
var _bobber_flight_t := 1.0
var _bobber_phase := 0.0

## Rowboat the player is seated in (null when on foot) and which seat.
var boat: Boat = null
var seat := 0


func set_creative_mode(enabled: bool) -> void:
	creative_mode = enabled
	if inventory != null:
		inventory.creative_mode = enabled


func is_seated() -> bool:
	return boat != null and is_instance_valid(boat)


func board(b: Boat, seat_index: int) -> void:
	boat = b
	seat = seat_index
	vel = Vector3.ZERO
	on_ground = false
	swimming = false
	horizontal_speed = 0.0
	if _highlight != null:
		_highlight.visible = false
	if _ghost != null:
		_ghost.visible = false
	if rig != null:
		rig.extra_dist = 2.2


func unboard(stand_at: Vector3) -> void:
	boat = null
	position = stand_at
	vel = Vector3.ZERO
	_step_offset = 0.0
	if rig != null:
		rig.extra_dist = 0.0


func set_player_name(p_name: String) -> void:
	player_name = p_name
	if nameplate != null:
		nameplate.text = player_name


func _ready() -> void:
	# --- Entities (Agent A): placement, interaction and pick-up controller
	placement = PlacementController.new()
	add_child(placement)
	placement.setup(self)
	# ---
	model = CharacterModel.new()
	add_child(model)
	model.setup(Palette.COAT_A, Palette.HAT_A, customizer)

	nameplate = Label3D.new()
	nameplate.name = "PlayerNameplate"
	nameplate.text = player_name
	nameplate.position = Vector3(0, 2.15, 0)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 38
	nameplate.outline_size = 10
	nameplate.modulate = Color(1.0, 0.98, 0.92)
	nameplate.pixel_size = 0.004
	nameplate.no_depth_test = true
	add_child(nameplate)

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
		elif slot_name == &"accessory":
			var def: ItemDef = ItemDB.get_item(slot.item_id) if not slot.is_empty() else null
			var is_shield: bool = def != null and def.has_tag("shield")
			var is_lantern: bool = def != null and def.has_tag("light")
			model.set_shield_visible(is_shield)
			model.set_offhand_lantern_visible(is_lantern)
	)

	vitality.player_defeated.connect(func(pos: Vector3) -> void:
		if SparringRingEntity.is_in_sparring_ring(position):
			SparringRingEntity.handle_sparring_defeat(self)
			vitality.revive(position)
			return
		if hud:
			hud.show_toast("Defeated! Awakening safely ashore...")
		if world and world.gen:
			var respawn: Dictionary = world.gen.get_spawn_for_player(1)
			position = respawn.get("pos", position)
			if has_meta("respawn_point"):  # Entities (Agent A): wake at the last bed used
				position = get_meta("respawn_point")
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
	_setup_fishing_visuals()

	# Starter kit: a castaway's three tools and an armful of salvage. The axe, hoe, seeds and
	# cutlass are handed over by Wren with the lesson that uses them (see Tutorial.MISSIONS).
	ItemDB.init_db()
	inventory.add_item(&"driftwood_pickaxe", 1)
	inventory.add_item(&"builders_hammer", 1)
	inventory.add_item(&"whittle_rod", 1)
	if inventory.capacity > 8:
		inventory.slots[8] = ItemSlot.new(&"driftwood", 10)
	else:
		inventory.add_item(&"driftwood", 10)

	inventory.slot_changed.connect(func(slot_idx: int, _slot: ItemSlot) -> void:
		if slot_idx == inventory.active_hotbar_index:
			_sync_tool_from_hotbar()
		if quests != null and not quests.paused_reward_quests.is_empty():
			var claimed := quests.check_paused_rewards(inventory)
			for cid in claimed:
				if hud != null:
					var def: QuestDef = quests.get_quest_def(cid)
					var q_title := def.title if def != null else String(cid)
					hud.show_toast("Space cleared! Claimed paused rewards for '%s'" % q_title)
	)
	inventory.active_hotbar_changed.connect(func(_idx: int) -> void:
		_sync_tool_from_hotbar()
	)
	_sync_tool_from_hotbar()

	# Recipe discovery: new ingredients, recipe scrolls -> learned recipes.
	RecipeBook.register_scroll_items()
	inventory.item_added.connect(func(item_id: StringName, _count: int) -> void:
		recipes.on_item_acquired(item_id, inventory))
	recipes.recipe_learned.connect(func(rid: StringName, _source: String) -> void:
		var r: RecipeDef = RecipeDB.get_recipe(rid)
		if hud != null and r != null:
			hud.show_toast("New recipe learned: %s" % r.name))

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


## Report progress on quest objectives (tutorial, story, chores).
func quest_event(type: QuestDef.ObjectiveType, target: StringName = &"", amount: int = 1) -> void:
	if quests != null:
		quests.notify_event(type, target, amount, inventory)


func bind_quest_signals() -> void:
	if quests and not quests.quest_progressed.is_connected(_on_quest_progressed):
		quests.quest_progressed.connect(_on_quest_progressed)
		quests.quest_completed.connect(_on_quest_completed)
		quests.quest_rewards_paused.connect(_on_quest_rewards_paused)


func _on_quest_progressed(q: QuestDef, step: QuestDef.QuestStep) -> void:
	if hud and step != null:
		hud.show_toast("[%s] %s (%d/%d)" % [q.title, step.description, step.current_count, step.target_count])


func _on_quest_rewards_paused(q: QuestDef) -> void:
	if hud:
		hud.show_toast("Inventory full! Rewards for '%s' paused until you make room." % q.title)


func _on_quest_completed(q: QuestDef) -> void:
	if hud:
		hud.show_toast("Quest Completed: %s!" % q.title)


# ---------------------------------------------------------------- movement

func _collides(p: Vector3) -> bool:
	# Box shrunk by EPS so resting exactly on a voxel boundary doesn't count as overlap.
	const EPS := 0.002
	var lo := Vector3(p.x - HW + EPS, p.y + EPS, p.z - HW + EPS)
	var hi := Vector3(p.x + HW - EPS, p.y + H - EPS, p.z + HW - EPS)
	# Entities (Agent A): solid entities and boat hulls block the player too.
	return world.aabb_collides(lo, hi) or (entities != null and entities.blocks(lo, hi))


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

	var in_water: bool = (position.y + 0.75 < water_level) and (world == null or world.is_water_at(position + Vector3(0.0, 0.75, 0.0), water_level))
	swimming = in_water
	var is_submerged: bool = (position.y + 1.2 < water_level) and (world == null or world.is_water_at(position + Vector3(0.0, 1.2, 0.0), water_level))
	var sprint := input_enabled and Input.is_action_pressed("sprint")
	is_sprinting = sprint and wish.length_squared() > 0.01 and not vitality.is_exhausted and vitality.current_stamina > 0.0

	if is_sprinting:
		vitality.drain_stamina_continuous(10.0, delta)
	elif swimming and wish.length_squared() > 0.01:
		vitality.drain_stamina_continuous(4.0, delta)

	vitality.has_diving_helmet = inventory.has_item(&"brass_diving_helmet") or inventory.has_item(&"diving_helmet")
	vitality.has_cold_protection = inventory.get_cold_protection() >= 0.5 or inventory.has_item(&"borean_parka")
	if swimming and BoreanLair.current != null:
		var lm := BoreanLair.current.lair_m()
		if lm != Vector3.ZERO and position.distance_to(lm) < 180.0 and not vitality.has_cold_immunity():
			vitality.drain_stamina_continuous(8.0, delta)
			if vitality.current_stamina <= 0.0:
				vitality.take_damage(6.0 * delta, &"cold", position)
	vitality.tick(delta, is_submerged, is_sprinting or (swimming and wish.length_squared() > 0.01))

	var swim_mult := inventory.get_swim_speed_multiplier() * vitality.get_swim_speed_multiplier()
	if vitality.is_exhausted:
		swim_mult *= 0.65

	var speed := (3.2 * swim_mult) if swimming else (7.2 if is_sprinting else 4.4)
	var accel := 6.0 if swimming else (14.0 if on_ground else 5.0)
	var target_v := wish * speed
	if combat != null:   # Agent C: sneaking slows you, a dodge roll overrides movement
		target_v = combat.modify_move(target_v)
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
	if combat != null and combat.is_plunging and landed:
		combat.on_land_plunge()

	# Keep inside the island bounds.
	var lim := VoxelWorld.WX * VS
	position.x = clampf(position.x, 0.5, lim - 0.5)
	position.z = clampf(position.z, 0.5, lim - 0.5)
	if position.y < -5.0:
		position.y = (VoxelWorld.WY - 2) * VS

	horizontal_speed = Vector2(vel.x, vel.z).length()
	if combat != null and combat.is_dodging():
		if not combat.is_dodge_hop() and (rig == null or not rig.first_person):
			facing = atan2(combat.get_dodge_dir().x, combat.get_dodge_dir().z)
	elif rig != null and rig.first_person:
		facing = rig.yaw + PI
	elif wish.length() > 0.1:
		facing = lerp_angle(facing, atan2(wish.x, wish.z), 1.0 - exp(-12.0 * delta))


# ---------------------------------------------------------------- tools

func current_material() -> int:
	return Palette.BUILDABLE[mat_index]


func _ensure_valid_block_material() -> void:
	if inventory == null:
		return
	var cur_mat := current_material()
	var cur_item := BuildCosts.item_for(cur_mat)
	if inventory.get_item_count(cur_item) > 0:
		return
	for idx in Palette.BUILDABLE.size():
		var m: int = Palette.BUILDABLE[idx]
		var item_id := BuildCosts.item_for(m)
		if item_id != &"" and inventory.get_item_count(item_id) > 0:
			mat_index = idx
			return


## Drops an item from a specific inventory slot into the 3D world in front of the player.
## If count <= 0, drops the entire stack.
func drop_item_from_inventory(slot_idx: int, count: int = -1) -> DroppedItem:
	if inventory == null or slot_idx < 0 or slot_idx >= inventory.capacity:
		return null
	var slot: ItemSlot = inventory.slots[slot_idx]
	if slot == null or slot.is_empty():
		return null
	var item_id := slot.item_id
	var def := ItemDB.get_item(item_id)
	var remove_cnt := slot.count if (count <= 0 or count >= slot.count) else count
	var actual_removed := inventory.remove_from_slot(slot_idx, remove_cnt)
	if actual_removed <= 0:
		return null

	_sync_tool_from_hotbar()

	# Drop into world in front of the player
	var fwd := -rig.cam.global_transform.basis.z if (rig != null and rig.cam != null) else -global_transform.basis.z
	fwd.y = 0.0
	if fwd.is_zero_approx():
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()

	var drop_pos := global_position + Vector3(0.0, 0.9, 0.0) + fwd * 0.9
	var drop := DroppedItem.spawn_drop(get_parent() if get_parent() != null else self, world, self, drop_pos, item_id, actual_removed)
	if drop != null:
		drop.pickup_delay = 1.8
		drop.velocity = fwd * randf_range(2.8, 4.2) + Vector3(0.0, 2.5, 0.0)
	if hud != null:
		var item_name := def.name if def != null else String(item_id)
		hud.show_toast("Dropped %s x%d" % [item_name, actual_removed])
	return drop


func is_hammer_equipped() -> bool:
	return inventory != null and inventory.is_hammer_active()


func select_hotbar_slot(idx: int) -> void:
	inventory.set_active_hotbar_index(idx)
	_sync_tool_from_hotbar()


func set_hammer_build_mode(mode: int) -> void:
	hammer_build_mode = clampi(mode, 0, 2)
	if is_hammer_equipped():
		_sync_tool_from_hotbar()


func select_hammer_prefab(id: int) -> void:
	hammer_build_mode = 0
	prefab_id = clampi(id, 0, Prefabs.count() - 1)
	if placement != null:
		placement.entity_blueprint = &""
	_sync_tool_from_hotbar()


func select_hammer_block(block_mat_idx: int) -> void:
	hammer_build_mode = 1
	mat_index = clampi(block_mat_idx, 0, Palette.BUILDABLE.size() - 1)
	if placement != null:
		placement.entity_blueprint = &""
	_sync_tool_from_hotbar()


func select_hammer_furniture(type: StringName) -> void:
	hammer_build_mode = 2
	if placement != null:
		placement.entity_blueprint = type
	_sync_tool_from_hotbar()


func get_active_item_def() -> ItemDef:
	if inventory == null:
		return null
	var slot := inventory.get_active_item()
	if slot == null or slot.is_empty():
		return null
	return ItemDB.get_item(slot.item_id)


func has_pickaxe_equipped() -> bool:
	var def := get_active_item_def()
	return def != null and (def.has_tag("pickaxe") or def.has_tag("chisel") or bool(def.tool_data.get("breaks_rock", false)))


func has_shovel_equipped() -> bool:
	var def := get_active_item_def()
	return def != null and def.has_tag("shovel")


func can_flatten() -> bool:
	return has_pickaxe_equipped() or has_shovel_equipped()


## A hatchet: the only tool that fells a whole tree, and the fastest on any wood.
func has_axe_equipped() -> bool:
	var def := get_active_item_def()
	return def != null and def.has_tag("axe")


## Can the held tool cut wood blocks at all? (A pick can chip at a trunk; only a hatchet fells it.)
func can_cut_wood() -> bool:
	return has_axe_equipped() or has_pickaxe_equipped()


func can_harvest_voxel(mat: int) -> bool:
	if mat <= 0:
		return false
	if VoxelWorld.is_stone_mat(mat):
		return has_pickaxe_equipped()
	if mat == Palette.TRUNK:
		var def := get_active_item_def()
		return def != null and (def.has_tag("axe") or def.has_tag("pickaxe"))
	return true


func _sync_tool_from_hotbar() -> void:
	if inventory == null:
		return
	var slot := inventory.get_active_item()
	if slot == null or slot.is_empty():
		_set_tool(-1)
		return
	var def: ItemDef = ItemDB.get_item(slot.item_id)
	if def == null:
		_set_tool(-1)
		return

	if def.has_tag("hammer") or def.id == &"builders_hammer":
		match hammer_build_mode:
			0: # Fabricated Pieces (Prefabs)
				if placement != null:
					placement.entity_blueprint = &""
				_set_tool(2)
			1: # Individual Blocks
				if placement != null:
					placement.entity_blueprint = &""
				_ensure_valid_block_material()
				_set_tool(1)
			2: # Furniture & Workstations
				if placement != null and placement.entity_blueprint == &"":
					var types := Placeables.blueprint_types()
					if not types.is_empty():
						placement.entity_blueprint = types[0]
				_set_tool(2)
		if model != null:
			model.set_tool(1) # Hold 3D Hammer mesh in hand
	elif def.has_tag("pickaxe") or def.has_tag("chisel"):
		_set_tool(0)
	elif def.has_tag("axe"):
		_set_tool(0)
		if model != null:
			model.set_tool(9)
	elif def.has_tag("shovel"):
		_set_tool(0)
		if model != null:
			model.set_tool(10)
	elif def.has_tag("fishing_rod"):
		_set_tool(3)
	elif def.has_tag("hoe") or def.has_tag("seed"):
		_set_tool(4)
	elif def.has_tag("weapon") or not def.weapon_data.is_empty():
		_set_tool(5)
	elif def.category == ItemDef.Category.BLUEPRINT or def.has_tag("blueprint"):
		_set_tool(2)
	elif EntityManager.type_for_item(def.id) != &"":
		_set_tool(4)
		if model != null:
			model.set_tool(2)
	elif def.is_voxel():
		var b_idx := Palette.BUILDABLE.find(def.voxel_mat)
		if b_idx >= 0:
			mat_index = b_idx
		# Preserve active placement size (e.g. 1x1, 3x3, 5x5) when switching or holding voxel blocks
		brush = clampi(brush, 0, BRUSHES.size() - 1)
		_set_tool(1)
	elif def.category == ItemDef.Category.FOOD:
		_set_tool(4)
		if model != null:
			model.set_tool(-1)
	else:
		_set_tool(-1)


func open_tool_wheel() -> void:
	if tool_wheel != null:
		tool_wheel.player = self
		tool_wheel.open_wheel()


func close_tool_wheel() -> int:
	if tool_wheel != null:
		return tool_wheel.close_wheel()
	return -1


func _set_tool(new_tool: int) -> void:
	if tool == 3 and new_tool != 3 and fishing != null:
		fishing.reset()
	if new_tool != 1:
		_line_anchor = Vector3i(-99999, -99999, -99999)
	if new_tool != 0:
		pickaxe_flatten_mode = false
	if controller:
		controller.reset_triggers()
	tool = new_tool
	if model != null:
		model.set_tool(tool)


func _unhandled_input(e: InputEvent) -> void:
	if not input_enabled:
		return
	if is_seated():
		if e.is_action_pressed("dodge") or (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_C):
			if boat != null:
				if boat.repair_at_sea(self):
					if hud != null:
						hud.show_toast("Patched boat hull with wood plank! (+40 HP)")
				elif boat.hull_hp >= boat.max_hull_hp and not boat.is_leaking():
					if hud != null:
						hud.show_toast("Boat hull is in seaworthy condition.")
				else:
					if hud != null:
						hud.show_toast("Need wood planks in pack to patch hull at sea!")
			return
		return
	if not InputMap.has_action(&"tool_1"):
		ControllerManager.new().setup_input_map()
	# Entities (Agent A): tap F = use nearest entity, hold F = pick it up.
	if placement != null and placement.handle_input(e):
		return
	if e.is_action_pressed("tool_1"): select_hotbar_slot(0)
	elif e.is_action_pressed("tool_2"): select_hotbar_slot(1)
	elif e.is_action_pressed("tool_3"): select_hotbar_slot(2)
	elif e.is_action_pressed("tool_4"): select_hotbar_slot(3)
	elif e.is_action_pressed("tool_5"): select_hotbar_slot(4)
	elif e.is_action_pressed("tool_6"): select_hotbar_slot(5)
	elif e.is_action_pressed("tool_7"): select_hotbar_slot(6)
	elif e.is_action_pressed("tool_8"): select_hotbar_slot(7)
	elif not (e is InputEventMouseButton) and e.is_action_pressed("cycle_tool_next"): select_hotbar_slot(posmod(inventory.active_hotbar_index + 1, Inventory.MAX_HOTBAR_SLOTS))
	elif not (e is InputEventMouseButton) and e.is_action_pressed("cycle_tool_prev"): select_hotbar_slot(posmod(inventory.active_hotbar_index - 1, Inventory.MAX_HOTBAR_SLOTS))
	elif e.is_action_pressed("build_menu_toggle"):
		if is_hammer_equipped():
			if build_menu_ui != null:
				build_menu_ui.toggle_catalogue()
			else:
				set_hammer_build_mode((hammer_build_mode + 1) % 3)
	elif is_hammer_equipped() and e.is_action_pressed("alt_use"):
		if build_menu_ui != null:
			build_menu_ui.toggle_catalogue()
		else:
			set_hammer_build_mode((hammer_build_mode + 1) % 3)
	elif can_flatten() and e.is_action_pressed("alt_use") and not e.is_echo():
		_flatten_at_target()
	elif has_pickaxe_equipped() and e.is_action_pressed("rotate") and not e.is_echo():
		toggle_pickaxe_flatten_mode()
	elif tool == 1 and not is_hammer_equipped() and e.is_action_pressed("alt_use") and not e.is_echo():
		cycle_brush_size()
	elif e.is_action_pressed("next_item"): _cycle(1)
	elif e.is_action_pressed("prev_item"): _cycle(-1)
	elif e.is_action_pressed("brush_up") and tool == 2 and e is InputEventJoypadButton:
		snap = not snap   # blueprints have no brush size, so D-Pad Up toggles grid snap on a pad
	elif e.is_action_pressed("brush_up"):
		brush = mini(brush + 1, BRUSHES.size() - 1)
		_on_brush_changed()
	elif e.is_action_pressed("brush_down"):
		brush = maxi(brush - 1, 0)
		_on_brush_changed()
	elif e.is_action_pressed("rotate"): prefab_rot = (prefab_rot + 1) % 4
	elif e.is_action_pressed("snap"): snap = not snap
	elif e.is_action_pressed("pick") and not target.is_empty():
		var c: Vector3i = target.cell
		var m := world.get_voxel(c.x, c.y, c.z)
		var idx := Palette.BUILDABLE.find(m)
		if idx >= 0:
			mat_index = idx
			if is_hammer_equipped():
				select_hammer_block(idx)
			else:
				_set_tool(1)
	elif tool == 4 and (e.is_action_pressed("alt_use") or e.is_action_pressed("use")):
		if _try_use_animal_whistle():
			return
		if e.is_action_pressed("alt_use"):
			if not _try_eat_active_food():
				if placement != null and placement.active_type() != &"" and placement.try_use():
					_use_cd = 0.35
					model.swing()
				else:
					_plant_seed_at_target()
	elif tool == 3:
		_handle_fishing_input(e)


func _try_use_animal_whistle() -> bool:
	var active: ItemSlot = inventory.get_active_item()
	if active and not active.is_empty() and active.item_id == &"animal_whistle":
		var main_node: Node = entities.main if (entities != null and entities.main != null) else get_parent()
		var livestock: Node = main_node.get("livestock_mgr") if main_node != null else null
		if livestock != null and livestock.has_method("sound_whistle"):
			var count: int = livestock.sound_whistle(position)
			if hud != null:
				hud.show_toast("♪ *Shepherd's Whistle shrills!* Alerted %d livestock." % count)
			return true
	return false


func _try_eat_active_food() -> bool:
	var active: ItemSlot = inventory.get_active_item()
	if active and not active.is_empty():
		var item_id: StringName = active.item_id
		if vitality.is_full_of(item_id):
			if hud:
				var d: ItemDef = ItemDB.get_item(item_id)
				hud.show_toast("Still full of %s. Try another dish, or wait %d min." % [
					d.name if d != null else String(item_id), maxi(1, ceili(vitality.reeat_wait_sec(item_id) / 60.0))])
			return true
		if vitality.can_eat_food(item_id):
			if vitality.eat_food(item_id, inventory):
				quest_event(QuestDef.ObjectiveType.EAT_FOOD, item_id)
				if hud:
					var def: ItemDef = ItemDB.get_item(item_id)
					var meal_name: String = def.name if def != null else String(item_id)
					hud.show_toast("Ate %s. Satiety: %d/3 meals" % [meal_name, vitality.get_active_meals().size()])
				return true
	return false


func cycle_brush_size(step: int = 1) -> void:

	brush = posmod(brush + step, BRUSHES.size())

	_on_brush_changed()





func _on_brush_changed() -> void:

	var r: int = BRUSHES[clampi(brush, 0, BRUSHES.size() - 1)]

	var dim: int = r * 2 + 1

	var sz_str := "%dx%d" % [dim, dim] if r > 0 else "1x1 (Single)"

	if hud != null:

		hud.show_toast("Placement Size: %s" % sz_str)


func toggle_pickaxe_flatten_mode() -> void:
	pickaxe_flatten_mode = not pickaxe_flatten_mode
	if hud != null:
		if pickaxe_flatten_mode:
			hud.show_toast("Flatten Land Mode: ON - Level ground to targeted height")
		else:
			hud.show_toast("Standard Mode")


func _flatten_at_target() -> void:
	if target.is_empty():
		return
	var cell: Vector3i = target.cell
	var active_def := get_active_item_def()
	var tier: int = int(active_def.tool_data.get("tier", 1)) if active_def != null else 1
	var flat_r := 2
	command_requested.emit({
		"t": "flatten",
		"p": cell,
		"r": flat_r,
		"target_y": cell.y,
		"tool_tier": tier,
	})
	_use_cd = 0.22
	if model != null:
		model.swing()
	swing_count += 1
	if rig != null:
		facing = rig.yaw + PI





func _cycle(d: int) -> void:
	if is_hammer_equipped():
		match hammer_build_mode:
			0: # Prefabs
				prefab_id = posmod(prefab_id + d, Prefabs.count())
			1: # Blocks
				mat_index = posmod(mat_index + d, Palette.BUILDABLE.size())
			2: # Furniture
				var types := Placeables.blueprint_types()
				if not types.is_empty() and placement != null:
					var cur := types.find(placement.entity_blueprint)
					placement.entity_blueprint = types[posmod(cur + d, types.size())]
		return
	if tool == 2 and placement != null:
		placement.cycle_blueprint(d)  # Entities (Agent A): prefabs, then placeable furniture
		return
	if tool == 2:
		prefab_id = posmod(prefab_id + d, Prefabs.count())
	elif tool == 1:
		mat_index = posmod(mat_index + d, Palette.BUILDABLE.size())
	else:
		select_hotbar_slot(posmod(inventory.active_hotbar_index + d, Inventory.MAX_HOTBAR_SLOTS))
		var active := inventory.get_active_item()
		if active and not active.is_empty():
			var item := ItemDB.get_item(active.item_id)
			if hud and item:
				hud.show_toast("Selected: %s (x%d)" % [item.name, active.count])


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
				fishing.strike_hook()   # nothing on yet: reels the lure in
				if hud:
					hud.show_toast("Reeled in. Click again to cast.")
	elif e.is_action_released("use"):
		if fishing.current_state == FishingController.State.CASTING:
			var tide_frac: float = 0.5
			var daylight: bool = true
			if sky:
				tide_frac = (sky.water_level_vox - (VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP)) / (2.0 * VoxelWorld.TIDE_AMP)
				daylight = sky.is_day()
			fishing.release_cast(fishing_cast_power, tide_frac, daylight, false, false)
			if rig != null:
				facing = rig.yaw + PI
			if model != null:
				model.cast_line()
			_launch_bobber(fishing_cast_power)
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
	if rig != null and rig.first_person:
		facing = rig.yaw + PI
	model.rotation = Vector3(0, facing, 0)
	model.set_fishing_state(fishing.current_state if tool == 3 and fishing != null else 0, fishing_cast_power)
	var is_dodging: bool = (combat != null and combat.is_dodging())
	if not is_dodging:
		model.animate(delta, horizontal_speed, on_ground, swimming)
	var shift_held := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	if not shift_held or tool != 1:
		_line_anchor = Vector3i(-99999, -99999, -99999)
	_update_fishing_bobber(delta)
	_update_target()
	_update_cursor_highlight(_last_ray_origin, _last_ray_dir, _last_ray_hit)
	if placement != null:
		placement.update_ghost()  # Entities (Agent A)
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
	# Agent C: a weapon in the active hotbar slot turns LMB into a swing (RMB parry, C dodge).
	if combat != null and combat.process_input(delta, input_enabled and can_input):
		return
	if input_enabled and can_input and _use_cd <= 0.0 and not target.is_empty():
		if can_flatten() and Input.is_action_pressed("alt_use"):
			_flatten_at_target()
		elif Input.is_action_pressed("use") and tool != 3:
			_use_tool()


func _update_target() -> void:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else vp.get_mouse_position()
	var origin := rig.cam.project_ray_origin(center)
	var dir := rig.cam.project_ray_normal(center)
	target = {}
	var hit := world.raycast(origin, dir, 40.0)
	_last_ray_origin = origin
	_last_ray_dir = dir
	_last_ray_hit = hit
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
	if false:
		var c := cell if tool <= 0 else cell + (target.normal as Vector3i)
		var r: int = mini(BRUSHES[brush], 1) if tool == -1 else int(BRUSHES[brush])
		var sz := Vector3.ONE * (2 * r + 1) * VS * 1.02
		pass
		if false:
			pass
		pass
		pass
		(_highlight.mesh as BoxMesh).size = sz
		_hl_mat.set_shader_parameter("size", sz)
		_hl_mat.set_shader_parameter("color", Color(1, 0.55, 0.4, 0.95) if tool == 0 else Color(0.6, 1, 0.75, 0.95))
		_highlight.global_position = (Vector3(c) + Vector3.ONE * 0.5) * VS
		_highlight.visible = true
	elif false:
		var sz := Vector3(2.85 * VS, VS * 1.15, 2.85 * VS)
		(_highlight.mesh as BoxMesh).size = sz
		_hl_mat.set_shader_parameter("size", sz)
		_hl_mat.set_shader_parameter("color", Color(0.4, 0.85, 0.3, 0.95))
		_highlight.global_position = (Vector3(_resolve_farm_plot_cell(cell)) + Vector3.ONE * 0.5) * VS
		_highlight.visible = true
	if tool == 2:
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


func _update_cursor_highlight(origin: Vector3, dir: Vector3, hit: Dictionary) -> void:
	hovered_entity = null
	var vox_dist: float = float(hit.get("dist", 999.0)) if not hit.is_empty() else 999.0
	if entities != null:
		var ent_hit := entities.raycast_entity(origin, dir, 40.0)
		if not ent_hit.is_empty() and float(ent_hit.get("dist", 999.0)) <= vox_dist + 0.05:
			hovered_entity = ent_hit.get("entity", null)
	if hovered_entity != null and is_instance_valid(hovered_entity):
		var ebox := hovered_entity.get_aabb().grow(0.03)
		var in_ent_reach := position.distance_to(hovered_entity.position) <= maxf(3.2, hovered_entity.interaction_radius)
		(_highlight.mesh as BoxMesh).size = ebox.size
		_hl_mat.set_shader_parameter("size", ebox.size)
		_hl_mat.set_shader_parameter("color", Color(1.0, 0.85, 0.32, 0.95) if in_ent_reach else Color(1.0, 0.85, 0.32, 0.55))
		_highlight.global_position = ebox.get_center()
		_highlight.visible = true
	elif not hit.is_empty():
		var hcell: Vector3i = hit.cell
		var hnorm: Vector3i = hit.normal
		var in_reach := not target.is_empty()
		var alpha_mult := 0.95 if in_reach else 0.52
		var active_def := get_active_item_def()
		var is_farm_item := active_def != null and (active_def.has_tag("hoe") or active_def.has_tag("seed"))
		var shift_held := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
		if can_flatten() and (pickaxe_flatten_mode or Input.is_action_pressed("alt_use")) and (tool == 0 or tool == -1):
			var flat_r := 2
			var hsz := Vector3((2 * flat_r + 1) * VS * 1.02, VS * 0.25, (2 * flat_r + 1) * VS * 1.02)
			(_highlight.mesh as BoxMesh).size = hsz
			_hl_mat.set_shader_parameter("size", hsz)
			_hl_mat.set_shader_parameter("color", Color(1.0, 0.75, 0.25, alpha_mult))
			_highlight.global_position = (Vector3(hcell.x, hcell.y, hcell.z) + Vector3(0.5, 0.125, 0.5)) * VS
			_highlight.visible = true
		elif tool == 1 and brush == 0 and shift_held and _line_anchor.x != -99999 and (Vector3(hcell) - Vector3(_line_anchor)).length() <= 16.0:
			var hc := hcell + hnorm
			var delta := hc - _line_anchor
			var adx := absi(delta.x)
			var ady := absi(delta.y)
			var adz := absi(delta.z)
			var line_c := hc
			if adx >= ady and adx >= adz:
				line_c = Vector3i(hc.x, _line_anchor.y, _line_anchor.z)
			elif ady >= adx and ady >= adz:
				line_c = Vector3i(_line_anchor.x, hc.y, _line_anchor.z)
			else:
				line_c = Vector3i(_line_anchor.x, _line_anchor.y, hc.z)
			var min_p := Vector3i(mini(_line_anchor.x, line_c.x), mini(_line_anchor.y, line_c.y), mini(_line_anchor.z, line_c.z))
			var max_p := Vector3i(maxi(_line_anchor.x, line_c.x), maxi(_line_anchor.y, line_c.y), maxi(_line_anchor.z, line_c.z))
			var span := max_p - min_p + Vector3i.ONE
			var hsz := Vector3(span.x, span.y, span.z) * VS * 1.02
			(_highlight.mesh as BoxMesh).size = hsz
			_hl_mat.set_shader_parameter("size", hsz)
			_hl_mat.set_shader_parameter("color", Color(0.4, 0.9, 1.0, alpha_mult))
			_highlight.global_position = (Vector3(min_p) + Vector3(span) * 0.5) * VS
			_highlight.visible = true
		elif tool == 0 or tool == 1 or tool == -1:
			var hc := hcell if tool <= 0 else hcell + hnorm
			var hr: int = mini(BRUSHES[brush], 1) if tool == -1 else int(BRUSHES[brush])
			var hsz := Vector3.ONE * (2 * hr + 1) * VS * 1.02
			(_highlight.mesh as BoxMesh).size = hsz
			_hl_mat.set_shader_parameter("size", hsz)
			var base_col := Color(1.0, 0.55, 0.4, alpha_mult) if tool == 0 else (Color(0.6, 1.0, 0.75, alpha_mult) if tool == 1 else Color(0.9, 0.95, 1.0, alpha_mult))
			_hl_mat.set_shader_parameter("color", base_col)
			_highlight.global_position = (Vector3(hc) + Vector3.ONE * 0.5) * VS
			_highlight.visible = true
		elif tool == 4 and is_farm_item:
			var fsz := Vector3(2.85 * VS, VS * 1.15, 2.85 * VS)
			(_highlight.mesh as BoxMesh).size = fsz
			_hl_mat.set_shader_parameter("size", fsz)
			_hl_mat.set_shader_parameter("color", Color(0.4, 0.85, 0.3, alpha_mult))
			_highlight.global_position = (Vector3(_resolve_farm_plot_cell(hcell)) + Vector3.ONE * 0.5) * VS
			_highlight.visible = true
		else:
			var bsz := Vector3.ONE * VS * 1.03
			(_highlight.mesh as BoxMesh).size = bsz
			_hl_mat.set_shader_parameter("size", bsz)
			_hl_mat.set_shader_parameter("color", Color(0.85, 0.95, 1.0, alpha_mult))
			_highlight.global_position = (Vector3(hcell) + Vector3.ONE * 0.5) * VS
			_highlight.visible = true


func prefab_origin() -> Vector3i:
	var o: Vector3i = (target.cell as Vector3i) + (target.normal as Vector3i)
	if (target.normal as Vector3i).y == 0:
		o.y = (target.cell as Vector3i).y  # side hit: sit level with the face
	if snap:
		o.x = int(round(o.x / 6.0)) * 6
		o.z = int(round(o.z / 6.0)) * 6
	return o


func _use_tool() -> void:
	if placement != null and placement.try_use():  # Entities (Agent A): placing furniture
		_use_cd = 0.35
		return
	var cell: Vector3i = target.cell
	match (0 if tool == -1 else tool):
		0:
			var mat := world.get_voxel(cell.x, cell.y, cell.z)
			if controller:
				controller.apply_mining(mat)
			if has_pickaxe_equipped() and pickaxe_flatten_mode:
				var active_def := get_active_item_def()
				var tier: int = int(active_def.tool_data.get("tier", 1)) if active_def != null else 1
				var flat_r: int = maxi(1, int(BRUSHES[brush])) if brush > 0 else 2
				command_requested.emit({
					"t": "flatten",
					"p": cell,
					"r": flat_r,
					"target_y": cell.y,
					"tool_tier": tier,
				})
				_use_cd = 0.22
				if model != null:
					model.swing()
				swing_count += 1
				if rig != null:
					facing = rig.yaw + PI
				return
			if not can_harvest_voxel(mat):
				if hud != null:
					if VoxelWorld.is_stone_mat(mat):
						hud.show_toast("Requires a Pickaxe to mine stone!")
					elif mat == Palette.TRUNK:
						hud.show_toast("Equip a Hatchet or Pickaxe to chop trees!")
					else:
						hud.show_toast("Cannot harvest this material with current tool.")
				_use_cd = 0.35
				model.swing()
				swing_count += 1
				facing = rig.yaw + PI
				return
			var active_def := get_active_item_def()
			var tier: int = int(active_def.tool_data.get("tier", 1)) if active_def != null else 1
			var dig_r: int = mini(BRUSHES[brush], 1) if tool == -1 else int(BRUSHES[brush])
			var axe := has_axe_equipped()
			command_requested.emit({
				"t": "dig",
				"p": cell,
				"r": dig_r,
				"allow_stone": has_pickaxe_equipped(),
				"allow_wood": can_cut_wood(),
				"fell": axe,
				"tool_tier": tier,
			})
			_use_cd = maxf(0.08, (0.16 + dig_r * 0.03) / sqrt(float(maxi(1, tier))))
			# Wood: a hatchet bites fast, a pick only chips.
			if VoxelWorld.is_wood_mat(mat):
				_use_cd *= 0.55 if axe else 1.8
				if mat == Palette.TRUNK and not axe and hud != null and not _told_use_hatchet:
					_told_use_hatchet = true
					hud.show_toast("A pick only chips at a trunk. A hatchet fells the whole tree.")

		1:
			var c: Vector3i = cell + (target.normal as Vector3i)
			var shift_held := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)

			if brush == 0 and shift_held and _line_anchor.x != -99999:
				var delta := c - _line_anchor
				var adx := absi(delta.x)
				var ady := absi(delta.y)
				var adz := absi(delta.z)
				if adx >= ady and adx >= adz:
					c = Vector3i(c.x, _line_anchor.y, _line_anchor.z)
				elif ady >= adx and ady >= adz:
					c = Vector3i(_line_anchor.x, c.y, _line_anchor.z)
				else:
					c = Vector3i(_line_anchor.x, _line_anchor.y, c.z)

				var dist := maxi(maxi(absi(c.x - _line_anchor.x), absi(c.y - _line_anchor.y)), absi(c.z - _line_anchor.z))
				if dist > 0:
					var step_dir := Vector3(c - _line_anchor).normalized()
					var placed_count := 0
					for step in range(1, dist + 1):
						var pt := _line_anchor + Vector3i(round(step_dir.x * step), round(step_dir.y * step), round(step_dir.z * step))
						if _brush_hits_self(pt, 0):
							continue
						var cost := BuildCosts.brush_cost(world, pt, 0, current_material())
						if not _pay_or_warn(cost):
							break
						command_requested.emit({"t": "place", "p": pt, "r": 0, "m": current_material()})
						placed_count += 1
					if placed_count > 0:
						quest_event(QuestDef.ObjectiveType.PLACE_VOXELS, &"")
						if controller:
							controller.pulse_place()
					_line_anchor = c
					_use_cd = 0.2
					if model != null:
						model.swing()
					swing_count += 1
					if rig != null:
						facing = rig.yaw + PI
					return

			var r: int = BRUSHES[brush]
			if _brush_hits_self(c, r):
				if hud != null:
					hud.show_toast("Too close to player to place!")
				return
			# Survival: placing costs materials (1 item per 4 voxels, like digging yields).
			var cost := BuildCosts.brush_cost(world, c, r, current_material())
			if not _pay_or_warn(cost):
				_use_cd = 0.4
				return
			command_requested.emit({"t": "place", "p": c, "r": r, "m": current_material()})
			_line_anchor = c
			quest_event(QuestDef.ObjectiveType.PLACE_VOXELS, &"")
			if controller:
				controller.pulse_place()
			_use_cd = 0.16 + r * 0.03
		2:
			if not _pay_or_warn(BuildCosts.prefab_cost(prefab_id, prefab_rot)):
				_use_cd = 0.6
				return
			command_requested.emit({"t": "prefab", "p": prefab_origin(), "r": prefab_rot, "id": prefab_id})
			quest_event(QuestDef.ObjectiveType.PLACE_PREFAB, &"")
			_use_cd = 0.45
		4:
			_use_farm_tool(cell)
			_use_cd = 0.25
	if model != null:
		model.swing()
	swing_count += 1
	if rig != null:
		facing = rig.yaw + PI


func _resolve_farm_plot_cell(cell: Vector3i) -> Vector3i:
	if farm == null:
		return cell
	if farm.plots.has(cell):
		return cell
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)
				if farm.plots.has(near):
					return near
	return cell


func _convert_surface_to_tilled_dirt(cell: Vector3i) -> void:
	if world == null:
		return
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var vx := cell.x + dx
			var vz := cell.z + dz
			var m := world.get_voxel(vx, cell.y, vz)
			if m == Palette.GRASS or m == Palette.GRASS_DRY:
				world.set_voxel(vx, cell.y, vz, Palette.DIRT)


func _use_farm_tool(p_cell: Vector3i) -> void:
	var cell := _resolve_farm_plot_cell(p_cell)
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
	_convert_surface_to_tilled_dirt(cell)
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
		cell = _resolve_farm_plot_cell(cell)
		if not farm.plots.has(cell):
			farm.till_plot(cell)
			_convert_surface_to_tilled_dirt(cell)
	var planted := farm.plant_from_inventory(cell, inventory)
	if planted:
		if controller:
			controller.apply_farming_sow()
		var plot := farm.get_plot(cell)
		quest_event(QuestDef.ObjectiveType.PLANT_CROP, plot.crop_id)
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
			var hint := " (or resize with Z/RMB)" if (tool == 1 and brush > 0) else ""
			hud.show_toast("Need " + BuildCosts.describe_missing(inventory, cost) + hint)
		return false
	BuildCosts.pay(inventory, cost)
	return true


func _brush_hits_self(c: Vector3i, r: int) -> bool:
	var plo := position - Vector3(HW, 0, HW)
	var phi := position + Vector3(HW, H, HW)
	var r2 := r * r + r
	for y in range(-r, r + 1):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y + z * z > r2:
					continue
				var px := c.x + x
				var py := c.y + y
				var pz := c.z + z
				# If voxel is already solid in the world, placing won't modify it:
				if world != null and world.get_voxel(px, py, pz) != 0 and not Palette.is_plant(world.get_voxel(px, py, pz)):
					continue
				var vlo := Vector3(px, py, pz) * VS
				var vhi := Vector3(px + 1, py + 1, pz + 1) * VS
				if vlo.x < phi.x and vhi.x > plo.x and vlo.y < phi.y and vhi.y > plo.y and vlo.z < phi.z and vhi.z > plo.z:
					return true
	return false


func _setup_fishing_visuals() -> void:
	# A chunky red-and-white float with a little antenna: readable from 20 m away.
	_bobber = Node3D.new()
	_bobber.top_level = true
	_bobber.visible = false
	add_child(_bobber)
	var parts := [
		# [size, y offset, colour, glow]
		[Vector3(0.22, 0.12, 0.22), 0.06, Color(0.95, 0.20, 0.15), 0.35],
		[Vector3(0.22, 0.12, 0.22), -0.06, Color(0.96, 0.95, 0.90), 0.0],
		[Vector3(0.04, 0.16, 0.04), 0.20, Color(1.0, 0.85, 0.25), 0.6],
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[2]
		mat.roughness = 0.4
		if float(part[3]) > 0.0:
			mat.emission_enabled = true
			mat.emission = part[2]
			mat.emission_energy_multiplier = float(part[3])
		box.material = mat
		mi.mesh = box
		mi.position = Vector3(0, float(part[1]), 0)
		_bobber.add_child(mi)

	_fishing_line = MeshInstance3D.new()
	_fishing_line.top_level = true
	_fishing_line.visible = false
	_fishing_line_mesh = ImmediateMesh.new()
	_fishing_line.mesh = _fishing_line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.90, 0.93, 0.96, 0.85)
	_fishing_line.material_override = line_mat
	add_child(_fishing_line)


func _launch_bobber(power: float) -> void:
	var dir := Vector3(sin(facing), 0.0, cos(facing)).normalized()
	var dist := 4.5 + clampf(power, 0.1, 1.0) * 9.5
	_bobber_start = position + Vector3(0, 1.38, 0) + dir * 0.65
	# Land the lure on the farthest open water along the cast (it drops short of a far
	# shore instead of failing). Water is tested just below the surface.
	var found := world == null
	var d := dist
	while not found and d >= 1.5:
		var probe := position + dir * d
		probe.y = water_level - 0.25
		if world.is_water_at(probe, water_level):
			found = true
			dist = d
		else:
			d -= 0.5
	_bobber_target = position + dir * dist
	_bobber_target.y = water_level
	if not found:
		if hud != null:
			hud.show_toast("No water there to fish!")
		if fishing != null:
			fishing.reset()
		if _bobber != null:
			_bobber.visible = false
		if _fishing_line != null:
			_fishing_line.visible = false
		return
	_bobber_flight_t = 0.0
	_bobber_phase = 0.0
	if _bobber != null:
		_bobber.global_position = _bobber_start
		_bobber.visible = true
	if _fishing_line != null:
		_fishing_line.visible = true


func _update_fishing_bobber(delta: float) -> void:
	if _bobber == null or _fishing_line == null:
		return
	var active_cast: bool = tool == 3 and fishing != null and fishing.current_state in [
		FishingController.State.WAITING_FOR_BITE,
		FishingController.State.NIBBLING,
		FishingController.State.HOOK_WINDOW,
		FishingController.State.REELING,
	]
	if not active_cast:
		_bobber.visible = false
		_fishing_line.visible = false
		return

	_bobber.visible = true
	_fishing_line.visible = true
	_bobber_phase += delta * 4.5
	var dir := Vector3(sin(facing), 0.0, cos(facing)).normalized()
	var rod_tip := position + Vector3(0, 1.42, 0) + dir * 0.82

	if _bobber_flight_t < 1.0:
		_bobber_flight_t = minf(1.0, _bobber_flight_t + delta * 2.6)
		var p := _bobber_start.lerp(_bobber_target, _bobber_flight_t)
		p.y += sin(_bobber_flight_t * PI) * 2.6
		_bobber.global_position = p
	else:
		var base_pos := _bobber_target
		base_pos.y = water_level + sin(_bobber_phase) * 0.035
		if fishing.current_state == FishingController.State.NIBBLING:
			base_pos.y -= absf(sin(_bobber_phase * 3.5)) * 0.10
		elif fishing.current_state == FishingController.State.HOOK_WINDOW:
			base_pos.y -= 0.18 + sin(_bobber_phase * 5.0) * 0.05
		elif fishing.current_state == FishingController.State.REELING:
			var reel_frac := clampf(fishing.reel_progress, 0.0, 1.0)
			var shore_pos := position + dir * 1.4
			shore_pos.y = water_level
			base_pos = _bobber_target.lerp(shore_pos, reel_frac)
			base_pos.x += sin(_bobber_phase * 3.2) * 0.25 * (1.0 - reel_frac)
			base_pos.z += cos(_bobber_phase * 2.7) * 0.25 * (1.0 - reel_frac)
			base_pos.y = water_level - 0.04 + sin(_bobber_phase * 4.0) * 0.04
		_bobber.global_position = base_pos

	_fishing_line_mesh.clear_surfaces()
	_fishing_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var end_pos := _bobber.global_position + Vector3(0, 0.06, 0)
	var sag := 0.35 if fishing.current_state != FishingController.State.REELING else 0.06
	for i in range(9):
		var t := float(i) / 8.0
		var pt := rod_tip.lerp(end_pos, t)
		pt.y -= sin(t * PI) * sag
		_fishing_line_mesh.surface_add_vertex(pt)
	_fishing_line_mesh.surface_end()
