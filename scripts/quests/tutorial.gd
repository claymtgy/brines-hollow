class_name Tutorial
extends Node
## The opening. A new castaway washes up beside a storm-battered hut with three tools and a
## journal: dig, make a campfire, patch the hut (the "Washed Ashore" page, no guide). Smoke
## from that first fire brings Wren, a travelling fisher, rowing in to the pier. Wren teaches
## the coast's less obvious crafts through short lessons, each one handing over the tool it
## uses, then rows away and hands over Act I of the story.
##
## Per player and local (each co-op player gets their own journal and guide). Progress is
## ordinary QuestManager state, so it saves with the player profile. Players can skip Wren.

const NPC_ID := &"wren"
const NPC_NAME := "Wren the Wayfarer"
const SKIP_ID := &"tut_skipped"
const TALK_RANGE := 3.0

## The castaway's own first page: no guide, just a few nudges (hints show the right keys).
const JOURNAL_ID := &"tut_0_ashore"
const JOURNAL := {
	"title": "Washed Ashore",
	"giver": "Your journal",
	"steps": [
		["Dig up 6 handfuls of sand, earth or stone", QuestDef.ObjectiveType.GATHER_ITEM, &"", 6,
			"Pickaxe [1]: hold {use} on the ground"],
		["Hand-craft a campfire", QuestDef.ObjectiveType.CRAFT_ITEM, &"campfire", 1,
			"Open your pack ({inventory_toggle}). Short of stone? Try the chest by the hut"],
		["Set the campfire down near the hut", QuestDef.ObjectiveType.PLACE_ENTITY, &"campfire", 1,
			"Pick it on your hotbar and press {use}"],
		["Patch the hut: place 12 blocks in the gaps", QuestDef.ObjectiveType.PLACE_VOXELS, &"", 12,
			"Hammer [2]: {use} to place, {build_menu_toggle} to choose blocks"],
	],
}
## Wren comes anyway after this long, so nobody waits forever for a guide.
const ARRIVE_AFTER_SEC := 300.0
## Lessons the old tutorial had that this one replaced (their progress is folded into the new chain).
const RETIRED := [&"tut_1_feet", &"tut_2_mark", &"tut_3_tools"]

