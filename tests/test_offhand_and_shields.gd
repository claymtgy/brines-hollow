class_name TestOffhandAndShields
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("\n==================================================")
	print("Running Off-Hand Equipment & Shields Test Suite")
	print("==================================================\n")

	_test_item_registration_and_recipes()
	_test_shield_guard_math()
	_test_player_offhand_shield_guarding()
	_test_offhand_lantern_utility()
	_test_character_model_paperdoll_sync()

	print("\n==================================================")
	print("Off-Hand & Shields Suite: %d / %d tests passed!" % [_passed, _passed + _failed])
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


func _test_item_registration_and_recipes() -> void:
	print("-- 1. Item Registration & Recipes")
	var shield := ItemDB.get_item(&"boarding_shield")
	_assert(shield != null, "Boarding shield registered in ItemDB")
	_assert(shield.equip_slot == &"accessory", "Boarding shield equips to accessory slot")
	_assert(shield.has_tag("shield"), "Boarding shield has 'shield' tag")
	_assert(shield.armor_data.get("guard_efficiency") == 0.5, "Shield has 0.5 guard efficiency (50% stamina reduction)")
	_assert(shield.armor_data.get("block_angle_deg") == 140.0, "Shield expands block angle to 140 degrees")
	_assert(shield.armor_data.get("parry_window_bonus") == 0.05, "Shield grants +0.05s parry window bonus")

	var lantern := ItemDB.get_item(&"offhand_brass_lantern")
	_assert(lantern != null, "Mariner's Belt Lantern registered")
	_assert(lantern.equip_slot == &"accessory", "Belt lantern equips to accessory slot")
	_assert(lantern.has_tag("light"), "Belt lantern has 'light' tag")

	_assert(RecipeDB.get_recipe(&"craft_boarding_shield") != null, "Crafting recipe exists for boarding shield")
	_assert(RecipeDB.get_recipe(&"craft_offhand_lantern") != null, "Crafting recipe exists for offhand lantern")


func _test_shield_guard_math() -> void:
	print("\n-- 2. CombatMath Guard Calculations with Shield")
	# Standard weapon block (guard_efficiency = 1.0)
	var std_block := CombatMath.calculate_guard_block(20.0, 100.0, CombatMath.Difficulty.TIDEWATCH, 1.0)
	_assert(std_block.blocked, "Standard block succeeds")
	_assert(is_equal_approx(std_block.stamina_cost, 24.0), "Standard block costs 24.0 stamina (20 * 1.2)")

	# Shield block (guard_efficiency = 0.5)
	var shield_block := CombatMath.calculate_guard_block(20.0, 100.0, CombatMath.Difficulty.TIDEWATCH, 0.5)
	_assert(shield_block.blocked, "Shield block succeeds")
	_assert(is_equal_approx(shield_block.stamina_cost, 12.0), "Shield block halves stamina cost (12.0 stamina)")

	# Angle check: 60 degrees off center (120 deg arc)
	var facing := Vector3(0, 0, -1)
	var attacker_flank := Vector3(sin(deg_to_rad(65.0)), 0, -cos(deg_to_rad(65.0))) # 65 deg off center
	var std_angle_ok := CombatMath.guard_succeeds(Vector3.ZERO, facing, attacker_flank, CombatMath.GUARD_ARC_DEG)
	var shield_angle_ok := CombatMath.guard_succeeds(Vector3.ZERO, facing, attacker_flank, 140.0)
	_assert(not std_angle_ok, "Standard 110 deg guard fails against 65 deg flank attack")
	_assert(shield_angle_ok, "Shield 140 deg guard successfully blocks 65 deg flank attack")

	# Parry window check: 0.30s since parry press
	var std_parry := CombatMath.parry_succeeds(0.30, Vector3.ZERO, facing, Vector3(0, 0, -2), CombatMath.PARRY_WINDOW)
	var shield_parry := CombatMath.parry_succeeds(0.30, Vector3.ZERO, facing, Vector3(0, 0, -2), CombatMath.PARRY_WINDOW + 0.05)
	_assert(not std_parry, "Standard parry expired at 0.30s (window is 0.28s)")
	_assert(shield_parry, "Shield parry succeeds at 0.30s (extended 0.33s window)")


