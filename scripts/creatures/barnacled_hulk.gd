class_name BarnacledHulk
extends Creature
## The Barnacled Hulk: the Hollow Flats' biome boss. A colossal hermit crab that wears the
## stove-in stern of a galleon as its shell, lying up on a far strand (see HulkLair).
##
## The shell turns almost every blow (only 15% gets through) until it's cracked. Two ways
## to beat it without trading blows all day:
##   - Cliff boulders: loose boulders sit on the rocks above the strand. Lure the Hulk
##     below one and push it (F): each boulder that lands cracks the shell; two cracks
##     and the shell splits, and every blow lands in full.
##   - Tidal mud: the strand is low. Catch the Hulk out on the flats as the tide drops
##     below half and it sinks into the mud, mired for a while: it can't fight back, and
##     its soft underside takes 2.5x damage.
## It never leaves its strand, and it won't follow you into deep water.
## Cozy: it rises and roars, but never strikes.
##
## Attacks (all telegraphed with "!"): a sweeping claw (a slow wind-up, then a wide arc in
## front of it) and a shell slam (it rears up, then crashes down all around it).

const LEASH := 34.0
const WAKE_R := 16.0
const SHELL_MULT := 0.15
const MUD_MULT := 2.5
const MIRE_SEC := 9.0
const BOULDER_DMG := 140.0

var lair := Vector3.ZERO            # the strand (metres)
var cracks := 0                     # host: boulder cracks in the shell (2 = split)
var risen := false
var _mire_cd := 0.0
var _attack := 0                    # 0 claw sweep, 1 shell slam
var _cd := 1.5
var _orbit := 1.0
var body: Node3D
var shell: Node3D
var claw_l: Node3D
var claw_r: Node3D
var _phase := 0.0
var _reported := false


func _init() -> void:
	hostile = true
	kind = &"barnacled_hulk"
	max_hp = 650.0
	hp = max_hp
	radius = 2.2
	max_poise = 400.0
	poise = max_poise


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	body.scale = Vector3.ONE * 2.0
	root.add_child(body)
	# the crab: a pale, soft body sticking out of the front of the shell, on six thick legs
	var b := Prefabs.Grid.new(14, 8, 10)
	b.box(1, 2, 0, 12, 7, 9, Palette.SANDSTONE_B)
	b.box(2, 1, 5, 11, 2, 9, Palette.SANDSTONE_C)
	b.box(3, 7, 7, 4, 9, 8, Palette.ROOF_RED)              # eye stalks
	b.box(9, 7, 7, 10, 9, 8, Palette.ROOF_RED)
	b.setv(3, 10, 8, Palette.EYE)
	b.setv(10, 10, 8, Palette.EYE)
	part(body, b, Vector3(-7, 1, 6))
	for side: int in [-1, 1]:
		for k in 3:
			var lg := Prefabs.Grid.new(3, 6, 3)
			lg.box(0, 0, 0, 2, 5, 2, Palette.ROOF_RED)
			lg.box(0, 0, 0, 2, 0, 2, Palette.SANDSTONE_C)
			part(body, lg, Vector3(side * 8 - 1, -4, 6 + k * 3))
	# the shell: the stern of a galleon, upside down and crusted with barnacles and weed
	shell = Node3D.new()
	body.add_child(shell)
	var s := Prefabs.Grid.new(24, 18, 28)
	for z in 28:
		for y in 18:
			for x in 24:
				var e := Vector3((x - 11.5) / 12.0, (y - 2.0) / 16.0, (z - 14.0) / 15.0)
				var d := e.length()
				if d > 1.0 or d < 0.82 or y < 2:
					continue
				var h := posmod(hash(Vector3i(x, y, z)), 100)
				var m := Palette.DARK_WOOD if (z / 3) % 2 == 0 else Palette.PLANK
				if h < 22:
					m = Palette.WHITEWASH                           # barnacles
				elif h < 34:
					m = Palette.KELP
				elif h < 40:
					m = Palette.SANDSTONE_C
				s.setv(x, y, z, m)
	# a stern gallery window and a bit of gilt on the transom
	s.box(9, 9, 27, 14, 12, 27, Palette.SHUTTER)
	s.box(8, 13, 27, 15, 13, 27, Palette.BUOY)
	part(shell, s, Vector3(-12, 0, -16))
	claw_l = pivot(body, Vector3(-6, 5, 15))
	claw_r = pivot(body, Vector3(6, 5, 15))
	for c: Node3D in [claw_l, claw_r]:
		var g := Prefabs.Grid.new(6, 6, 10)
		g.box(0, 0, 0, 5, 5, 6, Palette.ROOF_RED)
		g.box(0, 0, 7, 5, 2, 9, Palette.BUOY)
		g.box(0, 4, 7, 5, 5, 9, Palette.BUOY)
		g.box(1, 1, 1, 4, 4, 2, Palette.WHITEWASH)
		part(c, g, Vector3(-3, -3, 0))


