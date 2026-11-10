class_name CombatAudio
extends Node
## Procedural combat audio synthesizer: generates punchy, visceral sound effects for
## swings, flesh/shell impacts, parries, blocks, poise breaks, and creature tells.
## No external sound files needed.

const RATE := 22050
const BUS_EFFECTS := "Effects"

static var _sounds: Dictionary = {}
static var _init_done := false
static var _pool_root: Node = null
static var _pool_3d: Array[AudioStreamPlayer3D] = []
static var _pool_2d: Array[AudioStreamPlayer] = []
static var _idx_3d := 0
static var _idx_2d := 0
const POOL_3D_SIZE := 16
const POOL_2D_SIZE := 8


static func _ensure_pool(tree: SceneTree) -> void:
	if _pool_root != null and is_instance_valid(_pool_root):
		return
	_pool_root = Node.new()
	_pool_root.name = "CombatAudioPool"
	tree.root.add_child(_pool_root)
	_pool_3d.clear()
	_pool_2d.clear()
	for i in POOL_3D_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_EFFECTS
		p.max_distance = 40.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		_pool_root.add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D_SIZE:
		var p2 := AudioStreamPlayer.new()
		p2.bus = BUS_EFFECTS
		_pool_root.add_child(p2)
		_pool_2d.append(p2)


static func init_audio(force: bool = false) -> void:
	if _init_done and not force:
		return
	_init_done = true
	if DisplayServer.get_name() == "headless" and not force:
		return

	# Ensure Effects bus exists
	if AudioServer.get_bus_index(BUS_EFFECTS) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_EFFECTS)
		AudioServer.set_bus_send(idx, "Master")

	_sounds["swing_light"] = _bake_sound(0.12, _gen_swing_light)
	_sounds["swing_heavy"] = _bake_sound(0.22, _gen_swing_heavy)
	_sounds["swing_thrust"] = _bake_sound(0.10, _gen_swing_thrust)
	_sounds["hit_flesh"] = _bake_sound(0.14, _gen_hit_flesh)
	_sounds["hit_shell"] = _bake_sound(0.16, _gen_hit_shell)
	_sounds["parry"] = _bake_sound(0.35, _gen_parry)
	_sounds["block"] = _bake_sound(0.16, _gen_block)
	_sounds["poise_break"] = _bake_sound(0.38, _gen_poise_break)
	_sounds["dodge"] = _bake_sound(0.18, _gen_dodge)
	_sounds["plunge_land"] = _bake_sound(0.32, _gen_plunge_land)
	_sounds["tell_snap"] = _bake_sound(0.15, _gen_tell_snap)
	_sounds["tell_screech"] = _bake_sound(0.25, _gen_tell_screech)
	_sounds["tell_roar"] = _bake_sound(0.28, _gen_tell_roar)
	_sounds["water_lap"] = _bake_sound(0.28, _gen_water_lap)
	_sounds["fanfare"] = _bake_sound(0.75, _gen_fanfare)
	_sounds["arrow_release"] = _bake_sound(0.16, _gen_arrow_release)
	_sounds["bow_draw"] = _bake_sound(0.20, _gen_bow_draw)
	_sounds["flintlock_shot"] = _bake_sound(0.38, _gen_flintlock_shot)
	_sounds["dry_click"] = _bake_sound(0.08, _gen_dry_click)
	_sounds["shield_block"] = _bake_sound(0.22, _gen_shield_block)


static func play_sound(sound_key: String, origin: Vector3 = Vector3.ZERO, volume_db: float = 0.0, pitch_var: float = 0.08) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _init_done:
		init_audio()
	var stream: AudioStreamWAV = _sounds.get(sound_key)
	if stream == null:
		return

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return

	_ensure_pool(tree)
	var pitch := 1.0 + randf_range(-pitch_var, pitch_var)

	if origin != Vector3.ZERO:
		var p: AudioStreamPlayer3D = null
		for candidate in _pool_3d:
			if is_instance_valid(candidate) and not candidate.playing:
				p = candidate
				break
		if p == null:
			p = _pool_3d[_idx_3d % POOL_3D_SIZE]
			_idx_3d += 1
		p.stream = stream
		p.position = origin
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p2: AudioStreamPlayer = null
		for candidate in _pool_2d:
			if is_instance_valid(candidate) and not candidate.playing:
				p2 = candidate
				break
		if p2 == null:
			p2 = _pool_2d[_idx_2d % POOL_2D_SIZE]
			_idx_2d += 1
		p2.stream = stream
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		p2.play()


