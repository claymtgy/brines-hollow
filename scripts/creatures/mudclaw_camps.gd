class_name MudClawCamps
extends Node
## Mud-Claw camps (planned by WorldGen.plan_camps, stamped into the terrain). Lives at
## /root/Main/Creatures/Camps on every peer.
##
## Host: when a player comes within RAISE_DIST of a camp that isn't cleared, its garrison
## (what's left of it) is spawned at the domes and the chest. Kills are counted per camp;
## once the whole garrison is beaten the camp is cleared for good (world state "camps") and
## every peer gets a banner. Camps are never planned on the home island or within ~300 m of
## the starter hut (see WorldGen.CAMP_MIN_HOME).
## Each character discovers camps on their own (profile key "camps"): a banner, and a mark
## on the sea chart.

const RAISE_DIST := 55.0
const DISCOVER_R := 45.0
const VS := VoxelWorld.VS

var net: Node                   # CreatureNet
var camps: Array = []           # WorldGen.camps records (voxel units)
var cleared := {}               # camp index -> true
var killed := {}                # camp index -> {kind: count}
var discovered := {}            # camp index -> true (this character)
var _gen: WorldGen
var _t := 0.0


func _ready() -> void:
	name = "Camps"
	var s: Node = net.main.get("session")
	if s != null:
		s.register_state(&"camps", _save_state, _load_state)


func _sync_gen() -> bool:
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		camps = _gen.camps
	return true


func center_m(i: int) -> Vector3:
	return (camps[i].center as Vector3) * VS


## What a camp starts with: a pack of swarmers and one brute.
func garrison(difficulty: int) -> Dictionary:
	match difficulty:
		CombatMath.Difficulty.COZY: return {&"mudclaw": 3, &"mudbrute": 1}
		CombatMath.Difficulty.UNDERTOW: return {&"mudclaw": 6, &"mudbrute": 1}
	return {&"mudclaw": 4, &"mudbrute": 1}


func remaining(i: int) -> Dictionary:
	var g := garrison(net.difficulty)
	var k: Dictionary = killed.get(i, {})
	var out := {}
	for kind: StringName in g:
		out[kind] = maxi(0, int(g[kind]) - int(k.get(String(kind), 0)))
	return out


func alive(i: int) -> Array:
	var out: Array = []
	for c: Creature in net.creatures.values():
		if c is MudClaw and (c as MudClaw).camp == i and c.state != Creature.State.DEAD:
			out.append(c)
	return out


## Host, from CreatureNet._spawn_tick.
func spawn_tick(players: Array) -> void:
	if not _sync_gen():
		return
	for i in camps.size():
		if cleared.has(i) or not alive(i).is_empty():
			continue
		var cm := center_m(i)
		var near := false
		for pl: Dictionary in players:
			if Vector2(pl.pos.x - cm.x, pl.pos.z - cm.z).length() < RAISE_DIST:
				near = true
				break
		if near:
			raise_garrison(i)


func raise_garrison(i: int) -> int:
	var rec: Dictionary = camps[i]
	var cm := center_m(i)
	var left := remaining(i)
	var domes: Array = rec.domes
	var n := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(i) + Time.get_ticks_msec()
	for kind: StringName in [&"mudbrute", &"mudclaw"]:
		for k in int(left.get(kind, 0)):
			var at: Vector3
			if kind == &"mudbrute":
				at = (Vector3(rec.chest) + Vector3(0.5, 0, 0.5)) * VS + Vector3((rec.gate as Vector2).x, 0, (rec.gate as Vector2).y) * 1.2
			else:
				at = (domes[k % domes.size()] as Vector3) * VS + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
			net._ensure_column(floori(at.x / VS), floori(at.z / VS))
			# on the camp floor (inside the dome, not on its roof)
			var c := net.spawn(kind, Vector3(at.x, cm.y + 0.3, at.z)) as MudClaw
			if c == null:
				continue
			var g := c.ground_under(c.position, 0.4, 1.2)
			if not is_nan(g):
				c.position.y = g
			c.camp = i
			c.camp_center = cm
			c.dome = Vector3(at.x, c.position.y, at.z)
			c.home = c.dome
			n += 1
	if n > 0:
		print("[camps] raised %d Mud-Claws at camp %d" % [n, i])
	return n


## Swarmers of camp `i` mid-attack (winding up or striking).
func attackers(i: int) -> int:
	var n := 0
	for c: MudClaw in alive(i):
		if not c.brute and c.state in [Creature.State.WINDUP, Creature.State.STRIKE]:
			n += 1
	return n


