class_name CreatureNet
extends Node
## Creatures + optional combat for every session (solo, host, client, dedicated server).
##
## Authority: the host / dedicated server spawns, simulates and damages creatures, and
## decides when a creature hits a player. Clients render compact 10 Hz snapshots, predict
## their own swings locally (flash), and send hit requests the host validates by distance.
## The hit player's own client resolves dodge / parry (trusted co-op, like inventories).
##
## Spawn rules (host, around every player):
##   tide-crabs  intertidal beach columns exposed at a below-mid tide
##   gulls       daytime flocks near the player, roosting (despawned) at night
##   cave eels   flooded water under a roof (the sea cave) after dark; any time on Undertow;
##               never on Cozy
## Difficulty is world-level: saved as <world>/difficulty.cfg by the authority.

const SIM_DT := 0.05
const SNAPSHOT_DT := 0.1
const SPAWN_DT := 1.0
const CAP := {&"crab": 12, &"gull": 12, &"eel": 4, &"gloomcrawler": 4}
## Snapshot kind indices: append only (clients map index -> kind).
const KINDS := [&"crab", &"gull", &"eel", &"hare", &"seal", &"puffin", &"otter", &"heron", &"whale",
	&"fox", &"stoat", &"rat", &"eagle", &"mudclaw", &"mudbrute", &"gloomcrawler",
	&"reaver", &"reaver_harpooner", &"barnacled_hulk", &"abyssal_siren", &"abyssal_angler", &"caldera_shell",
	&"borean_gore_fin", &"tide_sovereign"]
const DESPAWN_DIST := 70.0

static var current: CreatureNet = null

var main: Node
var difficulty := CombatMath.Difficulty.TIDEWATCH
var creatures := {}             # cid -> Creature
var _next_id := 1
var _sim_acc := 0.0
var _snap_acc := 0.0
var _spawn_acc := 0.0
var _flags_acc := 0.0
var _pflags := {}               # peer -> flag bits (sneak 1, bait 2, light 4, fish 8)
var _ppos := {}                 # peer -> [last pos, speed]
var _still_with_fish := {}      # peer -> seconds standing still holding fish
var _hinted := {}
var _rng := RandomNumberGenerator.new()
var _combat: PlayerCombat
var _overlay: ColorRect
var _overlay_a := 0.0
var _overlay_color := Color(0.6, 0.05, 0.05)
var _diff_loaded := false
var _args := {}
var wildlife: WildlifeDirector       # ambient animals, farm raids, dens (scripts/wildlife/)
var fx: WildlifeFX
var camps: MudClawCamps              # Mud-Claw camps on the outer islands
var outposts: ReaverOutposts         # Sea-Reaver outposts on the far islands
var hulk: HulkLair                   # the Barnacled Hulk's strand (Hollow Flats boss)
var siren: SirenLair                 # the Abyssal Siren's trench (Murk-Reef boss)
var caldera: CalderaLair             # the Caldera Shell (Basalt Skerries boss)
var borean: BoreanLair               # Borean Gore-Fin (Frost-Shoals boss)
var maelstrom: MaelstromSpire        # The Tide Sovereign (Climax boss)

# Dev-check counters
var stats_hits := 0
var stats_hurt := 0.0


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	current = self
	_rng.randomize()
	wildlife = WildlifeDirector.new(self)
	fx = WildlifeFX.new()
	fx.name = "WildlifeFX"
	add_child(fx)
	camps = MudClawCamps.new()
	camps.net = self
	add_child(camps)
	outposts = ReaverOutposts.new()
	outposts.net = self
	add_child(outposts)
	hulk = HulkLair.new()
	hulk.net = self
	add_child(hulk)
	siren = SirenLair.new()
	siren.net = self
	add_child(siren)
	caldera = CalderaLair.new()
	caldera.net = self
	add_child(caldera)
	borean = BoreanLair.new()
	borean.net = self
	add_child(borean)
	maelstrom = MaelstromSpire.new()
	maelstrom.net = self
	add_child(maelstrom)
	if main.get("session") != null:
		main.session.register_state(&"wildlife", wildlife.serialize, wildlife.deserialize)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_add_action("sneak", [KEY_CTRL], [JOY_BUTTON_PADDLE2])
	_add_action("dodge", [KEY_C], [JOY_BUTTON_PADDLE1])
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0, 0, 0, 0)
	layer.add_child(_overlay)
	main.multiplayer.peer_connected.connect(_on_peer_connected)
	main.multiplayer.peer_disconnected.connect(func(id: int) -> void:
		_pflags.erase(id)
		_ppos.erase(id))


func _add_action(action: String, keys: Array, pads: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in pads:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)


func is_authority() -> bool:
	return not main.is_net or main.multiplayer.multiplayer_peer == null or main.multiplayer.is_server()


func local_id() -> int:
	return main.multiplayer.get_unique_id() if main.is_net and main.multiplayer.multiplayer_peer != null else 1


## Voxel query used by creature movement (tests substitute a fake).
func voxel(x: int, y: int, z: int) -> int:
	return main.world.get_voxel(x, y, z)


func _world_ready() -> bool:
	return main.world != null and main.world.ready_for_play and main.world.gen != null


# ---------------------------------------------------------------- difficulty

func _diff_path() -> String:
	return main.session.dir + "difficulty.cfg" if main.session != null else ""


func _load_difficulty() -> void:
	_diff_loaded = true
	if not is_authority():
		return
	var cfg := ConfigFile.new()
	if _diff_path() != "" and cfg.load(_diff_path()) == OK:
		difficulty = int(cfg.get_value("world", "difficulty", difficulty))
	if _args.has("difficulty"):
		var i := ["cozy", "tidewatch", "undertow"].find(String(_args.difficulty).to_lower())
		if i >= 0:
			set_difficulty(i)


func set_difficulty(d: int) -> void:
	if not is_authority():
		return
	difficulty = clampi(d, 0, 2)
	if _diff_path() != "":
		DirAccess.make_dir_recursive_absolute(main.session.dir)
		var cfg := ConfigFile.new()
		cfg.set_value("world", "difficulty", difficulty)
		cfg.save(_diff_path())
	if not CombatMath.hostiles_allowed(difficulty):
		for c: Creature in creatures.values():
			if c.hostile:
				despawn(c)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		cr_difficulty.rpc(difficulty)
	print("[creatures] difficulty: ", CombatMath.DIFFICULTY_NAMES[difficulty])


@rpc("authority", "call_remote", "reliable")
func cr_difficulty(d: int) -> void:
	difficulty = d


