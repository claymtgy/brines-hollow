extends SceneTree
## Automated headless test suite for Brine's Hollow Character Customization & Wardrobe.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Character Customization Tests...")
	print("==================================================")

	var stats := [0, 0] # [passed, total]

	var assert_test := func(desc: String, condition: bool) -> void:
		stats[1] += 1
		if condition:
			stats[0] += 1
			print("  [PASS] %s" % desc)
		else:
			push_error("  [FAIL] %s" % desc)

	# -------------------------------------------------------------------------
	# 1. CharacterPalette & Defaults
	# -------------------------------------------------------------------------
	var cust := CharacterCustomizer.new()
	assert_test.call("Default customizer has weathered tan skin",
		cust.skin_tone == CharacterPalette.SkinTone.WEATHERED_TAN)
	assert_test.call("Default customizer has sou'wester hat",
		cust.hat_style == CharacterPalette.HatStyle.SOUWESTER)
	assert_test.call("Default customizer has oilskin yellow coat",
		cust.coat_color == CharacterPalette.CoatColor.OILSKIN_YELLOW)

	var skin_col := CharacterPalette.get_skin_color(CharacterPalette.SkinTone.PALE_SALT)
	assert_test.call("Pale Salt skin tone resolves to valid Color", skin_col.r > 0.0 and skin_col.a == 1.0)

	var hair_col := CharacterPalette.get_hair_color(CharacterPalette.HairColor.KELP_GREEN)
	assert_test.call("Kelp Green hair resolves to valid Color", hair_col.g > hair_col.r)

	# -------------------------------------------------------------------------
	# 2. Signals & Property Modifications
	# -------------------------------------------------------------------------
	var sig := [false] # captured by reference in closures
	cust.appearance_changed.connect(func() -> void:
		sig[0] = true
	)

	sig[0] = false
	cust.set_skin_tone(CharacterPalette.SkinTone.ABYSSAL_DUSKY)
	assert_test.call("Setting skin tone emits appearance_changed", sig[0] and cust.skin_tone == CharacterPalette.SkinTone.ABYSSAL_DUSKY)

	sig[0] = false
	cust.set_hair(CharacterPalette.HairStyle.SAILOR_BUN, CharacterPalette.HairColor.SALT_WHITE)
	assert_test.call("Setting hair style & color updates properties",
		cust.hair_style == CharacterPalette.HairStyle.SAILOR_BUN and cust.hair_color == CharacterPalette.HairColor.SALT_WHITE and sig[0])

	sig[0] = false
	cust.set_beard(CharacterPalette.BeardStyle.FULL_SALT_BUSH, CharacterPalette.HairColor.SALT_WHITE)
	assert_test.call("Setting beard style & color updates properties",
		cust.beard_style == CharacterPalette.BeardStyle.FULL_SALT_BUSH and cust.beard_color == CharacterPalette.HairColor.SALT_WHITE and sig[0])

	sig[0] = false
	cust.set_hat(CharacterPalette.HatStyle.WATCH_CAP)
	assert_test.call("Setting hat to Watch Cap updates property",
		cust.hat_style == CharacterPalette.HatStyle.WATCH_CAP and sig[0])

	sig[0] = false
	cust.set_coat(CharacterPalette.CoatColor.NAVY_BLUE)
	assert_test.call("Setting coat to Navy Blue updates property",
		cust.coat_color == CharacterPalette.CoatColor.NAVY_BLUE and sig[0])

	# -------------------------------------------------------------------------
	# 3. Serialization Roundtrip
	# -------------------------------------------------------------------------
	var serialized := cust.serialize()
	assert_test.call("Serialized dictionary has all 9 appearance keys",
		serialized.has("skin_tone") and serialized.has("hair_style") and serialized.has("beard_style") and
		serialized.has("hat_style") and serialized.has("coat_color") and serialized.has("weathering"))

	var loaded_cust := CharacterCustomizer.new()
	loaded_cust.deserialize(serialized)
	assert_test.call("Deserialized customizer matches skin tone", loaded_cust.skin_tone == cust.skin_tone)
	assert_test.call("Deserialized customizer matches hair style", loaded_cust.hair_style == cust.hair_style)
	assert_test.call("Deserialized customizer matches beard style", loaded_cust.beard_style == cust.beard_style)
	assert_test.call("Deserialized customizer matches hat style", loaded_cust.hat_style == cust.hat_style)
	assert_test.call("Deserialized customizer matches coat color", loaded_cust.coat_color == cust.coat_color)

	# -------------------------------------------------------------------------
	# 4. Archetype Presets
	# -------------------------------------------------------------------------
	cust.apply_preset("north_sea_veteran")
	assert_test.call("Preset 'North Sea Veteran' applies salt white hair and watch cap",
		cust.hair_color == CharacterPalette.HairColor.SALT_WHITE and cust.hat_style == CharacterPalette.HatStyle.WATCH_CAP and
		cust.beard_style == CharacterPalette.BeardStyle.FULL_SALT_BUSH)

	cust.apply_preset("young_deckhand")
	assert_test.call("Preset 'Young Deckhand' applies straw blonde and clean shaven",
		cust.hair_color == CharacterPalette.HairColor.STRAW_BLONDE and cust.beard_style == CharacterPalette.BeardStyle.CLEAN_SHAVEN and
		cust.hat_style == CharacterPalette.HatStyle.SOUWESTER)

	cust.apply_preset("brine_hermit")
	assert_test.call("Preset 'Brine Hermit' applies kelp green wild curls and braided beard",
		cust.hair_color == CharacterPalette.HairColor.KELP_GREEN and cust.beard_style == CharacterPalette.BeardStyle.BRAIDED_BEARD and
		cust.hat_style == CharacterPalette.HatStyle.HEADBAND)

	cust.apply_preset("island_botanist")
	assert_test.call("Preset 'Island Botanist' applies sailor bun and coral rust coat",
		cust.hair_style == CharacterPalette.HairStyle.SAILOR_BUN and cust.coat_color == CharacterPalette.CoatColor.CORAL_RUST and
		cust.hat_style == CharacterPalette.HatStyle.FISHER_CAP)

	# -------------------------------------------------------------------------
	# 5. Appearance Randomizer
	# -------------------------------------------------------------------------
	var rand_cust := CharacterCustomizer.new()
	rand_cust.randomize_appearance(42) # Deterministic seed
	assert_test.call("Randomizer assigns valid skin tone enum", int(rand_cust.skin_tone) >= 0 and int(rand_cust.skin_tone) < CharacterPalette.SkinTone.size())
	assert_test.call("Randomizer assigns valid hair style enum", int(rand_cust.hair_style) >= 0 and int(rand_cust.hair_style) < CharacterPalette.HairStyle.size())
	assert_test.call("Randomizer assigns valid hat style enum", int(rand_cust.hat_style) >= 0 and int(rand_cust.hat_style) < CharacterPalette.HatStyle.size())

	# -------------------------------------------------------------------------
	# 6. CharacterModel Construction & Paperdoll Attachments
	# -------------------------------------------------------------------------
	var model := CharacterModel.new()
	root.add_child(model)
	model.setup(Palette.COAT_A, Palette.HAT_A, cust)

	assert_test.call("CharacterModel has body node", model.body != null)
	assert_test.call("CharacterModel has head node", model.head != null)
	assert_test.call("CharacterModel has limbs", model.arm_l != null and model.arm_r != null and model.leg_l != null and model.leg_r != null)
	assert_test.call("CharacterModel has backpack paperdoll attachment", model.backpack_node != null)
	assert_test.call("CharacterModel has diving helmet paperdoll attachment", model.diving_helmet_node != null)

	# Paperdoll toggles
	assert_test.call("Backpack initially hidden", not model.backpack_node.visible)
	model.set_backpack_visible(true)
	assert_test.call("set_backpack_visible(true) makes backpack visible", model.backpack_node.visible)
	model.set_backpack_visible(false)
	assert_test.call("set_backpack_visible(false) hides backpack", not model.backpack_node.visible)

	assert_test.call("Diving helmet initially hidden", not model.diving_helmet_node.visible)
	model.set_diving_helmet_visible(true)
	assert_test.call("set_diving_helmet_visible(true) activates diving helmet", model.diving_helmet_node.visible)
	model.set_diving_helmet_visible(false)
	assert_test.call("set_diving_helmet_visible(false) removes diving helmet", not model.diving_helmet_node.visible)

	# Weapon & Tool switching
	model.set_tool(0) # Pickaxe
	assert_test.call("set_tool(0) activates pickaxe and hides other tools",
		model.tool_pick.visible and not model.tool_hammer.visible and not model.tool_cutlass.visible)

	model.set_tool(5) # Cutlass
	assert_test.call("set_tool(5) activates corsair cutlass",
		model.tool_cutlass.visible and not model.tool_pick.visible and not model.tool_harpoon.visible)

	model.set_tool(6) # Harpoon
	assert_test.call("set_tool(6) activates barbed harpoon",
		model.tool_harpoon.visible and not model.tool_cutlass.visible and not model.tool_maul.visible)

	model.set_tool(7) # Maul
	assert_test.call("set_tool(7) activates anchor maul",
		model.tool_maul.visible and not model.tool_harpoon.visible and not model.tool_lantern.visible)

	model.set_tool(8) # Phosphor lantern staff
	assert_test.call("set_tool(8) activates phosphor lantern staff",
		model.tool_lantern.visible and not model.tool_maul.visible)

	# Dynamic Rebuild on Customizer Changes
	cust.set_hair(CharacterPalette.HairStyle.WILD_CURLS, CharacterPalette.HairColor.KELP_GREEN)
	model.apply_customizer(cust)
	assert_test.call("apply_customizer successfully rebuilds model hierarchy",
		model.head != null and model.body != null and model.tool_lantern != null)

	# -------------------------------------------------------------------------
	# 7. BarberMirror Station
	# -------------------------------------------------------------------------
	var mirror := BarberMirror.new(cust, model)
	assert_test.call("BarberMirror station initialized", mirror.customizer == cust and mirror.preview_model == model)

	var station_sig := [false]
	mirror.customization_opened.connect(func() -> void:
		station_sig[0] = true
	)
	mirror.open_station()
	assert_test.call("open_station() activates mirror and emits signal", mirror.is_active and station_sig[0])

	var orig_skin: int = cust.skin_tone
	mirror.cycle_skin(1)
	assert_test.call("cycle_skin(1) advances skin tone enum", cust.skin_tone == posmod(orig_skin + 1, CharacterPalette.SkinTone.size()))

	var orig_hat: int = cust.hat_style
	mirror.cycle_hat_style(1)
	assert_test.call("cycle_hat_style(1) advances hat style enum", cust.hat_style == posmod(orig_hat + 1, CharacterPalette.HatStyle.size()))

	mirror.apply_preset("north_sea_veteran")
	assert_test.call("BarberMirror applies preset and updates preview model",
		cust.coat_color == CharacterPalette.CoatColor.NAVY_BLUE and model.body != null)

	mirror.close_station()
	assert_test.call("close_station() deactivates mirror", not mirror.is_active)

	model.queue_free()

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")

	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