func telegraph_height() -> float:
	return 7.5


func hint() -> String:
	return "The Barnacled Hulk's shell turns your blows. Lure it under a cliff boulder and push it (F) to crack the shell, or catch it out on the flats as the tide drops: mired in the mud, it can't fight back."


func drops() -> Array:
	return [[&"hulk_pearl", 1], [&"chitin_plate", 10], [&"brass_guilder", 150], [&"sea_glass", 12]]


func shell_split() -> bool:
	return cracks >= 2


func mired() -> bool:
	return state == State.STAGGER and has_meta("mired")


## Damage after the shell (and the mud) have had their say.
func effective_damage(dmg: float) -> float:
	var m := 1.0 if shell_split() else SHELL_MULT
	if mired():
		m = maxf(m, 1.0) * MUD_MULT
	return dmg * m


func is_armored() -> bool:
	return true


func _on_windup_started() -> void:
	CombatAudio.play_sound("tell_snap", position, 3.0, 0.05)


func on_hit(dmg: float, from: Vector3, power: float, attacker: int) -> bool:
	if state == State.DEAD:
		return false
	risen = true
	var keep_poise := poise
	var ok := super.on_hit(effective_damage(dmg), from, power * (0.2 if not mired() else 1.0), attacker)
	if not mired():
		poise = maxf(keep_poise - power * 2.0, 1.0)     # only the mud or a boulder stops it
		if state == State.STAGGER:
			set_state(State.ALERT)
	return ok


## Harpoon finisher: piercing the exposed eye stalks deals massive 2.2x weakpoint damage, bypassing shell armor.
func eye_stalk_harpoon_strike(dmg: float, from: Vector3, attacker: int) -> bool:
	if state == State.DEAD:
		return false
	risen = true
	var weakpoint_dmg: float = dmg * 2.2
	var ok := super.on_hit(weakpoint_dmg, from, 4.0, attacker)
	CombatAudio.play_sound("tell_screech", position, 4.0, 0.05)
	if net != null and net.main != null and net.main.hud != null:
		net.main.hud.show_banner("Vulnerable Eye-Stalk Wrenched!", "Harpoon grapple bypasses galleon shell plating!")
	return ok


