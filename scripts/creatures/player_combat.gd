class_name PlayerCombat
extends Node
## Local player's optional combat + stealth: melee swings with the active hotbar weapon,
## a dodge roll (C / back paddle), a parry (right mouse / LT while holding a weapon) and
## sneaking (hold Ctrl / back paddle 2). Hits on creatures are sent to the host, which owns
## creature health. Creature hits on us arrive from the host via `receive_hit`.

var player: Player
var net: Node                    # CreatureNet

var sneaking := false
var combo_step := 0             # 0: ready, 1: Light 1, 2: Light 2, 3: Heavy Finisher
var combo_timer := 0.0          # resets combo_step when it expires
var charge_held_t := 0.0        # seconds primary attack is held
var is_charging := false        # true while charging heavy attack
var is_guarding := false        # true while holding guard (RMB / LT)
var guard_broken_t := 0.0       # stun recovery timer after guard break
var riposte_ready_t := 0.0      # window to unleash high-multiplier counter
var is_plunging := false        # true during downward aerial strike

var _attack_cd := 0.0
var _strike_in := -1.0          # seconds until the swing's active frame
var _swing_stats := {}
var _dodge_t := -1.0            # elapsed time in the current dodge (-1 = none)
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _parry_t := -1.0            # elapsed since parry press (-1 = none)
var _parry_cd := 0.0
var _shake := 0.0
var _hit_stop_t := 0.0
var _weapon_cached: ItemDef = null


func weapon_def() -> ItemDef:
	if player == null or player.inventory == null:
		return null
	var slot: ItemSlot = player.inventory.get_active_item()
	if slot == null or slot.is_empty():
		return null
	var def: ItemDef = ItemDB.get_item(slot.item_id)
	if def != null and (def.has_tag("weapon") or not def.weapon_data.is_empty()) and not def.weapon_data.get("is_ranged", false):
		return def
	return null


func active_item() -> ItemDef:
	if player == null or player.inventory == null:
		return null
	var slot: ItemSlot = player.inventory.get_active_item()
	return null if slot == null or slot.is_empty() else ItemDB.get_item(slot.item_id)


func has_bait() -> bool:
	var d := active_item()
	return d != null and (d.has_tag("fish") or d.id == &"kelp_frond")


func holding_fish() -> bool:
	var d := active_item()
	return d != null and d.has_tag("fish")


func has_light() -> bool:
	var d := active_item()
	return d != null and d.has_tag("light")


func is_dodging() -> bool:
	return CombatMath.dodge_protects(_dodge_t)


## Called from Player._process. Returns true when a weapon is in hand (tools are skipped).
func process_input(delta: float, can_input: bool) -> bool:
	_attack_cd -= delta
	_dodge_cd -= delta
	_parry_cd -= delta

	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_step = 0

	if riposte_ready_t > 0.0:
		riposte_ready_t -= delta

	if guard_broken_t > 0.0:
		guard_broken_t -= delta
		is_guarding = false

	if _hit_stop_t > 0.0:
		_hit_stop_t -= delta

	if _dodge_t >= 0.0:
		_dodge_t += delta
		if _dodge_t > CombatMath.DODGE_TIME:
			_dodge_t = -1.0
			player.model.rotation.x = 0.0
		else:
			player.model.rotation.x = -TAU * (_dodge_t / CombatMath.DODGE_TIME)

	if _parry_t >= 0.0:
		_parry_t += delta
		if _parry_t > 0.5:
			_parry_t = -1.0

	_update_shake(delta)
	sneaking = can_input and Input.is_action_pressed("sneak") and guard_broken_t <= 0.0

	# 8-directional dodge roll (cancels attack animations)
	if can_input and Input.is_action_just_pressed("dodge") and guard_broken_t <= 0.0:
		try_dodge()

	if _strike_in >= 0.0:
		_strike_in -= delta
		if _strike_in < 0.0:
			_resolve_strike()

	var wd := weapon_def()
	if wd == null:
		return false

	var wt: int = int(CombatMath.weapon_stats(wd).weapon_type)
	player.model.set_tool(6 if wt == WeaponDef.WeaponType.HARPOON else (7 if wt == WeaponDef.WeaponType.ANCHOR_MAUL else 5))

	# Guard stance / parry pose visuals
	is_guarding = can_input and Input.is_action_pressed("alt_use") and guard_broken_t <= 0.0
	if (_parry_t >= 0.0 and _parry_t < CombatMath.PARRY_WINDOW) or is_guarding:
		player.model.arm_r.rotation.x = -1.4   # blade / shield raised across chest
		player.model.arm_r.rotation.z = 0.9

	# Precision Parry trigger (initial RMB press)
	if can_input and Input.is_action_just_pressed("alt_use") and _parry_cd <= 0.0 and guard_broken_t <= 0.0:
		_parry_t = 0.0
		_parry_cd = CombatMath.PARRY_COOLDOWN
		player.facing = player.rig.yaw + PI

	# Primary attack inputs: tap combo, hold charge, sprint engage, or aerial plunge
	if can_input and guard_broken_t <= 0.0 and _dodge_t < 0.0 and not is_guarding:
		# Check for aerial plunging attack first
		if Input.is_action_just_pressed("use") and not player.on_ground and not player.swimming and not is_plunging:
			start_plunge_attack(wd)
		elif not is_plunging:
			# Charge meter tracking
			if Input.is_action_pressed("use") and _attack_cd <= 0.0:
				charge_held_t += delta
				if charge_held_t >= CombatMath.CHARGE_TIME_MIN:
					is_charging = true
				# Auto-release at full charge
				if charge_held_t >= 1.0:
					execute_charged_attack(wd)
			elif Input.is_action_just_released("use"):
				if is_charging:
					execute_charged_attack(wd)
				elif charge_held_t > 0.0 and _attack_cd <= 0.0:
					attack(wd, false)
				charge_held_t = 0.0
				is_charging = false

	return true


