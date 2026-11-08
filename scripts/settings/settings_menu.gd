class_name SettingsMenu
extends CanvasLayer
## Esc / Start: pause panel (Resume, Settings, Save & Quit) and the settings screen.
## Co-op never pauses the world; the menu just frees the mouse and blocks player input.

var main: Node
var settings: GameSettings

var _root: Control
var _pause: Control
var _settings_panel: Control
var _preset_opt: OptionButton
var _rebind_action := ""
var _rebind_button: Button
var _key_buttons := {}
var _building := false

const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["jump", "Jump / swim up"], ["sprint", "Sprint / pull hard"],
	["interact", "Interact / board"], ["inventory_toggle", "Inventory"], ["build_menu_toggle", "Build menu (hammer)"],
	["tool_1", "Hotbar 1"], ["tool_2", "Hotbar 2"], ["tool_3", "Hotbar 3"], ["tool_4", "Hotbar 4"],
	["tool_5", "Hotbar 5"], ["tool_6", "Hotbar 6"], ["tool_7", "Hotbar 7"], ["tool_8", "Hotbar 8"],
	["prev_item", "Previous item"], ["next_item", "Next item"],
	["brush_down", "Brush smaller"], ["brush_up", "Brush bigger"], ["rotate", "Rotate prefab"],
	["snap", "Grid snap"], ["swap_shoulder", "Swap shoulder"], ["toggle_first_person", "First-person toggle"], ["fast_time", "Fast-forward time"],
]


func is_open() -> bool:
	return _root != null and _root.visible


func setup(p_main: Node, p_settings: GameSettings) -> void:
	main = p_main
	settings = p_settings
	layer = 20
	_build()
	_root.visible = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			_menu_shots(a.trim_prefix("--menushot="))


## Dev: screenshots of the pause panel and each settings tab, then quit.
func _menu_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	while main.player == null or not main.world.ready_for_play:
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	# Foliage fade: turn the camera until leaves sit between it and the player.
	var rig: CameraRig = main.rig
	var pivot: Vector3 = main.player.position + Vector3(0, 1.55, 0)
	var found := false
	for k in 72:
		var yaw := k * TAU / 72.0
		var back := Basis.from_euler(Vector3(rig.pitch, yaw, 0)).z
		var hit: Dictionary = main.world.raycast(pivot, back, rig.dist)
		if not hit.is_empty() and Palette.is_foliage(main.world.get_voxel(hit.cell.x, hit.cell.y, hit.cell.z)):
			rig.yaw = yaw
			found = true
			break
	print("[menushot] leaves between camera and player: ", found)
	if found:
		for i in 4:
			await get_tree().process_frame
		await _grab(dir + "/fade_on.png")
		rig.foliage_fade = false
		for i in 3:
			await get_tree().process_frame
		await _grab(dir + "/fade_off.png")
		rig.foliage_fade = true
	open()
	var names := ["pause"]
	for i in 3:
		await get_tree().process_frame
	await _grab(dir + "/menu_pause.png")
	_pause.visible = false
	_settings_panel.visible = true
	var tabs: TabContainer = _settings_panel.get_child(0).get_child(0)
	for t in tabs.get_tab_count():
		tabs.current_tab = t
		for i in 3:
			await get_tree().process_frame
		await _grab(dir + "/menu_tab_%d.png" % t)
	get_tree().quit()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	_root.visible = true
	_pause.visible = true
	_settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if main.player != null:
		main.player.input_enabled = false


## Straight to the settings screen (main menu "Settings" button).
func open_settings() -> void:
	open()
	_pause.visible = false
	_settings_panel.visible = true


func close() -> void:
	_cancel_rebind()
	_root.visible = false
	if main.player != null:
		main.player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if _rebind_action == "" or not (e is InputEventKey) or not e.pressed:
		return
	get_viewport().set_input_as_handled()
	if e.physical_keycode == KEY_ESCAPE:
		_cancel_rebind()
		return
	settings.key_overrides[_rebind_action] = int(e.physical_keycode)
	settings.apply_keys()
	settings.save()
	_rebind_action = ""
	_refresh_keys()


# ---------------------------------------------------------------- UI

