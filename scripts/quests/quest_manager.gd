class_name QuestManager
extends RefCounted
## Manages active quests, story arcs, villager requests, and objective progress.

signal quest_accepted(quest: QuestDef)
signal quest_progressed(quest: QuestDef, step: QuestDef.QuestStep)
signal quest_completed(quest: QuestDef)
signal quest_rewards_paused(quest: QuestDef)

var active_quests: Dictionary = {}          ## quest_id -> QuestDef
var completed_quests: Array[StringName] = []## Array of completed quest IDs
var completed_quest_defs: Dictionary = {}   ## quest_id -> QuestDef
var paused_reward_quests: Array[StringName] = []## Quest IDs whose rewards are paused due to full inventory
var available_quests: Dictionary = {}        ## quest_id -> QuestDef (Notice board)


func _init() -> void:
	_init_storyline_catalogue()


func _init_storyline_catalogue() -> void:
	# Storyline Act I: Reclaiming the Shallows
	var q1 := QuestDef.new(&"story_first_hearth", "The First Hearth", "Elder Brenda")
	q1.storyline_act = 1
	q1.add_step("Collect 10 Driftwood (dig old stumps and logs)", QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 10)
	q1.add_step("Make a home: walls, a roof, a door, a light and a bed", QuestDef.ObjectiveType.BUILD_ROOM, &"shelter", 1)
	q1.rewards["brass_guilder"] = 25
	q1.rewards["items"] = [{"id": "seed_shore_wheat", "count": 5}]
	register_available_quest(q1)

	var q2 := QuestDef.new(&"story_tide_tackle", "What the Tide Brings", "Old Man Corin")
	q2.storyline_act = 1
	q2.add_step("Catch 2 Silver Mackerel during high tide", QuestDef.ObjectiveType.CATCH_FISH, &"silver_mackerel", 2)
	q2.add_step("Harvest 2 Sea Salt from coastal evaporation pans", QuestDef.ObjectiveType.GATHER_ITEM, &"sea_salt", 2)
	q2.rewards["brass_guilder"] = 40
	q2.rewards["tide_scrip"] = 5
	q2.rewards["items"] = [{"id": "blueprint_tide_mill", "count": 1}]
	register_available_quest(q2)

	# Storyline Act II: Depths of the Murk-Reef & The Incursions
	var q3 := QuestDef.new(&"story_phosphor_flare", "Lanterns of the Trench", "Elder Brenda")
	q3.storyline_act = 2
	q3.add_step("Craft a Phosphor Brazier at the workbench", QuestDef.ObjectiveType.CRAFT_ITEM, &"phosphor_brazier", 1)
	q3.add_step("Place a Phosphor Brazier in the sound or shallows", QuestDef.ObjectiveType.PLACE_ENTITY, &"phosphor_brazier", 1)
	q3.rewards["brass_guilder"] = 50
	q3.rewards["tide_scrip"] = 10
	q3.rewards["items"] = [{"id": "sea_brass_ingot", "count": 2}]
	register_available_quest(q3)

	var q4 := QuestDef.new(&"story_siren_hunt", "The Siren's Requiem", "Old Man Corin")
	q4.storyline_act = 2
	q4.add_step("Stun and defeat the Abyssal Siren in the Murk-Reef", QuestDef.ObjectiveType.DEFEAT_ENEMY, &"abyssal_siren", 1)
	q4.add_step("Recover the Heart of the Siren", QuestDef.ObjectiveType.GATHER_ITEM, &"siren_heart", 1)
	q4.rewards["brass_guilder"] = 120
	q4.rewards["tide_scrip"] = 25
	q4.rewards["items"] = [{"id": "ancient_weapon_fragment", "count": 2}]
	register_available_quest(q4)

	var q5 := QuestDef.new(&"story_storm_fortress", "The Shoreline Bastion", "Town Guard")
	q5.storyline_act = 2
	q5.add_step("Erect 2 Spike Barricades along the shoreline", QuestDef.ObjectiveType.PLACE_ENTITY, &"defense_barricade", 2)
	q5.add_step("Ring the Harbour Bell and repel a Storm Incursion", QuestDef.ObjectiveType.SURVIVE_INCURSION, &"storm_incursion", 1)
	q5.rewards["brass_guilder"] = 80
	q5.rewards["tide_scrip"] = 15
	q5.rewards["items"] = [{"id": "reaver_crest", "count": 2}]
	register_available_quest(q5)

	# Storyline Act III: The Basalt Skerries & The Grand Equilibrium
	var q6 := QuestDef.new(&"story_caldera_hunt", "Fire of the Benthic Deep", "Old Man Corin")
	q6.storyline_act = 3
	q6.add_step("Defeat the Caldera Shell in the Basalt Skerries", QuestDef.ObjectiveType.DEFEAT_ENEMY, &"caldera_shell", 1)
	q6.add_step("Forge Volcanic Basalt Armor at the Blacksmith's Anvil", QuestDef.ObjectiveType.CRAFT_ITEM, &"volcanic_basalt_armor", 1)
	q6.rewards["brass_guilder"] = 150
	q6.rewards["tide_scrip"] = 30
	q6.rewards["items"] = [{"id": "ancient_weapon_fragment", "count": 3}]
	register_available_quest(q6)

	var q7 := QuestDef.new(&"story_undertow_trial", "Trial of the Spring Tide", "Elder Brenda")
	q7.storyline_act = 3
	q7.add_step("Channel the Undertow Altar during spring low tide", QuestDef.ObjectiveType.SURVIVE_INCURSION, &"undertow_altar", 1)
	q7.add_step("Claim the Ancient Regulator Keystone", QuestDef.ObjectiveType.GATHER_ITEM, &"regulator_keystone", 1)
	q7.rewards["brass_guilder"] = 120
	q7.rewards["tide_scrip"] = 25
	q7.rewards["items"] = [{"id": "undertow_crest", "count": 1}]
	register_available_quest(q7)

	var q8 := QuestDef.new(&"story_grand_regulator", "The Grand Equilibrium", "Cartographer Vane")
	q8.storyline_act = 3
	q8.add_step("Erect an Ancient Tide Regulator on the high ground", QuestDef.ObjectiveType.PLACE_ENTITY, &"tide_regulator", 1)
	q8.rewards["brass_guilder"] = 250
	q8.rewards["tide_scrip"] = 50
	q8.rewards["items"] = [{"id": "gilded_ship_wheel", "count": 1}]
	register_available_quest(q8)

	# Storyline Act IV: The Frozen Reach & The Maelstrom
	var q9 := QuestDef.new(&"story_borean_hunt", "The Glacial Patriarch", "Old Salt Rorik")
	q9.storyline_act = 4
	q9.add_step("Defeat Borean Gore-Fin in the Frost-Shoals", QuestDef.ObjectiveType.DEFEAT_ENEMY, &"borean_gore_fin", 1)
	q9.add_step("Tailor a Borean Insulated Parka", QuestDef.ObjectiveType.CRAFT_ITEM, &"borean_parka", 1)
	q9.rewards["brass_guilder"] = 200
	q9.rewards["tide_scrip"] = 40
	q9.rewards["items"] = [{"id": "glacial_tusk", "count": 2}]
	register_available_quest(q9)

	var q10 := QuestDef.new(&"story_tide_sovereign", "Heart of the Deluge", "Elder Brenda")
	q10.storyline_act = 4
	q10.add_step("Vanquish The Tide Sovereign at the Maelstrom Spire", QuestDef.ObjectiveType.DEFEAT_ENEMY, &"tide_sovereign", 1)
	q10.add_step("Claim the Deluge Core", QuestDef.ObjectiveType.GATHER_ITEM, &"deluge_core", 1)
	q10.rewards["brass_guilder"] = 500
	q10.rewards["tide_scrip"] = 100
	q10.rewards["items"] = [{"id": "deluge_core", "count": 1}]
	register_available_quest(q10)

	var q11 := QuestDef.new(&"story_grand_architecture", "Master of the Skerries", "Cartographer Vane")
	q11.storyline_act = 4
	q11.add_step("Construct an Architect's Drafting Desk", QuestDef.ObjectiveType.PLACE_ENTITY, &"drafting_desk", 1)
	q11.add_step("Draft an Architectural Blueprint Scroll", QuestDef.ObjectiveType.CRAFT_ITEM, &"blueprint_scroll", 1)
	q11.rewards["brass_guilder"] = 180
	q11.rewards["tide_scrip"] = 35
	register_available_quest(q11)

	# Notice Board & Villager Chores
	var chore_regatta := QuestDef.new(&"chore_regatta_trial", "The Saltwater Regatta", "Dockmaster Oisin")
	chore_regatta.add_step("Place a Regatta Checkpoint Buoy in open water", QuestDef.ObjectiveType.PLACE_ENTITY, &"regatta_buoy", 1)
	chore_regatta.add_step("Sail through the course buoys to complete a trial", QuestDef.ObjectiveType.COMPLETE_REGATTA, &"regatta_buoy", 1)
	chore_regatta.rewards["brass_guilder"] = 45
	chore_regatta.rewards["tide_scrip"] = 8
	register_available_quest(chore_regatta)

	var chore_spar := QuestDef.new(&"chore_sparring_bout", "Sharpening the Salt", "Old Salt Rorik")
	chore_spar.add_step("Place a Town Sparring Ring on the beach", QuestDef.ObjectiveType.PLACE_ENTITY, &"sparring_ring", 1)
	chore_spar.add_step("Win a friendly sparring bout in the ring", QuestDef.ObjectiveType.WIN_SPARRING, &"sparring_ring", 1)
	chore_spar.rewards["brass_guilder"] = 35
	chore_spar.rewards["tide_scrip"] = 5
	register_available_quest(chore_spar)

	var chore1 := QuestDef.new(&"chore_winter_kale", "Greens for the Kettle", "Town Cook Barnaby")
	chore1.add_step("Harvest 4 Tide Kale", QuestDef.ObjectiveType.HARVEST_CROP, &"tide_kale", 4)
	chore1.rewards["brass_guilder"] = 15
	register_available_quest(chore1)

	var chore2 := QuestDef.new(&"chore_mara_catch", "Mara's Tide Catch", "Mara")
	chore2.add_step("Catch 2 Silver Mackerel", QuestDef.ObjectiveType.CATCH_FISH, &"silver_mackerel", 2)
	chore2.add_step("Return to Mara", QuestDef.ObjectiveType.TALK_TO, &"Mara", 1)
	chore2.rewards["brass_guilder"] = 20
	chore2.rewards["items"] = [{"id": "bait_lugworm", "count": 3}]
	register_available_quest(chore2)

	var chore3 := QuestDef.new(&"chore_tobin_timber", "Tobin's Driftwood Reserve", "Tobin")
	chore3.add_step("Collect 6 Driftwood", QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 6)
	chore3.add_step("Return to Tobin", QuestDef.ObjectiveType.TALK_TO, &"Tobin", 1)
	chore3.rewards["brass_guilder"] = 20
	chore3.rewards["items"] = [{"id": "plank", "count": 4}]
	register_available_quest(chore3)