func execute_charged_attack(wd: ItemDef) -> bool:
	is_charging = false
	charge_held_t = 0.0
	return attack(wd, true)


func start_plunge_attack(wd: ItemDef) -> bool:
	var stats := CombatMath.weapon_stats(wd)
	if not player.vitality.consume_stamina(float(stats.stamina_per_swing) * 1.5):
		if player.hud != null:
			player.hud.show_toast("Too winded to plunge")
		return false
	is_plunging = true
	player.vel.y = -15.0
	player.facing = player.rig.yaw + PI
	player.model.swing()
	player.swing_count += 1
	_attack_cd = 0.8
	return true


func on_land_plunge() -> void:
	if not is_plunging:
		return
	is_plunging = false
	var wd := weapon_def()
	var base_stats := CombatMath.weapon_stats(wd)
	var plunge_stats := base_stats.duplicate()
	plunge_stats["damage_mult"] = CombatMath.PLUNGE_DAMAGE_MULT
	plunge_stats["stagger_mult"] = CombatMath.PLUNGE_STAGGER_MULT
	plunge_stats["is_finisher"] = true

	var hits := 0
	if net != null and net.has_method("local_aoe_strike"):
		hits = net.local_aoe_strike(player.position, CombatMath.PLUNGE_AOE_RADIUS, plunge_stats, player.swimming)

	if hits > 0:
		trigger_hit_stop(CombatMath.HITSTOP_HEAVY)
	_shake = 0.28
	if player.hud != null:
		player.hud.show_toast("Plunging Shockwave!")


func attack(wd: ItemDef, is_charged: bool = false) -> bool:
	var base_stats := CombatMath.weapon_stats(wd)
	var is_sprint: bool = player.is_sprinting or (player.horizontal_speed > 5.5 and not is_charged)
	var is_riposte: bool = (riposte_ready_t > 0.0)

	# Stamina consumption
	var stamina_cost := float(base_stats.stamina_per_swing)
	if is_charged:
		stamina_cost *= CombatMath.CHARGE_STAMINA_MULT
	if not player.vitality.consume_stamina(stamina_cost):
		if player.hud != null:
			player.hud.show_toast("Too winded to swing")
		_attack_cd = 0.5
		combo_step = 0
		return false

	# Combo sequence progression
	if is_riposte:
		riposte_ready_t = 0.0
		combo_step = 3
		if player.hud != null:
			player.hud.show_toast("Riposte Counter-Attack!")
	elif is_charged:
		combo_step = 3
	elif is_sprint:
		combo_step = 2
	else:
		combo_step = 1 if combo_step >= 3 else combo_step + 1

	var strike_stats := CombatMath.build_strike_stats(base_stats, combo_step, is_charged, is_sprint, is_riposte)
	_swing_stats = strike_stats

	# Attack cooldown & timing
	var rate: float = maxf(0.2, float(base_stats.attack_rate))
	if strike_stats.is_finisher:
		_attack_cd = 0.55 / rate
		_strike_in = 0.14
		combo_timer = 0.0
	else:
		_attack_cd = 0.35 / rate
		_strike_in = 0.10
		combo_timer = CombatMath.COMBO_WINDOW

	# Forward momentum lunge
	player.facing = player.rig.yaw + PI
	var fwd := Vector3(sin(player.facing), 0.0, cos(player.facing))
	player.vel += fwd * float(strike_stats.lunge_speed)

	player.model.swing()
	player.swing_count += 1
	return true


