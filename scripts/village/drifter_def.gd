class_name DrifterDef
extends Resource
## Villager definition, profession, routines, and work production logic.

enum Profession {
	FISHER,       ## Catches fish and stocks town barrels
	FARMER,       ## Cultivates crops and salt pans
	CARPENTER,    ## Refines logs into lumber and planks
	SMOKER_CHEF,  ## Smokes fish and cooks hearty meals
	LAMPLIGHTER,  ## Renders fish into lamp oil and keeps the lighthouse lamp filled
	TRADER,       ## Sells town surplus to visiting merchant boats
	RANCHER,      ## Tends livestock and gathers milk, wool, and eggs
	BUILDER       ## Hauls materials from Community Chest and erects requested buildings
}

const LAMP_OIL_STOCK := 6   ## the lamplighter stops rendering fish once the depot holds this much oil
## [fish, how many make 1 Refined Fish Oil], same as the hand recipes
const OIL_FISH := [[&"cliff_salmon", 1], [&"silver_mackerel", 2], [&"tidepool_flounder", 2]]

enum Routine {
	SLEEP,        ## Resting in assigned room (night)
	WORK,         ## Performing profession chores (morning to afternoon)
	EAT,          ## Eating meals at town tavern / hearth (midday & evening)
	SOCIALIZE     ## Gathering at harbor / village square (dusk)
}

@export var id: StringName = &""
@export var name: String = ""
@export var profession: Profession = Profession.FISHER
@export var morale: float = 0.8         ## 0.0 to 1.0; boosts productivity by up to +30%
@export var assigned_room_id: int = -1  ## Index of assigned validated room, or -1 if homeless
@export var job_locked := false         ## the player picked this job; the town won't reassign them
var current_routine: Routine = Routine.WORK
var work_progress_sec: float = 0.0
var last_gift_time: float = -9999.0


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_profession: Profession = Profession.FISHER
) -> void:
	id = p_id
	name = p_name
	profession = p_profession


func is_homeless() -> bool:
	return assigned_room_id < 0


## Simulates daily routine transitions based on day/night cycle fraction (0.0=dawn, 0.5=noon, 0.75=dusk, 1.0=night)
func update_routine(day_fraction: float) -> void:
	if day_fraction < 0.2:
		current_routine = Routine.SLEEP
	elif day_fraction < 0.65:
		current_routine = Routine.WORK
	elif day_fraction < 0.8:
		current_routine = Routine.EAT
	elif day_fraction < 0.9:
		current_routine = Routine.SOCIALIZE
	else:
		current_routine = Routine.SLEEP


