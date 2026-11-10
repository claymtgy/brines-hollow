class_name NpcVillages
extends Node
## The NPC villages on the other islands of the big archipelago (layout 2+): their names,
## the villagers who live there (VillagerNPC), talking to them, the village trader (via
## TradeManager) and the elder's chain of requests (per-player quests), and discovering
## each village (a banner, and its name on the sea chart). Lives at /root/Main/NpcVillages.
##
## The villages themselves are stamped into the terrain by WorldGen.plan_villages, so every
## peer has them. Villagers' movement is a function of the synced time of day; only trader
## stock is networked (TradeManager). Quests and discoveries are per character (profile).

const VS := VoxelWorld.VS
const SPAWN_R := 160.0
const DESPAWN_R := 220.0
const TALK_R := 3.0
const DISCOVER_R := 55.0
const ROLES := ["trader", "elder", "fisher", "farmer", "mender"]
const SUFFIXES := ["Haven", "Staithe", "Harbour", "Wick", "Landing", "Cove", "Quay"]
const FIRST_NAMES := ["Maren", "Tobin", "Isolde", "Corwen", "Elspeth", "Hamish", "Brannagh", "Odo",
	"Morwenna", "Fergus", "Ysolde", "Piran", "Tamsin", "Jory", "Kerra", "Ewan", "Nessa", "Rhoswen",
	"Alder", "Bryony", "Cadoc", "Delyth", "Gethin", "Lowenna", "Mabyn", "Nye", "Senara", "Tegen"]
## The elder's requests: [item, count, brass]. Each village draws its own seeded order.
const REQUESTS := [
	[&"sea_salt", 6, 18], [&"wood_plank", 20, 14], [&"silver_mackerel", 4, 20],
	[&"smoked_fish_ration", 3, 40], [&"copper_ore", 6, 24], [&"shore_wheat", 10, 22],
	[&"sea_glass", 3, 30], [&"driftwood", 12, 10], [&"kelp_frond", 10, 12], [&"stone", 30, 12],
]
const CHAIN_LEN := 5
const FLAVOUR := {
	"fisher": ["Mackerel run thick off the point at dawn. Mind the tide on the way back in.",
		"I've mended that hull three times this season. Sea wants her back, I reckon.",
		"There's a cave under the cliffs past the headland. Only go at low water."],
	"farmer": ["Wheat likes the salt air well enough, if you keep the gulls off it.",
		"Rain's due. You can smell it on the wind before the clouds show.",
		"Raiders took half my turnips last moon. A fence and a dog would be grand."],
	"mender": ["Nets don't mend themselves. Well, they would, if I'd let them sit long enough.",
		"Hand me that twine, would you? No? Then mind the hooks.",
		"Every knot in this net has a story. Most of them are about my temper."],
}

var main: Node
var villages: Array = []          # [{key, name, island, center (m), front, side, record}]
var discovered := {}              # village key -> true (local player)
var npcs := {}                    # villager key -> VillagerNPC (spawned ones)
var dialogue: DialogueBox
var _gen: Object = null
var _near: VillagerNPC = null
var _talking: VillagerNPC = null
var _disc_t := 0.0


func _ready() -> void:
	name = "NpcVillages"
	dialogue = DialogueBox.new()
	dialogue.name = "VillageDialogue"
	add_child(dialogue)
	dialogue.setup(main)


## Build the village list from the world generator (once per generated world).
func _try_init() -> void:
	if main.world == null or main.world.gen == null or not main.world.ready_for_play:
		return
	if _gen == main.world.gen:
		return
	_gen = main.world.gen
	for n: VillagerNPC in npcs.values():
		n.queue_free()
	npcs.clear()
	villages = build_records(main.world.gen.villages, main.atlas, main.seed_value)
	if main.trade != null:
		for v: Dictionary in villages:
			var t: Dictionary = v.people[0]
			main.trade.ensure_trader(v.key, "%s of %s" % [t.name, v.name], int(v.style), t.work)
	if not villages.is_empty():
		print("[villages] %s" % ", ".join(villages.map(func(v: Dictionary) -> String: return v.name)))


