class_name PlayerCombat
extends Node
## Local player's optional combat + stealth: melee swings with the active hotbar weapon,
## a dodge roll (C / back paddle), a parry (right mouse / LT while holding a weapon) and
## sneaking (hold Ctrl / back paddle 2). Hits on creatures are sent to the host, which owns
## creature health. Creature hits on us arrive from the host via `receive_hit`.

var player: Player
var net: Node                    # CreatureNet

var sneaking := false
var _attack_cd := 0.0
var _strike_in := -1.0           # seconds until the swing's active frame
var _swing_stats := {}
var _dodge_t := -1.0             # elapsed time in the current dodge (-1 = none)
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _parry_t := -1.0             # elapsed since parry press (-1 = none)
var _parry_cd := 0.0
var _shake := 0.0
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
	sneaking = can_input and Input.is_action_pressed("sneak")
	if can_input and Input.is_action_just_pressed("dodge"):
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
	if _parry_t >= 0.0 and _parry_t < CombatMath.PARRY_WINDOW:
		player.model.arm_r.rotation.x = -1.4   # blade raised across the body
		player.model.arm_r.rotation.z = 0.9
	if can_input and Input.is_action_just_pressed("alt_use") and _parry_cd <= 0.0:
		_parry_t = 0.0
		_parry_cd = CombatMath.PARRY_COOLDOWN
		player.facing = player.rig.yaw + PI
	if can_input and Input.is_action_pressed("use") and _attack_cd <= 0.0 and _dodge_t < 0.0:
		attack(wd)
	return true


func attack(wd: ItemDef) -> bool:
	var stats := CombatMath.weapon_stats(wd)
	if not player.vitality.consume_stamina(float(stats.stamina_per_swing)):
		if player.hud:
			player.hud.show_toast("Too winded to swing")
		_attack_cd = 0.5
		return false
	_attack_cd = 1.0 / maxf(0.2, float(stats.attack_rate))
	_swing_stats = stats
	_strike_in = 0.12               # active frame a moment after the wind-up
	player.facing = player.rig.yaw + PI
	player.model.swing()
	player.swing_count += 1
	return true


func _resolve_strike() -> void:
	var fwd := Vector3(sin(player.facing), 0.0, cos(player.facing))
	var hits: int = net.local_swing(player.position + Vector3.UP * 0.9, fwd, _swing_stats, player.swimming)
	if hits > 0:
		_shake = 0.12   # hit-stop feel: short camera kick


func try_dodge() -> bool:
	if _dodge_cd > 0.0 or _dodge_t >= 0.0 or player.is_seated() or player.swimming:
		return false
	if not player.vitality.consume_stamina(CombatMath.DODGE_STAMINA):
		return false
	var b := Basis(Vector3.UP, player.rig.yaw)
	var wish := -b.z * Input.get_axis("move_back", "move_forward") + b.x * Input.get_axis("move_left", "move_right")
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
	if sneaking:
		return target_v * 0.45
	return target_v


## Host says a creature hit us. Returns "dodged", "parried" or "hit".
func receive_hit(amount: float, from: Vector3, creature_id: int) -> String:
	if is_dodging():
		return "dodged"
	var facing := Vector3(sin(player.facing), 0.0, cos(player.facing))
	if weapon_def() != null and CombatMath.parry_succeeds(_parry_t, player.position, facing, from):
		net.report_parry(creature_id)
		_shake = 0.1
		return "parried"
	if amount <= 0.0:
		return "hit"
	player.vitality.take_damage(amount, &"physical", from)
	var kb := CombatMath.knockback(from, player.position, 1.0)
	player.vel += kb
	_shake = 0.2
	return "hit"


func _update_shake(delta: float) -> void:
	var cam: Camera3D = player.rig.cam
	if _shake > 0.0:
		_shake -= delta
		cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
