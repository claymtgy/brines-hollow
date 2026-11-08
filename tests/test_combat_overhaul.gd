extends SceneTree
## Automated Headless Test Suite for Brine's Hollow Overhauled High-Impact Combat System.
## Tests:
## 1. 3-Hit Combo Chains (Light 1, Light 2, Heavy Finisher), Lunge Momentum & Timers
## 2. Charged Heavy Attacks (Windup, Multipliers, Poise Damage, Movement Slow)
## 3. Sprint Engage Cleaves (Momentum, Damage Boost, Combo Linking)
## 4. Aerial Downward Plunging Strike & Landing AOE Shockwave
## 5. Precision Timed Parry, Deflection Window & Riposte Counter-Attack State
## 6. Guard Stance (RMB), Stamina Absorption, Guard Break Stumble & Recovery
## 7. 8-Directional Dodge Roll with i-Frames and Dodge Cancelling
## 8. Enemy Poise / Stagger Meter, Posture Fracture & Stagger Recovery
## 9. Micro Hit-Stop & Camera Trauma Juice

var passed := 0
var total := 0

func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		push_error("  [FAIL] %s" % label)
		print("  [FAIL] %s" % label)


class MockRig extends CameraRig:
	func _init() -> void:
		cam = Camera3D.new()
		add_child(cam)


class MockNet extends Node:
	var swing_calls: Array = []
	var aoe_calls: Array = []
	var parry_reported := -1

	func local_swing(origin: Vector3, fwd: Vector3, stats: Dictionary, in_water: bool) -> int:
		swing_calls.append({"origin": origin, "fwd": fwd, "stats": stats, "in_water": in_water})
		return 1

	func local_aoe_strike(center: Vector3, radius: float, stats: Dictionary, in_water: bool = false) -> int:
		aoe_calls.append({"center": center, "radius": radius, "stats": stats, "in_water": in_water})
		return 2

	func report_parry(cid: int) -> void:
		parry_reported = cid


class MockHud extends Hud:
	var last_toast := ""

	func _init() -> void:
		pass

	func show_toast(msg: String) -> void:
		last_toast = msg


class MockModel extends CharacterModel:
	var swings := 0

	func _init() -> void:
		arm_r = Node3D.new()
		arm_l = Node3D.new()
		body = Node3D.new()
		head = Node3D.new()
		leg_l = Node3D.new()
		leg_r = Node3D.new()
		add_child(arm_r)
		add_child(arm_l)
		add_child(body)
		add_child(head)
		add_child(leg_l)
		add_child(leg_r)

	func set_tool(_tool_id: int) -> void:
		pass

	func swing() -> void:
		swings += 1


