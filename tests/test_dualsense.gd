extends SceneTree
## Test suite for GodotDualSense plugin and Adaptive Trigger state engine.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow DualSense & Adaptive Trigger Tests...")
	print("==================================================")
	var stats := [0, 0] # [passed, total]

	var assert_true := func(cond: bool, msg: String) -> void:
		stats[1] += 1
		if cond:
			stats[0] += 1
			print("  [PASS] %s" % msg)
		else:
			push_error("  [FAIL] %s" % msg)
			print("  [FAIL] %s" % msg)

	var ds := DualSenseManager.new()

	# 1. Base Trigger Mode & Clamping Tests
	var trig := DualSenseTrigger.new()
	assert_true.call(trig.mode == DualSenseConstants.TriggerMode.OFF, "Default trigger mode is OFF")

	trig.set_resistance(2, 6)
	assert_true.call(trig.mode == DualSenseConstants.TriggerMode.FEEDBACK, "Resistance sets FEEDBACK mode")
	assert_true.call(trig.params[0] == 2 and trig.params[1] == 6, "Resistance params: start_pos=2, force=6")

	# Clamping test: force > 8 clamped to 8
	trig.set_resistance(15, 99)
	assert_true.call(trig.params[0] == 9 and trig.params[1] == 8, "Resistance values clamped to max (pos=9, force=8)")

	# Weapon Mode Test
	trig.set_weapon(2, 6, 7)
	assert_true.call(trig.mode == DualSenseConstants.TriggerMode.WEAPON, "Weapon mode sets WEAPON enum")
	assert_true.call(trig.params[0] == 2 and trig.params[1] == 6 and trig.params[2] == 7, "Weapon params correctly stored")

	# Bow Mode Test
	trig.set_bow(1, 7, 2, 8)
	assert_true.call(trig.mode == DualSenseConstants.TriggerMode.BOW, "Bow mode sets BOW enum")
	assert_true.call(trig.params[0] == 1 and trig.params[1] == 7 and trig.params[2] == 2 and trig.params[3] == 8, "Bow curve params stored")

	# Vibration Mode Test
	trig.set_vibration(3, 7, 25)
	assert_true.call(trig.mode == DualSenseConstants.TriggerMode.MACHINE, "Vibration sets MACHINE enum")
	assert_true.call(trig.params[0] == 3 and trig.params[1] == 7 and trig.params[2] == 25, "Vibration params: amp=7, freq=25")

	# 2. Byte Serialization (11 bytes per trigger)
	var raw_bytes := trig.to_bytes()
	assert_true.call(raw_bytes.size() == 11, "Trigger byte block is exactly 11 bytes")
	assert_true.call(raw_bytes[0] == DualSenseConstants.TriggerMode.MACHINE, "Byte 0 matches trigger mode")
	assert_true.call(raw_bytes[1] == 3 and raw_bytes[2] == 7 and raw_bytes[3] == 25, "Bytes 1-3 match vibration parameters")

	# 3. DualSense USB Report Packet Assembly (63 bytes)
	ds.left_trigger.set_resistance(1, 4)
	ds.right_trigger.set_weapon(2, 5, 8)
	ds.set_lightbar(Color(0.2, 0.6, 1.0))
	var usb_rep := ds._build_usb_report()

	assert_true.call(usb_rep.size() == 63, "USB HID report is exactly 63 bytes")
	assert_true.call(usb_rep[0] == DualSenseConstants.USB_REPORT_ID, "Report ID is 0x02")
	assert_true.call(usb_rep[1] == (0x01 | 0x02), "Valid flag 0 enables rumble + haptics")
	assert_true.call(usb_rep[2] == (0x04 | 0x08), "Valid flag 1 enables R2 and L2 trigger effects")
	assert_true.call(usb_rep[14] == DualSenseConstants.TriggerMode.WEAPON, "R2 block at byte 14 matches Right Trigger mode")
	assert_true.call(usb_rep[25] == DualSenseConstants.TriggerMode.FEEDBACK, "L2 block at byte 25 matches Left Trigger mode")
	assert_true.call(usb_rep[45] == 51 and usb_rep[46] == 153 and usb_rep[47] == 255, "Lightbar RGB bytes set correctly")

	# 4. Contextual Gameplay Presets Tests
	# A. Fishing Cast Tension Curve
	ds.apply_fishing_cast(0.25)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.BOW, "Cast sets bow curve")
	var cast_early_str := ds.right_trigger.params[3]

	ds.apply_fishing_cast(0.95)
	var cast_late_str := ds.right_trigger.params[3]
	assert_true.call(cast_late_str > cast_early_str, "Charging cast power increases trigger end tension")

	# B. Fishing Bite Telegraph
	ds.apply_fishing_bite()
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.WEAPON, "Fishing bite sets weapon break")
	assert_true.call(ds.right_trigger.params[2] == 8, "Bite trigger force is maximum (8)")

	# C. Fishing Reeling Mechanics
	# Calm reeling: smooth resistance
	ds.apply_fishing_reeling(0.4, false)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.FEEDBACK, "Calm reeling uses smooth feedback resistance")

	# Thrashing fish: vibrating trigger buck
	ds.apply_fishing_reeling(0.6, true)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.MACHINE, "Thrashing fish triggers vibration mode")

	# High tension snap warning (> 0.82): hard stop
	ds.apply_fishing_reeling(0.88, false)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.FEEDBACK and ds.right_trigger.params[1] == 8,
		"Dangerous line tension triggers hard resistance stop")

	# D. Agriculture Presets
	ds.apply_farming_till()
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.WEAPON, "Tilling soil sets crisp weapon break")

	ds.apply_farming_sow()
	assert_true.call(ds.left_trigger.mode == DualSenseConstants.TriggerMode.FEEDBACK, "Sowing seeds sets soft L2 resistance")

	# E. Mining Presets
	ds.apply_mining(Palette.STONE)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.WEAPON, "Mining limestone sets mineral weapon snap")

	ds.apply_mining(Palette.SAND)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.OFF, "Digging sand resets trigger resistance")

	# F. Maritime Rowing Hydrodynamic Drag
	# Water stroke (phase at peak power)
	ds.apply_rowing(1.0, PI * 0.5)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.FEEDBACK and ds.left_trigger.mode == DualSenseConstants.TriggerMode.FEEDBACK,
		"Rowing stroke applies hydraulic resistance to both L2 and R2")

	# Air recovery stroke (phase at negative sine)
	ds.apply_rowing(1.0, -PI * 0.5)
	assert_true.call(ds.right_trigger.mode == DualSenseConstants.TriggerMode.OFF and ds.left_trigger.mode == DualSenseConstants.TriggerMode.OFF,
		"Oar recovery resets triggers to zero drag")

	# Reset All
	ds.reset_triggers()
	assert_true.call(ds.left_trigger.mode == DualSenseConstants.TriggerMode.OFF and ds.right_trigger.mode == DualSenseConstants.TriggerMode.OFF,
		"reset_triggers() clears both triggers to normal")

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")
	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
