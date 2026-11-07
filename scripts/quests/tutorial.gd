class_name Tutorial
extends Node
## The starter quest line. Wren, a travelling fisher, walks up to new players when they
## wash ashore and teaches the basics through a chain of short missions. Each mission
## ends by returning to Wren, who pays out and teaches new recipes.
##
## Per player and local (each co-op player gets their own guide). Progress is ordinary
## QuestManager state, so it saves with the player profile. Players can skip it.

const NPC_ID := &"wren"
const NPC_NAME := "Wren the Wayfarer"
const SKIP_ID := &"tut_skipped"
const TALK_RANGE := 3.0

## The mission chain. objectives: [description, ObjectiveType, target, count]
const MISSIONS := [
	{
		"id": &"tut_1_feet", "title": "Find Your Feet",
		"intro": "Easy now, you've had a rough night at sea. I'm Wren. I walk these shores between villages. Let's get you on your feet: grab your pickaxe [1] and dig up a few handfuls of sand or stone.",
		"objectives": [["Dig up 6 handfuls of sand, dirt or stone", QuestDef.ObjectiveType.GATHER_ITEM, &"", 6]],
		"done": "Good arms on you. Everything you dig comes back as material, about one handful for every four blocks.",
		"rewards": {"items": [["driftwood", 8]], "recipes": []},
	},
	{
		"id": &"tut_2_mark", "title": "Make Your Mark",
		"intro": "Now put some of it back where you want it. Take the hammer [2], press B to choose blocks, and lay a few. Building costs what digging gives.",
		"objectives": [["Place 5 blocks with the hammer", QuestDef.ObjectiveType.PLACE_VOXELS, &"", 5]],
		"done": "There. The coast is yours to shape. Walls, huts and furniture are all in the hammer's build menu (B).",
		"rewards": {"items": [["wood_plank", 12]], "recipes": [&"place_storage_crate"]},
	},
	{
		"id": &"tut_3_tools", "title": "Tools of the Trade",
		"intro": "Let's make something. Open your pack (Tab or I) to hand-craft, or use a workbench if you find one. Planks from driftwood is a fine start.",
		"objectives": [["Craft anything (inventory or a workbench)", QuestDef.ObjectiveType.CRAFT_ITEM, &"", 1]],
		"done": "Recipes are worth more than gold out here. You'll learn new ones from ingredients you find, from folk who join your village, and from scrolls the merchants carry. Here, the crab pot is an old friend of mine.",
		"rewards": {"items": [["crab_pot", 1], ["kelp_frond", 4]], "recipes": [&"place_crab_pot"]},
	},
	{
		"id": &"tut_4_tide", "title": "Let the Tide Work",
		"intro": "Take that crab pot down to the wet sand between the tide lines and set it from your hotbar or the hammer's build menu (B). Bait it with kelp. When the tide comes in, it fishes for you.",
		"objectives": [["Set a crab pot between the tide lines", QuestDef.ObjectiveType.PLACE_ENTITY, &"crab_pot", 1]],
		"done": "The sea does half the work if you let it. Salt pans are the same: flood at high tide, dry in the sun.",
		"rewards": {"items": [["salt_pan", 1]], "recipes": [&"place_salt_pan"]},
	},
	{
		"id": &"tut_5_line", "title": "A Line in the Water",
		"intro": "Time to eat. Take your rod [3], hold the button to cast into deep water, then strike when it bites.",
		"objectives": [["Catch a fish", QuestDef.ObjectiveType.CATCH_FISH, &"", 1]],
		"done": "Fine catch! Fish keep longer in a sea barrel, and better still smoked.",
		"rewards": {"items": [["silver_mackerel", 2]], "recipes": [&"cook_roasted_mackerel", &"place_sea_barrel"]},
	},
	{
		"id": &"tut_6_belly", "title": "A Warm Belly",
		"intro": "Cook that fish at a campfire and eat it with the right button. A full belly means more health and stamina for a good while.",
		"objectives": [["Eat a meal", QuestDef.ObjectiveType.EAT_FOOD, &"", 1]],
		"done": "Much better. You can hold up to three meals at once, and the best ones stack nicely.",
		"rewards": {"items": [], "recipes": [&"place_smokehouse", &"place_hearth_pot"]},
	},
	{
		"id": &"tut_7_sea", "title": "Beyond the Shallows",
		"intro": "Last lesson. There's a rowboat at the pier. Climb in with F and row out a little. Other islands are waiting.",
		"objectives": [["Take a rowboat out", QuestDef.ObjectiveType.BOARD_BOAT, &"", 1]],
		"done": "You'll do just fine. Folk wash up on these beaches all the time; give them a roof and a bed and they'll stay. I'll be on my way. Look for me on the pier when the merchants come in.",
		"rewards": {"items": [["brass_guilder", 30]], "recipes": [&"craft_parchment_chart"]},
	},
]

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
var _speed := 0.0
var _check := ""
var _bind_delay := 1.0
var _stuck_t := 0.0


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


