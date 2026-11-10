class_name TestBowsAndFlintlock
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n==================================================")
	print("Running Bows & Flintlock Ranged Arsenal Test Suite")
	print("==================================================\n")

	_test_item_definitions_and_recipes()
	_test_combat_math_ballistics_and_damage()
	_test_player_combat_bow_mechanics()
	_test_player_combat_flintlock_mechanics()
	_test_creature_net_ranged_strikes()

	print("\n==================================================")
	print("Bows & Flintlock Suite: %d / %d tests passed!" % [_passed, _passed + _failed])
	print("==================================================\n")

	if _failed > 0:
		print("FAILED with %d errors" % _failed)
	quit(_failed)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] %s" % message)
		_passed += 1
	else:
		print("  [FAIL] %s" % message)
		_failed += 1


func _test_item_definitions_and_recipes() -> void:
	print("-- 1. Item Definitions & Crafting Recipes")
	var bow1 := ItemDB.get_item(&"hunting_bow")
	_assert(bow1 != null, "Whittled Shore Bow registered in ItemDB")
	_assert(bow1.weapon_data.get("weapon_type") == WeaponDef.WeaponType.BOW, "Hunting bow weapon_type is BOW")
	_assert(bow1.weapon_data.get("is_ranged") == true, "Hunting bow is flagged is_ranged")

	var recurve := ItemDB.get_item(&"driftwood_recurve")
	_assert(recurve != null, "Driftwood Recurve Bow registered")
	_assert(recurve.weapon_data.get("damage") == 34, "Recurve bow has 34 base damage")

	var flintlock := ItemDB.get_item(&"flintlock_pistol")
	_assert(flintlock != null, "Sea-Dog's Flintlock registered")
	_assert(flintlock.weapon_data.get("weapon_type") == WeaponDef.WeaponType.FLINTLOCK, "Flintlock weapon_type is FLINTLOCK")
	_assert(flintlock.weapon_data.get("stagger_power") == 2.2, "Flintlock has high 2.2 stagger power")

	var arrow1 := ItemDB.get_item(&"flint_arrow")
	var arrow2 := ItemDB.get_item(&"iron_broadhead")
	var cart := ItemDB.get_item(&"paper_cartridge")
	var powder := ItemDB.get_item(&"black_powder")
	_assert(arrow1 != null and arrow1.has_tag("arrow"), "Flint arrow registered with arrow tag")
	_assert(arrow2 != null and arrow2.has_tag("pierce"), "Iron broadhead registered with pierce tag")
	_assert(cart != null and cart.has_tag("bullet"), "Paper cartridge registered")
	_assert(powder != null and powder.has_tag("powder"), "Black powder registered")

	_assert(RecipeDB.get_recipe(&"craft_hunting_bow") != null, "Recipe exists for hunting bow")
	_assert(RecipeDB.get_recipe(&"craft_flint_arrow") != null, "Recipe exists for flint arrows")
	_assert(RecipeDB.get_recipe(&"craft_paper_cartridge") != null, "Recipe exists for paper cartridges")
	_assert(RecipeDB.get_recipe(&"forge_flintlock_pistol") != null, "Recipe exists for flintlock pistol")