## Pure: names, people and their homes / work spots (metres) from WorldGen's records.
static func build_records(raw: Array, atlas: IslandAtlas, world_seed: int) -> Array:
	var out: Array = []
	var used_names := {}
	for i in raw.size():
		var r: Dictionary = raw[i]
		var isl := int(r.island)
		var isl_name := atlas.name_of(isl) if atlas != null else ""
		var pre := isl_name.split(" ")[0] if isl_name != "" else "Far"
		var h := hash([world_seed, i, isl])
		var vname := "%s %s" % [pre, SUFFIXES[h % SUFFIXES.size()]]
		var key := "v%d" % i
		var style := int(atlas.islands[isl].style) if atlas != null and isl < atlas.islands.size() else 0
		var people: Array = []
		var cottages: Array = r.cottages
		for j in ROLES.size():
			var role: String = ROLES[j]
			var nh := hash([world_seed, i, role])
			var nm: String = FIRST_NAMES[nh % FIRST_NAMES.size()]
			var tries := 0
			while used_names.has(nm) and tries < FIRST_NAMES.size():
				nh += 1
				nm = FIRST_NAMES[nh % FIRST_NAMES.size()]
				tries += 1
			used_names[nm] = true
			var door: Vector3 = cottages[j % cottages.size()].door if not cottages.is_empty() else r.center
			var spot: Vector3 = r.spots.get(role, r.center)
			people.append({"key": "%s:%s" % [key, role], "role": role, "name": nm,
				"home": door * VS, "work": spot * VS, "seed": nh & 0x7FFFFFFF})
		var order: Array = []
		var rq := RandomNumberGenerator.new()
		rq.seed = h
		var pool := range(REQUESTS.size())
		for k in CHAIN_LEN:
			order.append(pool.pop_at(rq.randi() % pool.size()))
		out.append({"key": key, "name": vname, "island": isl, "style": style, "front": r.front,
			"center": (r.center as Vector3) * VS, "people": people, "requests": order})
	return out


func village(key: String) -> Dictionary:
	for v: Dictionary in villages:
		if v.key == key:
			return v
	return {}


func chart_labels() -> Array:
	var out: Array = []
	for v: Dictionary in villages:
		if discovered.has(v.key):
			out.append({"pos": v.center, "name": v.name, "village": true})
	return out


func serialize() -> Array:
	return discovered.keys()


func deserialize(data: Variant) -> void:
	discovered = {}
	if data is Array:
		for k in data:
			discovered[String(k)] = true


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_try_init()
	if villages.is_empty():
		return
	var pp: Vector3 = main.player.position
	for v: Dictionary in villages:
		var d := Vector2(pp.x - v.center.x, pp.z - v.center.z).length()
		if d < SPAWN_R:
			_spawn(v)
		elif d > DESPAWN_R:
			_despawn(v)
	for n: VillagerNPC in npcs.values():
		n.talking = n == _talking and dialogue.is_open()
		n.step(delta, pp)
	if _talking != null and not dialogue.is_open():
		_talking = null
	_update_markers()
	_update_prompt()
	_disc_t -= delta
	if _disc_t <= 0.0:
		_disc_t = 0.5
		_check_discovery(pp)


func _spawn(v: Dictionary) -> void:
	for p: Dictionary in v.people:
		if npcs.has(p.key):
			continue
		var n := VillagerNPC.new()
		add_child(n)
		n.setup(p.key, p.role, p.name, p.home, p.work, int(p.seed), main.world, main.sky)
		n.set_meta("village", v.key)
		npcs[p.key] = n


func _despawn(v: Dictionary) -> void:
	for p: Dictionary in v.people:
		if npcs.has(p.key):
			if npcs[p.key] == _talking:
				dialogue.close()
				_talking = null
			npcs[p.key].queue_free()
			npcs.erase(p.key)


func _check_discovery(pp: Vector3) -> void:
	if main.session != null and main.session._pending_profile != null:
		return   # wait for this character's saved discoveries
	if main.player.is_seated():
		return
	for v: Dictionary in villages:
		if discovered.has(v.key):
			continue
		if Vector2(pp.x - v.center.x, pp.z - v.center.z).length() < DISCOVER_R:
			discovered[v.key] = true
			print("[villages] discovered %s" % v.name)
			main.hud.show_banner(v.name, "Village discovered  ·  %s  ·  marked on your chart" % main.atlas.name_of(int(v.island)))


func _update_markers() -> void:
	for n: VillagerNPC in npcs.values():
		var t := ""
		if n.role == "elder":
			var st := elder_state(n.get_meta("village"))
			t = "?" if st == "ready" else ("!" if st == "offer" else "")
		n.marker.text = t


func _update_prompt() -> void:
	_near = null
	var p: Player = main.player
	if p.is_seated() or dialogue.is_open() or (main.trade != null and main.trade.ui.visible):
		return
	var best := TALK_R
	for n: VillagerNPC in npcs.values():
		if not n.is_available():
			continue
		var d := Vector2(p.position.x - n.position.x, p.position.z - n.position.z).length()
		if d < best and absf(p.position.y - n.position.y) < 2.5:
			best = d
			_near = n
	if _near != null:
		main.hud.set_prompt("F  Talk to %s" % _near.villager_name)


func _unhandled_input(e: InputEvent) -> void:
	if _near == null or not e.is_action_pressed("interact"):
		return
	if not main.player.input_enabled:
		return
	get_viewport().set_input_as_handled()
	talk_to(_near)


# ---------------------------------------------------------------- talking

