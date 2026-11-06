class_name ControllerManager
extends RefCounted
## Manages controller device detection, DualSense & Xbox button glyphs,
## full gamepad mapping, and haptic rumble / vibration feedback.

signal controller_type_changed(new_type: Type)
signal controller_connected(device_id: int, name: String, type: Type)
signal controller_disconnected(device_id: int)

enum Type {
	KEYBOARD_MOUSE,
	XBOX,
	DUALSENSE,
	GENERIC
}

var current_type: Type = Type.KEYBOARD_MOUSE
var active_device_id: int = 0
var rumble_enabled: bool = true
var rumble_intensity: float = 1.0
var dualsense: DualSenseManager


func _init() -> void:
	dualsense = DualSenseManager.get_instance()
	_check_initial_devices()
	if Input.has_signal("joy_connection_changed"):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _update_dualsense_state() -> void:
	if dualsense:
		dualsense.is_dualsense_active = (current_type == Type.DUALSENSE)
		if not dualsense.is_dualsense_active:
			dualsense.reset_triggers()


func _check_initial_devices() -> void:
	var joys := Input.get_connected_joypads()
	if not joys.is_empty():
		active_device_id = joys[0]
		var joy_name := Input.get_joy_name(active_device_id)
		current_type = detect_type_from_name(joy_name)
	_update_dualsense_state()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		active_device_id = device
		var joy_name := Input.get_joy_name(device)
		var detected := detect_type_from_name(joy_name)
		current_type = detected
		_update_dualsense_state()
		controller_connected.emit(device, joy_name, detected)
		controller_type_changed.emit(current_type)
	else:
		controller_disconnected.emit(device)
		var remaining := Input.get_connected_joypads()
		if remaining.is_empty():
			current_type = Type.KEYBOARD_MOUSE
			_update_dualsense_state()
			controller_type_changed.emit(current_type)
		else:
			active_device_id = remaining[0]
			current_type = detect_type_from_name(Input.get_joy_name(active_device_id))
			_update_dualsense_state()
			controller_type_changed.emit(current_type)


## Classifies controller device from name string (case-insensitive).
func detect_type_from_name(joy_name: String) -> Type:
	var lower := joy_name.to_lower()

	# DualSense (PS5) and DualShock (PS4) patterns
	if lower.contains("dualsense") or lower.contains("ps5") or lower.contains("playstation") \
			or lower.contains("ps4") or lower.contains("dualshock") or lower.contains("sony"):
		return Type.DUALSENSE

	# Xbox patterns (Xbox 360, Xbox One, Xbox Series, XInput, Microsoft)
	if lower.contains("xbox") or lower.contains("x-box") or lower.contains("xinput") or lower.contains("microsoft"):
		return Type.XBOX

	return Type.GENERIC


## Call from _unhandled_input / _input to detect dynamic input method switching.
func track_input_event(e: InputEvent) -> void:
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		# Filter motion deadzone jitter
		if e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) < 0.2:
			return
		if current_type == Type.KEYBOARD_MOUSE:
			active_device_id = e.device
			var joy_name := Input.get_joy_name(active_device_id)
			current_type = detect_type_from_name(joy_name)
			_update_dualsense_state()
			controller_type_changed.emit(current_type)
	elif e is InputEventKey or e is InputEventMouseButton:
		if current_type != Type.KEYBOARD_MOUSE:
			current_type = Type.KEYBOARD_MOUSE
			_update_dualsense_state()
			controller_type_changed.emit(current_type)


## Returns user-facing glyph/button name according to current device type.
func get_glyph(action: StringName) -> String:
	match current_type:
		Type.DUALSENSE:
			return _get_dualsense_glyph(action)
		Type.XBOX, Type.GENERIC:
			return _get_xbox_glyph(action)
		_:
			return _get_keyboard_glyph(action)


func _get_dualsense_glyph(action: StringName) -> String:
	match action:
		&"use": return "R2"
		&"alt_use": return "L2"
		&"jump": return "✕"
		&"interact": return "□"
		&"sprint": return "L3 / ○"
		&"pick": return "R3"
		&"rotate": return "△"
		&"cycle_tool_prev": return "L1"
		&"cycle_tool_next": return "R1"
		&"prev_item": return "D-Pad Left"
		&"next_item": return "D-Pad Right"
		&"brush_up": return "D-Pad Up"
		&"brush_down": return "D-Pad Down"
		&"snap": return "Touchpad / Select"
		&"menu_toggle": return "Options"
		&"swap_shoulder": return "R3"
		_: return String(action)