func _test_combat_math_ballistics_and_damage() -> void:
	print("\n-- 2. CombatMath Ballistics & Range Falloff")
	_assert(CombatMath.is_ranged_weapon(WeaponDef.WeaponType.BOW), "BOW recognized as ranged weapon")
	_assert(CombatMath.is_ranged_weapon(WeaponDef.WeaponType.FLINTLOCK), "FLINTLOCK recognized as ranged weapon")
	_assert(not CombatMath.is_ranged_weapon(WeaponDef.WeaponType.CUTLASS), "CUTLASS is not ranged weapon")

	# Arrow launch velocity
	var v_full := CombatMath.calc_arrow_launch_velocity(Vector3.FORWARD, 1.0, 40.0)
	var v_half := CombatMath.calc_arrow_launch_velocity(Vector3.FORWARD, 0.5, 40.0)
	var v_min := CombatMath.calc_arrow_launch_velocity(Vector3.FORWARD, 0.1, 40.0)

	_assert(is_equal_approx(v_full.length(), 40.0), "Full draw arrow speed reaches max 40.0 m/s")
	_assert(is_equal_approx(v_half.length(), 20.0), "Half draw arrow speed is 20.0 m/s")
	_assert(v_min.length() >= 10.0, "Low draw arrow velocity clamped to minimum 0.25 power (10 m/s)")

	# Flintlock damage falloff
	var dmg_close := CombatMath.calc_flintlock_damage(48.0, 3.0)
	var dmg_mid := CombatMath.calc_flintlock_damage(48.0, 10.0)
	var dmg_far := CombatMath.calc_flintlock_damage(48.0, 18.0)
	var dmg_out := CombatMath.calc_flintlock_damage(48.0, 26.0)

	_assert(is_equal_approx(dmg_close, 72.0), "Point-blank flintlock deals 1.5x damage (72 dmg)")
	_assert(is_equal_approx(dmg_mid, 48.0), "Medium range flintlock deals 1.0x base damage (48 dmg)")
	_assert(is_equal_approx(dmg_far, 48.0 * 0.65), "Long range flintlock deals 0.65x damage with falloff")
	_assert(is_equal_approx(dmg_out, 0.0), "Out of range flintlock deals 0 damage")


func _test_player_combat_bow_mechanics() -> void:
	print("\n-- 3. PlayerCombat Bow Mechanics & Ammo Consumption")
	var p := _create_mock_player()
	var combat := PlayerCombat.new()
	combat.player = p
	p.combat = combat

	# Place hunting bow in hotbar active slot
	p.inventory.slots[0] = ItemSlot.new(&"hunting_bow", 1)
	p.inventory.active_hotbar_index = 0

	_assert(combat.is_holding_ranged(), "PlayerCombat detects holding ranged weapon")
	_assert(combat.active_weapon().id == &"hunting_bow", "Active weapon is hunting_bow")
	_assert(combat.weapon_def() == null, "Melee weapon_def() returns null for ranged weapon")

	# Fire without ammo
	var fired_no_ammo := combat.fire_bow(combat.active_weapon(), 0.75)
	_assert(not fired_no_ammo, "Bow cannot fire without arrows in inventory")

	# Add flint arrows to inventory
	p.inventory.add_item(&"flint_arrow", 5)
	_assert(p.inventory.get_item_count(&"flint_arrow") == 5, "Added 5 flint arrows")

	# Fire with flint arrow
	var fired_flint := combat.fire_bow(combat.active_weapon(), 0.75)
	_assert(fired_flint, "Bow fired successfully with flint arrows")
	_assert(p.inventory.get_item_count(&"flint_arrow") == 4, "Consumed 1 flint arrow (4 remaining)")

	# Add iron broadheads (should take priority)
	p.inventory.add_item(&"iron_broadhead", 2)
	var fired_broadhead := combat.fire_bow(combat.active_weapon(), 0.75)
	_assert(fired_broadhead, "Bow fired successfully with broadheads")
	_assert(p.inventory.get_item_count(&"iron_broadhead") == 1, "Consumed 1 broadhead arrow (priority over flint)")
	_assert(p.inventory.get_item_count(&"flint_arrow") == 4, "Flint arrows untouched while broadheads available")

	# Swimming penalty
	p.swimming = true
	var fired_swimming := combat.fire_bow(combat.active_weapon(), 0.75)
	_assert(fired_swimming, "Bow can loose arrows underwater at reduced efficiency")
	p.swimming = false

	p.free()
	combat.free()