## Simulates work shift production. Deposits finished yields into the town depot.
## Returns dictionary of produced items: {"item_id": count}
func tick_work(delta_sec: float, town_depot: StorageContainer) -> Dictionary:
	if current_routine != Routine.WORK:
		return {}

	# Homelessness reduces work efficiency by 50%
	var home_mult: float = 1.0 if not is_homeless() else 0.5
	var morale_mult: float = 0.7 + morale * 0.6 # 0.7x to 1.3x speed
	work_progress_sec += delta_sec * home_mult * morale_mult

	# Base work cycle completes every 60 seconds of active work
	if work_progress_sec < 60.0:
		return {}

	work_progress_sec = 0.0
	var produced: Dictionary = {}

	match profession:
		Profession.FISHER:
			var fish_id: StringName = &"silver_mackerel" if randf() < 0.6 else &"tidepool_flounder"
			town_depot.deposit(fish_id, 2)
			produced[fish_id] = 2

		Profession.FARMER:
			var crop_id: StringName = &"shore_wheat" if randf() < 0.5 else &"tide_kale"
			town_depot.deposit(crop_id, 3)
			produced[crop_id] = 3

		Profession.CARPENTER:
			# Consumes 1 pine wood or driftwood to produce 4 wood planks
			if town_depot.inventory.has_item(&"driftwood", 1):
				town_depot.withdraw(&"driftwood", 1)
				town_depot.deposit(&"wood_plank", 4)
				produced[&"wood_plank"] = 4
			elif town_depot.inventory.has_item(&"pine_wood", 1):
				town_depot.withdraw(&"pine_wood", 1)
				town_depot.deposit(&"wood_plank", 4)
				produced[&"wood_plank"] = 4

		Profession.SMOKER_CHEF:
			# Converts raw fish + sea salt into preserved smoked rations
			if town_depot.inventory.has_item(&"silver_mackerel", 1) and town_depot.inventory.has_item(&"sea_salt", 1):
				town_depot.withdraw(&"silver_mackerel", 1)
				town_depot.withdraw(&"sea_salt", 1)
				town_depot.deposit(&"smoked_fish_ration", 2)
				produced[&"smoked_fish_ration"] = 2

		Profession.LAMPLIGHTER:
			# Renders fish from the depot into lamp oil, keeping a small stock for the lighthouse
			# (VillageManager has them pour it into the lamp).
			if town_depot.inventory.get_item_count(&"fish_oil") < LAMP_OIL_STOCK:
				for src: Array in OIL_FISH:
					if town_depot.inventory.has_item(src[0], src[1]):
						town_depot.withdraw(src[0], src[1])
						town_depot.deposit(&"fish_oil", 1)
						produced[&"fish_oil"] = 1
						break

		Profession.TRADER:
			# Converts surplus cured fish into trade currency
			if town_depot.inventory.has_item(&"smoked_fish_ration", 2):
				town_depot.withdraw(&"smoked_fish_ration", 2)
				town_depot.deposit(&"brass_guilder", 3)
				produced[&"brass_guilder"] = 3

		Profession.RANCHER:
			# Tends livestock and gathers milk, wool, or eggs into town depot
			var produce: StringName = [&"salt_milk", &"sea_wool", &"sea_egg"].pick_random()
			town_depot.deposit(produce, 2)
			produced[produce] = 2

		Profession.BUILDER:
			# Shapes masonry and refines timber for village construction
			if town_depot.inventory.has_item(&"stone", 2):
				town_depot.withdraw(&"stone", 2)
				town_depot.deposit(&"cobblestone", 2)
				produced[&"cobblestone"] = 2
			elif town_depot.inventory.has_item(&"driftwood", 1):
				town_depot.withdraw(&"driftwood", 1)
				town_depot.deposit(&"wood_plank", 4)
				produced[&"wood_plank"] = 4
			else:
				town_depot.deposit(&"stone", 2)
				produced[&"stone"] = 2

	return produced


## Work routine specifically for constructing an active building site.
## Draws needed materials from community chest/depot and advances site progress.
func tick_builder_site(delta_sec: float, site: ConstructionSiteEntity, chest: ChestEntity = null, world: VoxelWorld = null) -> bool:
	if profession != Profession.BUILDER or current_routine != Routine.WORK or site == null or site.is_completed:
		return false

	var home_mult: float = 1.0 if not is_homeless() else 0.5
	var morale_mult: float = 0.7 + morale * 0.6
	var build_power: float = delta_sec * 0.05 * home_mult * morale_mult

	if chest != null and not site.is_materials_satisfied():
		site.pull_from_chest(chest)

	return site.build_step(build_power, world)


func profession_name() -> String:
	return profession_label(profession)


static func profession_label(prof: int) -> String:
	match prof:
		Profession.FISHER: return "Fisher"
		Profession.FARMER: return "Farmer"
		Profession.CARPENTER: return "Carpenter"
		Profession.SMOKER_CHEF: return "Smoker-Chef"
		Profession.LAMPLIGHTER: return "Lamplighter"
		Profession.TRADER: return "Trader"
		Profession.RANCHER: return "Rancher"
		Profession.BUILDER: return "Builder"
		_: return "Drifter"


func serialize() -> Dictionary:
	return {
		"id": String(id),
		"name": name,
		"profession": profession,
		"morale": morale,
		"room_id": assigned_room_id,
		"work_progress": work_progress_sec,
		"job_locked": job_locked
	}


static func deserialize(d: Dictionary) -> DrifterDef:
	var drifter := DrifterDef.new(
		StringName(d.get("id", "")),
		d.get("name", "Drifter"),
		int(d.get("profession", 0))
	)
	drifter.morale = float(d.get("morale", 0.8))
	drifter.assigned_room_id = int(d.get("room_id", -1))
	drifter.work_progress_sec = float(d.get("work_progress", 0.0))
	drifter.job_locked = bool(d.get("job_locked", false))
	return drifter
