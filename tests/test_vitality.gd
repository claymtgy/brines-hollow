extends SceneTree
## Automated headless test suite for Brine's Hollow Vitality Triad (Nourishment, Health & Stamina).

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Vitality Triad Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] %s" % desc)
		else:
			push_error("  [FAIL] %s" % desc)

	ItemDB.init_db()

	# -------------------------------------------------------------------------
	# 1. Baseline Survival Stats (Empty Stomach / Starvation Protection)
	# -------------------------------------------------------------------------
	var vit := VitalityController.new()
	assert_test.call("Baseline Max HP is 25", vit.get_max_hp() == 25.0)
	assert_test.call("Baseline Max Stamina is 50", vit.get_max_stamina() == 50.0)
	assert_test.call("Baseline Max Breath is 30s", vit.get_max_breath() == 30.0)
	assert_test.call("Baseline HP regen is 0 (no food passive healing)", vit.get_hp_regen_rate() == 0.0)
	assert_test.call("Stomach is initially empty", vit.get_active_meals().is_empty())

	# Non-punitive starvation: ticking with empty stomach does not kill player
	for _sec in range(60):
		vit.tick(1.0, false, false)
	assert_test.call("Empty stomach does not inflict starvation damage (HP remains at 25)", vit.current_hp == 25.0)
	assert_test.call("Player is not defeated while idling with empty stomach", not vit.is_defeated)

	# -------------------------------------------------------------------------
	# 2. The 3-Meal Satiety Stomach & Cumulative Food Buffs
	# -------------------------------------------------------------------------
	var inv := Inventory.new(16)
	inv.add_item(&"smoked_fish_ration", 2)
	inv.add_item(&"samphire_bouillabaisse", 1)
	inv.add_item(&"glazed_abyssal_crab", 1)
	inv.add_item(&"peppermint_kelp_tea", 1)

	# Meal 1: Smoked Fish Ration (+25 HP, +25 Stamina, +1.2 HP/s regen)
	var eat_1_ok := vit.eat_food(&"smoked_fish_ration", inv)
	assert_test.call("Eating smoked fish ration succeeds", eat_1_ok)
	assert_test.call("Smoked fish consumed from inventory (1 remaining)", inv.get_item_count(&"smoked_fish_ration") == 1)
	assert_test.call("Max HP increased from 25 to 50", vit.get_max_hp() == 50.0)
	assert_test.call("Max Stamina increased from 50 to 75", vit.get_max_stamina() == 75.0)
	assert_test.call("HP regen increased to 1.2 HP/s", is_equal_approx(vit.get_hp_regen_rate(), 1.2))

	# Meal 2: Samphire Bouillabaisse (+45 HP, +40 Stamina, +1.8 HP/s regen, +20% swim)
	var eat_2_ok := vit.eat_food(&"samphire_bouillabaisse", inv)
	assert_test.call("Eating bouillabaisse succeeds", eat_2_ok)
	assert_test.call("Max HP increased to 95 (25 + 25 + 45)", vit.get_max_hp() == 95.0)
	assert_test.call("Max Stamina increased to 115 (50 + 25 + 40)", vit.get_max_stamina() == 115.0)
	assert_test.call("HP regen increased to 3.0 HP/s (1.2 + 1.8)", is_equal_approx(vit.get_hp_regen_rate(), 3.0))
	assert_test.call("Swim speed multiplier boosted to 1.45x (1.0 + 0.25 + 0.20)", is_equal_approx(vit.get_swim_speed_multiplier(), 1.45))

	# Meal 3: Glazed Abyssal Crab (+70 HP, +60 Stamina, cold immunity, +60s breath)
	var eat_3_ok := vit.eat_food(&"glazed_abyssal_crab", inv)
	assert_test.call("Eating glazed abyssal crab succeeds", eat_3_ok)
	assert_test.call("Max HP reached 165 (95 + 70)", vit.get_max_hp() == 165.0)
	assert_test.call("Max Stamina reached 175 (115 + 60)", vit.get_max_stamina() == 175.0)
	assert_test.call("Cold immunity is active", vit.has_cold_immunity())
	assert_test.call("Max breath expanded to 90s (30 + 60)", vit.get_max_breath() == 90.0)
	assert_test.call("Stomach holds exactly 3 distinct meals", vit.get_active_meals().size() == 3)

	# Re-eating a dish you're still full of is refused and doesn't use it up
	vit.tick(100.0, false, false) # burn 100s of digestion
	var fish_left := inv.get_item_count(&"smoked_fish_ration")
	var check_full := vit.is_full_of(&"smoked_fish_ration")
	assert_test.call("Still full of a freshly eaten dish", check_full and not vit.can_eat_food(&"smoked_fish_ration"))
	assert_test.call("Eating it again is refused", not vit.eat_food(&"smoked_fish_ration", inv))
	assert_test.call("and the meal isn't wasted", inv.get_item_count(&"smoked_fish_ration") == fish_left)
	# Once half digested, eating it again refreshes it and tops up health
	vit.active_meals[0].remaining_sec = vit.active_meals[0].duration_sec * 0.3
	var prev_rem: float = vit.get_active_meals()[0].remaining_sec
	vit.current_hp = 10.0
	assert_test.call("Half digested: it can be eaten again", vit.eat_food(&"smoked_fish_ration", inv))
	assert_test.call("Re-eating smoked fish refreshed duration", vit.get_active_meals()[0].remaining_sec > prev_rem)
	assert_test.call("and gave its instant heal", vit.current_hp >= 10.0 + 25.0 - 0.01)
	assert_test.call("Stomach still holds 3 meals", vit.get_active_meals().size() == 3)

	# 4th meal replacement: eating peppermint tea replaces meal with lowest remaining time
	# Set bouillabaisse to only 5s remaining
	vit.active_meals[1].remaining_sec = 5.0
	vit.eat_food(&"peppermint_kelp_tea", inv)
	assert_test.call("4th meal successfully consumed", not inv.has_item(&"peppermint_kelp_tea", 1))
	assert_test.call("Bouillabaisse was evicted from stomach", not vit.has_meal(&"samphire_bouillabaisse"))
	assert_test.call("Peppermint tea is present in stomach", vit.has_meal(&"peppermint_kelp_tea"))
	assert_test.call("Stomach capped at 3 meals", vit.get_active_meals().size() == 3)

	# -------------------------------------------------------------------------
	# 3. Rested Comfort Mechanics & Stamina Multiplier
	# -------------------------------------------------------------------------
	var base_sta_rate: float = vit.get_stamina_regen_rate()
	vit.set_rested(true)
	assert_test.call("Rested comfort increases stamina recharge by 50%", is_equal_approx(vit.get_stamina_regen_rate(), base_sta_rate * 1.5))
	assert_test.call("Rested comfort accelerates HP regeneration", vit.get_hp_regen_rate() > 3.0)
	vit.set_rested(false)

	# -------------------------------------------------------------------------
	# 4. Physical Exertion, Stamina Depletion & Out of Breath Exhaustion
	# -------------------------------------------------------------------------
	vit.current_stamina = 50.0
	var jumped := vit.consume_stamina(20.0)
	assert_test.call("Jumping consumes 20 stamina", jumped and is_equal_approx(vit.current_stamina, 30.0))

	# Continuous sprint drain
	vit.drain_stamina_continuous(15.0, 2.0) # 30 stamina drained
	assert_test.call("Stamina completely drained to 0", vit.current_stamina == 0.0)
	assert_test.call("Exhaustion 'Out of Breath' state triggered", vit.is_exhausted)

	var sprint_rejected := vit.consume_stamina(10.0)
	assert_test.call("Exertion blocked while exhausted", not sprint_rejected)

	# Exhaustion recovery timer (2.0 seconds)
	vit.tick(1.0, false, false)
	assert_test.call("Still exhausted after 1.0s", vit.is_exhausted)
	vit.tick(1.1, false, false)
	assert_test.call("Exhaustion ends after full duration", not vit.is_exhausted)

	# -------------------------------------------------------------------------
	# 5. Damage, Cold Immunity & Non-Punitive Defeat
	# -------------------------------------------------------------------------
	vit.current_hp = 100.0
	var phys_dmg := vit.take_damage(30.0, &"physical")
	assert_test.call("Physical damage taken (30 HP)", phys_dmg == 30.0 and vit.current_hp == 70.0)

	# Cold damage test: Crab meal confers cold immunity
	var cold_dmg := vit.take_damage(40.0, &"cold")
	assert_test.call("Cold damage completely negated by crab meal cold immunity", cold_dmg == 0.0 and vit.current_hp == 70.0)

	# Lethal blow
	var fatal_dmg := vit.take_damage(100.0, &"physical")
	assert_test.call("Fatal damage taken", fatal_dmg == 70.0 and vit.current_hp == 0.0)
	assert_test.call("Player marked as defeated", vit.is_defeated)

	# Safe respawn ashore
	vit.revive(Vector3(10, 5, 10))
	assert_test.call("Player revived from defeat", not vit.is_defeated)
	assert_test.call("Player HP restored to baseline", vit.current_hp >= 25.0)

	# -------------------------------------------------------------------------
	# 6. Aquatic Stamina Drag & Drowning Mechanics
	# -------------------------------------------------------------------------
	vit.current_breath = 30.0
	vit.current_stamina = 50.0

	# Normal underwater breathing: 1.0 breath per sec
	vit.tick(5.0, true, false)
	assert_test.call("Normal underwater breath drains at 1.0/sec (25 remaining)", is_equal_approx(vit.current_breath, 25.0))

	# Underwater with zero stamina while exerting: burns oxygen 50% faster (1.5/sec)
	vit.current_stamina = 0.0
	vit.tick(10.0, true, true) # should drain 15 breath -> 10 remaining
	assert_test.call("Exhausted aquatic breath burns 50% faster (10 remaining)", is_equal_approx(vit.current_breath, 10.0))

	# Asphyxiation drowning damage
	vit.tick(10.0, true, true) # breath reaches 0
	assert_test.call("Breath fully depleted", vit.current_breath == 0.0)
	var hp_before_drown: float = vit.current_hp
	vit.tick(5.0, true, true) # drowning damage applies while out of air
	assert_test.call("Drowning inflicts continuous damage when out of air", vit.current_hp < hp_before_drown)

	# Surfacing to breathe
	vit.tick(2.0, false, false)
	assert_test.call("Surfacing rapidly catches breath", vit.current_breath > 20.0)

	# -------------------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------------------
	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		print("ALL VITALITY TRIAD TESTS PASSED!")
		quit(0)
	else:
		push_error("SOME TESTS FAILED!")
		quit(1)
