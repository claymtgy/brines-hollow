class_name WeatherModel
extends RefCounted
## Pure, deterministic weather: a function of (world seed, absolute game time in days).
## Every peer evaluates the same schedule, so host, clients and dedicated servers agree
## without streaming weather state; only the absolute time is synced occasionally.
##
## Time is split into fronts of FRONT_DAYS; each front draws a state from weighted odds.
## The first BLEND of a front crossfades from the previous front's parameters.

enum State { CLEAR, OVERCAST, FOG, RAIN, STORM }
const STATE_NAMES := ["Clear", "Overcast", "Fog bank", "Rain", "Storm"]

const FRONT_DAYS := 0.22        # ~2.6 real minutes per front at 720 s/day
const BLEND := 0.3              # fraction of a front spent transitioning in

# Odds per state (storms are rare: they're the opt-in "hard mode" weather).
const WEIGHTS := [48.0, 20.0, 10.0, 14.0, 8.0]

# Continuous parameters each state pushes toward:
#   cloud: sky cover / light dimming   fog: extra fog   rain: precipitation
#   wind: sea swell + drift + audio    storm: lightning, surge, whitecaps
const TARGETS := [
	{"cloud": 0.05, "fog": 0.0,  "rain": 0.0, "wind": 0.20, "storm": 0.0},  # CLEAR
	{"cloud": 0.65, "fog": 0.02, "rain": 0.0, "wind": 0.35, "storm": 0.0},  # OVERCAST
	{"cloud": 0.45, "fog": 0.85, "rain": 0.0, "wind": 0.08, "storm": 0.0},  # FOG
	{"cloud": 0.85, "fog": 0.06, "rain": 0.7, "wind": 0.50, "storm": 0.0},  # RAIN
	{"cloud": 1.0,  "fog": 0.10, "rain": 1.0, "wind": 1.0,  "storm": 1.0},  # STORM
]
const KEYS := ["cloud", "fog", "rain", "wind", "storm"]
# Storm is drawn first so its odds interval only ever shrinks when other weights are
# boosted: "actual storm" implies "raw storm", which makes the no-back-to-back rule exact.
const ORDER := [State.STORM, State.CLEAR, State.OVERCAST, State.FOG, State.RAIN]


static func _hash(seed_value: int, i: int) -> int:
	var h := seed_value * 73856093 ^ i * 19349663 ^ 0x5bd1e995
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


## Weather state of front `i` (deterministic). No two storms in a row; mornings favour fog.
static func front_state(seed_value: int, i: int) -> int:
	if i <= 0:
		return State.CLEAR  # a new world always starts on a calm front
	var r := float(_hash(seed_value, i) % 100000) / 100000.0
	var w: Array = WEIGHTS.duplicate()
	var t_start := fposmod(i * FRONT_DAYS, 1.0)
	if t_start > 0.18 and t_start < 0.38:
		w[State.FOG] *= 1.4      # dawn fog banks
	if _raw_state(seed_value, i - 1) == State.STORM:
		w[State.STORM] = 0.0
	return _pick(w, r)


static func _pick(w: Array, r: float) -> int:
	var total := 0.0
	for x: float in w:
		total += x
	var acc := 0.0
	for s: int in ORDER:
		acc += w[s] / total
		if r < acc:
			return s
	return State.CLEAR


static func _raw_state(seed_value: int, i: int) -> int:
	if i <= 0:
		return State.CLEAR
	var r := float(_hash(seed_value, i) % 100000) / 100000.0
	return _pick(WEIGHTS, r)


## Parameters at absolute time `abs_days` (days since world creation, fractional).
## Returns {state, cloud, fog, rain, wind, storm, wind_dir (Vector2), front}.
static func sample(seed_value: int, abs_days: float) -> Dictionary:
	var f := maxf(abs_days, 0.0) / FRONT_DAYS
	var i := int(floor(f))
	var local := f - i
	var cur := front_state(seed_value, i)
	var prev := front_state(seed_value, i - 1)
	var k := smoothstep(0.0, BLEND, local)
	var out := {"state": cur if k > 0.5 else prev, "front": i}
	var a: Dictionary = TARGETS[prev]
	var b: Dictionary = TARGETS[cur]
	for key: String in KEYS:
		out[key] = lerpf(a[key], b[key], k)
	# Gusts: slow deterministic wobble on top of the front's wind.
	out["wind"] = clampf(out["wind"] * (0.85 + 0.15 * sin(abs_days * 97.0 + seed_value)), 0.0, 1.0)
	# Wind direction drifts slowly over days.
	var ang := float(_hash(seed_value, 7777) % 6283) / 1000.0 + abs_days * 1.3
	out["wind_dir"] = Vector2(cos(ang), sin(ang))
	return out


# Swell angular frequencies: 105 and 162 cycles per WAVE_LOOP seconds, so the pattern
# repeats exactly and wave_time can wrap without a visible jump.
const WAVE_LOOP := 600.0
const W1 := TAU * 105.0 / WAVE_LOOP   # ~1.0996 rad/s
const W2 := TAU * 162.0 / WAVE_LOOP   # ~1.6965 rad/s


## Swell height (metres) for the given wind strength — matches shaders/water.gdshader.
static func swell_amp(wind: float) -> float:
	return 0.03 + wind * wind * 0.32


## Sea surface offset at world xz (metres). Mirrors the swell term in water.gdshader:
## two long crests along the wind plus a cross-wave. `t` = Weather.wave_time.
static func wave_height(xz: Vector2, t: float, wind: float, wind_dir: Vector2) -> float:
	var amp := swell_amp(wind)
	var d := wind_dir.normalized() if wind_dir.length() > 0.001 else Vector2(1, 0)
	var p := xz.dot(d)
	var q := xz.dot(Vector2(-d.y, d.x))
	return amp * (sin(p * 0.22 - t * W1) * 0.65 + sin(p * 0.41 + q * 0.13 - t * W2) * 0.35)


## Storm surge (voxels) on top of the tide: only near high tide, only in storms.
static func surge_vox(storm: float, tide_rel: float) -> float:
	return storm * 2.2 * smoothstep(0.0, 1.0, tide_rel)


## True if something solid is above `cell` within `max_up` voxels (a roof, a canopy, a cliff
## overhang). Checks the column and its 4 neighbours so rain doesn't leak in by a door frame.
## `query` is Callable(x, y, z) -> int material.
static func is_sheltered(query: Callable, cell: Vector3i, max_up: int = 40) -> bool:
	var hits := 0
	for o: Vector2i in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		for dy in range(2, max_up):
			var m: int = query.call(cell.x + o.x, cell.y + dy, cell.z + o.y)
			if m != 0 and not Palette.is_foliage(m):
				hits += 1
				break
	return hits >= 3