## Wren's lessons. objectives: [description, ObjectiveType, target, count]; gifts are handed
## over when the lesson starts, rewards when it's turned in. {action} becomes that action's key.
const MISSIONS := [
	{
		"id": &"tut_4_tide", "title": "Let the Tide Work",
		"intro": "Here, an old friend of mine: a crab pot. Set it on the wet sand between the tide lines and bait it with kelp. When the tide comes in, it fishes for you.",
		"objectives": [["Set a crab pot between the tide lines", QuestDef.ObjectiveType.PLACE_ENTITY, &"crab_pot", 1]],
		"hint": "Pick the pot on your hotbar, aim at wet sand, {use}",
		"gifts": [["crab_pot", 1], ["kelp_frond", 4]],
		"done": "The sea does half the work if you let it. Salt pans are the same: flood at high tide, dry in the sun.",
		"rewards": {"items": [["salt_pan", 1]], "recipes": [&"place_crab_pot", &"place_salt_pan"]},
	},
	{
		"id": &"tut_5_line", "title": "A Line in the Water",
		"intro": "Time to eat. Take your rod [3], hold {use} to cast into deep water, then strike when it bites.",
		"objectives": [["Catch a fish", QuestDef.ObjectiveType.CATCH_FISH, &"", 1]],
		"hint": "Rod [3]: hold {use}, release to cast, {use} again on a bite",
		"done": "Fine catch! Fish keep longer in a sea barrel, and better still smoked.",
		"rewards": {"items": [["silver_mackerel", 2]], "recipes": [&"cook_roasted_mackerel", &"place_sea_barrel"]},
	},
	{
		"id": &"tut_6_belly", "title": "A Warm Belly",
		"intro": "Cook that fish at your campfire ({interact}) and eat it with {alt_use}. A full belly means more health and stamina for a good while.",
		"objectives": [["Eat a meal", QuestDef.ObjectiveType.EAT_FOOD, &"", 1]],
		"hint": "Cook at your campfire ({interact}), then {alt_use} to eat",
		"done": "Much better. You can hold up to three meals at once, and the best ones stack nicely.",
		"rewards": {"items": [], "recipes": [&"place_smokehouse", &"place_hearth_pot"]},
	},
	{
		"id": &"tut_8_timber", "title": "Timber",
		"intro": "Driftwood won't build you much, and a pick only chips at a trunk. Take this hatchet: {use} on a pine and the whole tree comes down. Plant the saplings it drops and you'll never run short.",
		"objectives": [["Fell a pine and gather its logs", QuestDef.ObjectiveType.GATHER_ITEM, &"pine_wood", 2]],
		"hint": "Hatchet: {use} on a pine trunk, then walk over the logs",
		"gifts": [["driftwood_axe", 1]],
		"done": "Good timber. Pine makes planks by hand, and a workbench makes nearly everything else. Build yourself one when you can.",
		"rewards": {"items": [["wood_plank", 8]], "recipes": []},
	},
	{
		"id": &"tut_9_sow", "title": "Till & Sow",
		"intro": "Fish won't fill you forever. Take this hoe and some seed: till a patch with {use}, then sow it with {alt_use}. Rain waters it, but keep it back from the salt spray.",
		"objectives": [["Sow 3 seeds in tilled earth", QuestDef.ObjectiveType.PLANT_CROP, &"", 3]],
		"hint": "Hoe: {use} to till grass or dirt, {alt_use} to sow",
		"gifts": [["driftwood_hoe", 1], ["seed_shore_wheat", 5], ["seed_samphire", 3]],
		"done": "Come back in a few days and you'll have wheat. Wheat makes hardtack, and parchment for charts.",
		"rewards": {"items": [["seed_shore_wheat", 3]], "recipes": []},
	},
	{
		"id": &"tut_10_blade", "title": "Steady Your Blade",
		"intro": "The shore crabs pinch, and worse things come up out of the deep at night. Here's an old cutlass. {use} to strike, {alt_use} to block (time it to parry), {dodge} to roll clear. Go and see off a crab.",
		"objectives": [["Defeat a creature", QuestDef.ObjectiveType.DEFEAT_ENEMY, &"", 1]],
		"hint": "Cutlass: {use} strike, {alt_use} block, {dodge} roll",
		"gifts": [["rusty_cutlass", 1]],
		"done": "You'll keep. Sleep in a bed when the light goes; nights out here are long.",
		"rewards": {"items": [["shore_crab", 1]], "recipes": []},
	},
	{
		"id": &"tut_7_sea", "title": "Beyond the Shallows",
		"intro": "Last lesson. There's a rowboat at the pier. Climb in with {interact} and row out a little. Other islands are waiting, and the chart I gave you fills in as you go. Keep that old stone lighthouse on the bluff in mind if you sail late—a lit beacon brings you safely back.",
		"objectives": [["Take a rowboat out", QuestDef.ObjectiveType.BOARD_BOAT, &"", 1]],
		"hint": "Walk up to the rowboat and press {interact}",
		"done": "You'll do just fine out on the water. Folk wash up along these shores all the time; build them a proper roof, bed, and doorway and they'll settle right here in your haven.\n\nElder Brenda and Old Corin sent word across the water with requests—I've jotted both in your journal ({quest_log_toggle}). You don't need to sail searching for them first; you can gather the timber, raise your first hearth, and harvest salt right here on your own sands.\n\nAnd keep an eye on that old stone lighthouse up on the bluff! If you feed its lantern with fish oil, its beam will cut through the night and fog to guide you home when you're out on the dark water.\n\nI'll be on my way now. Look for me on the pier when the merchant vessels come in.",
		"rewards": {"items": [["brass_guilder", 30]], "recipes": [&"craft_parchment_chart"]},
	},
]

## Handed over at the first meeting (and on skipping): a map from the first conversation.
const GREETING_GIFTS := [["parchment_shore_chart", 1]]
## Act I of the story, given when Wren leaves.
const STORY_QUESTS := [&"story_first_hearth", &"story_tide_tackle"]

var main: Node
var dialogue: DialogueBox
var wren: Node3D
var _model: CharacterModel
var _marker: Label3D
var _tracker_root: Control
var _tracker: VBoxContainer
var _bound := false
var _greeted := false
var _was_seated := false
var _leaving := false
var _arriving := false
var _speed := 0.0
var _check := ""
var _bind_delay := 1.0
var _stuck_t := 0.0
var _since_bind := 0.0
## Wren keeps to the home pier: _pier is where Wren stands, _face_land which way Wren looks
## when nobody's near. Wren rows in to the pier's end, and rows away from it at the end.
var _pier := Vector3.ZERO
var _pier_end := Vector3.ZERO
var _face_land := 0.0
var _boat: Boat
var _depart_t := 0.0
var _hinted := false
var _tracker_tween: Tween
var _hud_tracker_pinned := false
var _tracker_hidden := false   # the player hid it from the quest log


func setup(p_main: Node) -> void:
	main = p_main
	dialogue = DialogueBox.new()
	dialogue.name = "Dialogue"
	add_child(dialogue)
	dialogue.setup(main)
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_tracker_root = Control.new()
	UiTheme.prepare(_tracker_root)
	_tracker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_root.position = Vector2(14, 158)
	layer.add_child(_tracker_root)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tutorialcheck"):
			_check = a.trim_prefix("--tutorialcheck").trim_prefix("=")
			if _check == "":
				_check = "run"


## The HUD places the tracker (under the clock plaque); the default is the old fixed spot.
func set_tracker_position(p: Vector2) -> void:
	if _tracker_root != null:
		_tracker_root.position = p


func tracker_size() -> Vector2:
	if _tracker_root == null or not _tracker_root.visible or _tracker_root.get_child_count() == 0:
		return Vector2.ZERO
	var c := _tracker_root.get_child(_tracker_root.get_child_count() - 1) as Control
	return c.get_combined_minimum_size() if c != null else Vector2.ZERO