func _get_xbox_glyph(action: StringName) -> String:
	match action:
		&"use": return "RT"
		&"alt_use": return "LT"
		&"jump": return "A"
		&"interact": return "X"
		&"sprint": return "LS / B"
		&"pick": return "RS"
		&"rotate": return "Y"
		&"cycle_tool_prev": return "LB"
		&"cycle_tool_next": return "RB"
		&"prev_item": return "D-Pad Left"
		&"next_item": return "D-Pad Right"
		&"brush_up": return "D-Pad Up"
		&"brush_down": return "D-Pad Down"
		&"snap": return "View / Back"
		&"menu_toggle": return "Menu"
		&"swap_shoulder": return "RS"
		_: return String(action)


func _get_keyboard_glyph(action: StringName) -> String:
	match action:
		&"use": return "LMB"
		&"alt_use": return "RMB"
		&"jump": return "Space"
		&"interact": return "F"
		&"sprint": return "Shift"
		&"pick": return "MMB"
		&"rotate": return "R"
		&"cycle_tool_prev": return "1-5"
		&"cycle_tool_next": return "1-5"
		&"prev_item": return "Q"
		&"next_item": return "E"
		&"brush_up": return "X"
		&"brush_down": return "Z"
		&"snap": return "G"
		&"menu_toggle": return "Esc"
		&"swap_shoulder": return "V"
		_: return String(action)


## Translates prompt strings containing keyboard keys into gamepad buttons if a controller is active.
func format_prompt_for_active_device(text: String) -> String:
	if current_type == Type.KEYBOARD_MOUSE:
		return text

	var res := text
	var interact_btn := get_glyph(&"interact")
	var sprint_btn := "L3" if current_type == Type.DUALSENSE else "LS"
	var use_btn := get_glyph(&"use")
	var alt_btn := get_glyph(&"alt_use")

	res = res.replace("F  Step off", "%s  Step off" % interact_btn)
	res = res.replace("F  Board rowboat", "%s  Board rowboat" % interact_btn)
	res = res.replace("F  Ride along", "%s  Ride along" % interact_btn)
	res = res.replace("W/S  row", "L-Stick  row")
	res = res.replace("A/D  turn", "L-Stick  turn")
	res = res.replace("Shift  pull hard", "%s  pull hard" % sprint_btn)
	res = res.replace("[LMB]", "[%s]" % use_btn)
	res = res.replace("LMB", use_btn)
	res = res.replace("[RMB]", "[%s]" % alt_btn)
	res = res.replace("RMB", alt_btn)
	return res


# -------------------------------------------------------------------------
# Rumble / Haptic Feedback
# -------------------------------------------------------------------------

func vibrate(weak: float, strong: float, duration: float) -> void:
	if not rumble_enabled or current_type == Type.KEYBOARD_MOUSE:
		return
	var w := clampf(weak * rumble_intensity, 0.0, 1.0)
	var s := clampf(strong * rumble_intensity, 0.0, 1.0)
	Input.start_joy_vibration(active_device_id, w, s, duration)


func stop_vibration() -> void:
	Input.stop_joy_vibration(active_device_id)


func pulse_dig() -> void:
	vibrate(0.18, 0.42, 0.09)


func pulse_place() -> void:
	vibrate(0.25, 0.0, 0.06)


func pulse_nibble() -> void:
	vibrate(0.35, 0.05, 0.12)


func pulse_bite() -> void:
	vibrate(0.65, 0.85, 0.28)


func pulse_tension_warning() -> void:
	vibrate(0.7, 0.3, 0.1)


func pulse_catch() -> void:
	vibrate(0.5, 0.7, 0.35)


func pulse_row() -> void:
	vibrate(0.22, 0.15, 0.18)


# -------------------------------------------------------------------------
# DualSense Adaptive Trigger Hooks
# -------------------------------------------------------------------------

func apply_fishing_cast(power: float) -> void:
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_fishing_cast(power)