func _build() -> void:
	_building = true
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.09, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	# --- pause panel
	_pause = PanelContainer.new()
	center.add_child(_pause)
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(320, 0)
	pv.add_theme_constant_override("separation", 10)
	_pause.add_child(pv)
	var title := Label.new()
	title.text = "Brine's Hollow"
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(title)
	_button(pv, "Resume", close)
	_button(pv, "Settings", func() -> void:
		_pause.visible = false
		_settings_panel.visible = true)
	_button(pv, "Quit to Menu", _quit_to_menu)
	_button(pv, "Exit to Desktop", _save_and_quit)

	# --- settings panel
	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(_settings_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	_settings_panel.add_child(sv)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(tabs)
	_build_controls(_tab(tabs, "Controls"))
	_build_graphics(_tab(tabs, "Graphics"))
	_build_interface(_tab(tabs, "Interface"))
	_build_keys(_tab(tabs, "Keys"))
	_build_audio(_tab(tabs, "Audio"))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	sv.add_child(bottom)
	_button(bottom, "Back", func() -> void:
		_cancel_rebind()
		_settings_panel.visible = false
		if main == null or main.player == null:
			_root.visible = false
		else:
			_pause.visible = true)
	_building = false


func _tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	return v


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(260, 0)
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, label: String, field: String, lo: float, hi: float, step: float, fmt: String, graphics := false) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = settings.get(field)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(260, 0)
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	var show := func(x: float) -> String:
		return "Auto" if field == "render_scale" and x <= 0.0 else fmt % x
	v.text = show.call(s.value)
	s.value_changed.connect(func(x: float) -> void:
		v.text = show.call(x)
		settings.set(field, int(x) if typeof(settings.get(field)) == TYPE_INT else x)
		_changed(graphics))
	h.add_child(s)
	h.add_child(v)


func _check(parent: Control, label: String, field: String, graphics := false) -> void:
	var h := _row(parent, label)
	var c := CheckBox.new()
	c.button_pressed = settings.get(field)
	c.toggled.connect(func(on: bool) -> void:
		settings.set(field, on)
		_changed(graphics))
	h.add_child(c)


func _option(parent: Control, label: String, field: String, names: Array, graphics := false) -> OptionButton:
	var h := _row(parent, label)
	var o := OptionButton.new()
	for n: String in names:
		o.add_item(n)
	o.selected = int(settings.get(field))
	o.item_selected.connect(func(i: int) -> void:
		settings.set(field, i)
		_changed(graphics))
	h.add_child(o)
	return o


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