# ---------------------------------------------------------------- state

func _q() -> QuestManager:
	return main.quests


func _mission_index(id: StringName) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].id == id:
			return i
	return -1


func is_finished() -> bool:
	var q := _q()
	return q.is_quest_completed(SKIP_ID) or q.is_quest_completed(MISSIONS[-1].id)


## Has the player met Wren (any lesson begun, or skipped)?
func is_started() -> bool:
	var q := _q()
	for m in MISSIONS:
		if q.is_quest_active(m.id) or q.is_quest_completed(m.id):
			return true
	return q.is_quest_completed(SKIP_ID)


func journal_done() -> bool:
	return _q().is_quest_completed(JOURNAL_ID)


## Index of the active mission, or -1.
func current() -> int:
	for i in MISSIONS.size():
		if _q().is_quest_active(MISSIONS[i].id):
			return i
	return -1


## Replaces {action} tokens with that action's key or button on the current device.
func _fmt(text: String) -> String:
	var c: Variant = main.get("controller") if main != null else null
	for a in ["use", "alt_use", "interact", "dodge", "inventory_toggle", "build_menu_toggle", "quest_log_toggle"]:
		var key := "{%s}" % a
		if text.contains(key):
			var g: String = String(c.get_glyph(StringName(a))) if c != null else String(a)
			text = text.replace(key, g)
	return text


func _quest_for(i: int) -> QuestDef:
	var m: Dictionary = MISSIONS[i]
	var qd := QuestDef.new(m.id, m.title, NPC_NAME)
	for o: Array in m.objectives:
		qd.add_step(o[0], o[1], o[2], o[3])
	qd.add_step("Return to Wren", QuestDef.ObjectiveType.TALK_TO, NPC_ID, 1)
	var items := []
	for it: Array in m.rewards.get("items", []):
		items.append({"id": it[0], "count": it[1]})
	qd.rewards = {"brass_guilder": 0, "tide_scrip": 0, "items": items}
	return qd


func _start(i: int) -> void:
	var qd := _quest_for(i)
	_q().register_available_quest(qd)
	_q().accept_quest(qd.id)
	_give(MISSIONS[i].get("gifts", []))
	_refresh_tracker()
	show_tracker()


## Hands items to the player; whatever doesn't fit lands at their feet.
func _give(items: Array) -> void:
	var p: Player = main.player
	if p == null or p.inventory == null:
		return
	for it: Array in items:
		var left: int = p.inventory.add_item(StringName(it[0]), int(it[1]))
		if left > 0 and main.has_method("spawn_item_drop"):
			main.spawn_item_drop(p.position + Vector3(0, 0.6, 0), StringName(it[0]), left)


## True when only "Return to Wren" is left.
func _ready_to_turn_in(i: int) -> bool:
	var qd: QuestDef = _q().active_quests.get(MISSIONS[i].id)
	if qd == null:
		return false
	for s in qd.steps:
		if not s.is_completed and s.type != QuestDef.ObjectiveType.TALK_TO:
			return false
	return true


func _start_journal() -> void:
	var qd := QuestDef.new(JOURNAL_ID, JOURNAL.title, JOURNAL.giver)
	for st: Array in JOURNAL.steps:
		qd.add_step(st[0], st[1], st[2], st[3])
	qd.rewards = {"brass_guilder": 0, "tide_scrip": 0, "items": []}
	_q().register_available_quest(qd)
	_q().accept_quest(JOURNAL_ID)


## Act I: the villagers' requests, written into the journal as Wren leaves.
func start_story() -> void:
	for id: StringName in STORY_QUESTS:
		if not _q().is_quest_active(id) and not _q().is_quest_completed(id):
			_q().accept_quest(id)
	_refresh_tracker()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var p: Player = main.player
	if p == null or main.quests == null or not main.world.ready_for_play:
		return
	if not _bound:
		# Give Session a moment to restore a returning player's quests first.
		_bind_delay -= delta
		if _bind_delay <= 0.0:
			_bind()
		return
	_since_bind += delta
	# Boarding a boat is detected here (no hook needed in the boat code).
	var seated := p.is_seated()
	if seated and not _was_seated:
		p.quest_event(QuestDef.ObjectiveType.BOARD_BOAT, &"")
		_refresh_tracker()
	_was_seated = seated
	if wren == null:
		if not is_finished() and not is_started() and (journal_done() or _since_bind >= ARRIVE_AFTER_SEC):
			_spawn_wren(p, true)
		return
	if _arriving:
		_update_arrival(delta)
	else:
		_update_wren(delta, p)
	if Engine.get_process_frames() % 15 == 0:
		_refresh_tracker()