func is_started() -> bool:
	var q := _q()
	for m in MISSIONS:
		if q.is_quest_active(m.id) or q.is_quest_completed(m.id):
			return true
	return q.is_quest_completed(SKIP_ID)


## Index of the active mission, or -1.
func current() -> int:
	for i in MISSIONS.size():
		if _q().is_quest_active(MISSIONS[i].id):
			return i
	return -1


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
	_refresh_tracker()


## True when only "Return to Wren" is left.
func _ready_to_turn_in(i: int) -> bool:
	var qd: QuestDef = _q().active_quests.get(MISSIONS[i].id)
	if qd == null:
		return false
	for s in qd.steps:
		if not s.is_completed and s.type != QuestDef.ObjectiveType.TALK_TO:
			return false
	return true


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
	# Boarding a boat is detected here (no hook needed in the boat code).
	var seated := p.is_seated()
	if seated and not _was_seated:
		p.quest_event(QuestDef.ObjectiveType.BOARD_BOAT, &"")
		_refresh_tracker()
	_was_seated = seated
	if wren == null:
		return
	_update_wren(delta, p)
	if Engine.get_process_frames() % 15 == 0:
		_refresh_tracker()


func _bind() -> void:
	_bound = true
	main.quests.quest_progressed.connect(func(_q2: Variant, _s: Variant) -> void: _refresh_tracker())
	main.quests.quest_accepted.connect(func(_q2: Variant) -> void: _refresh_tracker())
	main.quests.quest_completed.connect(_on_quest_completed)
	if not is_finished():
		_spawn_wren(main.player)
	_refresh_tracker()
	if _check != "":
		_run_check()


func _spawn_wren(p: Player) -> void:
	wren = Node3D.new()
	wren.name = "Wren"
	main.add_child(wren)
	_model = CharacterModel.new()
	wren.add_child(_model)
	_model.setup(Palette.ROOF_BLUE, Palette.DARK_WOOD)
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
	_marker.position = Vector3(0, 2.55, 0)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 96
	_marker.outline_size = 16
	_marker.pixel_size = 0.004
	_marker.modulate = UiTheme.BRASS
	_marker.no_depth_test = true
	wren.add_child(_marker)
	# New players: Wren walks up from along the beach. Returning players: he's nearby.
	var away := Vector3(sin(main.rig.yaw), 0, cos(main.rig.yaw)) * (14.0 if not is_started() else 4.0)
	wren.position = _ground(p.position + away + Vector3(2, 0, 0))


func _ground(p: Vector3) -> Vector3:
	var hit: Dictionary = main.world.raycast(p + Vector3(0, 4.0, 0), Vector3.DOWN, 12.0, true)
	if hit.is_empty():
		return p
	return Vector3(p.x, p.y + 4.0 - float(hit.dist), p.z)


func _update_wren(delta: float, p: Player) -> void:
	var i := current()
	# Marker: "!" new mission to give, "?" ready to hand in, nothing while working.
	if not is_started() or (i >= 0 and _ready_to_turn_in(i)):
		_marker.text = "!" if not is_started() else "?"
	else:
		_marker.text = ""
	if _leaving:
		var away := (wren.position - p.position)
		away.y = 0
		_walk(delta, wren.position + away.normalized() * 3.0, 2.0)
		if wren.position.distance_to(p.position) > 40.0:
			wren.queue_free()
			wren = null
		return
	# Walk up to the player (closer when there's something to say), wait at the water's edge.
	var d := wren.position.distance_to(p.position)
	var want := 2.2 if _marker.text != "" else 5.0
	if d > want and not p.is_seated() and d < 60.0:
		_walk(delta, p.position, 3.2 if d > 10.0 else 2.2)
	else:
		_speed = lerpf(_speed, 0.0, 1.0 - exp(-delta * 8.0))
		var to := p.position - wren.position
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
	_model.animate(delta, _speed, true, false)
	if d > 80.0:
		wren.position = _ground(p.position + Vector3(4, 0, 4))   # don't lose the player
	# First meeting starts on its own.
	if not _greeted and not is_started() and d < 2.6 and not dialogue.is_open():
		_greeted = true
		_intro()
	if d < TALK_RANGE and not dialogue.is_open() and is_started():
		main.hud.set_prompt("F  Talk to Wren")


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
		# Truly blocked (cliff, water): pop up beside the player instead of standing there.
		_stuck_t = 0.0
		var p: Player = main.player
		var side := Vector3(cos(main.rig.yaw), 0, -sin(main.rig.yaw)) * 2.5
		wren.position = _ground(p.position + side)


func _unhandled_input(e: InputEvent) -> void:
	if wren == null or dialogue.is_open() or not e.is_action_pressed("interact"):
		return
	var p: Player = main.player
	if p == null or not p.input_enabled or wren.position.distance_to(p.position) > TALK_RANGE:
		return
	get_viewport().set_input_as_handled()
	talk()


# ---------------------------------------------------------------- dialogue