func _test_player_offhand_shield_guarding() -> void:
	print("\n-- 3. PlayerCombat Off-Hand Shield Integration")
	var p := _create_mock_player()
	var combat := PlayerCombat.new()
	combat.player = p
	p.combat = combat

	# Unarmed without shield: cannot guard
	_assert(not combat.has_offhand_shield(), "Player does not have offhand shield")
	_assert(combat.weapon_def() == null, "Player is unarmed")

	# Equip boarding shield into accessory slot
	p.inventory.equipment[&"accessory"] = ItemSlot.new(&"boarding_shield", 1)

	_assert(combat.has_offhand_shield(), "Player has offhand shield equipped")
	_assert(combat.get_offhand_item().id == &"boarding_shield", "get_offhand_item() returns boarding_shield")

	# Guard with shield even while unarmed!
	p.facing = 0.0
	var hit_front := p.position + Vector3(0, 0, 2.0)
	combat.is_guarding = true
	var res := combat.receive_hit(20.0, hit_front, 50)
	_assert(res == "blocked", "Unarmed player with shield successfully blocks incoming hit")
	_assert(p.vitality.current_hp == 100.0, "Player took 0 damage on clean shield block")
	_assert(p.vitality.current_stamina < 100.0, "Stamina consumed on shield block")

	# Parry with shield
	combat.is_guarding = false
	combat._parry_t = 0.30 # within 0.33s shield parry window
	var res_parry := combat.receive_hit(20.0, hit_front, 50)
	_assert(res_parry == "parried", "Shield parries attack within extended window")
	_assert(combat.riposte_ready_t > 0.0, "Parry activated riposte window")

	p.free()
	combat.free()


func _test_offhand_lantern_utility() -> void:
	print("\n-- 4. Off-Hand Lantern & Light Utility")
	var p := _create_mock_player()
	var combat := PlayerCombat.new()
	combat.player = p
	p.combat = combat

	# Hold weapon in main hand (cutlass)
	p.inventory.slots[0] = ItemSlot.new(&"rusty_cutlass", 1)
	p.inventory.active_hotbar_index = 0

	_assert(not combat.has_light(), "Player with cutlass does not emit light initially")

	# Equip offhand lantern in accessory slot
	p.inventory.equipment[&"accessory"] = ItemSlot.new(&"offhand_brass_lantern", 1)

	_assert(combat.has_offhand_light(), "Player has offhand light equipped")
	_assert(combat.has_light(), "has_light() returns true while wielding cutlass with offhand lantern!")

	# Switch to bow: light still active!
	p.inventory.slots[0] = ItemSlot.new(&"hunting_bow", 1)
	_assert(combat.has_light(), "has_light() remains true while holding bow with offhand lantern")

	# Unequip lantern
	p.inventory.equipment[&"accessory"] = ItemSlot.new()
	_assert(not combat.has_offhand_light(), "Offhand light unequipped")
	_assert(not combat.has_light(), "has_light() is false after unequipping lantern")

	p.free()
	combat.free()


func _test_character_model_paperdoll_sync() -> void:
	print("\n-- 5. CharacterModel Paperdoll Gear Synchronization")
	var p := _create_mock_player()

	_assert(p.model != null, "Player model initialized")
	_assert(p.model.shield_node != null, "shield_node exists on character model")
	_assert(p.model.offhand_lantern != null, "offhand_lantern exists on character model")
	_assert(not p.model.shield_node.visible, "Shield is initially invisible")
	_assert(not p.model.offhand_lantern.visible, "Offhand lantern is initially invisible")

	# Simulate accessory equip event
	p.inventory.equipment_changed.emit(&"accessory", ItemSlot.new(&"boarding_shield", 1))
	_assert(p.model.shield_node.visible, "Shield node becomes visible when shield equipped")
	_assert(not p.model.offhand_lantern.visible, "Lantern remains hidden")

	# Equip lantern
	p.inventory.equipment_changed.emit(&"accessory", ItemSlot.new(&"offhand_brass_lantern", 1))
	_assert(not p.model.shield_node.visible, "Shield hidden when lantern equipped")
	_assert(p.model.offhand_lantern.visible, "Lantern node becomes visible when lantern equipped")

	# Unequip
	p.inventory.equipment_changed.emit(&"accessory", ItemSlot.new())
	_assert(not p.model.shield_node.visible, "Shield hidden when unequipped")
	_assert(not p.model.offhand_lantern.visible, "Lantern hidden when unequipped")

	p.free()


func _create_mock_player() -> Player:
	var p := Player.new()
	p.hud = MockHud.new()
	p._ready()
	p.vitality.current_stamina = 100.0
	p.vitality.current_hp = 100.0
	return p


class MockHud extends Hud:
	var last_toast := ""

	func _init() -> void:
		pass

	func show_toast(msg: String, _duration: float = 3.0, _immediate: bool = false) -> void:
		last_toast = msg