func _bind() -> void:
	_bound = true
	main.quests.quest_progressed.connect(func(_q2: Variant, _s: Variant) -> void:
		_refresh_tracker()
		show_tracker()
	)
	main.quests.quest_accepted.connect(func(_q2: Variant) -> void:
		_refresh_tracker()
		show_tracker()
	)
	main.quests.quest_completed.connect(_on_quest_completed)
	_migrate_retired()
	if not is_finished() and not is_started() and not journal_done() and not _q().is_quest_active(JOURNAL_ID):
		_start_journal()
	if not is_finished() and (is_started() or journal_done()):
		_spawn_wren(main.player, false)   # returning player: Wren is already on the pier
	_refresh_tracker()
	show_tracker()
	if _check != "":
		_run_check()


## Saves from the old seven-lesson tutorial: drop the retired lessons and pick the chain up
## at the first new lesson not yet done.
func _migrate_retired() -> void:
	var had := false
	for id: StringName in RETIRED:
		if _q().active_quests.has(id):
			_q().active_quests.erase(id)
			had = true
		elif _q().is_quest_completed(id):
			had = true
	if had and not journal_done():
		_q().completed_quests.append(JOURNAL_ID)   # they're well past washing ashore
	if had and not is_finished() and current() < 0:
		for i in MISSIONS.size():
			if not _q().is_quest_completed(MISSIONS[i].id):
				_start(i)
				break