func _build_controls(v: VBoxContainer) -> void:
	_header(v, "Camera")
	_check(v, "First-person camera (F5 / P toggles)", "first_person")
	_slider(v, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2fx")
	_check(v, "Invert vertical look", "invert_y")
	_slider(v, "Controller look speed", "controller_look_speed", 1.0, 5.0, 0.1, "%.1f")
	_slider(v, "Field of view", "fov", 55.0, 90.0, 1.0, "%d°")
	_slider(v, "Camera distance", "camera_distance", 2.0, 12.0, 0.25, "%.1f m")
	_slider(v, "Camera side offset", "camera_side_offset", 0.0, 2.0, 0.05, "%.2f m")
	_check(v, "Right shoulder (V swaps)", "shoulder_right")
	_check(v, "Fade leaves in front of you", "foliage_fade")


func _build_graphics(v: VBoxContainer) -> void:
	_header(v, "Quality")
	_preset_opt = _option(v, "Preset", "preset", GameSettings.PRESET_NAMES)
	_preset_opt.item_selected.connect(func(i: int) -> void:
		if i != GameSettings.Preset.CUSTOM:
			settings.apply_preset(i)
			settings.apply(main)
			settings.save()
			_rebuild_settings(1))
	_slider(v, "Render scale (0 = auto)", "render_scale", 0.0, 1.0, 0.05, "%.2fx", true)
	_option(v, "Upscaler", "upscaler", GameSettings.UPSCALER_NAMES, true)
	_option(v, "Anti-aliasing", "aa", GameSettings.AA_NAMES, true)
	_option(v, "Shadows", "shadows", GameSettings.SHADOW_NAMES, true)
	_slider(v, "View distance (full detail)", "view_distance", 5, 14, 1, "%d", true)
	_option(v, "Glow / bloom", "glow", GameSettings.GLOW_NAMES, true)
	_check(v, "Atmospheric fog", "fog", true)
	_header(v, "Display")
	_option(v, "Window", "window_mode", GameSettings.WINDOW_NAMES)
	_check(v, "V-Sync", "vsync")
	_slider(v, "Frame cap (0 = none)", "max_fps", 0, 144, 1, "%d")


func _build_audio(v: VBoxContainer) -> void:
	_header(v, "Volume")
	_slider(v, "Master", "master_volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(v, "Ambience (sea, wind, rain)", "ambience_volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(v, "Effects (thunder)", "effects_volume", 0.0, 1.0, 0.05, "%.2f")


func _build_interface(v: VBoxContainer) -> void:
	_header(v, "Interface")
	_slider(v, "UI scale", "ui_scale", 0.75, 2.0, 0.05, "%.2fx")
	if main.get("creatures") != null:   # Agent C: world difficulty (host-editable)
		main.creatures.build_settings_row(v)


func _build_keys(v: VBoxContainer) -> void:
	_header(v, "Keyboard (click, then press a key; Esc cancels)")
	_key_buttons.clear()
	for pair: Array in REBINDABLE:
		var h := _row(v, pair[1])
		var b := Button.new()
		b.custom_minimum_size = Vector2(160, 0)
		var action: String = pair[0]
		b.pressed.connect(func() -> void:
			_cancel_rebind()
			_rebind_action = action
			_rebind_button = b
			b.text = "Press a key...")
		h.add_child(b)
		_key_buttons[action] = b
	_button(v, "Reset keys to defaults", func() -> void:
		settings.key_overrides.clear()
		settings.save()
		_cancel_rebind()
		settings.reset_keys()
		_refresh_keys())
	_refresh_keys()


func _refresh_keys() -> void:
	for action: String in _key_buttons:
		var names := []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				names.append(OS.get_keycode_string(ev.physical_keycode))
		(_key_buttons[action] as Button).text = " / ".join(names) if not names.is_empty() else "(none)"


func _cancel_rebind() -> void:
	if _rebind_action != "":
		_rebind_action = ""
		_refresh_keys()


## A graphics control changed by hand: switch the preset label to Custom.
func _changed(graphics: bool) -> void:
	if _building:
		return
	if graphics and settings.preset != GameSettings.Preset.CUSTOM:
		settings.preset = GameSettings.Preset.CUSTOM
		if _preset_opt != null:
			_preset_opt.set_block_signals(true)
			_preset_opt.selected = GameSettings.Preset.CUSTOM
			_preset_opt.set_block_signals(false)
	settings.apply(main)
	settings.save()


## Rebuild the settings screen so every control shows the new preset's values.
func _rebuild_settings(tab: int) -> void:
	var was_open := is_open()
	_root.queue_free()
	_build()
	_root.visible = was_open
	_pause.visible = false
	_settings_panel.visible = was_open
	var tabs: TabContainer = _settings_panel.get_child(0).get_child(0)
	tabs.current_tab = tab


var _quitting := false


func _quit_to_menu() -> void:
	if _quitting:
		return
	_quitting = true
	if main != null and main.has_method("return_to_main_menu"):
		await main.return_to_main_menu()
		return
	if main != null and "session" in main and main.session != null:
		if main.session.is_authority():
			main.session.save_all()
		elif main.player != null and main.multiplayer != null and main.multiplayer.multiplayer_peer != null:
			main.session.profile_upload.rpc_id(1, main.session.player_key, main.session.capture_profile())
			await get_tree().create_timer(0.3).timeout
	if main != null and main.multiplayer != null and main.multiplayer.multiplayer_peer != null:
		main.multiplayer.multiplayer_peer = null
		if "is_net" in main:
			main.is_net = false
	Main.force_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://main.tscn")


func _save_and_quit() -> void:
	if _quitting:
		return
	_quitting = true
	if main != null and main.has_method("save_and_quit"):
		await main.save_and_quit()
		return
	if main.session != null and main.session.is_authority():
		main.session.save_all()
	elif main.session != null and main.player != null and main.multiplayer.multiplayer_peer != null:
		main.session.profile_upload.rpc_id(1, main.session.player_key, main.session.capture_profile())
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()