# ---------------------------------------------------------------- baking helper

static func _bake_sound(duration_sec: float, gen_func: Callable) -> AudioStreamWAV:
	var total_samples := int(duration_sec * RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)

	for i in total_samples:
		var sample: float = clampf(float(gen_func.call(i, total_samples)), -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32000.0))

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


# ---------------------------------------------------------------- generators

# Light blade swoosh: sweeping bandpass noise
static func _gen_swing_light(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := sin(prog * PI)
	var wn := randf_range(-1.0, 1.0)
	var freq := lerpf(1200.0, 450.0, prog)
	var tone := sin(TAU * t * freq)
	return (wn * 0.7 + tone * 0.3) * env * 0.75


# Heavy maul / finisher whoosh: deeper low-end air displacement
static func _gen_swing_heavy(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := pow(sin(prog * PI), 1.2)
	var wn := randf_range(-1.0, 1.0)
	var bass := sin(TAU * t * lerpf(240.0, 80.0, prog))
	return (wn * 0.5 + bass * 0.5) * env * 0.95


# Harpoon thrust: sharp, fast whoosh/pierce
static func _gen_swing_thrust(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := pow(sin(prog * PI), 0.8)
	var wn := randf_range(-1.0, 1.0)
	var whistle := sin(TAU * t * lerpf(1800.0, 700.0, prog))
	return (wn * 0.6 + whistle * 0.4) * env * 0.8


# Flesh hit: low thump + wet snap
static func _gen_hit_flesh(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := exp(-prog * 18.0)
	var transient := randf_range(-1.0, 1.0) * exp(-prog * 60.0)
	var thump := sin(TAU * t * lerpf(120.0, 45.0, prog))
	return (thump * 0.7 + transient * 0.5) * env * 0.9


# Shell / Chitin hit: high transient click + hollow resonance
static func _gen_hit_shell(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := exp(-prog * 14.0)
	var click := randf_range(-1.0, 1.0) * exp(-prog * 90.0)
	var chime := sin(TAU * t * 740.0) * exp(-prog * 20.0) + sin(TAU * t * 1480.0) * exp(-prog * 35.0)
	return (click * 0.6 + chime * 0.5) * env * 0.85


# Precision parry: bright metallic ringing chime
static func _gen_parry(i: int, _n: int) -> float:
	var t := float(i) / RATE
	var click := randf_range(-1.0, 1.0) * exp(-t * 220.0)
	var ring1 := sin(TAU * t * 1350.0) * exp(-t * 8.0)
	var ring2 := sin(TAU * t * 1920.0) * exp(-t * 12.0)
	var ring3 := sin(TAU * t * 3100.0) * exp(-t * 22.0)
	return (click * 0.45 + ring1 * 0.45 + ring2 * 0.35 + ring3 * 0.2) * 0.95


# Guard block: heavy wooden/metal thud
static func _gen_block(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := exp(-prog * 16.0)
	var thud := sin(TAU * t * lerpf(180.0, 60.0, prog))
	var noise := randf_range(-1.0, 1.0) * exp(-prog * 45.0)
	return (thud * 0.75 + noise * 0.4) * env * 0.85


# Poise break: dramatic shattering crash & dissonant chime
static func _gen_poise_break(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var crack := randf_range(-1.0, 1.0) * exp(-prog * 12.0)
	var ring1 := sin(TAU * t * 580.0) * exp(-prog * 6.0)
	var ring2 := sin(TAU * t * 870.0) * exp(-prog * 8.0)
	var ring3 := sin(TAU * t * 1160.0) * exp(-prog * 11.0)
	return (crack * 0.5 + ring1 * 0.3 + ring2 * 0.3 + ring3 * 0.2) * 1.0


# Dodge roll: swift fabric swoosh & ground scuff
static func _gen_dodge(i: int, n: int) -> float:
	var prog := float(i) / n
	var env := sin(prog * PI)
	var wn := randf_range(-1.0, 1.0)
	return wn * env * 0.5


# Plunging attack land: explosive bass boom & debris rumble
static func _gen_plunge_land(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var boom := sin(TAU * t * lerpf(90.0, 32.0, prog)) * exp(-prog * 7.0)
	var rumble := randf_range(-1.0, 1.0) * exp(-prog * 9.0)
	return (boom * 0.75 + rumble * 0.45) * 1.0


# Enemy tell: crab pincer double snap
static func _gen_tell_snap(i: int, _n: int) -> float:
	var t := float(i) / RATE
	var snap1 := randf_range(-1.0, 1.0) * exp(-t * 120.0)
	var t2 := maxf(0.0, t - 0.05)
	var snap2 := (randf_range(-1.0, 1.0) * exp(-t2 * 120.0)) if t >= 0.05 else 0.0
	return (snap1 * 0.6 + snap2 * 0.8) * 0.7


# Enemy tell: crawler hiss/screech
static func _gen_tell_screech(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := sin(prog * PI)
	var noise := randf_range(-1.0, 1.0)
	var hiss := sin(TAU * t * (2200.0 + sin(t * 80.0) * 400.0))
	return (noise * 0.55 + hiss * 0.45) * env * 0.65


# Enemy tell: sea-reaver war shout
static func _gen_tell_roar(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var env := sin(prog * PI)
	var growl := sin(TAU * t * lerpf(160.0, 110.0, prog)) * (0.6 + 0.4 * sin(t * 70.0))
	return growl * env * 0.75


# Dynamic water hull lapping sound
static func _gen_water_lap(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var splash := randf_range(-1.0, 1.0) * exp(-prog * 8.0) * 0.4
	var lap := sin(TAU * t * lerpf(220.0, 75.0, prog)) * exp(-prog * 6.0) * 0.65
	var bubble := sin(TAU * t * 450.0 + sin(t * 120.0) * 4.0) * exp(-prog * 12.0) * 0.3
	return (splash + lap + bubble) * 0.75


# Triumphant 4-note brass/chime fanfare
static func _gen_fanfare(i: int, _n: int) -> float:
	var t := float(i) / RATE
	var freq := 523.25   # C5
	var note_t := t
	if t >= 0.54:
		freq = 1046.50   # C6
		note_t = t - 0.54
	elif t >= 0.36:
		freq = 783.99    # G5
		note_t = t - 0.36
	elif t >= 0.18:
		freq = 659.25    # E5
		note_t = t - 0.18

	var env := exp(-note_t * (3.5 if t >= 0.54 else 7.0))
	var fundamental := sin(TAU * t * freq)
	var overtone := sin(TAU * t * freq * 2.0) * 0.35
	var third := sin(TAU * t * freq * 3.0) * 0.15
	return (fundamental + overtone + third) * env * 0.65


# Bow string release snap & arrow hiss
static func _gen_arrow_release(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var snap := sin(TAU * t * lerpf(980.0, 320.0, prog)) * exp(-prog * 18.0)
	var noise := randf_range(-1.0, 1.0) * exp(-prog * 14.0) * 0.4
	return (snap * 0.7 + noise * 0.3) * 0.85


# Bow draw wood-creak and string tension
static func _gen_bow_draw(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var creak := sin(TAU * t * (280.0 + sin(t * 80.0) * 40.0)) * sin(prog * PI)
	var grit := randf_range(-0.5, 0.5) * sin(prog * PI) * 0.25
	return (creak * 0.6 + grit) * 0.5


# Flintlock explosive muzzle report
static func _gen_flintlock_shot(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var crack := randf_range(-1.0, 1.0) * exp(-prog * 24.0) * 1.0
	var boom := sin(TAU * t * lerpf(140.0, 45.0, prog)) * exp(-prog * 6.0) * 0.9
	var rumble := sin(TAU * t * 65.0) * exp(-prog * 4.0) * 0.6
	return clampf(crack * 0.55 + boom * 0.35 + rumble * 0.25, -1.0, 1.0)


# Dry click on empty chamber / unstrung bow
static func _gen_dry_click(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var click := sin(TAU * t * 2400.0) * exp(-prog * 45.0)
	return click * 0.6


# Solid shield block impact
static func _gen_shield_block(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var thud := sin(TAU * t * lerpf(280.0, 90.0, prog)) * exp(-prog * 10.0) * 0.8
	var wood_crack := randf_range(-0.8, 0.8) * exp(-prog * 18.0) * 0.5
	return (thud + wood_crack) * 0.85