func _spawn_wren(p: Player, arrive: bool) -> void:
	wren = Node3D.new()
	wren.name = "Wren"
	main.add_child(wren)
	_model = CharacterModel.new()
	wren.add_child(_model)
	var wren_customizer := CharacterCustomizer.new()
	wren_customizer.apply_preset("dirty_old_sailor")
	_model.setup(Palette.COAT_A, Palette.HAT_A, wren_customizer)
	_model.set_tool(3)
	var tag := Label3D.new()
	tag.text = "Wren"
	tag.position = Vector3(0, 2.2, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.004
	tag.modulate = Color(1, 0.96, 0.88)
	wren.add_child(tag)
	_marker = Label3D.new()
	_marker.position = Vector3(0, 2.6, 0)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 96
	_marker.outline_size = 16
	_marker.pixel_size = 0.009   # about 0.9 m tall: readable from the far end of the beach
	_marker.modulate = UiTheme.BRASS
	_marker.no_depth_test = true
	wren.add_child(_marker)
	_find_pier(p)
	if arrive:
		_begin_arrival()
		return
	wren.position = _pier
	_model.rotation.y = _face_land


## Where Wren stands: a few steps out along the starter dock, looking back at the island.
func _find_pier(p: Player) -> void:
	var st: Dictionary = main.world.gen.starter if main.world != null and main.world.gen != null else {}
	if st.is_empty():
		_pier = _ground(p.position + Vector3(3, 0, 3))
		_pier_end = _pier
		return
	var d: Vector2i = st.front
	var o: Vector2i = st.dock_o
	var top := float(int(st.dock_y) + 6) * VoxelWorld.VS
	var at := func(s: int) -> Vector3:
		var v := Vector2(o) + Vector2(d) * s + Vector2(0.5, 0.5)
		return _ground(Vector3(v.x * VoxelWorld.VS, top, v.y * VoxelWorld.VS))
	_pier = at.call(8)
	_pier_end = at.call(26)
	if _pier_end.y < main.sky.water_level_m() - 0.3:
		_pier_end = at.call(18)
	_face_land = atan2(-float(d.x), -float(d.y))


func _ground(p: Vector3) -> Vector3:
	var hit: Dictionary = main.world.raycast(p + Vector3(0, 4.0, 0), Vector3.DOWN, 12.0, true)
	if hit.is_empty():
		return p
	return Vector3(p.x, p.y + 4.0 - float(hit.dist), p.z)


func _out_to_sea() -> Vector3:
	return Vector3(-sin(_face_land), 0, -cos(_face_land))


## Where Wren's boat ties up: beside the end of the pier.
func _mooring() -> Vector3:
	var out := _out_to_sea()
	var bp := _pier_end + Vector3(out.z, 0, -out.x) * 1.6
	bp.y = main.sky.water_level_m()
	return bp


## The smoke has been seen: Wren rows in from open water to the end of the pier.
func _begin_arrival() -> void:
	_arriving = true
	_depart_t = 0.0
	var out := _out_to_sea()
	_boat = Boat.new()
	_boat.name = "WrensBoat"
	main.add_child(_boat)
	_boat.setup(-77, main.world, main.sky, _mooring() + out * 55.0, atan2(-out.x, -out.z))
	if main.hud != null:
		var why := "Someone has seen your smoke: a small boat is rowing in to the pier." if journal_done() \
			else "A small boat is rowing in to the pier."
		main.hud.show_toast(why, 7.0, true)


func _update_arrival(delta: float) -> void:
	_depart_t += delta
	var goal := _mooring()
	var to := goal - _boat.position
	to.y = 0
	if to.length() > 1.2 and _depart_t < 45.0:
		var spd := minf(2.4, 0.6 + _depart_t * 0.4) if to.length() > 8.0 else maxf(0.5, to.length() * 0.3)
		var dir := to.normalized()
		_boat.position += dir * spd * delta
		_boat.position.y = _boat.water_y()
		_boat.yaw = atan2(dir.x, dir.z)
		_boat.vel = Vector2(dir.x, dir.z) * spd
		_boat.row_power = 1.0
		_boat.row_phase += delta * 4.0
		var st := _boat.seat_transform(0)
		wren.position = st.origin
		_model.position = Vector3.ZERO
		_model.rotation = st.basis.get_euler()
		_model.animate_seated(delta, _boat.row_phase, 1.0)
		_marker.text = "!"
		return
	# Tied up: step onto the pier; _update_wren walks Wren to the usual spot.
	_boat.position = Vector3(goal.x, _boat.water_y(), goal.z)
	_boat.vel = Vector2.ZERO
	_boat.row_power = 0.0
	_model.rotation = Vector3(0, _model.rotation.y, 0)
	wren.position = _pier_end
	_arriving = false


func _update_wren(delta: float, p: Player) -> void:
	if _boat != null and not _leaving:
		_boat.position.y = _boat.water_y()   # tied up at the pier's end
	var i := current()
	# Marker: "!" new mission to give, "?" ready to hand in, nothing while working.
	var is_paused: bool = (i >= 0 and main.get("quests") != null and main.quests.paused_reward_quests.has(MISSIONS[i].id))
	if not is_started() or (i >= 0 and (_ready_to_turn_in(i) or is_paused)):
		_marker.text = "!" if not is_started() else "?"
	else:
		_marker.text = ""
	if _marker != null and _marker.text != "":
		_marker.position.y = 2.6 + sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 0.06
	if not _leaving and is_finished() and not dialogue.is_open():
		_leaving = true   # every lesson done (or skipped): time to go, however the last chat closed
	if _leaving:
		_update_departure(delta)
		return
	# Wren waits on the pier: turns to greet whoever comes near, otherwise watches the island.
	var d := wren.position.distance_to(p.position)
	if wren.position.distance_to(_pier) > 0.4:
		_walk(delta, _pier, 2.2)   # back to the usual spot (after a talk, or if nudged)
	else:
		_speed = lerpf(_speed, 0.0, 1.0 - exp(-delta * 8.0))
		var look := _face_land
		if d < 12.0:
			var to := p.position - wren.position
			look = atan2(to.x, to.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, look, 1.0 - exp(-delta * 4.0))
	_model.animate(delta, _speed, true, false)
	# First meeting starts on its own once you walk up.
	if not _greeted and not is_started() and d < 2.8 and not dialogue.is_open():
		_greeted = true
		_intro()
	if d < TALK_RANGE and not dialogue.is_open():
		main.hud.set_prompt("%s  Talk to Wren" % _fmt("{interact}"))


## All lessons done: walk to the end of the pier, step into the boat and row out to sea.
func _update_departure(delta: float) -> void:
	_depart_t += delta
	var rowing := _boat != null and _boat.row_power > 0.0
	if not rowing and wren.position.distance_to(_pier_end) > 0.6 and _depart_t < 12.0:
		_walk(delta, _pier_end, 2.0)
		_model.animate(delta, _speed, true, false)
		return
	var out := _out_to_sea()
	if _boat == null:
		_boat = Boat.new()
		_boat.name = "WrensBoat"
		main.add_child(_boat)
		_boat.setup(-77, main.world, main.sky, _mooring(), atan2(out.x, out.z))
	if not rowing:
		_boat.yaw = atan2(out.x, out.z)
		_boat.row_power = 1.0
		_depart_t = 0.0
		if main.hud != null:
			main.hud.show_toast("Wren casts off. Fair winds, Wren!")
	var fw := Vector3(sin(_boat.yaw), 0, cos(_boat.yaw))
	var spd := minf(2.6, 0.4 + _depart_t * 0.5)
	_boat.position += fw * spd * delta
	_boat.position.y = _boat.water_y()
	_boat.vel = Vector2(fw.x, fw.z) * spd
	_boat.row_phase += delta * 4.0
	var st := _boat.seat_transform(0)
	wren.position = st.origin
	_model.position = Vector3.ZERO
	_model.rotation = st.basis.get_euler()
	_model.animate_seated(delta, _boat.row_phase, 1.0)
	_marker.text = ""
	if _depart_t > 40.0 or _boat.position.distance_to(_pier_end) > 70.0:
		_boat.queue_free()
		_boat = null
		wren.queue_free()
		wren = null
		_leaving = false


func _walk(delta: float, goal: Vector3, speed: float) -> void:
	var to := goal - wren.position
	to.y = 0
	if to.length() < 0.05:
		return
	var dir := to.normalized()
	var budget := minf(speed * delta, to.length())
	var moved := 0.0
	# Small sub-steps so slopes are climbable at any frame rate; sidestep around obstacles.
	while moved < budget - 0.001:
		var stepped := false
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var d2 := dir.rotated(Vector3.UP, turn)
			var next := _ground(wren.position + d2 * minf(0.25, budget - moved))
			if next.y >= main.sky.water_level_m() - 0.3 and absf(next.y - wren.position.y) <= 0.6:
				wren.position = next
				stepped = true
				break
		if not stepped:
			break
		moved += 0.25
	_speed = speed if moved > 0.0 else 0.0
	_stuck_t = 0.0 if moved > 0.0 else _stuck_t + delta
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-delta * 8.0))
	if _stuck_t > 4.0:
		# Truly blocked (something built on the pier?): step straight to the goal.
		_stuck_t = 0.0
		wren.position = goal