func register_available_quest(q: QuestDef) -> void:
	available_quests[q.id] = q


func accept_quest(quest_id: StringName) -> bool:
	if not available_quests.has(quest_id) or active_quests.has(quest_id) or quest_id in completed_quests:
		return false

	var q: QuestDef = available_quests[quest_id]
	active_quests[quest_id] = q
	available_quests.erase(quest_id)
	quest_accepted.emit(q)
	return true


func is_quest_active(quest_id: StringName) -> bool:
	return active_quests.has(quest_id)


func is_quest_completed(quest_id: StringName) -> bool:
	return quest_id in completed_quests


func get_quests_by_act(act: int) -> Array[QuestDef]:
	var result: Array[QuestDef] = []
	for q in available_quests.values():
		if q.storyline_act == act:
			result.append(q)
	for q in active_quests.values():
		if q.storyline_act == act and not result.has(q):
			result.append(q)
	for q_id in completed_quests:
		var q = get_quest_def(q_id)
		if q != null and q.storyline_act == act and not result.has(q):
			result.append(q)
	return result


func get_quest_def(quest_id: StringName) -> QuestDef:
	if active_quests.has(quest_id):
		return active_quests[quest_id]
	if completed_quest_defs.has(quest_id):
		return completed_quest_defs[quest_id]
	if available_quests.has(quest_id):
		return available_quests[quest_id]
	return null