func _intro() -> void:
	dialogue.say(NPC_NAME, "Ho there! You washed up with the tide, didn't you? Most folk do, on this coast. I'm Wren. I can show you how to get by here, if you like.", [
		["Show me around", func() -> void: _offer(0)],
		["I know my way", _skip],
	])


func talk() -> void:
	if not is_started():
		_intro()
		return
	var i := current()
	if i < 0:
		dialogue.say(NPC_NAME, "Fair winds! Build something worth sailing home to.")
		return
	if _ready_to_turn_in(i):
		_q().notify_event(QuestDef.ObjectiveType.TALK_TO, NPC_ID, 1, main.player.inventory)
		return   # _on_quest_completed continues the conversation
	var qd: QuestDef = _q().active_quests[MISSIONS[i].id]
	var left := []
	for s in qd.steps:
		if not s.is_completed and s.type != QuestDef.ObjectiveType.TALK_TO:
			left.append("%s (%d/%d)" % [s.description, s.current_count, s.target_count])
	dialogue.say(NPC_NAME, "%s\n\nStill to do: %s" % [MISSIONS[i].intro, ", ".join(left)])


func _offer(i: int) -> void:
	_start(i)
	var m: Dictionary = MISSIONS[i]
	dialogue.say("%s  ·  %s" % [NPC_NAME, m.title], m.intro, [["Got it", dialogue.close]])


func _on_quest_completed(qd: QuestDef) -> void:
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
		dialogue.say(NPC_NAME, m.done + reward, [["Next lesson", func() -> void: _offer(i + 1)], ["Later", dialogue.close]])
		if not _q().is_quest_active(MISSIONS[i + 1].id):
			_start(i + 1)   # accepted either way; "Later" just closes the window
	else:
		dialogue.say(NPC_NAME, m.done + reward, [["Farewell, Wren", func() -> void:
			dialogue.close()
			_leaving = true]])


## Skip: mark everything done and teach the recipes the missions would have taught.
func _skip() -> void:
	dialogue.close()
	for m in MISSIONS:
		main.player.recipes.learn_all(m.rewards.get("recipes", []), "quest")
	var skip := QuestDef.new(SKIP_ID, "Tutorial skipped", NPC_NAME)
	_q().completed_quests.append(skip.id)
	for m in MISSIONS:
		if _q().is_quest_active(m.id):
			_q().active_quests.erase(m.id)
	main.hud.show_toast("Tutorial skipped. Wren's recipes are in your book.")
	_leaving = true
	_refresh_tracker()


# ---------------------------------------------------------------- tracker

func _refresh_tracker() -> void:
	if _tracker_root == null or main.quests == null:
		return
	for c in _tracker_root.get_children():
		c.queue_free()
	var shown := 0
	var order: Array = []
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
		for s in qd.steps:
			if s.is_completed:
				continue
			var l := Label.new()
			l.theme_type_variation = &"Small"
			l.add_theme_font_size_override("font_size", 15)
			l.text = "•  " + s.description + ("  (%d/%d)" % [s.current_count, s.target_count] if s.target_count > 1 else "")
			v.add_child(l)
			break   # show the next step only


# ---------------------------------------------------------------- dev check

## --tutorialcheck: drives the whole chain headless through the real event hooks.
func _run_check() -> void:
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	if _check.begins_with("shots:"):
		var dir := _check.trim_prefix("shots:")
		DirAccess.make_dir_recursive_absolute(dir)
		main.hud.help.visible = false
		for k in 40:   # let Wren walk up and greet
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
		main.inventory_ui.open()
		await _grab(dir + "/tut_4_crafting.png")
		get_tree().quit()
		return
	if _check == "verify":
		print("[tutorial] reloaded: finished=%s wren=%s knows crab pot=%s smokehouse=%s brass=%d" % [
			is_finished(), wren != null, p.recipes.knows(&"place_crab_pot"), p.recipes.knows(&"place_smokehouse"),
			p.inventory.get_item_count(&"brass_guilder")])
		get_tree().quit()
		return
	print("[tutorial] wren spawned=%s started=%s" % [wren != null, is_started()])
	_offer(0)
	dialogue.close()
	var feed := [
		func() -> void: main.quests.notify_event(QuestDef.ObjectiveType.GATHER_ITEM, &"sand", 6, p.inventory),
		func() -> void:
			for k in 5: p.quest_event(QuestDef.ObjectiveType.PLACE_VOXELS, &""),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, &"wood_plank"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.PLACE_ENTITY, &"crab_pot"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.CATCH_FISH, &"silver_mackerel"),
		func() -> void: p.quest_event(QuestDef.ObjectiveType.EAT_FOOD, &"roasted_mackerel"),
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
	print("[tutorial] finished=%s knows crab pot=%s mackerel=%s smokehouse=%s brass=%d" % [
		is_finished(), p.recipes.knows(&"place_crab_pot"), p.recipes.knows(&"cook_roasted_mackerel"),
		p.recipes.knows(&"place_smokehouse"), p.inventory.get_item_count(&"brass_guilder")])
	if _check == "save":
		main.session.save_all()
	get_tree().quit()


func _grab(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[tutorial] shot ", path)