## Wren is in talking range (her "Talk" prompt is up).
func wants_talk() -> bool:
	var p: Player = main.player if main != null else null
	return wren != null and p != null and not _arriving and not dialogue.is_open() \
			and wren.position.distance_to(p.position) <= TALK_RANGE


func _unhandled_input(e: InputEvent) -> void:
	if wren == null or _arriving or dialogue.is_open() or not e.is_action_pressed("interact"):
		return
	var p: Player = main.player
	if p == null or not p.input_enabled or wren.position.distance_to(p.position) > TALK_RANGE:
		return
	get_viewport().set_input_as_handled()
	talk()


# ---------------------------------------------------------------- dialogue

func _intro() -> void:
	var opener := "Ho there! I saw your smoke from the water and thought: another one the tide brought in." if journal_done() \
		else "Ho there! You washed up with the tide, didn't you? Most folk do, on this coast."
	dialogue.say(NPC_NAME, opener + " I'm Wren. I walk these shores between villages. Take this chart, it fills in as you explore. And I can show you how to get by here, if you like.", [
		["Show me around", func() -> void:
			_give(GREETING_GIFTS)
			_offer(0)],
		["I know my way", _skip],
	])


func talk() -> void:
	if not is_started():
		_intro()
		return
	var i := current()
	if i < 0:
		dialogue.say(NPC_NAME, "Fair winds! Build something worth sailing home to, and keep that lighthouse lantern lit.")
		return
	if _ready_to_turn_in(i):
		var qd: QuestDef = _q().active_quests[MISSIONS[i].id]
		if main.player != null and main.player.inventory != null and not _q().can_accept_rewards(main.player.inventory, qd):
			dialogue.say(NPC_NAME, "Good work! I've got your reward right here, but your pack is completely full.\n\nMake some room in your bag and talk to me again so I can hand it over.", [["I'll make room", dialogue.close]])
			if not _q().paused_reward_quests.has(qd.id):
				_q().paused_reward_quests.append(qd.id)
			_refresh_tracker()
			return
		if _q().paused_reward_quests.has(qd.id):
			_q().paused_reward_quests.erase(qd.id)
		_q().notify_event(QuestDef.ObjectiveType.TALK_TO, NPC_ID, 1, main.player.inventory)
		return   # _on_quest_completed continues the conversation
	var qd: QuestDef = _q().active_quests[MISSIONS[i].id]
	var left := []
	for s in qd.steps:
		if not s.is_completed and s.type != QuestDef.ObjectiveType.TALK_TO:
			left.append("%s (%d/%d)" % [s.description, s.current_count, s.target_count])
	dialogue.say(NPC_NAME, "%s\n\nStill to do: %s" % [_fmt(MISSIONS[i].intro), ", ".join(left)])


func _offer(i: int) -> void:
	if not _q().is_quest_active(MISSIONS[i].id):
		_start(i)
	var m: Dictionary = MISSIONS[i]
	dialogue.say("%s  ·  %s" % [NPC_NAME, m.title], _fmt(m.intro), [["Got it", dialogue.close]])


func _on_quest_completed(qd: QuestDef) -> void:
	if qd.id == JOURNAL_ID:
		_refresh_tracker()
		return   # _process brings Wren in
	var i := _mission_index(qd.id)
	if i < 0:
		return
	var m: Dictionary = MISSIONS[i]
	var learned: Array = main.player.recipes.learn_all(m.rewards.get("recipes", []), "quest")
	var gifts := []
	for it: Array in m.rewards.get("items", []):
		var def: ItemDef = ItemDB.get_item(StringName(it[0]))
		gifts.append("%d %s" % [it[1], def.name if def != null else it[0]])
	for rid in learned:
		gifts.append("recipe: " + RecipeDB.get_recipe(rid).name)
	var reward := ("\n\nReceived: " + ", ".join(gifts)) if not gifts.is_empty() else ""
	_refresh_tracker()
	if i + 1 < MISSIONS.size():
		dialogue.say(NPC_NAME, _fmt(m.done) + reward, [["Next lesson", func() -> void: _offer(i + 1)], ["Later", dialogue.close]])
		if not _q().is_quest_active(MISSIONS[i + 1].id):
			_start(i + 1)   # accepted either way; "Later" just closes the window
	else:
		start_story()
		dialogue.say(NPC_NAME, _fmt(m.done) + reward, [["Farewell, Wren", func() -> void:
			dialogue.close()
			_leaving = true]])