func _init() -> void:
	print("==================================================")
	print("Running Overhauled High-Impact Combat Test Suite...")
	print("==================================================")

	VoxelWorld.push_palette()
	ItemDB.init_db()

	var cutlass_def := ItemDB.get_item(&"rusty_cutlass")
	var sabre_def := ItemDB.get_item(&"corsair_sabre")
	var maul_def := ItemDB.get_item(&"anchor_maul")

	# =========================================================================
	# 1. Combo Multipliers & Move Mechanics in CombatMath
	# =========================================================================
	print("\n-- 1. Combo Moveset Math & Progression")
	check(CombatMath.combo_multiplier(1) == CombatMath.COMBO_STEP_1_MULT, "Combo Step 1 multiplier is 1.0x")
	check(CombatMath.combo_multiplier(2) == CombatMath.COMBO_STEP_2_MULT, "Combo Step 2 multiplier is 1.2x")
	check(CombatMath.combo_multiplier(3) == CombatMath.COMBO_STEP_3_MULT, "Combo Step 3 Finisher multiplier is 1.6x")

	check(CombatMath.combo_stagger_multiplier(1) == 1.0, "Combo Step 1 stagger multiplier is 1.0x")
	check(CombatMath.combo_stagger_multiplier(2) == 1.3, "Combo Step 2 stagger multiplier is 1.3x")
	check(CombatMath.combo_stagger_multiplier(3) == 2.0, "Combo Step 3 Finisher stagger multiplier is 2.0x")

	check(CombatMath.combo_lunge_speed(1) == 2.2, "Combo Step 1 forward lunge is 2.2 m/s")
	check(CombatMath.combo_lunge_speed(2) == 2.8, "Combo Step 2 forward lunge is 2.8 m/s")
	check(CombatMath.combo_lunge_speed(3) == 4.2, "Combo Step 3 Finisher forward lunge is 4.2 m/s")

	var base_cut := CombatMath.weapon_stats(cutlass_def)
	var strike1 := CombatMath.build_strike_stats(base_cut, 1, false, false, false)
	var strike2 := CombatMath.build_strike_stats(base_cut, 2, false, false, false)
	var strike3 := CombatMath.build_strike_stats(base_cut, 3, false, false, false)

	check(strike1.effective_damage == base_cut.damage * 1.0 and not strike1.is_finisher, "Strike 1 calculates normal damage")
	check(is_equal_approx(strike2.effective_damage, base_cut.damage * 1.2), "Strike 2 calculates 1.2x damage")
	check(is_equal_approx(strike3.effective_damage, base_cut.damage * 1.6) and strike3.is_finisher, "Strike 3 calculates 1.6x finisher damage")
	check(strike3.effective_stagger == base_cut.stagger_power * 2.0, "Strike 3 doubles stagger power")

	# =========================================================================
	# 2. Charged Heavy Attack Math
	# =========================================================================
	print("\n-- 2. Charged Heavy Attack Math")
	var charged_strike := CombatMath.build_strike_stats(base_cut, 0, true, false, false)
	check(charged_strike.is_charged and charged_strike.is_finisher, "Charged strike sets is_charged and is_finisher")
	check(is_equal_approx(charged_strike.effective_damage, base_cut.damage * CombatMath.CHARGE_DAMAGE_MULT), "Charged strike deals 2.0x damage")
	check(is_equal_approx(charged_strike.effective_stagger, base_cut.stagger_power * CombatMath.CHARGE_STAGGER_MULT), "Charged strike deals 2.5x stagger")
	check(charged_strike.lunge_speed == CombatMath.CHARGE_LUNGE_SPEED, "Charged strike has 5.0 m/s forward lunge")

	# =========================================================================
	# 3. Sprint Engage Cleave & Aerial Plunge Math
	# =========================================================================
	print("\n-- 3. Sprint Engage & Aerial Plunge Math")
	var sprint_strike := CombatMath.build_strike_stats(base_cut, 0, false, true, false)
	check(is_equal_approx(sprint_strike.effective_damage, base_cut.damage * CombatMath.SPRINT_ENGAGE_MULT), "Sprint cleave deals 1.25x damage")
	check(sprint_strike.lunge_speed == CombatMath.SPRINT_ENGAGE_LUNGE, "Sprint cleave has 4.2 m/s lunge momentum")

	check(CombatMath.PLUNGE_AOE_RADIUS == 3.5, "Plunging slam AOE radius is 3.5m")
	check(CombatMath.PLUNGE_DAMAGE_MULT == 1.75, "Plunging slam multiplier is 1.75x")
	check(CombatMath.PLUNGE_STAGGER_MULT == 2.2, "Plunging slam stagger is 2.2x")

	# =========================================================================
	# 4. Guard Stance & Guard Break Math
	# =========================================================================
	print("\n-- 4. Guard Stance & Guard Break Math")
	var defender_pos := Vector3.ZERO
	var defender_facing := Vector3.FORWARD # (0, 0, -1)
	var attacker_front := Vector3(0, 0, -2.0)
	var attacker_rear := Vector3(0, 0, 2.0)

	check(CombatMath.guard_succeeds(defender_pos, defender_facing, attacker_front), "Guard blocks frontal attack")
	check(not CombatMath.guard_succeeds(defender_pos, defender_facing, attacker_rear), "Guard fails against attack from rear")

	# Clean block with sufficient stamina
	var block_res := CombatMath.calculate_guard_block(10.0, 50.0, CombatMath.Difficulty.TIDEWATCH)
	check(block_res.blocked and not block_res.guard_broken, "Sufficient stamina results in clean block")
	check(block_res.damage_taken == 0.0, "Clean block absorbs 100% of damage on Tidewatch")
	check(block_res.stamina_cost == 12.0, "Block stamina cost is damage * 1.2 (12.0 stamina)")

	# Undertow difficulty has slight chip damage
	var undertow_block := CombatMath.calculate_guard_block(20.0, 50.0, CombatMath.Difficulty.UNDERTOW)
	check(undertow_block.blocked and undertow_block.damage_taken == 3.0, "Undertow has 15% chip damage on block")

	# Guard break when out of stamina
	var break_res := CombatMath.calculate_guard_block(30.0, 10.0, CombatMath.Difficulty.TIDEWATCH)
	check(not break_res.blocked and break_res.guard_broken, "Insufficient stamina triggers Guard Break")
	check(break_res.stamina_cost == 10.0, "Guard break consumes remaining stamina")
	check(break_res.damage_taken > 0.0, "Player takes unmitigated portion of damage on guard break")

	# =========================================================================
	# 5. Riposte Counter-Attack Math
	# =========================================================================
	print("\n-- 5. Riposte Counter-Attack Math")
	var riposte_strike := CombatMath.build_strike_stats(base_cut, 0, false, false, true)
	check(riposte_strike.is_riposte, "Riposte strike identified")
	check(is_equal_approx(riposte_strike.effective_damage, base_cut.damage * CombatMath.RIPOSTE_DAMAGE_MULT), "Riposte deals 2.5x damage")
	check(is_equal_approx(riposte_strike.effective_stagger, base_cut.stagger_power * CombatMath.RIPOSTE_STAGGER_MULT), "Riposte deals 2.5x stagger power")

	# =========================================================================
	# 6. Live PlayerCombat Component Integration
	# =========================================================================
	print("\n-- 6. Live PlayerCombat Component Integration")
	var player := Player.new()
	var rig := MockRig.new()
	var hud := MockHud.new()
	var model := MockModel.new()
	var mock_net := MockNet.new()

	player.rig = rig
	player.hud = hud
	player.model = model
	player.position = Vector3(10, 5, 10)
	player.on_ground = true

	var combat := PlayerCombat.new()
	combat.player = player
	combat.net = mock_net
	player.combat = combat
	player.add_child(combat)

	# Give player a cutlass
	player.inventory.slots[0] = ItemSlot.new(&"rusty_cutlass", 1)
	player.inventory.active_hotbar_index = 0
	player.vitality.current_stamina = 100.0

	# Test 3-Hit Combo Chain
	check(combat.combo_step == 0, "Initial combo step is 0 (idle)")
	combat.attack(cutlass_def, false)
	check(combat.combo_step == 1, "First swing advances to combo step 1 (Light 1)")
	check(combat.combo_timer == CombatMath.COMBO_WINDOW, "Combo timer set to 0.9s window")
	check(player.vel.length() > 0.0, "Forward lunge momentum applied on step 1")

	player.vel = Vector3.ZERO
	combat.attack(cutlass_def, false)
	check(combat.combo_step == 2, "Second swing advances to combo step 2 (Light 2)")
	check(player.vel.length() > 0.0, "Forward lunge momentum applied on step 2")

	player.vel = Vector3.ZERO
	combat.attack(cutlass_def, false)
	check(combat.combo_step == 3, "Third swing executes combo step 3 (Heavy Finisher)")
	check(combat._swing_stats.get("is_finisher", false) == true, "Finisher flag set on step 3 strike stats")
	check(player.vel.length() > 3.0, "Heavy finisher delivers decisive forward surge momentum")

	# Combo reset after timer expires
	combat.combo_timer = 0.05
	combat.process_input(0.1, false)
	check(combat.combo_step == 0, "Combo resets back to 0 after combo timer expires")

	# Test Charged Heavy Attack
	player.vitality.current_stamina = 100.0
	player.vel = Vector3.ZERO
	combat.execute_charged_attack(cutlass_def)
	check(combat._swing_stats.get("is_charged", false) == true, "execute_charged_attack sets is_charged")
	check(combat._swing_stats.get("is_finisher", false) == true, "Charged attack is a finisher")
	check(combat._swing_stats.get("damage_mult", 0.0) == CombatMath.CHARGE_DAMAGE_MULT, "Charged attack applies 2.0x damage mult")

	# Test Aerial Plunge
	player.vitality.current_stamina = 100.0
	player.on_ground = false
	player.vel.y = 0.0
	check(combat.start_plunge_attack(cutlass_def), "start_plunge_attack succeeds with stamina")
	check(combat.is_plunging, "Airborne attack initiates plunging strike")
	check(player.vel.y == -15.0, "Plunge accelerates downward at -15.0 m/s")

	# Test Landing Plunge Shockwave
	player.on_ground = true
	combat.on_land_plunge()
	check(not combat.is_plunging, "Landing clears plunging state")
	check(mock_net.aoe_calls.size() == 1, "Landing triggers local AOE shockwave on CreatureNet")
	check(mock_net.aoe_calls[0].radius == CombatMath.PLUNGE_AOE_RADIUS, "AOE shockwave radius is 3.5m")
	check(mock_net.aoe_calls[0].stats.get("damage_mult", 0.0) == CombatMath.PLUNGE_DAMAGE_MULT, "AOE shockwave deals 1.75x damage")

	# =========================================================================
	# 7. Parry, Riposte & Guard Stance in PlayerCombat
	# =========================================================================
	print("\n-- 7. Parry, Riposte & Guard Stance in PlayerCombat")
	player.vitality.current_stamina = 100.0
	player.vitality.current_hp = 100.0
	combat._parry_t = 0.1 # inside parry window
	player.facing = 0.0   # facing forward +Z
	var hit_front := player.position + Vector3(0, 0, 1.5)
	var parry_result := combat.receive_hit(15.0, hit_front, 42)
	check(parry_result == "parried", "Frontal hit during parry window returns 'parried'")
	check(mock_net.parry_reported == 42, "CreatureNet notified of parried creature ID 42")
	check(combat.riposte_ready_t == CombatMath.RIPOSTE_WINDOW, "Parry activates Riposte Ready state (1.5s)")

	# Unleash Riposte Counter-Attack
	combat.attack(cutlass_def, false)
	check(combat._swing_stats.get("is_riposte", false) == true, "Attack while Riposte Ready triggers Riposte Strike")
	check(combat._swing_stats.get("damage_mult", 0.0) == CombatMath.RIPOSTE_DAMAGE_MULT, "Riposte deals 2.5x damage")
	check(combat.riposte_ready_t == 0.0, "Riposte state consumed after strike")

	# Clean Guard Block
	combat._parry_t = -1.0
	combat.is_guarding = true
	player.facing = 0.0
	player.vitality.current_stamina = 100.0
	player.vitality.current_hp = 100.0
	var hp_before := player.vitality.current_hp
	var block_result := combat.receive_hit(15.0, hit_front, 42)
	check(block_result == "blocked", "Holding guard against frontal hit returns 'blocked'")
	check(player.vitality.current_hp == hp_before, "Blocked hit dealt 0 health damage")
	check(player.vitality.current_stamina < 100.0, "Blocked hit consumed stamina")

	# Guard Break
	player.facing = 0.0
	player.vitality.current_stamina = 2.0 # very low stamina
	player.vitality.current_hp = 100.0
	var break_result := combat.receive_hit(30.0, hit_front, 42)
	check(break_result == "guard_broken", "Heavy hit with insufficient stamina triggers 'guard_broken'")
	check(combat.guard_broken_t == CombatMath.GUARD_BREAK_DURATION, "Guard break sets stumble duration (0.85s)")
	check(not combat.is_guarding, "Guard broken drops guard stance")
	check(combat.modify_move(Vector3(1, 0, 0)) == Vector3.ZERO, "Guard broken stumble stops all movement")

	# =========================================================================
	# 8. 8-Directional Dodge Roll & i-Frames
	# =========================================================================
	print("\n-- 8. 8-Directional Dodge Roll & i-Frames")
	combat.guard_broken_t = 0.0
	player.vitality.revive()
	player.vitality.current_stamina = 50.0

	# Try dodge
	check(combat.try_dodge(), "Dodge succeeds with stamina")
	check(combat.is_dodging(), "is_dodging() is true during roll")
	check(combat.receive_hit(50.0, hit_front, 99) == "dodged", "Incoming hit while dodging returns 'dodged' with 0 damage")
	check(combat.modify_move(Vector3.ZERO).length() > 0.0, "Dodge applies roll speed to movement")

	# =========================================================================
	# 9. Enemy Poise System in Creature
	# =========================================================================
	print("\n-- 9. Enemy Poise System in Creature")
	var crab := TideCrab.new()
	crab.setup(101, mock_net, Vector3(0, 0, 0), true)
	crab.max_hp = 50.0
	crab.hp = 50.0
	check(crab.poise == CombatMath.DEFAULT_CREATURE_POISE, "Creature starts with full poise (20.0)")
	check(crab.max_poise == CombatMath.DEFAULT_CREATURE_POISE, "Creature max_poise is 20.0")

	# Hit with 0.8 power (deals 8 poise damage)
	crab.on_hit(5.0, Vector3(1, 0, 0), 0.8, 1)
	check(crab.poise == 12.0, "Light hit reduces poise from 20.0 to 12.0")
	check(crab.state != Creature.State.STAGGER, "Creature is not yet staggered")

	# Heavy hit with 1.5 power (deals 15 poise damage -> breaks poise)
	crab.on_hit(10.0, Vector3(1, 0, 0), 1.5, 1)
	check(crab.state == Creature.State.STAGGER, "Poise broken triggers State.STAGGER")
	check(crab.poise == crab.max_poise, "Poise resets to max upon stance break")

	# Poise regeneration test
	crab.set_state(Creature.State.IDLE)
	crab.poise = 10.0
	crab.poise_regen_cd = 0.0
	crab.tick_poise(0.5)
	check(crab.poise > 10.0, "Poise regenerates smoothly when out of combat")

	# =========================================================================
	# Summary
	# =========================================================================
	print("\n==================================================")
	print("Combat Overhaul Suite: %d / %d tests passed!" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
