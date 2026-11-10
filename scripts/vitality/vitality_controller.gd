class_name VitalityController
extends RefCounted
## Vitality Controller for Brine's Hollow.
## Implements the Vitality Triad: Nourishment (Hunger), Health & Stamina.
## Adheres strictly to Design Pillar 2 ("Home is always safe; danger is opt-in").

signal hp_changed(current: float, max_val: float)
signal stamina_changed(current: float, max_val: float)
signal breath_changed(current: float, max_val: float)
signal stomach_updated(active_meals: Array)
signal meal_consumed(item_id: StringName, food_data: Dictionary)
signal exhaustion_started
signal exhaustion_ended
signal rested_state_changed(is_rested: bool)
signal player_damaged(amount: float, damage_type: StringName)
signal player_defeated(defeat_pos: Vector3)
signal player_revived

const BASE_MAX_HP: float = 25.0
const BASE_MAX_STAMINA: float = 50.0
const BASE_MAX_BREATH: float = 30.0
const MAX_STOMACH_SLOTS: int = 3
const BASE_STAMINA_RECHARGE_RATE: float = 16.0 ## Stamina units per second
const STAMINA_RECHARGE_DELAY: float = 0.8     ## Delay in seconds after exertion before recharge starts
const EXHAUSTION_DURATION: float = 2.0        ## Out of breath state duration
const DROWNING_DAMAGE_RATE: float = 6.0       ## HP lost per second when air runs out

var current_hp: float = BASE_MAX_HP
var current_stamina: float = BASE_MAX_STAMINA
var current_breath: float = BASE_MAX_BREATH

var is_defeated: bool = false
var is_exhausted: bool = false
var is_rested: bool = false
var has_diving_helmet: bool = false

## Active meals in stomach: Array of Dictionaries
## Each entry: {
##   "item_id": StringName,
##   "name": String,
##   "duration_sec": float,
##   "remaining_sec": float,
##   "hp_bonus": int,
##   "stamina_bonus": int,
##   "regen_hp_sec": float,
##   "stamina_regen_mult": float,
##   "swim_speed": float,
##   "cold_immunity": bool,
##   "extra_breath_sec": float
## }
var active_meals: Array[Dictionary] = []

var _stamina_recharge_timer: float = 0.0
var _exhaustion_timer: float = 0.0


func _init() -> void:
	current_hp = BASE_MAX_HP
	current_stamina = BASE_MAX_STAMINA
	current_breath = BASE_MAX_BREATH


# =============================================================================
# STAT ATTRIBUTES & CALCULATIONS
# =============================================================================

func get_max_hp() -> float:
	var total: float = BASE_MAX_HP
	for meal in active_meals:
		total += float(meal.get("hp_bonus", 0))
	return total


func get_max_stamina() -> float:
	var total: float = BASE_MAX_STAMINA
	for meal in active_meals:
		total += float(meal.get("stamina_bonus", 0))
	return total


func get_max_breath() -> float:
	var total: float = BASE_MAX_BREATH
	for meal in active_meals:
		total += float(meal.get("extra_breath_sec", 0.0))
	return total


func get_hp_regen_rate() -> float:
	if is_defeated:
		return 0.0
	var base_regen: float = 0.0
	for meal in active_meals:
		base_regen += float(meal.get("regen_hp_sec", 0.0))
	if is_rested:
		# Sea-Breeze Rested buff accelerates healing (+1.0 base or 1.3x)
		base_regen = (base_regen * 1.3) + 1.0
	return base_regen


func get_stamina_regen_rate() -> float:
	var mult: float = 1.0
	for meal in active_meals:
		var m: float = float(meal.get("stamina_regen_mult", 1.0))
		if m > 1.0:
			mult += (m - 1.0)
	if is_rested:
		mult *= 1.5 # +50% stamina recharge from Rested comfort
	return BASE_STAMINA_RECHARGE_RATE * mult


func get_swim_speed_multiplier() -> float:
	var mult: float = 1.0
	for meal in active_meals:
		var s: float = float(meal.get("swim_speed", 1.0))
		if s > 1.0:
			mult += (s - 1.0)
	return mult


var has_cold_protection: bool = false


func has_cold_immunity() -> bool:
	if has_cold_protection:
		return true
	for meal in active_meals:
		if bool(meal.get("cold_immunity", false)):
			return true
	return false


# =============================================================================
# 3-MEAL SATIETY STOMACH & NOURISHMENT
# =============================================================================

## Share of a meal's digestion that must have passed before the same dish can be eaten
## again. Until then you're "still full" of it and eating is refused (nothing is used up).
const REEAT_AFTER := 0.5


func can_eat_food(item_id: StringName) -> bool:
	if not ItemDB.has_item(item_id):
		return false
	var def: ItemDef = ItemDB.get_item(item_id)
	return def.category == ItemDef.Category.FOOD and not def.food_data.is_empty() and not is_full_of(item_id)


