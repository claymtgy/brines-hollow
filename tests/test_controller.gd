extends SceneTree
## Test suite for ControllerManager and Joypad input mappings.

func _init() -> void:
	print("==================================================")
	print("Running Brine's Hollow Controller Tests...")
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

	var ctrl := ControllerManager.new()

	# 1. Device Type Identification tests
	assert_true.call(ctrl.detect_type_from_name("DualSense Wireless Controller") == ControllerManager.Type.DUALSENSE,
		"PS5 DualSense detected as DUALSENSE")
	assert_true.call(ctrl.detect_type_from_name("Sony Interactive Entertainment DualSense Edge") == ControllerManager.Type.DUALSENSE,
		"DualSense Edge detected as DUALSENSE")
	assert_true.call(ctrl.detect_type_from_name("PS4 Controller") == ControllerManager.Type.DUALSENSE,
		"PS4 DualShock detected as DUALSENSE (PlayStation family)")
	assert_true.call(ctrl.detect_type_from_name("Xbox Series X Controller") == ControllerManager.Type.XBOX,
		"Xbox Series X detected as XBOX")
	assert_true.call(ctrl.detect_type_from_name("Xbox 360 Controller") == ControllerManager.Type.XBOX,
		"Xbox 360 detected as XBOX")
	assert_true.call(ctrl.detect_type_from_name("XInput Gamepad") == ControllerManager.Type.XBOX,
		"XInput Gamepad detected as XBOX")
	assert_true.call(ctrl.detect_type_from_name("Generic USB Joystick") == ControllerManager.Type.GENERIC,
		"Generic USB Joystick detected as GENERIC")

	# 2. Button Glyph / Label formatting tests
	ctrl.current_type = ControllerManager.Type.XBOX
	assert_true.call(ctrl.get_glyph("use") == "RT", "Xbox use button is RT")
	assert_true.call(ctrl.get_glyph("alt_use") == "LT", "Xbox alt_use button is LT")
	assert_true.call(ctrl.get_glyph("jump") == "A", "Xbox jump button is A")
	assert_true.call(ctrl.get_glyph("interact") == "X", "Xbox interact button is X")
	assert_true.call(ctrl.get_glyph("rotate") == "Y", "Xbox rotate button is Y")
	assert_true.call(ctrl.get_glyph("cycle_tool_next") == "RB", "Xbox cycle tool next is RB")
	assert_true.call(ctrl.get_glyph("cycle_tool_prev") == "LB", "Xbox cycle tool prev is LB")

	ctrl.current_type = ControllerManager.Type.DUALSENSE
	assert_true.call(ctrl.get_glyph("use") == "R2", "DualSense use button is R2")
	assert_true.call(ctrl.get_glyph("alt_use") == "L2", "DualSense alt_use button is L2")
	assert_true.call(ctrl.get_glyph("jump") == "✕", "DualSense jump button is ✕ (Cross)")
	assert_true.call(ctrl.get_glyph("interact") == "□", "DualSense interact button is □ (Square)")
	assert_true.call(ctrl.get_glyph("rotate") == "△", "DualSense rotate button is △ (Triangle)")
	assert_true.call(ctrl.get_glyph("cycle_tool_next") == "R1", "DualSense cycle tool next is R1")
	assert_true.call(ctrl.get_glyph("cycle_tool_prev") == "L1", "DualSense cycle tool prev is L1")

	# 3. Dynamic formatting of context prompt strings
	ctrl.current_type = ControllerManager.Type.DUALSENSE
	var prompt_ds := ctrl.format_prompt_for_active_device("F  Board rowboat")
	assert_true.call(prompt_ds == "□  Board rowboat", "DualSense replaces 'F' with '□' in prompt")

	ctrl.current_type = ControllerManager.Type.XBOX
	var prompt_xb := ctrl.format_prompt_for_active_device("F  Board rowboat")
	assert_true.call(prompt_xb == "X  Board rowboat", "Xbox replaces 'F' with 'X' in prompt")

	# 4. Input map setup test
	ctrl.setup_input_map()
	assert_true.call(InputMap.has_action("look_right"), "InputMap has look_right")
	assert_true.call(InputMap.has_action("look_up"), "InputMap has look_up")
	assert_true.call(InputMap.has_action("cycle_tool_next"), "InputMap has cycle_tool_next")
	assert_true.call(InputMap.has_action("cycle_tool_prev"), "InputMap has cycle_tool_prev")

	print("==================================================")
	print("Summary: %d / %d tests passed!" % [stats[0], stats[1]])
	print("==================================================")
	if stats[0] == stats[1]:
		quit(0)
	else:
		quit(1)
