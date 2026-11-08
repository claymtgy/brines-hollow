class_name FishingController
extends RefCounted
## State machine and tension physics for the active angling minigame.

signal state_changed(new_state: State)
signal cast_started(power: float)
signal bobber_landed(distance_m: float)
signal nibble_telegraphed
signal hook_window_opened(duration_sec: float)
signal reeling_updated(tension: float, distance_m: float, fish_pull: float)
signal fish_landed(fish: FishDef, weight_kg: float)
signal fish_escaped(reason: String)

enum State {
	IDLE,
	CASTING,
	WAITING_FOR_BITE,
	NIBBLING,
	HOOK_WINDOW,
	REELING,
	CAUGHT,
	LOST
}

var current_state: State = State.IDLE
var active_fish: FishDef = null
var fish_weight_kg: float = 1.0
var rod_tier: int = 1

# Cast & Line parameters
var cast_power: float = 0.0
var line_distance: float = 0.0      ## Distance in metres remaining to reel in
var line_tension: float = 0.25      ## 0.0 (slack) to 1.0 (snap!)
var cast_distance: float = 0.0      ## Line length at the moment of the cast
## 0.0 = fish still where the lure landed, 1.0 = fish at the rod.
var reel_progress: float:
	get:
		if cast_distance <= 0.0:
			return 0.0
		return clampf(1.0 - line_distance / cast_distance, 0.0, 1.0)
var fish_stamina_left: float = 0.0

# Timers
var bite_timer: float = 0.0
var hook_window_timer: float = 0.0
var high_tension_timer: float = 0.0
var slack_timer: float = 0.0

const REEL_SPEED_BASE := 4.0        ## Metres per second reeled
const HOOK_WINDOW_BASE := 1.2       ## Reaction seconds to strike
const HIGH_TENSION_LIMIT := 0.92
const SLACK_LIMIT := 0.06


func _init(p_rod_tier: int = 1) -> void:
	rod_tier = p_rod_tier
	FishDB.init_db()


func _set_state(next_state: State) -> void:
	current_state = next_state
	state_changed.emit(current_state)


# -------------------------------------------------------------------------
# Action Inputs
# -------------------------------------------------------------------------

## Starts holding the cast button.
## Works from IDLE and straight after a catch or a lost fish (no reset needed).
func start_cast() -> bool:
	if current_state not in [State.IDLE, State.CAUGHT, State.LOST]:
		return false
	active_fish = null
	cast_power = 0.0
	_set_state(State.CASTING)
	return true


## Releases the cast button with a given power (0.0 to 1.0).
func release_cast(
	power: float,
	tide_fraction: float,
	is_daylight: bool,
	is_storming: bool,
	is_foggy: bool,
	rng: RandomNumberGenerator = null
) -> bool:
	if current_state != State.CASTING:
		return false

	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	cast_power = clampf(power, 0.1, 1.0)
	line_distance = 6.0 + cast_power * 14.0 # 6m to 20m cast distance
	cast_distance = line_distance
	cast_started.emit(cast_power)
	bobber_landed.emit(line_distance)

	# Roll an eligible fish bite
	active_fish = FishDB.roll_bite(tide_fraction, is_daylight, is_storming, is_foggy, rod_tier, r)
	if active_fish != null:
		fish_weight_kg = r.randf_range(active_fish.min_weight_kg, active_fish.max_weight_kg)
		fish_stamina_left = active_fish.base_stamina
		# Bite delay between 2.0 and 6.0 seconds
		bite_timer = r.randf_range(2.0, 5.5)
	else:
		bite_timer = 999.0 # No fish biting in these conditions

	_set_state(State.WAITING_FOR_BITE)
	return true


