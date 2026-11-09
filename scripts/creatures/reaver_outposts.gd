class_name ReaverOutposts
extends Node
## Sea-Reaver outposts (planned by WorldGen.plan_outposts, stamped into the terrain). Lives at
## /root/Main/Creatures/Outposts on every peer.
##
## Host: when a player comes within RAISE_DIST of an outpost that isn't captured, its full
## garrison stands to at their posts (one harpooner on the watchtower). While the War Horn
## Totem stands, a beaten garrison is back RESPAWN_SEC later, and the first time an outpost
## is roused the horn sounds and HORN_REINFORCE more reavers come running. Beat them and
## topple the totem (WarHornEntity, F) and the outpost is captured for good (world state
## "outposts"): no more reavers, and a bunk appears in the big tent as a forward base.
## Each character discovers outposts on their own (profile key "outposts").

const RAISE_DIST := 60.0
const DISCOVER_R := 50.0
const RESPAWN_SEC := 300.0
const HORN_REINFORCE := 2
const CLEAR_R := 30.0           # no reaver alive this close and the totem can be toppled
const VS := VoxelWorld.VS

static var current: ReaverOutposts

var net: Node                   # CreatureNet
var outposts: Array = []        # WorldGen.outposts records (voxel units)
var captured := {}              # index -> true
var discovered := {}            # index -> true (this character)
var _respawn_at := {}           # host: index -> msec when a beaten garrison regrows
var _horned := {}               # host: index -> true once the horn has sounded this muster
var _gen: WorldGen
var _t := 0.0


func _ready() -> void:
	name = "Outposts"
	current = self
	var s: Node = net.main.get("session")
	if s != null:
		s.register_state(&"outposts", _save_state, _load_state)


func _sync_gen() -> bool:
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		outposts = _gen.outposts
	return true


func center_m(i: int) -> Vector3:
	return (outposts[i].center as Vector3) * VS


## The muster: cutlass reavers and harpooners.
func garrison(difficulty: int) -> Dictionary:
	match difficulty:
		CombatMath.Difficulty.COZY: return {&"reaver": 3, &"reaver_harpooner": 1}
		CombatMath.Difficulty.UNDERTOW: return {&"reaver": 5, &"reaver_harpooner": 3}
	return {&"reaver": 4, &"reaver_harpooner": 2}


func alive(i: int) -> Array:
	var out: Array = []
	for c: Creature in net.creatures.values():
		if c is SeaReaver and (c as SeaReaver).outpost == i and c.state != Creature.State.DEAD:
			out.append(c)
	return out


func index_near(cell: Vector3i, r: float = 40.0) -> int:
	if not _sync_gen():
		return -1
	for i in outposts.size():
		var c: Vector3 = outposts[i].center
		if Vector2(c.x - cell.x, c.z - cell.z).length() < r / VS:
			return i
	return -1


## Host, from CreatureNet._spawn_tick.
func spawn_tick(players: Array) -> void:
	if not _sync_gen():
		return
	var now := Time.get_ticks_msec()
	for i in outposts.size():
		if captured.has(i) or not alive(i).is_empty():
			continue
		if int(_respawn_at.get(i, 0)) > now:
			continue
		var cm := center_m(i)
		for pl: Dictionary in players:
			if Vector2(pl.pos.x - cm.x, pl.pos.z - cm.z).length() < RAISE_DIST:
				muster(i)
				break


func muster(i: int) -> int:
	var rec: Dictionary = outposts[i]
	var g := garrison(net.difficulty)
	var posts: Array = rec.posts
	var n := 0
	_horned.erase(i)
	var slot := 0
	for kind: StringName in [&"reaver_harpooner", &"reaver"]:
		for k in int(g.get(kind, 0)):
			var at: Vector3
			if kind == &"reaver_harpooner" and k == 0:
				at = (rec.tower as Vector3) * VS            # the lookout
			else:
				at = (posts[slot % posts.size()] as Vector3) * VS
				slot += 1
			if _spawn_one(i, kind, at) != null:
				n += 1
	if n > 0:
		print("[outposts] mustered %d Sea-Reavers at outpost %d" % [n, i])
	return n


func _spawn_one(i: int, kind: StringName, at: Vector3) -> SeaReaver:
	net._ensure_column(floori(at.x / VS), floori(at.z / VS))
	var c := net.spawn(kind, at + Vector3.UP * 0.3) as SeaReaver
	if c == null:
		return null
	var gy := c.ground_under(c.position, 0.6, 1.4)
	if not is_nan(gy):
		c.position.y = gy
	c.outpost = i
	c.post_center = center_m(i)
	c.post = c.position
	c.home = c.position
	return c


func attackers(i: int) -> int:
	var n := 0
	for c: SeaReaver in alive(i):
		if not c.harpooner and c.state in [Creature.State.WINDUP, Creature.State.STRIKE]:
			n += 1
	return n