## True while the same dish is still mostly undigested (eating it again would do nothing).
func is_full_of(item_id: StringName) -> bool:
	for meal in active_meals:
		if meal.item_id == item_id:
			return float(meal.remaining_sec) > float(meal.duration_sec) * REEAT_AFTER
	return false


## Seconds until `item_id` can be eaten again (0 if it can be now).
func reeat_wait_sec(item_id: StringName) -> float:
	for meal in active_meals:
		if meal.item_id == item_id:
			return maxf(0.0, float(meal.remaining_sec) - float(meal.duration_sec) * REEAT_AFTER)
	return 0.0


func eat_food(item_id: StringName, inv: Inventory = null) -> bool:
	if is_defeated:
		return false
	if not ItemDB.has_item(item_id):
		return false
	var def: ItemDef = ItemDB.get_item(item_id)
	if def.category != ItemDef.Category.FOOD or def.food_data.is_empty():
		return false
	if is_full_of(item_id):
		return false   # still full of this dish: don't waste it

	if inv != null:
		if not inv.has_item(item_id, 1):
			return false
		if not inv.remove_item(item_id, 1):
			return false

	var data: Dictionary = def.food_data
	var duration: float = float(data.get("duration_sec", 900.0))
	var hp_bon: int = int(data.get("hp_bonus", 0))
	var sta_bon: int = int(data.get("stamina_bonus", 0))

	# Check if this meal type is already in stomach (refresh timer)
	var existing_idx: int = -1
	for i in range(active_meals.size()):
		if active_meals[i].item_id == item_id:
			existing_idx = i
			break

	var meal_entry: Dictionary = {
		"item_id": item_id,
		"name": def.name,
		"duration_sec": duration,
		"remaining_sec": duration,
		"hp_bonus": hp_bon,
		"stamina_bonus": sta_bon,
		"regen_hp_sec": float(data.get("regen_hp_sec", 0.0)),
		"stamina_regen_mult": float(data.get("stamina_regen_mult", 1.0)),
		"swim_speed": float(data.get("swim_speed", 1.0)),
		"cold_immunity": bool(data.get("cold_immunity", false)),
		"extra_breath_sec": float(data.get("extra_breath_sec", 0.0))
	}

	if existing_idx >= 0:
		active_meals[existing_idx] = meal_entry
	else:
		if active_meals.size() >= MAX_STOMACH_SLOTS:
			# Evict meal with smallest remaining digestion time
			var lowest_idx: int = 0
			var lowest_rem: float = active_meals[0].remaining_sec
			for i in range(1, active_meals.size()):
				if active_meals[i].remaining_sec < lowest_rem:
					lowest_rem = active_meals[i].remaining_sec
					lowest_idx = i
			active_meals[lowest_idx] = meal_entry
		else:
			active_meals.append(meal_entry)
	# Immediate sustenance (a refreshed dish tops you up too)
	current_hp = minf(get_max_hp(), current_hp + float(hp_bon))

	current_stamina = minf(get_max_stamina(), current_stamina + float(sta_bon))
	stomach_updated.emit(active_meals)
	meal_consumed.emit(item_id, data)
	hp_changed.emit(current_hp, get_max_hp())
	stamina_changed.emit(current_stamina, get_max_stamina())
	return true


func get_active_meals() -> Array[Dictionary]:
	return active_meals


func has_meal(item_id: StringName) -> bool:
	for meal in active_meals:
		if meal.item_id == item_id:
			return true
	return false


func clear_stomach() -> void:
	active_meals.clear()
	current_hp = minf(current_hp, get_max_hp())
	current_stamina = minf(current_stamina, get_max_stamina())
	current_breath = minf(current_breath, get_max_breath())
	stomach_updated.emit(active_meals)
	hp_changed.emit(current_hp, get_max_hp())
	stamina_changed.emit(current_stamina, get_max_stamina())


# =============================================================================
# PHYSICAL EXERTION & STAMINA CONSUMPTION
# =============================================================================

func consume_stamina(amount: float) -> bool:
	if is_exhausted or is_defeated:
		return false
	if current_stamina < 0.1:
		return false

	current_stamina -= amount
	_stamina_recharge_timer = STAMINA_RECHARGE_DELAY

	if current_stamina <= 0.0:
		current_stamina = 0.0
		_start_exhaustion()

	stamina_changed.emit(current_stamina, get_max_stamina())
	return true


func drain_stamina_continuous(rate_per_sec: float, delta: float) -> bool:
	if is_exhausted or is_defeated:
		return false
	return consume_stamina(rate_per_sec * delta)


func _start_exhaustion() -> void:
	if not is_exhausted:
		is_exhausted = true
		_exhaustion_timer = EXHAUSTION_DURATION
		exhaustion_started.emit()


# =============================================================================
# HEALTH, DAMAGE, HEALING & NON-PUNITIVE DEFEAT
# =============================================================================