func _resolve_strike() -> void:
	var fwd := Vector3(sin(player.facing), 0.0, cos(player.facing))
	var hits: int = 0
	if net != null and net.has_method("local_swing"):
		hits = net.local_swing(player.position + Vector3.UP * 0.9, fwd, _swing_stats, player.swimming)

	if hits > 0:
		if _swing_stats.get("is_finisher", false) or _swing_stats.get("is_charged", false) or _swing_stats.get("is_riposte", false):
			trigger_hit_stop(CombatMath.HITSTOP_HEAVY)
			_shake = 0.25
		else:
			trigger_hit_stop(CombatMath.HITSTOP_LIGHT)
			_shake = 0.12


func trigger_hit_stop(duration: float) -> void:
	_hit_stop_t = duration
	if DisplayServer.get_name() != "headless":
		Engine.time_scale = 0.1
		var tree := get_tree()
		if tree != null:
			tree.create_timer(duration, true, false, true).timeout.connect(func():
				Engine.time_scale = 1.0)


func try_dodge() -> bool:
	if guard_broken_t > 0.0 or _dodge_cd > 0.0 or _dodge_t >= 0.0 or player.is_seated() or player.swimming:
		return false
	if not player.vitality.consume_stamina(CombatMath.DODGE_STAMINA):
		return false

	# Cancel pending attacks or charge
	_strike_in = -1.0
	is_charging = false
	charge_held_t = 0.0

	var b := Basis(Vector3.UP, player.rig.yaw)
	var wish_z := Input.get_axis("move_back", "move_forward") if InputMap.has_action("move_back") and InputMap.has_action("move_forward") else 0.0
	var wish_x := Input.get_axis("move_left", "move_right") if InputMap.has_action("move_left") and InputMap.has_action("move_right") else 0.0
	var wish := -b.z * wish_z + b.x * wish_x
	_dodge_dir = wish.normalized() if wish.length() > 0.2 else b.z  # no input: hop backwards
	_dodge_t = 0.0
	_dodge_cd = CombatMath.DODGE_COOLDOWN
	return true


## Hook from Player._physics_process: sneaking slows you, dodging overrides movement.
func modify_move(target_v: Vector3) -> Vector3:
	if _dodge_t >= 0.0:
		player.vel.x = _dodge_dir.x * CombatMath.DODGE_SPEED
		player.vel.z = _dodge_dir.z * CombatMath.DODGE_SPEED
		return _dodge_dir * CombatMath.DODGE_SPEED
	if guard_broken_t > 0.0:
		return Vector3.ZERO
	if is_guarding:
		return target_v * 0.6
	if is_charging:
		return target_v * 0.5
	if sneaking:
		return target_v * 0.45
	return target_v


## Host says a creature hit us. Returns "dodged", "parried", "blocked", "guard_broken", or "hit".
func receive_hit(amount: float, from: Vector3, creature_id: int) -> String:
	if is_dodging():
		return "dodged"

	var facing := Vector3(sin(player.facing), 0.0, cos(player.facing))

	# Precision Parry check (first ~200ms of pressing RMB)
	if weapon_def() != null and CombatMath.parry_succeeds(_parry_t, player.position, facing, from):
		if net != null and net.has_method("report_parry"):
			net.report_parry(creature_id)
		riposte_ready_t = CombatMath.RIPOSTE_WINDOW
		_shake = 0.18
		trigger_hit_stop(CombatMath.HITSTOP_HEAVY)
		return "parried"

	# Guard Stance Block check (holding RMB)
	if weapon_def() != null and is_guarding and CombatMath.guard_succeeds(player.position, facing, from):
		var blk := CombatMath.calculate_guard_block(amount, player.vitality.current_stamina)
		if blk.guard_broken:
			player.vitality.consume_stamina(player.vitality.current_stamina)
			guard_broken_t = CombatMath.GUARD_BREAK_DURATION
			is_guarding = false
			player.vitality.take_damage(blk.damage_taken, &"physical", from)
			var kb := CombatMath.knockback(from, player.position, 1.4)
			player.vel += kb
			_shake = 0.25
			trigger_hit_stop(CombatMath.HITSTOP_LIGHT)
			return "guard_broken"
		else:
			player.vitality.consume_stamina(blk.stamina_cost)
			if blk.damage_taken > 0.0:
				player.vitality.take_damage(blk.damage_taken, &"physical", from)
			_shake = 0.08
			var kb := CombatMath.knockback(from, player.position, 0.3)
			player.vel += Vector3(kb.x, 0.0, kb.z) * 0.4
			trigger_hit_stop(CombatMath.HITSTOP_LIGHT)
			return "blocked"

	if amount <= 0.0:
		return "hit"

	player.vitality.take_damage(amount, &"physical", from)
	var kb := CombatMath.knockback(from, player.position, 1.0)
	player.vel += kb
	_shake = 0.2
	return "hit"


func _update_shake(delta: float) -> void:
	if player == null or player.rig == null or player.rig.cam == null:
		return
	var cam: Camera3D = player.rig.cam
	if _shake > 0.0:
		_shake -= delta
		cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
