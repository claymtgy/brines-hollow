class_name QuestDef
extends Resource
## Data structure for quests, storylines, objectives, and rewards in Brine's Hollow.

enum ObjectiveType {
	GATHER_ITEM,        ## Gather X count of item_id in inventory
	CATCH_FISH,         ## Catch specific fish species
	HARVEST_CROP,       ## Harvest specific crop
	BUILD_ROOM,         ## Construct and validate a room for a drifter
	DISCOVER_LANDMARK,  ## Reach geographic coordinates or beacon
	DEFEAT_ENEMY,       ## Pacify enemy outpost or boss
	PLACE_VOXELS,       ## Build with the hammer (one per placement)
	PLACE_PREFAB,       ## Place a blueprint prefab
	PLACE_ENTITY,       ## Place furniture / gear (target = entity type)
	CRAFT_ITEM,         ## Craft anything (target = output item id, "" = any)
	EAT_FOOD,           ## Eat a meal
	BOARD_BOAT,         ## Board a rowboat
	TALK_TO             ## Speak with an NPC (target = npc id)
}

class QuestStep:
	var description: String = ""
	var type: ObjectiveType = ObjectiveType.GATHER_ITEM
	var target_id: StringName = &""
	var target_count: int = 1
	var current_count: int = 0
	var is_completed: bool = false

	func _init(p_desc: String, p_type: ObjectiveType, p_target: StringName, p_count: int = 1) -> void:
		description = p_desc
		type = p_type
		target_id = p_target
		target_count = p_count
		current_count = 0
		is_completed = false

	func progress(amount: int = 1) -> bool:
		if is_completed:
			return false
		current_count = min(target_count, current_count + amount)
		if current_count >= target_count:
			is_completed = true
			return true
		return false

	func to_dict() -> Dictionary:
		return {
			"desc": description,
			"type": type,
			"target": String(target_id),
			"target_cnt": target_count,
			"current_cnt": current_count,
			"done": is_completed
		}

	static func from_dict(d: Dictionary) -> QuestStep:
		var step := QuestStep.new(
			d.get("desc", ""),
			int(d.get("type", 0)),
			StringName(d.get("target", "")),
			int(d.get("target_cnt", 1))
		)
		step.current_count = int(d.get("current_cnt", 0))
		step.is_completed = bool(d.get("done", false))
		return step

@export var id: StringName = &""
@export var title: String = ""
@export var giver_name: String = "Town Notice Board"
@export var storyline_act: int = 1      ## 1: Reclaiming Shallows, 2: Shattered Isles, 3: Deluge Finale
var steps: Array[QuestStep] = []
var rewards: Dictionary = {             ## {"brass_guilder": 25, "items": [{"id": "blueprint_dry_dock", "count": 1}]}
	"brass_guilder": 0,
	"tide_scrip": 0,
	"items": []
}


func _init(p_id: StringName = &"", p_title: String = "", p_giver: String = "Elder Brenda") -> void:
	id = p_id
	title = p_title
	giver_name = p_giver


func add_step(desc: String, type: ObjectiveType, target: StringName, count: int = 1) -> QuestDef:
	steps.append(QuestStep.new(desc, type, target, count))
	return self


func is_complete() -> bool:
	if steps.is_empty():
		return false
	for s in steps:
		if not s.is_completed:
			return false
	return true