func can_accept_rewards(inv: Inventory, q: QuestDef) -> bool:
	if inv == null or q == null:
		return true
	var list := q.get_reward_items()
	return inv.can_fit_items(list)


# -------------------------------------------------------------------------
# Event Hooks
# -------------------------------------------------------------------------

func notify_event(type: QuestDef.ObjectiveType, target_id: StringName, amount: int = 1, inv: Inventory = null) -> void:
	var finished_quests: Array[StringName] = []

	for q_id: StringName in active_quests.keys():
		var q: QuestDef = active_quests[q_id]
		var advanced := false

		for step in q.steps:
			if not step.is_completed and step.type == type and (step.target_id == target_id or step.target_id == &""):
				var just_finished: bool = step.progress(amount)
				advanced = true
				quest_progressed.emit(q, step)
				if just_finished:
					break

		if q.is_complete():
			if inv != null and not can_accept_rewards(inv, q):
				if not paused_reward_quests.has(q_id):
					paused_reward_quests.append(q_id)
				quest_rewards_paused.emit(q)
				quest_progressed.emit(q, q.steps[-1] if not q.steps.is_empty() else null)
			else:
				if paused_reward_quests.has(q_id):
					paused_reward_quests.erase(q_id)
				finished_quests.append(q_id)

	# Complete finished quests and payout rewards
	for f_id in finished_quests:
		_complete_quest(f_id, inv)