## Skip: everything the lessons would have taught and handed over, then Wren leaves.
func _skip() -> void:
	dialogue.close()
	_give(GREETING_GIFTS)
	for m in MISSIONS:
		main.player.recipes.learn_all(m.rewards.get("recipes", []), "quest")
		if not _q().is_quest_completed(m.id) and not _q().is_quest_active(m.id):
			_give(m.get("gifts", []))
	var skip := QuestDef.new(SKIP_ID, "Tutorial skipped", NPC_NAME)
	_q().completed_quests.append(skip.id)
	for m in MISSIONS:
		if _q().is_quest_active(m.id):
			_q().active_quests.erase(m.id)
	start_story()
	main.hud.show_toast("Tutorial skipped. Wren's tools are in your pack and the recipes in your book.")
	_leaving = true
	_refresh_tracker()


# ---------------------------------------------------------------- tracker

## Is a journal page or one of Wren's lessons on the go? (the tracker stays up for those)
func _guided_active() -> bool:
	return _q().is_quest_active(JOURNAL_ID) or current() >= 0


func _hint_for(qd: QuestDef, step_idx: int) -> String:
	if qd.id == JOURNAL_ID and step_idx < JOURNAL.steps.size():
		return _fmt(JOURNAL.steps[step_idx][4])
	var i := _mission_index(qd.id)
	if i >= 0:
		if qd.steps[step_idx].type == QuestDef.ObjectiveType.TALK_TO:
			return "Wren is waiting on the pier"
		return _fmt(MISSIONS[i].get("hint", ""))
	if qd.id == &"story_first_hearth":
		if step_idx == 0:
			return "Pickaxe [1]: dig driftwood logs along your shore"
		elif step_idx == 1:
			return "Hammer [2]: walls, roof, door, bed, and light to found your haven"
		elif step_idx == 2:
			return "Follow the signal smoke or circling gulls along the beach to invite a drifter [F]"
	elif qd.id == &"story_tide_tackle":
		if step_idx == 0:
			return "Rod [3]: cast into deep water during high tide"
		elif step_idx == 1:
			return _fmt("Salt Pan: place on wet sand ({use}); dry in the sun")
	return ""


func _refresh_tracker() -> void:
	if _tracker_root == null or main.quests == null:
		return
	for c in _tracker_root.get_children():
		c.queue_free()
	var shown := 0
	var order: Array = []
	if _q().active_quests.has(JOURNAL_ID):
		order.append(_q().active_quests[JOURNAL_ID])
	for m in MISSIONS:
		if _q().active_quests.has(m.id):
			order.append(_q().active_quests[m.id])
	for qd: QuestDef in _q().active_quests.values():
		if not order.has(qd):
			order.append(qd)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_tracker_root.add_child(col)
	for qd: QuestDef in order:
		if shown >= 2:
			break
		shown += 1
		var p := PanelContainer.new()
		p.theme_type_variation = &"Plaque"
		col.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)
		var t := Label.new()
		t.theme_type_variation = &"Header"
		t.add_theme_font_size_override("font_size", 18)
		t.text = qd.title
		v.add_child(t)
		if _q().paused_reward_quests.has(qd.id):
			var l := Label.new()
			l.theme_type_variation = &"Small"
			l.add_theme_font_size_override("font_size", 15)
			l.text = "•  Rewards Paused  (Pack Full - Make Room)"
			l.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
			v.add_child(l)
			continue
		for si in qd.steps.size():
			var s: QuestDef.QuestStep = qd.steps[si]
			if s.is_completed:
				continue
			var l := Label.new()
			l.theme_type_variation = &"Small"
			l.add_theme_font_size_override("font_size", 15)
			l.text = "•  " + s.description + ("  (%d/%d)" % [s.current_count, s.target_count] if s.target_count > 1 else "")
			v.add_child(l)
			var hint := _hint_for(qd, si)
			if hint != "":
				var h := Label.new()
				h.theme_type_variation = &"Small"
				h.add_theme_font_size_override("font_size", 14)
				h.add_theme_color_override("font_color", Color(0.86, 0.80, 0.66))
				h.text = "    " + hint
				v.add_child(h)
			break   # show the next step only


## Shows the tracker after a change. While a journal page or one of Wren's lessons is on the
## go it stays up; other quests linger for `delay` seconds and then fade. If the player hid it
## from the quest log it stays hidden until they show it again.
func show_tracker(delay: float = 20.0) -> void:
	if _tracker_root == null or _tracker_hidden:
		return
	if _tracker_tween != null and _tracker_tween.is_valid():
		_tracker_tween.kill()
	_tracker_root.visible = true
	_tracker_root.modulate.a = 1.0
	if _hud_tracker_pinned or _guided_active():
		return
	_tracker_tween = create_tween()
	_tracker_tween.tween_interval(delay)
	_tracker_tween.tween_property(_tracker_root, "modulate:a", 0.0, 1.5)
	_tracker_tween.tween_callback(func() -> void:
		if not _hud_tracker_pinned and not _guided_active():
			_tracker_root.visible = false
	)


## Old name, kept for existing callers.
func fade_tracker_after_delay(delay: float = 20.0) -> void:
	show_tracker(delay)