func talk_to(n: VillagerNPC) -> void:
	_talking = n
	var vk: String = n.get_meta("village")
	var v := village(vk)
	var who := "%s, %s" % [n.villager_name, VillagerNPC.ROLE_TITLE.get(n.role, "")]
	match n.role:
		"trader":
			dialogue.say(who, "Welcome to %s! Wares from the island, fair prices. Have a look." % v.name, [
				["Trade", func() -> void:
					dialogue.close()
					if main.trade != null:
						main.trade.open_village(vk)],
				["Goodbye", dialogue.close]])
		"elder":
			_elder_talk(n, v, who)
		_:
			if main != null and main.get("quests") != null:
				if main.quests.is_quest_completed(&"story_siren_hunt"):
					dialogue.say(who, "The deep trench has gone quiet... you felled the Abyssal Siren! Mariners across the sound drink to your name.")
					return
				elif main.quests.is_quest_completed(&"story_storm_fortress"):
					dialogue.say(who, "Heard the harbour bell ring through the storm! You stood your ground against the reavers and held the line!")
					return
				elif main.quests.is_quest_completed(&"chore_regatta_trial"):
					dialogue.say(who, "Saw your boat flying through the buoys out in the sound! Quickest tack in the whole archipelago!")
					return
			var lines: Array = FLAVOUR.get(n.role, ["Fine day for it."])
			var t := int(main.sky.time_of_day * 24.0) if main.sky != null else 0
			dialogue.say(who, lines[(t + int(n._seed)) % lines.size()])


## "offer" (a new request to give), "active" (waiting for goods), "ready" (the player has
## them), or "done" (every request filled).
func elder_state(vk: String) -> String:
	var v := village(vk)
	if v.is_empty() or main.quests == null:
		return ""
	var n := requests_done(vk)
	if n >= CHAIN_LEN:
		return "done"
	var qid := StringName("vq_%s_%d" % [vk, n])
	if main.quests.is_quest_active(qid):
		var rq: Array = REQUESTS[v.requests[n]]
		return "ready" if main.player.inventory.has_item(rq[0], rq[1]) else "active"
	return "offer"


func requests_done(vk: String) -> int:
	var n := 0
	while n < CHAIN_LEN and main.quests.is_quest_completed(StringName("vq_%s_%d" % [vk, n])):
		n += 1
	return n


func request_def(v: Dictionary, n: int) -> QuestDef:
	var rq: Array = REQUESTS[v.requests[n]]
	var elder: Dictionary = v.people[1]
	var item_name := TradeManager._item_name(rq[0])
	var q := QuestDef.new(StringName("vq_%s_%d" % [v.key, n]), "%s: %s" % [v.name, item_name], "Elder " + elder.name)
	q.add_step("Bring %d %s to Elder %s in %s" % [rq[1], item_name, elder.name, v.name],
		QuestDef.ObjectiveType.TALK_TO, StringName("vel_%s" % v.key), 1)
	q.rewards = {"brass_guilder": int(rq[2]), "tide_scrip": 0, "items": []}
	return q


func _elder_talk(n: VillagerNPC, v: Dictionary, who: String) -> void:
	var vk: String = v.key
	var st := elder_state(vk)
	var i := requests_done(vk)
	match st:
		"done":
			dialogue.say(who, "%s is in your debt, friend. Whatever we have is yours to trade for, and you're always welcome at our hearths." % v.name)
		"offer":
			var q := request_def(v, i)
			var rq: Array = REQUESTS[v.requests[i]]
			var intro := "A traveller! We don't see many boats out this way. " if i == 0 else ""
			dialogue.say(who, "%sWe're short of %s. Could you bring me %d? I'll pay %d brass." % [
					intro, TradeManager._item_name(rq[0]).to_lower(), rq[1], rq[2]], [
				["I'll find some", func() -> void:
					accept_request(vk)
					dialogue.close()
					main.hud.show_toast("New request: %s" % q.title)],
				["Not now", dialogue.close]])
		"ready":
			var rq: Array = REQUESTS[v.requests[i]]
			dialogue.say(who, "Is that %d %s I see? Just what we needed." % [rq[1], TradeManager._item_name(rq[0]).to_lower()], [
				["Hand them over", func() -> void:
					var ok := deliver_request(vk)
					dialogue.close()
					if ok:
						main.hud.show_toast("+%d brass from Elder %s" % [rq[2], n.villager_name])],
				["Keep them", dialogue.close]])
		"active":
			var rq: Array = REQUESTS[v.requests[i]]
			var have: int = main.player.inventory.get_item_count(rq[0])
			dialogue.say(who, "Still hoping for those %s. You've %d of the %d." % [TradeManager._item_name(rq[0]).to_lower(), have, rq[1]])