## Settings menu row (Interface tab). Host/solo can change it; clients see it read-only.
func build_settings_row(parent: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "World difficulty"
	l.custom_minimum_size = Vector2(260, 0)
	h.add_child(l)
	var o := OptionButton.new()
	for n: String in ["Cozy (no hostile creatures)", "Tidewatch", "Undertow (hard)"]:
		o.add_item(n)
	o.selected = difficulty
	o.disabled = not is_authority()
	o.tooltip_text = "Only the host can change this." if o.disabled else ""
	o.item_selected.connect(set_difficulty)
	h.add_child(o)
	parent.add_child(h)


func _on_peer_connected(id: int) -> void:
	if main.multiplayer.is_server():
		cr_difficulty.rpc_id(id, difficulty)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not _world_ready():
		return
	if not _diff_loaded:
		_load_difficulty()
	_bind_player()
	if _args.has("creaturecheck") and not _check_started and (main.player != null or main.session.dedicated):
		_check_started = true
		_creature_check(String(_args.creaturecheck))
	_update_overlay(delta)
	_show_hints()
	if is_authority():
		_sim_acc += minf(delta, 0.25)
		while _sim_acc >= SIM_DT:
			_sim_acc -= SIM_DT
			_simulate(SIM_DT)
		_spawn_acc += delta
		if _spawn_acc >= SPAWN_DT:
			_spawn_acc = 0.0
			_spawn_tick()
		if main.is_net and main.multiplayer.multiplayer_peer != null:
			_snap_acc += delta
			if _snap_acc >= SNAPSHOT_DT:
				_snap_acc = 0.0
				cr_snapshot.rpc(_pack())
	elif main.player != null and main.multiplayer.multiplayer_peer != null:
		_flags_acc += delta
		if _flags_acc >= 0.2:
			_flags_acc = 0.0
			cr_pflags.rpc_id(1, _local_flags())


func _bind_player() -> void:
	if main.player == null or _combat != null:
		return
	_combat = PlayerCombat.new()
	_combat.name = "Combat"
	_combat.player = main.player
	_combat.net = self
	main.player.add_child(_combat)
	main.player.combat = _combat
	main.player.vitality.player_defeated.connect(func(_p: Vector3) -> void:
		_overlay_color = Color(0, 0, 0)
		_overlay_a = 1.6)  # faint: fade to black, wake ashore


func _local_flags() -> int:
	if _combat == null:
		return 0
	return (1 if _combat.sneaking else 0) | (2 if _combat.has_bait() else 0) \
			| (4 if _combat.has_light() else 0) | (8 if _combat.holding_fish() else 0)


@rpc("any_peer", "call_remote", "unreliable")
func cr_pflags(flags: int) -> void:
	_pflags[main.multiplayer.get_remote_sender_id()] = flags


## Everyone the creatures can perceive, as plain data.
func _players() -> Array:
	var out := []
	var p: Player = main.player
	if p != null and not p.vitality.is_defeated:
		out.append({"id": local_id(), "pos": p.position, "speed": p.horizontal_speed,
			"sneaking": _combat != null and _combat.sneaking, "sprinting": p.horizontal_speed > 5.5,
			"in_water": p.swimming, "has_bait": _combat != null and _combat.has_bait(),
			"has_light": _combat != null and _combat.has_light(), "holding_fish": _combat != null and _combat.holding_fish()})
	for id in main.remotes:
		var rp: Node3D = main.remotes[id]
		var prev: Array = _ppos.get(id, [rp.position, 0.0])
		var f: int = _pflags.get(id, 0)
		var water_y: float = main.sky.water_level_m()
		out.append({"id": id, "pos": rp.position, "speed": prev[1], "sneaking": f & 1 != 0,
			"sprinting": float(prev[1]) > 5.5, "in_water": rp.position.y + 0.75 < water_y,
			"has_bait": f & 2 != 0, "has_light": f & 4 != 0, "holding_fish": f & 8 != 0})
	return out


func _context() -> Dictionary:
	var players := _players()
	var lights := []
	for lp: Vector3i in main.world._lights.keys():
		var wp := (Vector3(lp) + Vector3.ONE * 0.5) * VoxelWorld.VS
		for pl: Dictionary in players:
			if wp.distance_squared_to(pl.pos) < 2500.0:
				lights.append(wp)
				break
	for pl: Dictionary in players:
		if pl.has_light:
			lights.append(pl.pos + Vector3.UP * 1.2)
	# Placed light sources: lantern posts, campfires, furnaces, smokehouses.
	var em := EntityManager.current
	if em != null:
		for e: WorldEntity in em.entities.values():
			if e.emits_light():
				for pl: Dictionary in players:
					if e.position.distance_squared_to(pl.pos) < 3600.0:
						lights.append(e.position + Vector3.UP * 0.8)
						break
	var night: float = main.sky.night_factor()
	return {"players": players, "lights": lights, "water_y": main.sky.water_level_m(),
		"night": night, "darkness": night, "difficulty": difficulty}


func _simulate(dt: float) -> void:
	# Remote player speeds (for noise) from position deltas.
	for id in main.remotes:
		var rp: Node3D = main.remotes[id]
		var prev: Array = _ppos.get(id, [rp.position, 0.0])
		var sp: float = Vector2(rp.position.x - prev[0].x, rp.position.z - prev[0].z).length() / dt
		_ppos[id] = [rp.position, lerpf(float(prev[1]), sp, 0.3)]
	var ctx := _context()
	for c: Creature in creatures.values():
		if is_instance_valid(c):
			if c.has_meta("pin") and c.state != Creature.State.DEAD:
				continue   # dev checks: hold still
			c.simulate(dt, ctx)
			if c.state == Creature.State.DEAD and not c.has_meta("granted"):
				c.set_meta("granted", true)
				_grant(c.last_attacker, c.drops())
				if c is BarnacledHulk and hulk != null and hulk.has_method("on_hulk_slain"):
					hulk.on_hulk_slain(c.last_attacker)
				elif c is AbyssalSiren and siren != null:
					siren.on_siren_slain(c.last_attacker)
				elif c is CalderaShell and caldera != null:
					caldera.on_caldera_slain(c.last_attacker)
				elif c is BoreanGoreFin and borean != null:
					borean.on_borean_slain(c.last_attacker)
				elif c is TideSovereign and maelstrom != null:
					maelstrom.on_sovereign_slain(c.last_attacker)
				if main != null and main.get("player") != null:
					main.player.quest_event(QuestDef.ObjectiveType.DEFEAT_ENEMY, c.kind)
	_gull_thieves(dt, ctx)


# ---------------------------------------------------------------- spawning

func _count(kind: StringName, near: Vector3, r: float) -> int:
	var n := 0
	for c: Creature in creatures.values():
		if c.kind == kind and (r <= 0.0 or c.position.distance_to(near) < r):
			n += 1
	return n


func spawn(kind: StringName, pos: Vector3, cid := -1) -> Creature:
	var c: Creature
	match kind:
		&"crab": c = TideCrab.new()
		&"gull": c = Gull.new()
		&"eel": c = CaveEel.new()
		&"hare": c = CoastalHare.new()
		&"seal": c = HarbourSeal.new()
		&"puffin": c = Puffin.new()
		&"otter": c = SeaOtter.new()
		&"heron": c = GreyHeron.new()
		&"whale": c = MigratingWhale.new()
		&"fox": c = RedFox.new()
		&"stoat": c = Stoat.new()
		&"rat": c = ShoreRat.new()
		&"eagle": c = SeaEagle.new()
		&"mudclaw": c = MudClaw.new()
		&"mudbrute": c = MudClaw.new(true)
		&"gloomcrawler": c = GloomCrawler.new()
		&"reaver": c = SeaReaver.new()
		&"reaver_harpooner": c = SeaReaver.new(true)
		&"barnacled_hulk": c = BarnacledHulk.new()
		&"abyssal_siren": c = AbyssalSiren.new()
		&"abyssal_angler": c = AbyssalAngler.new()
		&"caldera_shell": c = CalderaShell.new()
		&"borean_gore_fin": c = BoreanGoreFin.new()
		&"tide_sovereign": c = TideSovereign.new()
		_: return null
	if cid < 0:
		cid = _next_id
		_next_id += 1
	c.name = "%s_%d" % [kind, cid]
	add_child(c)
	c.setup(cid, self, pos, is_authority())
	c.max_hp = CombatMath.creature_hp(c.max_hp, difficulty)
	c.hp = c.max_hp
	creatures[cid] = c
	return c


func despawn(c: Creature) -> void:
	creatures.erase(c.cid)
	c.queue_free()


func _ensure_column(x: int, z: int) -> void:
	var col := Vector2i(x >> 5, z >> 5)
	if not main.world.store.is_column_generated(col):
		main.world.store.generate_column(col)


func _spawn_tick() -> void:
	var players := _players()
	var gen: WorldGen = main.world.gen
	var water_y: float = main.sky.water_level_m()
	var vs := VoxelWorld.VS
	var night: float = main.sky.night_factor()
	# Despawn far-away creatures.
	for c: Creature in creatures.values():
		var near := false
		for pl: Dictionary in players:
			if c.position.distance_to(pl.pos) < (40.0 if c.kind in [&"eel", &"gloomcrawler"] else wildlife.despawn_distance(c.kind)):
				near = true
				break
		if not near:
			despawn(c)
	for pl: Dictionary in players:
		var pp: Vector3 = pl.pos
		# Tide-crabs on exposed flats while the tide is below mid.
		if water_y < VoxelWorld.SEA_MID * vs and _count(&"crab", Vector3.ZERO, 0) < CAP[&"crab"] and _count(&"crab", pp, 35.0) < 5:
			for t in 6:
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(8.0, 30.0)
				var x := floori((pp.x + cos(a) * r) / vs)
				var z := floori((pp.z + sin(a) * r) / vs)
				var h := gen.col_h(x, z)
				var top := (h + 1) * vs
				if gen.col_k(x, z) == WorldGen.Kind.BEACH and top > water_y + 0.05 and h < gen.sea_high:
					_ensure_column(x, z)
					var c := spawn(&"crab", Vector3((x + 0.5) * vs, top, (z + 0.5) * vs))
					var g := c.ground_under(c.position, 1.0, 1.0)
					if is_nan(g) or g < water_y:
						despawn(c)
					else:
						c.position.y = g
						c.home = c.position
					break
		# Gull flocks by day.
		if night < 0.4 and _count(&"gull", pp, 45.0) == 0 and _count(&"gull", Vector3.ZERO, 0) + 4 <= CAP[&"gull"]:
			var a := _rng.randf() * TAU
			var center := pp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(10.0, 18.0)
			var ground := maxf(water_y, (gen.col_h(floori(center.x / vs), floori(center.z / vs)) + 1) * vs)
			center.y = ground
			var n := _rng.randi_range(4, 5)
			for i in n:
				var g := spawn(&"gull", center + Vector3(0, 8, 0)) as Gull
				g.flock_center = center
				g.circle_r = _rng.randf_range(5.0, 9.0)
				g.altitude = _rng.randf_range(6.0, 9.0)
				g.angle = TAU * i / n
				g.set_meta("flock", Vector3i(center))
		# Cave eels: flooded water under a roof, after dark (Undertow: always). Never Cozy.
		if CombatMath.hostiles_allowed(difficulty) and (night > 0.5 or difficulty == CombatMath.Difficulty.UNDERTOW) \
				and _count(&"eel", Vector3.ZERO, 0) < CAP[&"eel"] and _count(&"eel", pp, 25.0) < 2:
			var pvx := floori(pp.x / vs)
			var pvz := floori(pp.z / vs)
			if gen.col_h(pvx, pvz) > floori(pp.y / vs) + 8:   # the player is under rock: a cave
				var home := _find_cave_water(pp, water_y)
				if home != Vector3.INF and not Perception.is_lit(home, _context().lights):
					spawn(&"eel", home)
		# Gloom-Crawlers: on cavern ceilings deep under rock, any hour (caves are always dark).
		if CombatMath.hostiles_allowed(difficulty) and _count(&"gloomcrawler", Vector3.ZERO, 0) < CAP[&"gloomcrawler"] 				and _count(&"gloomcrawler", pp, 30.0) < (3 if difficulty == CombatMath.Difficulty.UNDERTOW else 2) 				and _rng.randf() < 0.35:
			var pvx := floori(pp.x / vs)
			var pvz := floori(pp.z / vs)
			if gen.col_h(pvx, pvz) > floori(pp.y / vs) + 14:   # well under rock: a cavern or mine
				var at := find_cave_ceiling(pp)
				if at != Vector3.INF and not Perception.is_lit(at, _context().lights, GloomCrawler.KEEP_OFF_LIGHT):
					var gc := spawn(&"gloomcrawler", at) as GloomCrawler
					gc.cling(at)
	wildlife.spawn_tick(players)
	camps.spawn_tick(players)
	outposts.spawn_tick(players)
	hulk.spawn_tick(players)
	siren.spawn_tick(players)
	caldera.spawn_tick(players)
	borean.spawn_tick(players)
	maelstrom.spawn_tick(players)
	for pl in players:
		if siren != null: siren.check_discovery(pl.pos)
		if caldera != null: caldera.check_discovery(pl.pos)
		if borean != null: borean.check_discovery(pl.pos)
		if maelstrom != null: maelstrom.check_discovery(pl.pos)


## The underside of a cavern ceiling near `pp` (but not right overhead), with a clear 2 m+
## drop to the floor, or INF.
func find_cave_ceiling(pp: Vector3) -> Vector3:
	var vs := VoxelWorld.VS
	var w: VoxelWorld = main.world
	var gen: WorldGen = w.gen
	for t in 20:
		var x := floori(pp.x / vs) + _rng.randi_range(-55, 55)
		var z := floori(pp.z / vs) + _rng.randi_range(-55, 55)
		if Vector2(x * vs - pp.x, z * vs - pp.z).length() < 6.0:
			continue
		_ensure_column(x, z)
		var y := floori(pp.y / vs) + 1
		if w.get_voxel(x, y, z) != 0:
			continue
		var floor_y := y
		while floor_y > 1 and w.get_voxel(x, floor_y - 1, z) == 0 and y - floor_y < 40:
			floor_y -= 1
		var top := y
		while top < y + 50 and w.get_voxel(x, top + 1, z) == 0:
			top += 1
		if top >= y + 50 or top - floor_y < 12 or gen.col_h(x, z) < top + 6:
			continue
		if floor_y * vs < main.sky.water_level_m():
			continue          # flooded: the eels' water
		return Vector3((x + 0.5) * vs, (top + 1) * vs, (z + 0.5) * vs)
	return Vector3.INF


## A flooded cell under a natural roof near `pp`, or INF.
func _find_cave_water(pp: Vector3, water_y: float) -> Vector3:
	var vs := VoxelWorld.VS
	var gen: WorldGen = main.world.gen
	var wy := floori(water_y / vs)
	for t in 24:
		var x := floori(pp.x / vs) + _rng.randi_range(-30, 30)
		var z := floori(pp.z / vs) + _rng.randi_range(-30, 30)
		var y := wy - _rng.randi_range(2, 5)
		if y < 2:
			continue
		_ensure_column(x, z)
		var w: VoxelWorld = main.world
		if w.get_voxel(x, y, z) == 0 and w.get_voxel(x, y - 1, z) == 0 and w.get_voxel(x + 1, y, z) == 0 \
				and gen.col_h(x, z) > y + 8:
			var p := Vector3(x + 0.5, y + 0.5, z + 0.5) * vs
			if p.distance_to(pp) > 2.5:
				return p
	return Vector3.INF


## Gulls steal from players who stand still holding a raw fish (not on Cozy).
func _gull_thieves(dt: float, ctx: Dictionary) -> void:
	if not CombatMath.hostiles_allowed(difficulty):
		return
	for pl: Dictionary in ctx.players:
		var still: float = _still_with_fish.get(pl.id, 0.0)
		still = still + dt if pl.holding_fish and pl.speed < 0.5 else 0.0
		_still_with_fish[pl.id] = still
		if still < Gull.STEAL_PATIENCE:
			continue
		for c: Creature in creatures.values():
			if c is Gull and c.state == Creature.State.WANDER and c.position.distance_to(pl.pos) < 16.0:
				c.target_id = pl.id
				c.set_state(Creature.State.WINDUP)
				_still_with_fish[pl.id] = -6.0  # one swoop at a time
				break


# ---------------------------------------------------------------- snapshots

func _pack() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for c: Creature in creatures.values():
		a.append_array([c.cid, KINDS.find(c.kind), c.position.x, c.position.y, c.position.z, c.yaw,
			c.state, c.hp / maxf(c.max_hp, 0.001)])
	return a


@rpc("authority", "call_remote", "unreliable_ordered")
func cr_snapshot(a: PackedFloat32Array) -> void:
	if not _world_ready():
		return
	var seen := {}
	for i in range(0, a.size(), 8):
		var cid := int(a[i])
		seen[cid] = true
		var c: Creature = creatures.get(cid)
		var pos := Vector3(a[i + 2], a[i + 3], a[i + 4])
		if c == null:
			c = spawn(KINDS[int(a[i + 1])], pos, cid)
		c.apply_net(pos, a[i + 5], int(a[i + 6]), a[i + 7])
	for cid in creatures.keys():
		if not seen.has(cid):
			creatures[cid].queue_free()
			creatures.erase(cid)


# ---------------------------------------------------------------- combat

## Local swing (any peer). Returns the number of creatures struck (for local feedback).
func local_swing(origin: Vector3, fwd: Vector3, stats: Dictionary, in_water: bool) -> int:
	var hits := 0
	for c: Creature in creatures.values():
		if c.state == Creature.State.DEAD:
			continue
		if not CombatMath.in_swing_arc(origin, fwd, c.position + Vector3.UP * 0.2, float(stats.reach_m), 120.0, c.radius):
			continue
		hits += 1
		c.flash()
		var dmg := CombatMath.outgoing_damage(stats, c.is_staggered(), in_water)
		var pwr: float = float(stats.get("stagger_power", 1.0)) * float(stats.get("stagger_mult", 1.0))

		# Harpoon sweet spot tip bonus
		var dist := origin.distance_to(c.position)
		var is_sweet_spot := CombatMath.is_harpoon_sweet_spot(dist, int(stats.get("weapon_type", 0)))
		if is_sweet_spot:
			dmg *= CombatMath.HARPOON_SWEET_SPOT_MULT
			pwr *= 1.4
			if main != null and main.hud != null:
				main.hud.show_toast("Clean Pierce · Sweet Spot!")

		CombatAudio.play_sound("hit_shell" if c.is_armored() else "hit_flesh", c.position)
		var p_parent: Node3D = c.get_parent() as Node3D
		if p_parent != null:
			CombatFX.spawn_hit_sparks(p_parent, c.position + Vector3.UP * 0.3, (c.position - origin).normalized(), c.is_armored(), stats.get("is_finisher", false) or is_sweet_spot)

		if is_authority():
			_apply_hit(c, dmg, origin, pwr, local_id())
		else:
			cr_hit.rpc_id(1, c.cid, dmg, origin, pwr)
	return hits


## Local AOE strike (e.g. plunging slam shockwave). Returns number of creatures struck.
func local_aoe_strike(center: Vector3, radius: float, stats: Dictionary, in_water: bool = false) -> int:
	var hits := 0
	for c: Creature in creatures.values():
		if c.state == Creature.State.DEAD:
			continue
		var dist := center.distance_to(c.position)
		if dist > radius + c.radius:
			continue
		hits += 1
		c.flash()
		var dmg := CombatMath.outgoing_damage(stats, c.is_staggered(), in_water)
		var pwr: float = float(stats.get("stagger_power", 1.0)) * float(stats.get("stagger_mult", 1.0))

		CombatAudio.play_sound("hit_shell" if c.is_armored() else "hit_flesh", c.position)
		var p_parent: Node3D = c.get_parent() as Node3D
		if p_parent != null:
			CombatFX.spawn_hit_sparks(p_parent, c.position + Vector3.UP * 0.3, (c.position - center).normalized(), c.is_armored(), true)

		if is_authority():
			_apply_hit(c, dmg, center, pwr, local_id())
		else:
			cr_hit.rpc_id(1, c.cid, dmg, center, pwr)
	return hits


func _apply_hit(c: Creature, dmg: float, from: Vector3, power: float, attacker: int) -> void:
	if c.on_hit(dmg, from, power, attacker):
		stats_hits += 1


@rpc("any_peer", "call_remote", "reliable")
func cr_hit(cid: int, dmg: float, from: Vector3, power: float) -> void:
	if not is_authority():
		return
	var sender := main.multiplayer.get_remote_sender_id()
	var c: Creature = creatures.get(cid)
	var rp: Node3D = main.remotes.get(sender)
	if c == null or rp == null:
		return
	# Validate: close enough (generous for latency) and a sane damage number.
	if rp.position.distance_to(c.position) > 7.0 or dmg > 80.0:
		return
	_apply_hit(c, dmg, from, clampf(power, 0.0, 3.0), sender)


## Host: creature `c` hits player `pid` for `base` damage (difficulty-scaled).
func hurt_player(pid: int, base: float, from: Vector3, c: Creature) -> void:
	var amount := CombatMath.incoming_damage(base, difficulty)
	if pid == local_id() and main.player != null:
		_local_hurt(amount, from, c.cid)
	elif main.is_net and main.multiplayer.multiplayer_peer != null and main.remotes.has(pid):
		cr_hurt.rpc_id(pid, amount, from, c.cid)


@rpc("authority", "call_remote", "reliable")
func cr_hurt(amount: float, from: Vector3, cid: int) -> void:
	_local_hurt(amount, from, cid)


func _local_hurt(amount: float, from: Vector3, cid: int) -> void:
	if _combat == null:
		return
	var res := _combat.receive_hit(amount, from, cid)
	var p_pos := _combat.player.position if _combat.player != null else Vector3.ZERO
	match res:
		"dodged":
			CombatAudio.play_sound("dodge", p_pos)
			if main.hud != null:
				main.hud.show_toast("Dodged!")
		"parried":
			CombatAudio.play_sound("parry", p_pos)
			if _combat.player != null and _combat.player.get_parent() != null:
				CombatFX.spawn_parry_spark(_combat.player.get_parent() as Node3D, p_pos + Vector3.UP * 1.0)
			if main.hud != null:
				main.hud.show_toast("Parried! Riposte ready - strike now!")
		"blocked":
			CombatAudio.play_sound("block", p_pos)
			if main.hud != null:
				main.hud.show_toast("Blocked!")
		"guard_broken":
			CombatAudio.play_sound("poise_break", p_pos)
			if main.hud != null:
				main.hud.show_toast("Guard Broken!")
			_overlay_color = Color(0.7, 0.4, 0.1)
			_overlay_a = 0.5
		_:
			CombatAudio.play_sound("hit_flesh", p_pos)
			stats_hurt += amount
			_overlay_color = Color(0.6, 0.05, 0.05)
			_overlay_a = 0.45


func report_parry(cid: int) -> void:
	if is_authority():
		var c: Creature = creatures.get(cid)
		if c != null:
			c.on_parried()
	else:
		cr_parry.rpc_id(1, cid)


@rpc("any_peer", "call_remote", "reliable")
func cr_parry(cid: int) -> void:
	var c: Creature = creatures.get(cid)
	if is_authority() and c != null and c.target_id == main.multiplayer.get_remote_sender_id():
		c.on_parried()


# ---------------------------------------------------------------- non-combat answers

## Gull `g` snatches a fish from player `pid`.
func steal_fish(pid: int, _g: Creature) -> void:
	if pid == local_id():
		_lose_fish()
	elif main.remotes.has(pid):
		cr_steal.rpc_id(pid)


@rpc("authority", "call_remote", "reliable")
func cr_steal() -> void:
	_lose_fish()


func _lose_fish() -> void:
	if _combat == null or not _combat.holding_fish():
		return
	var slot: ItemSlot = main.player.inventory.get_active_item()
	var def: ItemDef = ItemDB.get_item(slot.item_id)
	main.player.inventory.remove_item(slot.item_id, 1)
	main.hud.show_toast("A gull snatched your %s!" % (def.name if def != null else "fish"))


func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("interact") or main.player == null or _combat == null:
		return
	# Catch a lured crab by hand: costs one bait.
	for c: Creature in creatures.values():
		if c is TideCrab and c.state == Creature.State.LURED and c.position.distance_to(main.player.position) < 1.8 \
				and _combat.has_bait():
			get_viewport().set_input_as_handled()
			var slot: ItemSlot = main.player.inventory.get_active_item()
			main.player.inventory.remove_item(slot.item_id, 1)
			if is_authority():
				catch_crab(c.cid, local_id())
			else:
				cr_catch.rpc_id(1, c.cid)
			return
	if _wild_interact():
		get_viewport().set_input_as_handled()


## Wildlife answers that need F: offering a fish to an otter, filling in a fox den.
func _wild_interact() -> bool:
	var p: Player = main.player
	if p.is_seated():
		return false
	if _combat.holding_fish() and p.horizontal_speed < 1.0:
		for c: Creature in creatures.values():
			if c is SeaOtter and not (c as SeaOtter).is_friend() and c.state != Creature.State.FLEE 					and c.position.distance_to(p.position) < 4.0:
				var slot: ItemSlot = p.inventory.get_active_item()
				p.inventory.remove_item(slot.item_id, 1)
				if is_authority():
					befriend_otter(c.cid, local_id())
				else:
					cr_befriend.rpc_id(1, c.cid)
				main.hud.show_toast("The otter takes the fish from your hand. You've made a friend!")
				return true
	if wildlife.nearest_den(p.position, 2.6) >= 0:
		if is_authority():
			wildlife.fill_den(p.position)
		else:
			cr_fill_den.rpc_id(1, p.position)
		main.hud.show_toast("You fill in the den. The foxes will move on to a wood further from your farm.")
		return true
	return false


func befriend_otter(cid: int, pid: int) -> void:
	var c: Creature = creatures.get(cid)
	if c is SeaOtter:
		(c as SeaOtter).befriend(pid)
		wildlife.remember_otter_friend(pid)


@rpc("any_peer", "call_remote", "reliable")
func cr_befriend(cid: int) -> void:
	if is_authority():
		befriend_otter(cid, main.multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func cr_fill_den(pos: Vector3) -> void:
	if not is_authority():
		return
	var rp: Node3D = main.remotes.get(main.multiplayer.get_remote_sender_id())
	if rp != null and rp.position.distance_to(pos) < 4.0:
		wildlife.fill_den(pos)


## Host: items (and a note) for one player from the wildlife (otter gifts).
func wild_gift(pid: int, items: Array, toast: String) -> void:
	_grant(pid, items)
	if pid == local_id():
		main.hud.show_toast(toast)
	elif main.remotes.has(pid):
		cr_toast.rpc_id(pid, toast)


## Host: tell every player about a raid (the village bell).
func wild_alert(text: String) -> void:
	if main.hud != null and main.player != null:
		main.hud.show_toast(text)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		cr_toast.rpc(text)


@rpc("authority", "call_remote", "reliable")
func cr_toast(text: String) -> void:
	if main.hud != null:
		main.hud.show_toast(text)


## Host: a bell rang; let every client see and hear it.
func broadcast_bell(coord: Vector3i, at: Vector3, text: String) -> void:
	if main.is_net and main.multiplayer.multiplayer_peer != null and is_authority():
		cr_bell.rpc(coord, at, text)


@rpc("authority", "call_remote", "reliable")
func cr_bell(coord: Vector3i, at: Vector3, text: String) -> void:
	var em := EntityManager.current
	var b: WorldEntity = em.entities.get(coord) if em != null else null
	if b is VillageBellEntity:
		(b as VillageBellEntity).play_ring(at, text)


func broadcast_dens(list: Array) -> void:
	if main.is_net and main.multiplayer.multiplayer_peer != null and is_authority():
		cr_dens.rpc(list)


@rpc("authority", "call_remote", "reliable")
func cr_dens(list: Array) -> void:
	wildlife.set_dens(list)


func catch_crab(cid: int, pid: int) -> bool:
	var c: Creature = creatures.get(cid)
	if c == null or not (c is TideCrab):
		return false
	despawn(c)
	_grant(pid, [[&"shore_crab", 1]])
	return true


@rpc("any_peer", "call_remote", "reliable")
func cr_catch(cid: int) -> void:
	if is_authority():
		catch_crab(cid, main.multiplayer.get_remote_sender_id())


func _grant(pid: int, items: Array) -> void:
	if items.is_empty() or pid == 0 or main.session == null:
		return
	if pid == local_id() and main.player != null:
		main.session.grant_items(items)
	elif main.remotes.has(pid):
		main.session.grant_items.rpc_id(pid, items)


# ---------------------------------------------------------------- presentation

func _show_hints() -> void:
	if main.player == null:
		return
	for c: Creature in creatures.values():
		if not _hinted.has(c.kind) and c.position.distance_to(main.player.position) < 12.0 and c.hint() != "" \
				and c.hint_ready(main.player):
			_hinted[c.kind] = true
			main.hud.show_toast(c.hint())
			return


func _update_overlay(delta: float) -> void:
	if _overlay_a > 0.0:
		_overlay_a = maxf(0.0, _overlay_a - delta * 0.9)
	_overlay.color = Color(_overlay_color.r, _overlay_color.g, _overlay_color.b, clampf(_overlay_a, 0.0, 1.0))


# ---------------------------------------------------------------- dev checks
#   --solo --creaturecheck            spawns, kill + loot, hurt/dodge, Cozy, saved difficulty
#   --host --creaturecheck=host  /  --join --creaturecheck=client   co-op sync
#   --host --creaturecheck=fighthost  /  --join --creaturecheck=fightclient   co-op Mud-Claw fight
#   (add --port=N to both when another host already holds the default port)

var _check_started := false


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _kinds() -> Dictionary:
	var d := {&"crab": 0, &"gull": 0, &"eel": 0}
	for c: Creature in creatures.values():
		d[c.kind] = d.get(c.kind, 0) + 1
	return d


func _creature_check(role: String) -> void:
	var p: Player = main.player
	if role == "fighthost":
		# Co-op Mud-Claw fight: a swarmer and a brute right beside the joined player.
		while main.remotes.is_empty():
			await _wait(0.5)
		var rp: Node3D = main.remotes.values()[0]
		while rp.position.length() < 1.0:      # no position from the peer yet
			await _wait(0.5)
		await _wait(2.0)
		var claws := []
		for k in 2:
			var at: Vector3 = rp.position + Vector3(2.0 + k * 1.5, 0.2, 0.5)
			var mc := spawn(&"mudbrute" if k == 1 else &"mudclaw", at) as MudClaw
			mc.dome = at
			mc.camp_center = at
			mc.roused = true
			claws.append(mc)
		print("[fight-host] spawned claws %s beside peer %d" % [claws.map(func(c: Creature) -> int: return c.cid), main.remotes.keys()[0]])
		for k in 12:
			await _wait(1.0)
			print("[fight-host] t=%d %s" % [k, claws.map(func(c: Variant) -> String: return ("%s %s hp %.0f at %s" % [c.kind, Creature.STATE_NAMES[c.state], c.hp, c.position]) if is_instance_valid(c) else "freed")])
		if not is_instance_valid(claws[1]) or not is_instance_valid(claws[0]):
			print("[fight-host] hits_applied=%d claws freed" % stats_hits)
			get_tree().quit()
			return
		var brute: Creature = claws[1]
		print("[fight-host] hits_applied=%d swarmer_alive=%s brute_hp=%s" % [stats_hits,
				creatures.has(claws[0].cid), "%.0f/%.0f" % [brute.hp, brute.max_hp] if is_instance_valid(brute) and creatures.has(brute.cid) else "dead"])
		get_tree().quit()
		return
	if role == "fightclient":
		var t := 0.0
		var swarm: Creature = null
		var brute: Creature = null
		while (swarm == null or brute == null) and t < 20.0:
			for c: Creature in creatures.values():
				if c.kind == &"mudclaw":
					swarm = c
				elif c.kind == &"mudbrute":
					brute = c
			await _wait(0.25)
			t += 0.25
		print("[fight-client] sees swarmer=%s brute=%s" % [swarm != null, brute != null])
		if swarm == null or brute == null:
			get_tree().quit()
			return
		var hp0 := p.vitality.current_hp
		var sid := swarm.cid
		var stats := CombatMath.weapon_stats(ItemDB.get_item(&"rusty_cutlass"))
		var swings := 0
		var hits := 0
		for i in 14:
			var tgt: Creature = swarm if creatures.has(sid) else brute
			if not is_instance_valid(tgt):
				break
			var fwd := tgt.position - p.position
			fwd.y = 0.0
			if fwd.length() > 1.6:
				p.position = tgt.position - fwd.normalized() * 1.2 + Vector3.UP * 0.1
			hits += local_swing(p.position + Vector3.UP * 0.9, fwd.normalized(), stats, false)
			swings += 1
			await _wait(0.6)
		await _wait(1.5)
		print("[fight-client] swings=%d hits=%d swarmer_gone=%s brute_hp_ratio=%s hp %.1f -> %.1f hurt_taken=%.1f" % [
			swings, hits, not creatures.has(sid),
			"%.2f" % (brute.hp / brute.max_hp) if is_instance_valid(brute) and creatures.has(brute.cid) else "dead",
			hp0, p.vitality.current_hp, stats_hurt])
		get_tree().quit()
		return
	if role == "host":
		while main.remotes.is_empty():
			await _wait(0.5)
		await _wait(1.0)
		var crab := spawn(&"crab", p.position + Vector3(1.5, 0, 0))
		crab.set_meta("pin", true)
		var crab_id := crab.cid
		print("[creature-host] pinned crab %d at %s" % [crab_id, crab.position])
		await _wait(4.0)
		var cid: int = main.remotes.keys()[0]
		hurt_player(cid, 4.0, p.position, crab if is_instance_valid(crab) else spawn(&"gull", p.position + Vector3.UP * 6))
		await _wait(3.0)
		print("[creature-host] hits_applied=%d crab_alive=%s" % [stats_hits, creatures.has(crab_id)])
		get_tree().quit()
		return
	if role == "client":
		var target: Creature = null
		var t := 0.0
		while target == null and t < 15.0:
			for c: Creature in creatures.values():
				if c.has_meta("pin") or (c is TideCrab and c.position.distance_to(main.remotes[1].position) < 3.0):
					target = c
			await _wait(0.25)
			t += 0.25
		print("[creature-client] sees %d creatures %s; target=%s" % [creatures.size(), _kinds(), target.cid if target else -1])
		if target == null:
			get_tree().quit()
			return
		var crabs0 := p.inventory.get_item_count(&"shore_crab")
		var tid := target.cid
		p.position = target.position + Vector3(-1.0, 0.1, 0)
		await _wait(0.3)
		var hits := local_swing(p.position + Vector3.UP * 0.9, Vector3(1, 0, 0), CombatMath.weapon_stats(ItemDB.get_item(&"rusty_cutlass")), false)
		var hp0 := p.vitality.current_hp
		await _wait(3.5)
		print("[creature-client] swing_hits=%d target_state=%s gone=%s shore_crab +%d hp %.1f -> %.1f" % [
			hits, Creature.STATE_NAMES[target.state] if is_instance_valid(target) else "-",
			not creatures.has(tid), p.inventory.get_item_count(&"shore_crab") - crabs0, hp0, p.vitality.current_hp])
		get_tree().quit()
		return
	if role.begins_with("shots"):
		var dir := "/tmp/claude-1000/-home-clayton-Games-brines-hollow/46bd671c-bdec-436a-a831-87f318a07632/scratchpad/agentC"
		DirAccess.make_dir_recursive_absolute(dir)
		await _wait(2.0)
		for c: Creature in creatures.values():
			despawn(c)
		p.input_enabled = false
		if main.hud.get("help") != null:
			main.hud.help.visible = false
		# Stage on an exposed beach, looking out to sea (downhill).
		var vs := VoxelWorld.VS
		var gen: WorldGen = main.world.gen
		var c0 := Vector3i(p.position / vs)
		var spot := Vector3i(-1, -1, -1)
		for r in range(4, 600, 3):
			for k in 24:
				var a := TAU * k / 24.0
				var x := c0.x + int(cos(a) * r)
				var z := c0.z + int(sin(a) * r)
				var h := gen.col_h(x, z)
				if gen.col_k(x, z) == WorldGen.Kind.BEACH and (h + 1) * vs > main.sky.water_level_m() + 0.3 \
						and gen.col_h(x + 12, z) <= h + 1 and gen.col_h(x - 12, z) <= h + 3:
					spot = Vector3i(x, h + 1, z)
					break
			if spot.x >= 0:
				break
		var sea_dir := Vector3(1, 0, 0)
		if spot.x >= 0:
			_ensure_column(spot.x, spot.z)
			p.position = Vector3(spot) * vs + Vector3(0.09, 0, 0.09)
			var lo := INF
			for k in 16:
				var a := TAU * k / 16.0
				var hh := gen.col_h(spot.x + int(cos(a) * 30), spot.z + int(sin(a) * 30))
				if hh < lo:
					lo = hh
					sea_dir = Vector3(cos(a), 0, sin(a))
		p.rig.yaw = atan2(-sea_dir.x, -sea_dir.z) + 0.5
		for i in 20:
			await get_tree().process_frame
		var fwd := -Basis(Vector3.UP, p.rig.yaw).z
		var side := Basis(Vector3.UP, p.rig.yaw).x
		for i in 3:
			var cr := spawn(&"crab", p.position + fwd * (2.2 + i * 0.7) + side * (i - 1) * 0.8)
			var g0 := cr.ground_under(cr.position, 1.5, 2.0)
			if not is_nan(g0):
				cr.position.y = g0
			cr.set_meta("pin", true)
		var crabs := creatures.values()
		(crabs[1] as Creature).set_state(Creature.State.WINDUP)
		for i in 5:
			var g := spawn(&"gull", p.position + fwd * 7.0 + Vector3(0, 4, 0)) as Gull
			g.flock_center = p.position + fwd * 7.0 + Vector3(0, -2.5, 0)
			g.circle_r = 3.0
			g.altitude = 4.5
			g.angle = TAU * i / 5.0
		p.rig.pitch = -0.2
		p.rig.dist = 3.5
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/creatures_shore.png")
		for c: Creature in creatures.values():
			despawn(c)
		var eel := spawn(&"eel", p.position + fwd * 3.0 + side * 0.8 + Vector3(0, 0.9, 0))
		eel.set_meta("pin", true)
		eel.yaw = atan2(-fwd.x, -fwd.z)
		eel.set_state(Creature.State.WINDUP)
		p.inventory.active_hotbar_index = 1
		p.rig.dist = 3.0
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/creatures_eel_windup.png")
		print("[creature-shots] saved to ", dir)
		get_tree().quit()
		return
	if role == "perf":
		# Full cap in front of the camera: 12 crabs, 12 gulls, 4 eels.
		await _wait(2.0)
		for c: Creature in creatures.values():
			despawn(c)
		var fwd := -Basis(Vector3.UP, p.rig.yaw).z
		for i in 12:
			var cr := spawn(&"crab", p.position + fwd * (3.0 + i * 0.4) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
			cr.set_meta("pin", true)
		for i in 12:
			var g := spawn(&"gull", p.position + fwd * 8.0 + Vector3(0, 6, 0)) as Gull
			g.flock_center = p.position + fwd * 8.0
			g.angle = TAU * i / 12.0
		for i in 4:
			spawn(&"eel", p.position + fwd * (4.0 + i) + Vector3(0, 0.5, 0)).set_meta("pin", true)
		var ctx := _context()
		var t0 := Time.get_ticks_usec()
		for i in 200:
			for c: Creature in creatures.values():
				c.simulate(SIM_DT, ctx)
		var sim_us := float(Time.get_ticks_usec() - t0) / 200.0
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		for i in 10:
			await RenderingServer.frame_post_draw
		var res := []
		for vis in [true, false]:
			for c: Creature in creatures.values():
				c.visible = vis
			await RenderingServer.frame_post_draw
			var g := []
			for f in 30:
				RenderingServer.force_draw(false)
				if f >= 8:
					g.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			g.sort()
			res.append(g[g.size() / 2])
		print("[creature-perf] %d creatures: AI %.3f ms per 20 Hz step (%.3f ms/frame avg), GPU %.2f ms with vs %.2f ms without (+%.2f ms)" % [
			creatures.size(), sim_us / 1000.0, sim_us / 1000.0 / 3.0, res[0], res[1], res[0] - res[1]])
		get_tree().quit()
		return
	if role == "cave":
		# Find flooded water under a natural roof (the sea cave) near the home island.
		var vs := VoxelWorld.VS
		var gen: WorldGen = main.world.gen
		var c0 := Vector3i(gen.spawn)
		var wyv := floori(main.sky.water_level_m() / vs) - 2
		var found := Vector3.INF
		for r in range(0, 900, 6):
			for k in maxi(1, r / 3):
				var a := TAU * k / maxi(1, r / 3)
				var x := c0.x + int(cos(a) * r)
				var z := c0.z + int(sin(a) * r)
				if gen.col_h(x, z) <= wyv + 10:
					continue
				_ensure_column(x, z)
				if main.world.get_voxel(x, wyv, z) == 0 and main.world.get_voxel(x, wyv + 3, z) == 0:
					found = Vector3(x + 0.5, wyv + 1, z + 0.5) * vs
					break
			if found != Vector3.INF:
				break
		if found == Vector3.INF:
			# Natural cave not in range: carve a flooded chamber under high ground nearby
			# (same rule applies to any cave below the waterline, natural or dug).
			for r in range(10, 400, 4):
				var x := c0.x + r
				var z := c0.z
				if gen.col_h(x, z) > wyv + 18:
					_ensure_column(x, z)
					for k in 4:
						main.world.store.dig_sphere(Vector3i(x + k * 9, wyv + 1, z), 8)
					found = Vector3(x + 0.5, wyv + 1, z + 0.5) * vs
					print("[creature-cave] carved a flooded chamber under the hill at %s" % Vector3i(x, wyv + 1, z))
					break
		print("[creature-cave] flooded cave cell: %s (water %.2f m, night %.2f)" % [found, main.sky.water_level_m(), main.sky.night_factor()])
		if found == Vector3.INF:
			get_tree().quit()
			return
		p.position = found
		var hp0 := p.vitality.current_hp
		var t := 0.0
		var first := -1.0
		while t < 14.0:
			await _wait(0.5)
			t += 0.5
			if first < 0.0 and _kinds()[&"eel"] > 0:
				first = t
			p.position = found  # stay put at the water's edge
		print("[creature-cave] eels=%d (first after %.1f s) states=%s, still player hp %.1f -> %.1f" % [
			_kinds()[&"eel"], first, creatures.values().filter(func(c): return c is CaveEel).map(func(c): return Creature.STATE_NAMES[c.state]),
			hp0, p.vitality.current_hp])
		# Now blunder into view in front of an eel at the water's edge.
		var eels := creatures.values().filter(func(c): return c is CaveEel)
		if not eels.is_empty():
			var e: CaveEel = eels[0]
			var hp1 := p.vitality.current_hp
			var seen := {}
			for i in 30:
				p.position = e.position + e.facing() * 2.0 + Vector3.UP * 0.2
				await _wait(0.2)
				seen[Creature.STATE_NAMES[e.state]] = true
			print("[creature-cave] in front of an eel: states seen %s, hp %.1f -> %.1f" % [seen.keys(), hp1, p.vitality.current_hp])
		get_tree().quit()
		return
	# Solo
	await _wait(5.0)
	print("[creature-solo] natural spawns after 5 s: %s (difficulty %s, water %.2f m, night %.2f)" % [
		_kinds(), CombatMath.DIFFICULTY_NAMES[difficulty], main.sky.water_level_m(), main.sky.night_factor()])
	var fwd := Vector3(sin(p.facing), 0, cos(p.facing))
	var crab := spawn(&"crab", p.position + fwd * 1.2)
	crab.set_meta("pin", true)
	var crab_id := crab.cid
	var crabs0 := p.inventory.get_item_count(&"shore_crab")
	var cut_slot := -1
	for i in p.inventory.slots.size():
		if not p.inventory.slots[i].is_empty() and p.inventory.slots[i].item_id == &"rusty_cutlass":
			cut_slot = i
	p.inventory.active_hotbar_index = cut_slot
	print("[creature-solo] cutlass in slot %d, weapon=%s" % [cut_slot, _combat.weapon_def().id if _combat.weapon_def() else &"none"])
	p.rig.yaw = p.facing + PI
	var st0 := p.vitality.current_stamina
	_combat.attack(_combat.weapon_def())
	await _wait(1.2)
	print("[creature-solo] swing: stamina %.0f -> %.0f, crab dead/gone=%s, shore_crab +%d" % [
		st0, p.vitality.current_stamina, not creatures.has(crab_id) or creatures[crab_id].state == Creature.State.DEAD,
		p.inventory.get_item_count(&"shore_crab") - crabs0])
	var eel := spawn(&"eel", p.position + fwd * 2.0)
	eel.set_meta("pin", true)
	var hp0 := p.vitality.current_hp
	hurt_player(local_id(), CaveEel.BITE, eel.position, eel)
	var hp1 := p.vitality.current_hp
	_combat.try_dodge()
	hurt_player(local_id(), CaveEel.BITE, eel.position, eel)
	print("[creature-solo] eel bite: hp %.1f -> %.1f; bite during dodge -> %.1f" % [hp0, hp1, p.vitality.current_hp])
	set_difficulty(CombatMath.Difficulty.COZY)
	_spawn_tick()
	print("[creature-solo] cozy: eels left=%d, cozy bite hp %.1f -> %.1f" % [_kinds()[&"eel"], p.vitality.current_hp,
		_bite_and_read(p)])
	print("[creature-solo] difficulty saved: %s" % FileAccess.file_exists(_diff_path()))
	set_difficulty(CombatMath.Difficulty.TIDEWATCH)
	get_tree().quit()


func _bite_and_read(p: Player) -> float:
	var c := spawn(&"crab", p.position + Vector3(3, 0, 0))
	hurt_player(local_id(), 6.0, c.position, c)
	return p.vitality.current_hp