## Host: someone attacked or woke one of them: the whole camp turns out.
func rouse(i: int) -> void:
	for c: MudClaw in alive(i):
		c.roused = true


## Host: a Mud-Claw from camp `i` died.
func on_killed(i: int, c: MudClaw) -> void:
	if i < 0 or cleared.has(i):
		return
	var k: Dictionary = killed.get(i, {})
	k[String(c.kind)] = int(k.get(String(c.kind), 0)) + 1
	killed[i] = k
	var left := remaining(i)
	var total := 0
	for kind in left:
		total += int(left[kind])
	if total == 0:
		cleared[i] = true
		print("[camps] camp %d cleared" % i)
		if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
			camp_cleared.rpc(i)
		else:
			camp_cleared(i)


@rpc("authority", "call_local", "reliable")
func camp_cleared(i: int) -> void:
	cleared[i] = true
	if net.main.hud == null or not _sync_gen() or i >= camps.size():
		return
	var isle: String = net.main.atlas.name_of(int(camps[i].island)) if net.main.get("atlas") != null else ""
	var pp: Vector3 = net.main.player.position if net.main.player != null else Vector3.INF
	if pp.distance_to(center_m(i)) < 120.0:
		net.main.hud.show_banner("Mud-Claw camp cleared", "%s  ·  the camp chest is yours" % isle)
	else:
		net.main.hud.show_toast("A Mud-Claw camp on %s has been cleared." % isle)


## Every peer, each frame: discovery banners for this character.
func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	if net == null or net.main.player == null or not _sync_gen():
		return
	var s: Node = net.main.get("session")
	if s != null and s._pending_profile != null:
		return
	var pp: Vector3 = net.main.player.position
	for i in camps.size():
		if discovered.has(i):
			continue
		var cm := center_m(i)
		if Vector2(pp.x - cm.x, pp.z - cm.z).length() < DISCOVER_R:
			discovered[i] = true
			var isle: String = net.main.atlas.name_of(int(camps[i].island)) if net.main.get("atlas") != null else ""
			var sub := "cleared" if cleared.has(i) else ("hostile  ·  dozes by day" if CombatMath.hostiles_allowed(net.difficulty) else "timid on Cozy")
			net.main.hud.show_banner("Mud-Claw camp", "%s  ·  %s  ·  marked on your chart" % [isle, sub])


func chart_labels() -> Array:
	var out: Array = []
	if not _sync_gen():
		return out
	for i: int in discovered:
		if i < camps.size():
			out.append({"pos": center_m(i), "name": "Mud-Claw camp", "camp": true, "cleared": cleared.has(i)})
	return out


# ---------------------------------------------------------------- persistence

func _save_state() -> Variant:
	var k := {}
	for i: int in killed:
		k[str(i)] = killed[i]
	return {"cleared": cleared.keys(), "killed": k}


func _load_state(d: Variant) -> void:
	cleared = {}
	killed = {}
	if not (d is Dictionary):
		return
	for i in d.get("cleared", []):
		cleared[int(i)] = true
	var k: Dictionary = d.get("killed", {})
	for key in k:
		killed[int(key)] = k[key]


## This character's discoveries (profile key "camps").
func serialize_seen() -> Array:
	return discovered.keys()


func deserialize_seen(data: Variant) -> void:
	discovered = {}
	if data is Array:
		for i in data:
			discovered[int(i)] = true


# ---------------------------------------------------------------- dev check