func check_paused_rewards(inv: Inventory) -> Array[StringName]:
	if inv == null:
		return []
	var ready_to_claim: Array[StringName] = []
	for q_id in paused_reward_quests:
		var q: QuestDef = active_quests.get(q_id)
		if q != null and can_accept_rewards(inv, q):
			ready_to_claim.append(q_id)
	for q_id in ready_to_claim:
		paused_reward_quests.erase(q_id)
		_complete_quest(q_id, inv)
	return ready_to_claim


func _complete_quest(quest_id: StringName, inv: Inventory = null) -> void:
	var q: QuestDef = active_quests.get(quest_id, null)
	if not q:
		return

	if paused_reward_quests.has(quest_id):
		paused_reward_quests.erase(quest_id)

	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	completed_quest_defs[quest_id] = q

	# Payout rewards into player inventory if provided
	if inv != null:
		var brass: int = q.rewards.get("brass_guilder", 0)
		if brass > 0:
			inv.add_item(&"brass_guilder", brass)

		var scrip: int = q.rewards.get("tide_scrip", 0)
		if scrip > 0:
			inv.add_item(&"tide_scrip", scrip)

		var items: Array = q.rewards.get("items", [])
		for item_data in items:
			inv.add_item(StringName(item_data["id"]), int(item_data["count"]))

	quest_completed.emit(q)


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func serialize() -> Dictionary:
	var a_data: Array = []
	for q in active_quests.values():
		var steps_data: Array = []
		for s in q.steps:
			steps_data.append(s.to_dict())
		a_data.append({
			"id": String(q.id),
			"title": q.title,
			"giver": q.giver_name,
			"act": q.storyline_act,
			"rewards": q.rewards.duplicate(true),
			"steps": steps_data
		})

	var c_data: Array = []
	for cid in completed_quests:
		c_data.append(String(cid))

	var p_data: Array = []
	for pid in paused_reward_quests:
		p_data.append(String(pid))

	return {
		"active": a_data,
		"completed": c_data,
		"paused": p_data
	}


func deserialize(data: Dictionary) -> void:
	active_quests.clear()
	completed_quests.clear()
	paused_reward_quests.clear()

	if data.has("completed"):
		for cid in data["completed"]:
			completed_quests.append(StringName(cid))

	if data.has("paused"):
		for pid in data["paused"]:
			paused_reward_quests.append(StringName(pid))

	if data.has("active"):
		for q_dict in data["active"]:
			var q := QuestDef.new(StringName(q_dict["id"]), q_dict["title"], q_dict["giver"])
			q.storyline_act = int(q_dict.get("act", 1))
			q.rewards = q_dict.get("rewards", {}).duplicate(true)
			if q_dict.has("steps"):
				for s_dict in q_dict["steps"]:
					q.steps.append(QuestDef.QuestStep.from_dict(s_dict))
			active_quests[q.id] = q
