class_name QuestManager
extends RefCounted
## Manages active quests, story arcs, villager requests, and objective progress.

signal quest_accepted(quest: QuestDef)
signal quest_progressed(quest: QuestDef, step: QuestDef.QuestStep)
signal quest_completed(quest: QuestDef)

var active_quests: Dictionary = {}          ## quest_id -> QuestDef
var completed_quests: Array[StringName] = []## Array of completed quest IDs
var available_quests: Dictionary = {}        ## quest_id -> QuestDef (Notice board)


func _init() -> void:
	_init_storyline_catalogue()


func _init_storyline_catalogue() -> void:
	# Storyline Act I: Reclaiming the Shallows
	var q1 := QuestDef.new(&"story_first_hearth", "The First Hearth", "Elder Brenda")
	q1.storyline_act = 1
	q1.add_step("Collect 10 Driftwood from coastal flats", QuestDef.ObjectiveType.GATHER_ITEM, &"driftwood", 10)
	q1.add_step("Construct and validate an enclosed shelter", QuestDef.ObjectiveType.BUILD_ROOM, &"shelter", 1)
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

	# Notice Board Chores
	var chore1 := QuestDef.new(&"chore_winter_kale", "Greens for the Kettle", "Town Cook Barnaby")
	chore1.add_step("Harvest 4 Tide Kale", QuestDef.ObjectiveType.HARVEST_CROP, &"tide_kale", 4)
	chore1.rewards["brass_guilder"] = 15
	register_available_quest(chore1)


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
			finished_quests.append(q_id)

	# Complete finished quests and payout rewards
	for f_id in finished_quests:
		_complete_quest(f_id, inv)


func _complete_quest(quest_id: StringName, inv: Inventory = null) -> void:
	var q: QuestDef = active_quests.get(quest_id, null)
	if not q:
		return

	active_quests.erase(quest_id)
	completed_quests.append(quest_id)

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

	return {
		"active": a_data,
		"completed": c_data
	}


func deserialize(data: Dictionary) -> void:
	active_quests.clear()
	completed_quests.clear()

	if data.has("completed"):
		for cid in data["completed"]:
			completed_quests.append(StringName(cid))

	if data.has("active"):
		for q_dict in data["active"]:
			var q := QuestDef.new(StringName(q_dict["id"]), q_dict["title"], q_dict["giver"])
			q.storyline_act = int(q_dict.get("act", 1))
			q.rewards = q_dict.get("rewards", {}).duplicate(true)
			if q_dict.has("steps"):
				for s_dict in q_dict["steps"]:
					q.steps.append(QuestDef.QuestStep.from_dict(s_dict))
			active_quests[q.id] = q