## --campcheck[=SHOT_DIR]: where the camps are, the chest, the garrison, dozing by day, the
## night fight, light, the leash, and clearing a camp.
func run_check(shot_dir: String) -> void:
	var main: Node = net.main
	var p: Player = main.player
	p.input_enabled = false
	await get_tree().create_timer(1.0).timeout
	_sync_gen()
	var hut: Vector3 = Vector3(main.world.gen.starter.hut) * VS
	var far_ok := true
	print("[camps] %d camps planned" % camps.size())
	for i in camps.size():
		var d := Vector2(center_m(i).x - hut.x, center_m(i).z - hut.z).length()
		print("[camps] camp %d on island %d (%s), %.0f m from the hut" % [i, int(camps[i].island), main.atlas.name_of(int(camps[i].island)), d])
		if d < 300.0 or int(camps[i].island) == 0:
			far_ok = false
	print("[camps] every camp off the home island and 300 m+ from the hut: %s" % far_ok)
	if camps.is_empty():
		main.get_tree().quit()
		return
	var i := 0
	var cm := center_m(i)
	var g: Vector2 = camps[i].gate
	var gate := Vector3(g.x, 0, g.y)
	main.sky.time_of_day = 0.45
	_put(p, cm + gate * 14.0)
	main.hud.show_hud(false)
	await get_tree().create_timer(5.0).timeout
	var chest := false
	var cv: Vector3i = camps[i].chest
	for k: Vector3i in main.entities.entities:
		if Vector2(k.x - cv.x, k.z - cv.z).length() < 4.0 and main.entities.entities[k] is ChestEntity:
			chest = true
	print("[camps] camp chest in place: %s" % chest)
	var raised := alive(i)
	print("[camps] garrison raised: %d (%s)" % [raised.size(), raised.map(func(c: MudClaw) -> String: return String(c.kind))])
	# Daytime: stand still just inside the gate. Nobody should wake.
	_put(p, cm + gate * 3.5)
	await get_tree().create_timer(3.0).timeout
	var woke := alive(i).filter(func(c: MudClaw) -> bool: return c.roused).size()
	print("[camps] day, standing still inside the gate: %d awake" % woke)
	main.rig.yaw = atan2(gate.x, gate.z)
	main.rig.yaw = atan2(gate.x, gate.z)
	main.rig.pitch = -0.55
	main.rig.dist = 15.0
	if shot_dir != "":
		await main._shot(shot_dir, "camp_day")
	# A lantern keeps swarmers back (the brute ignores it).
	var sw: MudClaw = null
	for c: MudClaw in alive(i):
		if not c.brute:
			sw = c
	if sw != null:
		print("[camps] swarmer kept back by a held lantern: %s" % sw._repelled_by({"has_light": true, "dist": 3.0}, {"lights": []}))
	# Night: they come for you.
	main.sky.time_of_day = 0.92
	var hp0: float = p.vitality.current_hp
	var taken := 0.0
	for t in 20:   # 5 s, topping the player up so the fight keeps going
		await get_tree().create_timer(0.25).timeout
		taken += hp0 - p.vitality.current_hp
		p.vitality.current_hp = hp0
	var states := alive(i).map(func(c: MudClaw) -> String: return Creature.STATE_NAMES[c.state])
	print("[camps] night: states %s, damage taken standing still for 5 s: %.1f of %.0f hp, defeated %s" % [states, taken, hp0, p.vitality.is_defeated])
	if shot_dir != "":
		main.rig.pitch = -0.6
		main.rig.dist = 10.0
		main.sky.time_of_day = 0.79
		p.vitality.current_hp = hp0
		await get_tree().create_timer(0.3).timeout
		await main._shot(shot_dir, "camp_fight")
		main.sky.time_of_day = 0.92
	p.vitality.current_hp = p.vitality.get_max_hp()
	# Run for it: past the leash they give up and go home.
	_put(p, cm + gate * 40.0)
	await get_tree().create_timer(7.0).timeout
	var off := 0.0
	for c: MudClaw in alive(i):
		off = maxf(off, Vector2(c.position.x - cm.x, c.position.z - cm.z).length())
	print("[camps] after leaving: furthest Mud-Claw %.1f m from camp (leash %.0f), states %s" % [off, MudClaw.LEASH,
			alive(i).map(func(c: MudClaw) -> String: return Creature.STATE_NAMES[c.state])])
	# Beat the garrison: the camp is cleared and stays cleared.
	_put(p, cm + gate * 4.0)
	await get_tree().create_timer(1.0).timeout
	var plates0: int = p.inventory.get_item_count(&"chitin_plate")
	for c: MudClaw in alive(i):
		c.on_hit(999.0, p.position, 1.0, net.local_id())
	await get_tree().create_timer(2.0).timeout
	print("[camps] cleared: %s, chitin %d -> %d, saved %s" % [cleared.has(i), plates0, p.inventory.get_item_count(&"chitin_plate"), _save_state()])
	_put(p, cm + gate * 120.0)
	await get_tree().create_timer(3.0).timeout
	_put(p, cm + gate * 4.0)
	await get_tree().create_timer(3.0).timeout
	print("[camps] back at the cleared camp: %d Mud-Claws (want 0); chart %s" % [alive(i).size(), chart_labels()])
	main.get_tree().quit()


func _put(p: Player, at: Vector3) -> void:
	var gen: WorldGen = net.main.world.gen
	net._ensure_column(floori(at.x / VS), floori(at.z / VS))
	var y := gen.col_h(floori(at.x / VS), floori(at.z / VS)) + 1
	for yy in range(y + 12, y - 12, -1):
		if net.voxel(floori(at.x / VS), yy, floori(at.z / VS)) != 0:
			y = yy + 1
			break
	p.position = Vector3(at.x, y * VS + 0.05, at.z)
