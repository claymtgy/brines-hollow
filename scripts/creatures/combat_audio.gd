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
	_sounds["dodge"] = _bake_dodge()
	_sounds["dodge_hop"] = _bake_backstep()
	_sounds["dodge_evade"] = _bake_evade()
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
	_sounds["shears_snip"] = _bake_sound(0.15, _gen_shears_snip)
	_sounds["bucket_slosh"] = _bake_sound(0.25, _gen_bucket_slosh)
	_sounds["oil_refuel"] = _bake_sound(0.30, _gen_oil_refuel)
	_sounds["flatten_scrape"] = _bake_sound(0.24, _gen_flatten_scrape)
	_sounds["animal_whistle"] = _bake_sound(0.32, _gen_animal_whistle)
	_sounds["tame_chime"] = _bake_sound(0.45, _gen_tame_chime)
	_sounds["saw_wood"] = _bake_sound(0.28, _gen_saw_wood)


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


## Dodge roll, timed to the 0.56 s roll animation: a soft cloth whoosh on the dive, a dull
## shoulder thud as you hit the ground, a gritty scuff through the tumble, then two boot plants.
## Built from filtered noise (stateful), so it lives outside the per-sample generators.
static func _bake_dodge() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	var n := int(0.62 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp_cloth := 0.0     # cloth whoosh: band-limited noise (two one-pole lowpasses, difference)
	var lp_cloth_lo := 0.0
	var lp_grit := 0.0      # ground scuff: darker lowpassed noise, grain-modulated
	var grain := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		# Cloth whoosh 0..0.2 s, cutoff sweeping down like the body falling.
		var cut := lerpf(0.22, 0.06, clampf(t / 0.2, 0.0, 1.0))
		lp_cloth += (w - lp_cloth) * cut
		lp_cloth_lo += (w - lp_cloth_lo) * 0.012
		var cloth := (lp_cloth - lp_cloth_lo) * _bump(t, 0.02, 0.09, 0.22) * 1.6
		# Shoulder hits the ground at ~0.13 s: low thump with a short soft attack.
		var tt := t - 0.13
		var thud := 0.0
		if tt >= 0.0:
			thud = sin(TAU * (75.0 * tt - 60.0 * tt * tt)) * (1.0 - exp(-tt * 400.0)) * exp(-tt * 28.0)
		# Rolling scuff 0.13..0.42 s: sand/grit grains.
		lp_grit += (w - lp_grit) * 0.09
		if rng.randf() < 0.004:
			grain = rng.randf_range(0.5, 1.0)
		grain *= 0.996
		var grit := lp_grit * (0.35 + 0.65 * grain) * _bump(t, 0.12, 0.2, 0.44) * 1.3
		# Boot plants at ~0.40 s and ~0.47 s.
		var steps := _boot(t - 0.40, 0.8) + _boot(t - 0.47, 0.55)
		out[i] = thud * 0.55 + cloth * 0.5 + grit * 0.45 + steps * 0.4
	return _to_wav(out, 0.85)


## Backstep hop (dodge with no direction): a short cloth flick on push-off, two boots landing.
static func _bake_backstep() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp_lo := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.14
		lp_lo += (w - lp_lo) * 0.015
		var cloth := (lp - lp_lo) * _bump(t, 0.0, 0.05, 0.16) * 1.6
		var push := _boot(t - 0.02, 0.35)
		var land := _boot(t - 0.36, 0.8) + _boot(t - 0.405, 0.6)
		out[i] = cloth * 0.5 + (push + land) * 0.45
	return _to_wav(out, 0.75)


## Something swung through where you were: a fast, airy pass-by whoosh (no body sounds,
## so it layers cleanly over the roll that is already playing).
static func _bake_evade() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9187
	var n := int(0.22 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp_lo := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var cut := lerpf(0.12, 0.35, _bump(t, 0.0, 0.07, 0.22))   # brightens as it passes, then fades
		lp += (w - lp) * cut
		lp_lo += (w - lp_lo) * 0.03
		out[i] = (lp - lp_lo) * pow(_bump(t, 0.0, 0.06, 0.22), 1.5)
	return _to_wav(out, 0.6)


## 0 before a, rises to 1 at peak, falls back to 0 at b (smooth).
static func _bump(t: float, a: float, peak: float, b: float) -> float:
	if t <= a or t >= b:
		return 0.0
	if t < peak:
		return smoothstep(a, peak, t)
	return 1.0 - smoothstep(peak, b, t)


## Short muffled boot thump starting at tt = 0.
static func _boot(tt: float, gain: float) -> float:
	if tt < 0.0 or tt > 0.08:
		return 0.0
	return sin(TAU * 110.0 * tt) * exp(-tt * 70.0) * (1.0 - exp(-tt * 900.0)) * gain


## Normalises a float buffer to the given peak and packs it as 16-bit WAV.
static func _to_wav(buf: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var mx := 0.0001
	for s in buf:
		mx = maxf(mx, absf(s))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / mx * peak, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


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


# Shearing snip: metallic blades snipping wool
static func _gen_shears_snip(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var click := sin(TAU * t * 3200.0) * exp(-prog * 30.0)
	var scrape := randf_range(-1.0, 1.0) * exp(-prog * 15.0) * 0.4
	var ring := sin(TAU * t * 1850.0) * exp(-prog * 10.0) * 0.35
	return (click * 0.5 + scrape + ring) * 0.8


# Wooden bucket liquid slosh
static func _gen_bucket_slosh(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var thud := sin(TAU * t * lerpf(240.0, 80.0, prog)) * exp(-prog * 8.0) * 0.5
	var splash := randf_range(-1.0, 1.0) * exp(-prog * 10.0) * 0.4
	var bubble := sin(TAU * t * 520.0 + sin(t * 160.0) * 5.0) * exp(-prog * 9.0) * 0.4
	return (thud + splash + bubble) * 0.85


# Warm oil refuel: hissing sizzle + liquid glug
static func _gen_oil_refuel(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var glug := sin(TAU * t * lerpf(180.0, 320.0, prog)) * exp(-prog * 6.0) * 0.45
	var sizzle := randf_range(-1.0, 1.0) * sin(prog * PI) * 0.35
	var hum := sin(TAU * t * 120.0) * exp(-prog * 4.0) * 0.3
	return (glug + sizzle + hum) * 0.85


# Flatten earth/stone scrape
static func _gen_flatten_scrape(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var rumble := sin(TAU * t * lerpf(140.0, 50.0, prog)) * exp(-prog * 7.0) * 0.6
	var grit := randf_range(-1.0, 1.0) * exp(-prog * 12.0) * 0.5
	return (rumble + grit) * 0.85


# Shepherd's maritime pea whistle chime
static func _gen_animal_whistle(i: int, _n: int) -> float:
	var t := float(i) / RATE
	var tone1 := sin(TAU * t * 2400.0) * (0.8 + 0.2 * sin(t * 70.0))
	var tone2 := sin(TAU * t * 2880.0) * (0.6 + 0.2 * sin(t * 85.0))
	var air := randf_range(-0.3, 0.3)
	var env := pow(sin(clampf(t / 0.32, 0.0, 1.0) * PI), 0.6)
	return (tone1 * 0.55 + tone2 * 0.35 + air * 0.2) * env * 0.8


# Ascending 3-note harmonic tame chime (C5 -> E5 -> G5)
static func _gen_tame_chime(i: int, _n: int) -> float:
	var t := float(i) / RATE
	var freq := 523.25
	var sub_t := t
	if t >= 0.28:
		freq = 783.99
		sub_t = t - 0.28
	elif t >= 0.14:
		freq = 659.25
		sub_t = t - 0.14
	var env := exp(-sub_t * 6.0)
	var sine := sin(TAU * t * freq)
	var chime := sin(TAU * t * freq * 2.0) * 0.3
	return (sine + chime) * env * 0.7


# Rhythmic saw rasp on timber
static func _gen_saw_wood(i: int, n: int) -> float:
	var t := float(i) / RATE
	var prog := float(i) / n
	var rasp := randf_range(-1.0, 1.0) * (0.6 + 0.4 * sin(t * 60.0))
	var tone := sin(TAU * t * 380.0) * 0.3
	var env := sin(prog * PI)
	return (rasp * 0.7 + tone) * env * 0.75