## Host: a cliff boulder landed on it.
func boulder_hit(attacker: int) -> void:
	if state == State.DEAD:
		return
	risen = true
	cracks += 1
	last_attacker = attacker
	hp -= BOULDER_DMG
	flash()
	if hp <= 0.0:
		set_state(State.DEAD)
		return
	set_meta("mired", true)        # stunned under the rock for a moment
	set_state(State.STAGGER)
	state_t = MIRE_SEC * 0.6


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	_cd = maxf(0.0, _cd - dt)
	_mire_cd = maxf(0.0, _mire_cd - dt)
	var water_y: float = ctx.water_y
	if state == State.DEAD:
		if not _reported:
			_reported = true
			if net.get("hulk") != null:
				net.hulk.on_slain(self)
		if state_t > 4.0:
			net.despawn(self)
		return
	var p := _nearest_in_reach(ctx)
	var dist: float = p.get("dist", INF)
	if not risen:
		if not p.is_empty() and dist < WAKE_R:
			risen = true
			set_state(State.ALERT)
			if net.get("hulk") != null:
				net.hulk.on_risen()
		return
	if state == State.STAGGER:
		if state_t > MIRE_SEC:
			remove_meta("mired")
			_mire_cd = 25.0
			set_state(State.ALERT)
		return
	# Out on the flats as the tide drops: the mud takes it.
	if _mire_cd <= 0.0 and water_y < VoxelWorld.SEA_MID * VS and position.y < VoxelWorld.SEA_MID * VS + 0.1 \
			and water_y > position.y - 1.5:
		set_meta("mired", true)
		set_state(State.STAGGER)
		if net.get("hulk") != null:
			net.hulk.say("The tide drains off the flats and the Hulk sinks into the mud, mired! Strike its soft underside.")
		return
	match state:
		State.WINDUP:
			if p.is_empty():
				set_state(State.RETURN)
				return
			turn_toward(p.pos - position, 1.2, dt)
			if state_t >= CombatMath.windup_time(1.25 if _attack == 0 else 1.6, ctx.difficulty):
				set_state(State.STRIKE)
			return
		State.STRIKE:
			for pl: Dictionary in ctx.players:
				var to: Vector3 = pl.pos - position
				to.y = 0.0
				var d := to.length()
				if _attack == 0:
					if d < radius + 3.2 and facing().dot(to.normalized()) > 0.1:
						net.hurt_player(pl.id, 12.0, position, self)
				elif d < radius + 2.6:
					net.hurt_player(pl.id, 16.0, position, self)
			set_state(State.RECOVER)
			return
		State.RECOVER:
			if state_t > (1.4 if _attack == 0 else 2.0):
				_cd = rng.randf_range(1.0, 2.2)
				set_state(State.ALERT)
			return
	if p.is_empty():
		_go_home(dt, water_y)
		return
	if state != State.ALERT:
		set_state(State.ALERT)
	var to: Vector3 = p.pos - position
	to.y = 0.0
	turn_toward(to, 1.4, dt)
	if dist < radius + 3.0 and _cd <= 0.0 and CombatMath.hostiles_allowed(ctx.difficulty):
		_attack = 1 if dist < radius + 1.8 and rng.randf() < 0.45 else 0
		set_state(State.WINDUP)
		return
	if dist > radius + 1.5:
		if not walk(to, 1.7, dt, water_y, 0.9):
			if not walk(to.rotated(Vector3.UP, 0.8 * _orbit), 1.7, dt, water_y, 0.9):
				_orbit = -_orbit


func _go_home(dt: float, water_y: float) -> void:
	var d := lair - position
	d.y = 0.0
	if d.length() < 1.5:
		if state != State.IDLE:
			set_state(State.IDLE)
		return
	if state != State.RETURN:
		set_state(State.RETURN)
	turn_toward(d, 1.4, dt)
	if not walk(d, 1.4, dt, water_y, 0.9):
		if not walk(d.rotated(Vector3.UP, 0.8 * _orbit), 1.4, dt, water_y, 0.9):
			_orbit = -_orbit
			if state_t > 10.0:
				position = lair


func _nearest_in_reach(ctx: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	for pl: Dictionary in ctx.players:
		if Vector2(pl.pos.x - lair.x, pl.pos.z - lair.z).length() > LEASH:
			continue
		if pl.in_water and pl.pos.y < ctx.water_y - 0.9:
			continue
		var d: float = position.distance_to(pl.pos)
		if d < bd:
			bd = d
			best = pl
	if not best.is_empty():
		best = best.duplicate()
		best["dist"] = bd
	return best


func animate(dt: float) -> void:
	var moving := state in [State.ALERT, State.RETURN]
	_phase += dt * (3.0 if moving else 0.6)
	body.position.y = absf(sin(_phase)) * (0.06 if moving else 0.0)
	var sink := 0.0
	if state == State.STAGGER:
		sink = -0.9                                   # down in the mud
	elif not risen and authority:
		sink = -1.6                                   # buried on the strand, just the shell showing
	_visual_root.position.y = lerpf(_visual_root.position.y, sink, 1.0 - exp(-dt * 2.0))
	var claw := sin(_phase * 0.5) * 0.1
	if state == State.WINDUP:
		claw = -1.3 if _attack == 0 else -0.6
		body.rotation.x = lerpf(body.rotation.x, -0.12 if _attack == 0 else -0.35, 1.0 - exp(-dt * 4.0))
	elif state == State.STRIKE or state == State.RECOVER and state_t < 0.3:
		claw = 0.9
		body.rotation.x = lerpf(body.rotation.x, 0.2, 1.0 - exp(-dt * 14.0))
	else:
		body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-dt * 4.0))
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, 0.5, 1.0 - exp(-dt * 1.5))
		_visual_root.position.y = lerpf(_visual_root.position.y, -0.8, 1.0 - exp(-dt * 1.0))
	claw_l.rotation.x = lerpf(claw_l.rotation.x, claw, 1.0 - exp(-dt * 6.0))
	claw_r.rotation.x = lerpf(claw_r.rotation.x, claw if state == State.WINDUP else -claw * 0.5, 1.0 - exp(-dt * 6.0))