func _test_player_combat_flintlock_mechanics() -> void:
	print("\n-- 4. PlayerCombat Flintlock Mechanics & Gun-Kata")
	var p := _create_mock_player()
	var combat := PlayerCombat.new()
	combat.player = p
	p.combat = combat

	p.inventory.slots[0] = ItemSlot.new(&"flintlock_pistol", 1)
	p.inventory.active_hotbar_index = 0

	_assert(combat.is_holding_ranged(), "Flintlock recognized as ranged weapon")

	# Attempt fire without ammo
	var fire_empty := combat.fire_flintlock(combat.active_weapon())
	_assert(not fire_empty, "Flintlock fails to fire without paper cartridges")

	# Add paper cartridges
	p.inventory.add_item(&"paper_cartridge", 3)
	_assert(p.inventory.get_item_count(&"paper_cartridge") == 3, "Added 3 paper cartridges")

	# Waterlogged misfire check
	p.swimming = true
	var fire_wet := combat.fire_flintlock(combat.active_weapon())
	_assert(not fire_wet, "Flintlock misfires when swimming / submerged in water")
	_assert(p.inventory.get_item_count(&"paper_cartridge") == 3, "Cartridge preserved upon waterlogged misfire")
	p.swimming = false

	# Fire dry shot
	combat._attack_cd = 0.0
	var fire_dry := combat.fire_flintlock(combat.active_weapon())
	_assert(fire_dry, "Flintlock successfully fires when dry")
	_assert(p.inventory.get_item_count(&"paper_cartridge") == 2, "Consumed 1 paper cartridge on shot")
	_assert(combat._shake > 0.3, "Flintlock shot triggers recoil screen shake")

	# Gun-Kata combo chaining
	combat._attack_cd = 0.0
	combat.combo_step = 2 # previous melee cutlass slashes
	combat.fire_flintlock(combat.active_weapon())
	_assert(combat.combo_step == 0, "Gun-Kata finisher consumed combo chain")
	_assert(p.inventory.get_item_count(&"paper_cartridge") == 1, "Consumed cartridge on Gun-Kata shot")

	p.free()
	combat.free()


func _test_creature_net_ranged_strikes() -> void:
	print("\n-- 5. CreatureNet Ranged Hits Integration")
	var net := CreatureNet.new()

	# Spawn dummy target creature
	var target := Creature.new()
	target.cid = 101
	target.max_hp = 100.0
	target.hp = 100.0
	target.radius = 0.8
	target.position = Vector3(0, 0, -8.0) # 8m directly ahead
	net.creatures[target.cid] = target

	# Raycast arrow strike
	var arrow_stats := {
		"damage": 30.0,
		"stagger_power": 1.2,
		"weapon_type": WeaponDef.WeaponType.BOW,
		"reach_m": 40.0
	}
	var arrow_hits := net.local_raycast_strike(Vector3.ZERO, Vector3.FORWARD, 40.0, arrow_stats, false)
	_assert(arrow_hits == 1, "Arrow raycast scored 1 direct hit on target creature")
	_assert(target.hp < 100.0, "Creature took damage from arrow strike (hp: %.1f)" % target.hp)

	# Flintlock shot with distance scaling
	var hp_before := target.hp
	var flint_hits := net.local_flintlock_shot(Vector3.ZERO, Vector3.FORWARD, 48.0, 22.0, 2.2, false, false)
	_assert(flint_hits == 1, "Flintlock shot scored 1 hit at 8m range")
	_assert(target.hp < hp_before, "Creature took flintlock damage (hp: %.1f -> %.1f)" % [hp_before, target.hp])

	# Target out of cone / ray
	var miss_hits := net.local_raycast_strike(Vector3.ZERO, Vector3.RIGHT, 40.0, arrow_stats, false)
	_assert(miss_hits == 0, "Shot fired in wrong direction scores 0 hits")

	target.free()
	net.free()


func _create_mock_player() -> Player:
	var p := Player.new()
	p.hud = MockHud.new()
	p.model = CharacterModel.new()
	p.vitality.current_stamina = 100.0
	p.vitality.current_hp = 100.0
	return p


class MockHud extends Hud:
	var last_toast := ""

	func _init() -> void:
		pass

	func show_toast(msg: String, _duration: float = 3.0, _immediate: bool = false) -> void:
		last_toast = msg