func hide_tracker() -> void:
	if _tracker_tween != null and _tracker_tween.is_valid():
		_tracker_tween.kill()
	_hud_tracker_pinned = false
	_tracker_hidden = true
	if _tracker_root != null:
		_tracker_root.visible = false
		_tracker_root.modulate.a = 0.0


func toggle_tracker() -> void:
	if _tracker_root != null and _tracker_root.visible and _tracker_root.modulate.a > 0.05:
		hide_tracker()
	else:
		_tracker_hidden = false
		_hud_tracker_pinned = true
		show_tracker()


func is_tracker_pinned() -> bool:
	return _hud_tracker_pinned


# ---------------------------------------------------------------- dev check

## --tutorialcheck: drives the whole chain headless through the real event hooks.
func _run_check() -> void:
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	if wren == null and _check != "verify":
		if _q().is_quest_active(JOURNAL_ID):
			_q().active_quests.erase(JOURNAL_ID)
			_q().completed_quests.append(JOURNAL_ID)
		_spawn_wren(p, false)
	if _check.begins_with("shots:"):
		var dir := _check.trim_prefix("shots:")
		DirAccess.make_dir_recursive_absolute(dir)
		main.hud.help.visible = false
		p.position = wren.position + Vector3(1.5, 0, 0)   # walk up to him on the pier
		for k in 40:
			if dialogue.is_open():
				break
			await get_tree().process_frame
		await _grab(dir + "/tut_1_greeting.png")
		_offer(0)
		await _grab(dir + "/tut_2_mission.png")
		dialogue.close()
		p.inventory.add_item(&"silver_mackerel", 1)
		await get_tree().create_timer(0.5).timeout
		await _grab(dir + "/tut_3_tracker.png")
		main.crafting_ui.open()
		await _grab(dir + "/tut_4_crafting.png")
		get_tree().quit()
		return
	if _check == "verify":
		print("[tutorial] reloaded: finished=%s wren=%s knows crab pot=%s smokehouse=%s brass=%d story=%s" % [
			is_finished(), wren != null, p.recipes.knows(&"place_crab_pot"), p.recipes.knows(&"place_smokehouse"),
			p.inventory.get_item_count(&"brass_guilder"), _q().is_quest_active(&"story_first_hearth")])
		get_tree().quit()
		return
	print("[tutorial] wren spawned=%s started=%s at_pier=%s" % [wren != null, is_started(), wren != null and wren.position.distance_to(_pier) < 0.5])
	_give(GREETING_GIFTS)   # as the "Show me around" button does
	_offer(0)
	dialogue.close()
	var feed := [
		func() -> void: p.quest_event(QuestDef.ObjectiveType.PLACE_ENTITY, &"crab_pot"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.CATCH_FISH, &"silver_mackerel"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.EAT_FOOD, &"roasted_mackerel"),
		func() -> void: main.quests.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"pine_wood", 2, p.inventory),
		func() -> void:
			for k in 3: p.quest_event(QuestDef.ObjectiveType.PLANT_CROP, &"shore_wheat"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.DEFEAT_ENEMY, &"shore_crab"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.BOARD_BOAT, &""),
	]
	for i in MISSIONS.size():
		feed[i].call()
		var ready := _ready_to_turn_in(i)
		wren.position = p.position + Vector3(1, 0, 0)
		talk()
		dialogue.close()
		print("[tutorial] %-22s objectives done=%s turned in=%s next=%d" % [
			MISSIONS[i].title, ready, _q().is_quest_completed(MISSIONS[i].id), current()])
	print("[tutorial] finished=%s knows crab pot=%s mackerel=%s smokehouse=%s brass=%d axe=%d hoe=%d cutlass=%d chart=%d story=%s" % [
		is_finished(), p.recipes.knows(&"place_crab_pot"), p.recipes.knows(&"cook_roasted_mackerel"),
		p.recipes.knows(&"place_smokehouse"), p.inventory.get_item_count(&"brass_guilder"),
		p.inventory.get_item_count(&"driftwood_axe"), p.inventory.get_item_count(&"driftwood_hoe"),
		p.inventory.get_item_count(&"rusty_cutlass"), p.inventory.get_item_count(&"parchment_shore_chart"),
		_q().is_quest_active(&"story_first_hearth")])
	if _check == "save":
		main.session.save_all()
	if _check == "depart":
		var t0 := Time.get_ticks_msec()
		print("[tutorial] depart start: wren=%s pier_end=%s water=%.2f" % [wren.position.snapped(Vector3.ONE * 0.1), _pier_end.snapped(Vector3.ONE * 0.1), main.sky.water_level_m()])
		var boarded := false
		var max_out := 0.0
		while wren != null and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().process_frame
			if _boat != null:
				boarded = true
				max_out = maxf(max_out, _boat.position.distance_to(_pier_end))
		print("[tutorial] depart: pier=%s boarded=%s rowed_out=%.1f m gone=%s after %.1f s" % [
			_pier.snapped(Vector3.ONE * 0.1), boarded, max_out, wren == null, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()


func _grab(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[tutorial] shot ", path)
