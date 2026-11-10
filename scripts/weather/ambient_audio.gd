class_name AmbientAudio
extends Node
## Procedural coastal soundscape (there are no audio assets yet).
## Seamless noise loops are synthesised once on a worker thread at startup, then the
## runtime only adjusts volumes/pitch — near-zero CPU per frame.
##   surf        follows shoreline proximity, tide height and wind
##   wind        rises with the weather's wind
##   rain        "ground" hiss outdoors, muffled "roof" drumming when sheltered
##   thunder     one-shots after lightning, delayed by distance

const RATE := 22050
const BUS_AMBIENCE := "Ambience"
const BUS_EFFECTS := "Effects"

var _players := {}           # name -> AudioStreamPlayer
var _thunder: AudioStreamWAV
var _task := -1
var _baked := {}
var _shore := 0.0
var _shore_t := 0.0
var _pending_thunder: Array = []
var bake_ms := 0


static func ensure_buses() -> void:
	for bus_name in [BUS_AMBIENCE, BUS_EFFECTS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	ensure_buses()
	_task = WorkerThreadPool.add_task(_bake_all)


func _bake_all() -> void:
	var t0 := Time.get_ticks_msec()
	var out := {
		"surf": _load_or_bake("surf", 8.0, _gen_surf),
		"wind": _load_or_bake("wind", 6.0, _gen_wind),
		"rain_ground": _load_or_bake("rain_ground", 4.0, _gen_rain.bind(false)),
		"rain_roof": _load_or_bake("rain_roof", 4.0, _gen_rain.bind(true)),
		"underwater": _load_or_bake("underwater", 6.0, _gen_underwater),
		"thunder": _load_or_bake("thunder", 4.5, _gen_thunder, false),
		"shanty_whistle": _load_or_bake("shanty_whistle", 8.0, _gen_shanty_whistle),
		"harbor_drone": _load_or_bake("harbor_drone", 6.0, _gen_harbor_drone),
	}
	bake_ms = Time.get_ticks_msec() - t0
	_baked = out


static func _load_or_bake(key: String, secs: float, gen: Callable, loop := true) -> AudioStream:
	for ext: String in [".wav", ".ogg"]:
		var path: String = "res://audio/ambience/" + key + ext
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				return res
	return _bake(secs, gen, loop)


## Generates `secs` of mono samples with gen(i, n, state) -> float; loops get a crossfade.
static func _bake(secs: float, gen: Callable, loop := true) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var xf := int(0.25 * RATE) if loop else 0
	var buf := PackedFloat32Array()
	buf.resize(n + xf)
	var st := {"rng": RandomNumberGenerator.new(), "a": 0.0, "b": 0.0, "c": 0.0}
	st.rng.seed = 1234 + n
	for i in n + xf:
		buf[i] = gen.call(i, n, st)
	if loop:
		# Fold the overhang onto the start so the loop point is seamless.
		for i in xf:
			var k := float(i) / xf
			buf[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


# Each generator keeps filter state in `st` (one-pole filters on white noise).
static func _gen_surf(i: int, n: int, st: Dictionary) -> float:
	var t := float(i % n) / RATE
	var wn: float = st.rng.randf_range(-1.0, 1.0)
	st.a = st.a + (wn - st.a) * 0.06            # low rumble
	st.b = st.b + (wn - st.b) * 0.35            # mid wash
	var phase := fposmod(t / 8.0, 1.0)
	# one breaking wave per loop: sharp rise, long receding wash
	var env := pow(minf(phase / 0.12, 1.0), 2.0) * exp(-maxf(phase - 0.12, 0.0) * 4.0)
	var swell := 0.35 + 0.65 * (0.5 + 0.5 * sin(TAU * t / 8.0 - 1.2))
	return (st.a * 1.6 * swell + (wn - st.b) * 0.35 * env + st.b * 0.5 * env) * 0.7


static func _gen_wind(i: int, n: int, st: Dictionary) -> float:
	var t := float(i % n) / RATE
	var wn: float = st.rng.randf_range(-1.0, 1.0)
	var cut := 0.012 + 0.02 * (0.5 + 0.5 * sin(TAU * t / 6.0 * 2.0)) + 0.01 * sin(TAU * t / 6.0 * 5.0)
	st.a = st.a + (wn - st.a) * cut
	st.b = st.b + (st.a - st.b) * cut
	var gust := 0.6 + 0.4 * sin(TAU * t / 6.0 + 0.7)
	return st.b * 9.0 * gust


static func _gen_rain(i: int, _n: int, st: Dictionary, roof: bool) -> float:
	var wn: float = st.rng.randf_range(-1.0, 1.0)
	st.a = st.a + (wn - st.a) * (0.08 if roof else 0.55)
	var hiss: float = (st.a * 2.2) if roof else (wn - st.a) * 0.55
	# droplets: sparse decaying ticks
	if st.rng.randf() < (0.0025 if roof else 0.004):
		st.c = st.rng.randf_range(0.4, 1.0)
	st.c *= 0.992 if roof else 0.96
	var tick: float = st.c * (sin(float(i) * (0.35 if roof else 1.3)))
	return hiss * 0.5 + tick * (0.6 if roof else 0.3)


static func _gen_thunder(i: int, n: int, st: Dictionary) -> float:
	var t := float(i) / RATE
	var wn: float = st.rng.randf_range(-1.0, 1.0)
	st.a = st.a + (wn - st.a) * 0.02
	st.b = st.b + (st.a - st.b) * 0.05
	var crack: float = exp(-t * 9.0) * (wn - st.a) * 0.6
	var roll: float = exp(-t * 0.9) * (0.6 + 0.4 * sin(t * 7.0 + sin(t * 2.3) * 3.0))
	return (st.b * 14.0 * roll + crack) * (1.0 - smoothstep(4.0, 4.5, t))


static func _gen_underwater(i: int, n: int, st: Dictionary) -> float:
	var t := float(i % n) / RATE
	var wn: float = st.rng.randf_range(-1.0, 1.0)
	st.a = st.a + (wn - st.a) * 0.015         # ultra-low cutoff (~50 Hz)
	st.b = st.b + (st.a - st.b) * 0.02
	var pulse := sin(TAU * t * 0.25) * 0.35 + 0.65
	var resonance := sin(TAU * t * 44.0 + sin(t * 1.5) * 2.0) * 0.25
	return (st.b * 12.0 * pulse + resonance) * 0.8


static func _gen_shanty_whistle(i: int, n: int, st: Dictionary) -> float:
	var t := float(i % n) / RATE
	var notes := [293.66, 349.23, 392.00, 440.00, 523.25, 440.00, 392.00, 349.23]
	var note_idx := int(t * 1.0) % notes.size()
	var freq: float = notes[note_idx]
	var breath: float = st.rng.randf_range(-0.04, 0.04)
	var vibrato := sin(TAU * 5.0 * t) * 0.015
	var wave := sin(TAU * freq * (1.0 + vibrato) * t)
	var harm := sin(TAU * freq * 2.0 * t) * 0.25
	var note_phase := fposmod(t, 1.0)
	var env := minf(note_phase / 0.1, 1.0) * (1.0 - maxf(0.0, (note_phase - 0.7) / 0.3))
	return (wave + harm + breath) * env * 0.45


static func _gen_harbor_drone(i: int, n: int, _st: Dictionary) -> float:
	var t := float(i % n) / RATE
	var swell := 0.7 + 0.3 * sin(TAU * t / 6.0)
	var c1 := sin(TAU * 146.83 * t) * 0.5 + sin(TAU * 293.66 * t) * 0.2
	var c2 := sin(TAU * 220.00 * t) * 0.4 + sin(TAU * 440.00 * t) * 0.15
	var c3 := sin(TAU * 369.99 * t) * 0.35
	return (c1 + c2 + c3) * swell * 0.25


func _create_players() -> void:
	for key in ["surf", "wind", "rain_ground", "rain_roof", "underwater", "shanty_whistle", "harbor_drone"]:
		var p := AudioStreamPlayer.new()
		p.stream = _baked[key]
		p.bus = BUS_AMBIENCE
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * 3.0)
		_players[key] = p
	_thunder = _baked["thunder"]


func thunder(delay: float) -> void:
	_pending_thunder.append(delay)


func _vol(key: String, gain: float, delta: float) -> void:
	var p: AudioStreamPlayer = _players.get(key)
	if p == null:
		return
	var cur := db_to_linear(p.volume_db)
	var g := lerpf(cur, gain, 1.0 - exp(-delta * 2.5))
	p.volume_db = linear_to_db(maxf(g, 0.00001))


func update(delta: float, w: Weather) -> void:
	if _players.is_empty():
		if _task != -1 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_create_players()
		return
	var sky := w.sky
	var cam := get_viewport().get_camera_3d()
	_shore_t -= delta
	if _shore_t <= 0.0 and cam != null:
		_shore_t = 0.5
		_shore = _shore_proximity(w, cam.global_position)
	var p := w.params
	var tide_rel := (sky.water_level_vox - VoxelWorld.SEA_MID) / VoxelWorld.TIDE_AMP
	var height := 0.0
	if cam != null:
		height = cam.global_position.y - sky.water_level_m()
	var height_att := clampf(1.0 - (height - 3.0) / 30.0, 0.15, 1.0)
	var wind: float = p.wind
	var rain: float = p.rain
	var surf := _shore * (0.55 + 0.25 * tide_rel) * (0.8 + 0.7 * wind) * height_att
	var submerged := height < -0.3
	var depth_att := clampf((-height) / 8.0, 0.0, 1.0)

	if submerged:
		_vol("surf", 0.06, delta)
		_vol("wind", 0.02, delta)
		_vol("rain_ground", 0.0, delta)
		_vol("rain_roof", 0.0, delta)
		_vol("underwater", clampf(0.55 + depth_att * 0.45, 0.5, 1.0), delta)
		_vol("shanty_whistle", 0.0, delta)
		_vol("harbor_drone", 0.0, delta)
	else:
		_vol("underwater", 0.0, delta)
		_vol("surf", clampf(surf, 0.0, 1.2), delta)
		_vol("wind", 0.06 + wind * wind * 0.7 * (0.4 if w.sheltered else 1.0), delta)
		_vol("rain_ground", rain * 0.55 * (0.0 if w.sheltered else 1.0), delta)
		_vol("rain_roof", rain * 0.7 * (1.0 if w.sheltered else 0.0), delta)

		var sailing_speed := 0.0
		var in_boat := false
		if cam != null and cam.get_parent() != null and cam.get_parent().get("boat") != null:
			var b = cam.get_parent().boat
			if b != null and "vel" in b:
				in_boat = true
				sailing_speed = b.vel.length()
		var shanty_target: float = clampf((sailing_speed - 2.5) / 3.0, 0.0, 0.75) if in_boat and sailing_speed > 2.5 else 0.0
		var harbor_target: float = clampf((_shore - 0.5) * 1.2, 0.0, 0.55) if not in_boat and _shore > 0.5 and height >= 0.0 and height < 20.0 else 0.0
		_vol("shanty_whistle", shanty_target, delta)
		_vol("harbor_drone", harbor_target, delta)
	(_players["wind"] as AudioStreamPlayer).pitch_scale = 0.8 + wind * 0.45
	for i in range(_pending_thunder.size() - 1, -1, -1):
		_pending_thunder[i] -= delta
		if _pending_thunder[i] <= 0.0:
			_pending_thunder.remove_at(i)
			var tp := AudioStreamPlayer.new()
			tp.stream = _thunder
			tp.bus = BUS_EFFECTS
			tp.pitch_scale = randf_range(0.75, 1.1)
			tp.volume_db = linear_to_db(randf_range(0.5, 0.9))
			add_child(tp)
			tp.play()
			tp.finished.connect(tp.queue_free)


## 0 inland / open sea, 1 right at the shoreline: mixes water and land samples around you.
static func _shore_proximity(w: Weather, pos: Vector3) -> float:
	var m := w._main()
	if m == null or m.world == null or not m.world.ready_for_play:
		return 0.0
	var wl := floori(w.sky.water_level_vox)
	var vs := VoxelWorld.VS
	var water := 0.0
	var total := 0.0
	for r: float in [5.0, 14.0, 28.0]:
		var weight := 1.0 / sqrt(r)
		for k in 8:
			var a := TAU * k / 8.0
			var x := floori((pos.x + cos(a) * r) / vs)
			var z := floori((pos.z + sin(a) * r) / vs)
			total += weight
			if m.world.get_voxel(x, wl, z) == 0:
				water += weight
	var f := water / maxf(total, 0.001)
	return clampf(4.0 * f * (1.0 - f) * 1.15 + (0.25 if f > 0.95 else 0.0), 0.0, 1.0)