func accept_request(vk: String) -> bool:
	var v := village(vk)
	var i := requests_done(vk)
	if v.is_empty() or i >= CHAIN_LEN:
		return false
	var q := request_def(v, i)
	main.quests.register_available_quest(q)
	return main.quests.accept_quest(q.id)


func deliver_request(vk: String) -> bool:
	if elder_state(vk) != "ready":
		return false
	var v := village(vk)
	var rq: Array = REQUESTS[v.requests[requests_done(vk)]]
	var inv: Inventory = main.player.inventory
	inv.remove_item(rq[0], rq[1])
	main.quests.notify_event(QuestDef.ObjectiveType.TALK_TO, StringName("vel_%s" % vk), 1, inv)
	return true


# ---------------------------------------------------------------- dev check

## Close-ups of a few trees near the villages (for checking how they look).
func _tree_shots(dir: String) -> void:
	var shots := 0
	for v: Dictionary in villages:
		var c: Vector3 = v.center / VS
		var found := Vector3i(-1, -1, -1)
		for r in range(20, 260, 6):
			for k in 16:
				var a := TAU * k / 16.0
				var x := int(c.x + cos(a) * r)
				var z := int(c.z + sin(a) * r)
				var h := int(main.world.gen.col_h(x, z))
				for y in range(h + 6, h + 26):
					if main.world.get_voxel(x, y, z) == Palette.TRUNK:
						found = Vector3i(x, h, z)
						break
				if found.x >= 0:
					break
			if found.x >= 0:
				break
		if found.x < 0:
			continue
		var base := Vector3(found) * VS
		main.player.position = base + Vector3(5.5, 1.0, 0.0)
		main.rig.yaw = PI * 0.5
		main.rig.pitch = -0.05
		main.rig.dist = 9.0
		await get_tree().create_timer(2.0).timeout
		await main._shot(dir, "tree_%d" % shots)
		shots += 1
		if shots >= 3:
			return


## --villagescheck: visit each village, meet its people, fill a request, trade.
func run_check() -> void:
	while villages.is_empty() or main.player == null:
		await get_tree().process_frame
	main.sky.time_of_day = 0.45
	for v: Dictionary in villages:
		main.player.position = v.center + Vector3(0, 4, 0)
		await get_tree().create_timer(2.5).timeout
		var here := 0
		for p: Dictionary in v.people:
			if npcs.has(p.key):
				var n: VillagerNPC = npcs[p.key]
				if n.position.distance_to(p.work) < 4.0:
					here += 1
		print("[villagescheck] %s: discovered=%s villagers at work %d/%d" % [v.name, discovered.has(v.key), here, v.people.size()])
		if main._args.has("vshot"):
			main.player.position = v.center + Vector3(0, 4, 0) - Vector3(v.front.x, 0, v.front.y) * 6.0
			main.rig.yaw = atan2(-float(v.front.x), -float(v.front.y))
			main.rig.pitch = -0.35
			main.rig.dist = 22.0
			await get_tree().create_timer(2.0).timeout
			await main._shot(String(main._args.vshot), "village_%s" % v.key)
	if main._args.has("vshot"):
		await _tree_shots(String(main._args.vshot))
	var v0: Dictionary = villages[0]
	var inv: Inventory = main.player.inventory
	accept_request(v0.key)
	var rq: Array = REQUESTS[v0.requests[0]]
	inv.add_item(rq[0], rq[1])
	var b0 := inv.get_item_count(&"brass_guilder")
	main.player.position = v0.people[1].work + Vector3(0, 1, 0)
	print("[villagescheck] elder state %s -> deliver %s, brass %d -> %d, next %s" % [elder_state(v0.key), deliver_request(v0.key),
		b0, inv.get_item_count(&"brass_guilder"), elder_state(v0.key)])
	main.player.position = v0.people[0].work + Vector3(0, 1, 0)
	await get_tree().create_timer(0.5).timeout
	inv.add_item(&"brass_guilder", 50)
	main.trade.open_village(v0.key)
	var m: MerchantBoat = main.trade.current()
	var item: StringName = m.stock.slots[0].item_id
	var before := m.stock.get_item_count(item)
	main.trade.request_buy(item, 1)
	await get_tree().create_timer(0.3).timeout
	print("[villagescheck] bought 1 %s from %s: stock %d -> %d, have %d" % [item, m.merchant_name, before,
		main.trade.current().stock.get_item_count(item), inv.get_item_count(item)])
	main.trade.ui.close()
	main.sky.time_of_day = 0.95
	main.player.position = v0.center + Vector3(0, 30, 90)   # out of sight: they go straight home
	await get_tree().create_timer(1.0).timeout
	var inside := 0
	for n: VillagerNPC in npcs.values():
		if not n.visible:
			inside += 1
	print("[villagescheck] at night %d of %d nearby villagers are indoors" % [inside, npcs.size()])
	get_tree().quit()