func take_damage(amount: float, damage_type: StringName = &"physical", origin_pos: Vector3 = Vector3.ZERO) -> float:
	if is_defeated or amount <= 0.0:
		return 0.0

	# Cold immunity completely protects against Arctic hypothermia
	if damage_type == &"cold" and has_cold_immunity():
		return 0.0

	var actual_damage: float = minf(amount, current_hp)
	current_hp = maxf(0.0, current_hp - amount)

	player_damaged.emit(amount, damage_type)
	hp_changed.emit(current_hp, get_max_hp())

	if current_hp <= 0.0:
		is_defeated = true
		player_defeated.emit(origin_pos)

	return actual_damage


func heal(amount: float) -> float:
	if is_defeated or amount <= 0.0:
		return 0.0
	var old_hp: float = current_hp
	current_hp = minf(get_max_hp(), current_hp + amount)
	var diff: float = current_hp - old_hp
	if diff > 0.0:
		hp_changed.emit(current_hp, get_max_hp())
	return diff


func revive(pos: Vector3 = Vector3.ZERO) -> void:
	is_defeated = false
	is_exhausted = false
	_exhaustion_timer = 0.0
	_stamina_recharge_timer = 0.0
	current_hp = BASE_MAX_HP
	current_stamina = BASE_MAX_STAMINA
	current_breath = get_max_breath()

	player_revived.emit()
	hp_changed.emit(current_hp, get_max_hp())
	stamina_changed.emit(current_stamina, get_max_stamina())
	breath_changed.emit(current_breath, get_max_breath())


func set_rested(rested: bool) -> void:
	if is_rested != rested:
		is_rested = rested
		rested_state_changed.emit(is_rested)


# =============================================================================
# TIME TICKING (DIGESTION, REGENERATION, EXHAUSTION, BREATH)
# =============================================================================

func tick(delta: float, is_submerged: bool = false, is_exerting: bool = false) -> void:
	if delta <= 0.0:
		return

	# 1. Digestion decay of active meals in stomach
	var meals_changed := false
	var i := active_meals.size() - 1
	while i >= 0:
		active_meals[i].remaining_sec -= delta
		if active_meals[i].remaining_sec <= 0.0:
			active_meals.remove_at(i)
			meals_changed = true
		i -= 1

	if meals_changed:
		# Clamp current stats if max was reduced
		current_hp = minf(current_hp, get_max_hp())
		current_stamina = minf(current_stamina, get_max_stamina())
		current_breath = minf(current_breath, get_max_breath())
		stomach_updated.emit(active_meals)
		hp_changed.emit(current_hp, get_max_hp())
		stamina_changed.emit(current_stamina, get_max_stamina())

	if is_defeated:
		return

	# 2. Exhaustion cooldown
	if is_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0.0:
			is_exhausted = false
			_exhaustion_timer = 0.0
			exhaustion_ended.emit()

	# 3. Stamina recharge
	if _stamina_recharge_timer > 0.0:
		_stamina_recharge_timer = maxf(0.0, _stamina_recharge_timer - delta)
	elif not is_exerting and not is_exhausted:
		var max_sta: float = get_max_stamina()
		if current_stamina < max_sta:
			var old_sta: float = current_stamina
			current_stamina = minf(max_sta, current_stamina + get_stamina_regen_rate() * delta)
			if not is_equal_approx(old_sta, current_stamina):
				stamina_changed.emit(current_stamina, max_sta)

	# 4. Natural & Assisted HP regeneration (suppressed while drowning/asphyxiating)
	var max_hp: float = get_max_hp()
	if current_hp < max_hp and current_breath > 0.0:
		var regen: float = get_hp_regen_rate()
		if regen > 0.0:
			var old_hp: float = current_hp
			current_hp = minf(max_hp, current_hp + regen * delta)
			if not is_equal_approx(old_hp, current_hp):
				hp_changed.emit(current_hp, max_hp)

	# 5. Breath & Aquatic Stamina Exhaustion
	var max_br: float = get_max_breath()
	if is_submerged:
		# Underwater: burn oxygen. Burn 50% faster if out of stamina or exhausted.
		# Brass diving helmet reduces oxygen drain by 80% (5x dive time).
		var oxygen_drain: float = 1.5 if (current_stamina <= 0.0 or is_exhausted) else 1.0
		if has_diving_helmet:
			oxygen_drain *= 0.2
		var old_br: float = current_breath
		current_breath = maxf(0.0, current_breath - oxygen_drain * delta)
		if not is_equal_approx(old_br, current_breath):
			breath_changed.emit(current_breath, max_br)

		# Drowning asphyxiation damage when out of air
		if current_breath <= 0.0:
			take_damage(DROWNING_DAMAGE_RATE * delta, &"drowning")
	else:
		# Rapidly catch breath when surfacing
		if current_breath < max_br:
			var old_br: float = current_breath
			current_breath = minf(max_br, current_breath + 25.0 * delta)
			if not is_equal_approx(old_br, current_breath):
				breath_changed.emit(current_breath, max_br)