func apply_fishing_bite() -> void:
	pulse_bite()
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_fishing_bite()


func apply_fishing_reeling(tension: float, thrashing: bool) -> void:
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_fishing_reeling(tension, thrashing)


func apply_farming_till() -> void:
	pulse_place()
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_farming_till()


func apply_farming_sow() -> void:
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_farming_sow()


func apply_mining(mat: int) -> void:
	pulse_dig()
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_mining(mat)


func apply_rowing(power: float, phase: float) -> void:
	if current_type == Type.DUALSENSE and dualsense != null:
		dualsense.apply_rowing(power, phase)


func reset_triggers() -> void:
	if dualsense != null:
		dualsense.reset_triggers()


# -------------------------------------------------------------------------
# InputMap Registration
# -------------------------------------------------------------------------

func setup_input_map() -> void:
	# 1. Keyboard bindings
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"interact": [KEY_F],
		"tool_1": [KEY_1], "tool_2": [KEY_2], "tool_3": [KEY_3],
		"tool_4": [KEY_4], "tool_5": [KEY_5],
		"prev_item": [KEY_Q], "next_item": [KEY_E],
		"brush_down": [KEY_Z], "brush_up": [KEY_X],
		"rotate": [KEY_R], "snap": [KEY_G],
		"fast_time": [KEY_T], "swap_shoulder": [KEY_V],
		"menu_toggle": [KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)

	# 2. Mouse buttons
	var mouse := [
		["use", MOUSE_BUTTON_LEFT],
		["alt_use", MOUSE_BUTTON_RIGHT],
		["pick", MOUSE_BUTTON_MIDDLE]
	]
	for pair in mouse:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)

	# 3. Joypad Buttons (Cross-compatible DualSense & Xbox)
	var joy_buttons := {
		"jump": [JOY_BUTTON_A],                      # Xbox: A, DualSense: Cross
		"interact": [JOY_BUTTON_X],                  # Xbox: X, DualSense: Square
		"sprint": [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_B], # L3 or B/Circle
		"pick": [JOY_BUTTON_RIGHT_STICK],            # R3
		"rotate": [JOY_BUTTON_Y],                    # Xbox: Y, DualSense: Triangle
		"cycle_tool_prev": [JOY_BUTTON_LEFT_SHOULDER], # LB / L1
		"cycle_tool_next": [JOY_BUTTON_RIGHT_SHOULDER], # RB / R1
		"brush_up": [JOY_BUTTON_DPAD_UP],            # D-Pad Up
		"brush_down": [JOY_BUTTON_DPAD_DOWN],        # D-Pad Down
		"prev_item": [JOY_BUTTON_DPAD_LEFT],         # D-Pad Left
		"next_item": [JOY_BUTTON_DPAD_RIGHT],        # D-Pad Right
		"snap": [JOY_BUTTON_BACK],                   # View / Touchpad / Select
		"menu_toggle": [JOY_BUTTON_START],           # Menu / Options
	}
	for action in joy_buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in joy_buttons[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)

	# 4. Joypad Motions (Analog Sticks & Triggers)
	var joy_motions := [
		# Movement (Left Stick)
		["move_left", JOY_AXIS_LEFT_X, -1.0],
		["move_right", JOY_AXIS_LEFT_X, 1.0],
		["move_forward", JOY_AXIS_LEFT_Y, -1.0],
		["move_back", JOY_AXIS_LEFT_Y, 1.0],
		# Camera Look (Right Stick)
		["look_left", JOY_AXIS_RIGHT_X, -1.0],
		["look_right", JOY_AXIS_RIGHT_X, 1.0],
		["look_up", JOY_AXIS_RIGHT_Y, -1.0],
		["look_down", JOY_AXIS_RIGHT_Y, 1.0],
		# Triggers (Analog LT/RT or L2/R2)
		["use", JOY_AXIS_TRIGGER_RIGHT, 1.0],
		["alt_use", JOY_AXIS_TRIGGER_LEFT, 1.0],
	]
	for m in joy_motions:
		var act: String = m[0]
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		var ev := InputEventJoypadMotion.new()
		ev.axis = m[1]
		ev.axis_value = m[2]
		InputMap.action_add_event(act, ev)