## Host: someone was spotted or struck: the outpost turns out, and the horn sounds once.
func rouse(i: int) -> void:
	for c: SeaReaver in alive(i):
		c.roused = true
	if _horned.has(i) or captured.has(i):
		return
	_horned[i] = true
	var rec: Dictionary = outposts[i]
	var tot := (Vector3(rec.totem) + Vector3(0.5, 0, 0.5)) * VS
	for k in HORN_REINFORCE:
		var r := _spawn_one(i, &"reaver", tot + Vector3(0.8 * (k * 2 - 1), 0, 0.6))
		if r != null:
			r.roused = true
			r.post = (rec.posts[k % rec.posts.size()] as Vector3) * VS
	if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
		horn.rpc(i)
	else:
		horn(i)


@rpc("authority", "call_local", "reliable")
func horn(i: int) -> void:
	if net.main.hud == null or not _sync_gen() or i >= outposts.size():
		return
	var pp: Vector3 = net.main.player.position if net.main.player != null else Vector3.INF
	if pp.distance_to(center_m(i)) < 140.0:
		net.main.hud.show_toast("A war horn blares from the Sea-Reaver outpost: more of them are coming!")


## Host: a reaver died. When the last falls, the outpost waits to muster again.
func on_killed(i: int, _c: SeaReaver) -> void:
	if i < 0 or captured.has(i):
		return
	if alive(i).filter(func(c: SeaReaver) -> bool: return c != _c).is_empty():
		_respawn_at[i] = Time.get_ticks_msec() + int(RESPAWN_SEC * 1000.0)
		_horned.erase(i)
		var msg := "The outpost's guards are down. Topple the War Horn Totem (F) before more come ashore."
		if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
			net.cr_toast.rpc(msg)
		if net.main.hud != null:
			net.main.hud.show_toast(msg)


## Host: a player asks to topple the totem of outpost `i`. Returns "" on success, else why not.
func try_capture(i: int) -> String:
	if not _sync_gen() or i < 0 or i >= outposts.size():
		return "This totem belongs to no outpost."
	if captured.has(i):
		return ""
	var cm := center_m(i)
	for c: SeaReaver in alive(i):
		if Vector2(c.position.x - cm.x, c.position.z - cm.z).length() < CLEAR_R:
			return "The reavers still hold the outpost. Beat the guards first."
	captured[i] = true
	_respawn_at.erase(i)
	for c: SeaReaver in alive(i):
		net.despawn(c)
	print("[outposts] outpost %d captured" % i)
	if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
		outpost_captured.rpc(i)
	else:
		outpost_captured(i)
	return ""


@rpc("authority", "call_local", "reliable")
func outpost_captured(i: int) -> void:
	captured[i] = true
	if net.main.hud == null or not _sync_gen() or i >= outposts.size():
		return
	var isle: String = net.main.atlas.name_of(int(outposts[i].island)) if net.main.get("atlas") != null else ""
	var pp: Vector3 = net.main.player.position if net.main.player != null else Vector3.INF
	if pp.distance_to(center_m(i)) < 140.0:
		net.main.hud.show_banner("Outpost taken", "%s  ·  a forward base: sleep in the big tent to wake here" % isle)
	else:
		net.main.hud.show_toast("The Sea-Reaver outpost on %s has been taken." % isle)


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
	for i in outposts.size():
		if discovered.has(i):
			continue
		var cm := center_m(i)
		if Vector2(pp.x - cm.x, pp.z - cm.z).length() < DISCOVER_R:
			discovered[i] = true
			var isle: String = net.main.atlas.name_of(int(outposts[i].island)) if net.main.get("atlas") != null else ""
			var sub := "taken" if captured.has(i) else ("watchtower manned  ·  sneak to stay unseen" if CombatMath.hostiles_allowed(net.difficulty) else "all bluster on Cozy")
			net.main.hud.show_banner("Sea-Reaver outpost", "%s  ·  %s  ·  marked on your chart" % [isle, sub])


func chart_labels() -> Array:
	var out: Array = []
	if not _sync_gen():
		return out
	for i: int in discovered:
		if i < outposts.size():
			out.append({"pos": center_m(i), "name": "Forward base" if captured.has(i) else "Reaver outpost",
				"camp": true, "cleared": captured.has(i)})
	return out


func _save_state() -> Variant:
	return {"captured": captured.keys()}


func _load_state(d: Variant) -> void:
	captured = {}
	if d is Dictionary:
		for i in d.get("captured", []):
			captured[int(i)] = true


func serialize_seen() -> Array:
	return discovered.keys()


func deserialize_seen(data: Variant) -> void:
	discovered = {}
	if data is Array:
		for i in data:
			discovered[int(i)] = true