## Strikes / sets the hook when the hook window is open.
func strike_hook() -> bool:
	if current_state != State.HOOK_WINDOW:
		if current_state == State.WAITING_FOR_BITE:
			# Nothing on the line yet: just reel the lure back in, ready to cast again.
			reset()
			return false
		if current_state == State.NIBBLING:
			# Early hook spooks the fish
			_set_state(State.LOST)
			fish_escaped.emit("Pulled hook too early! Fish spooked.")
			return false
		return false

	line_tension = 0.4
	high_tension_timer = 0.0
	slack_timer = 0.0
	_set_state(State.REELING)
	return true


## Cancels or reels in an empty line.
func reset() -> void:
	active_fish = null
	_set_state(State.IDLE)


# -------------------------------------------------------------------------
# Simulation Tick Loop
# -------------------------------------------------------------------------

## Reeling frame update.
## is_reeling: player holding reel button
## counter_steer: player pulling rod opposite to fish direction (-1.0 to 1.0)
func tick_reeling(is_reeling: bool, counter_steer: float, delta_sec: float) -> void:
	if current_state != State.REELING or active_fish == null:
		return

	# Fish thrash mechanics
	var is_thrashing: bool = fish_stamina_left > 0.0
	var pull_force: float = active_fish.pull_strength if is_thrashing else active_fish.pull_strength * 0.35
	fish_stamina_left = max(0.0, fish_stamina_left - delta_sec)

	# Reeling pulls the fish closer and increases line tension
	if is_reeling:
		line_tension += (0.45 + pull_force * 0.4) * delta_sec
		# Counter-steering relieves excess tension
		line_tension -= absf(counter_steer) * 0.25 * delta_sec
		line_distance = max(0.0, line_distance - REEL_SPEED_BASE * delta_sec)
	else:
		# Letting go reduces tension, but fish can pull line out
		line_tension = max(0.0, line_tension - 0.5 * delta_sec)
		if is_thrashing:
			line_distance += pull_force * 1.5 * delta_sec

	# Clamp tension
	line_tension = clampf(line_tension, 0.0, 1.0)
	reeling_updated.emit(line_tension, line_distance, pull_force)

	# Win Condition: fish reaches shore / boat
	if line_distance <= 0.2:
		_set_state(State.CAUGHT)
		fish_landed.emit(active_fish, fish_weight_kg)
		return

	# Loss Condition 1: Snap
	if line_tension >= HIGH_TENSION_LIMIT:
		high_tension_timer += delta_sec
		if high_tension_timer >= 0.75:
			_set_state(State.LOST)
			fish_escaped.emit("Line snapped from extreme tension!")
			return
	else:
		high_tension_timer = max(0.0, high_tension_timer - delta_sec)

	# Loss Condition 2: Slack hook slip
	if line_tension <= SLACK_LIMIT:
		slack_timer += delta_sec
		if slack_timer >= 1.2:
			_set_state(State.LOST)
			fish_escaped.emit("Hook slipped due to slack line!")
			return
	else:
		slack_timer = max(0.0, slack_timer - delta_sec)


## General state tick (for casting, bites, and reaction windows)
func tick(delta_sec: float) -> void:
	match current_state:
		State.WAITING_FOR_BITE:
			bite_timer -= delta_sec
			if bite_timer <= 0.8 and bite_timer > 0.0:
				_set_state(State.NIBBLING)
				nibble_telegraphed.emit()
			elif bite_timer <= 0.0 and active_fish != null:
				hook_window_timer = HOOK_WINDOW_BASE
				_set_state(State.HOOK_WINDOW)
				hook_window_opened.emit(hook_window_timer)

		State.NIBBLING:
			bite_timer -= delta_sec
			if bite_timer <= 0.0 and active_fish != null:
				hook_window_timer = HOOK_WINDOW_BASE
				_set_state(State.HOOK_WINDOW)
				hook_window_opened.emit(hook_window_timer)

		State.HOOK_WINDOW:
			hook_window_timer -= delta_sec
			if hook_window_timer <= 0.0:
				_set_state(State.LOST)
				fish_escaped.emit("Fish ate the bait and got away!")
