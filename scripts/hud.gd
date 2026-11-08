class_name Hud
extends CanvasLayer
## Main menu, loading screen and in-game HUD, all on the shared UiTheme
## (driftwood plaques, brass, parchment, pixel icons). Public API used elsewhere:
##   show_toast, set_prompt, show_menu, set_loading, show_hud, update_hud, set_controller,
##   help (Control), minimap, signals solo_pressed / host_pressed / join_pressed.

signal solo_pressed
signal host_pressed
signal join_pressed(ip: String)

const TOOL_ICONS := [ItemIcons.Tool.PICKAXE, ItemIcons.Tool.HAMMER, ItemIcons.Tool.BLUEPRINT,
	ItemIcons.Tool.ROD, ItemIcons.Tool.HOE]
const TOOL_NAMES := ["Pickaxe", "Hammer", "Blueprints", "Rod", "Farm"]

var controller: ControllerManager

# menu / loading
var menu: Control
var status_label: Label
var ip_edit: LineEdit
var loading: Control
var loading_label: Label
var loading_bar: ProgressBar
var save_select: OptionButton
var world_name_edit: LineEdit
var seed_edit: LineEdit
var save_info_label: Label
var menu_customizer: CharacterCustomizer = CharacterCustomizer.new()
var skin_preset_select: OptionButton
var _skin_labels: Dictionary = {}
var _saved_worlds: Array[Dictionary] = []
var delete_world_btn: Button
var _delete_armed := false
var _preview_model: CharacterModel = null

# hud
var hud_root: Control
var clock_label: Label
var phase_label: Label
var phase_icon: TextureRect
var tide_label: Label
var tide_icon: TextureRect
var weather_label: Label
var weather_icon: TextureRect
var weather_row: HBoxContainer
var peers_label: Label
var fps_label: Label
var underwater: ColorRect
var toast: PanelContainer
var toast_label: Label
var prompt_container: HBoxContainer
var help: PanelContainer
var minimap: Minimap
var chart_frame: PanelContainer
var bottom_bar: VBoxContainer
var slots: Array = []
var slot_icons: Array = []
var slot_counts: Array = []
var slot_keys: Array = []
var info_label: Label
var info_icon: TextureRect
var vitality_panel: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var breath_row: HBoxContainer
var breath_bar: ProgressBar
var stomach_label: Label
var rested_label: Label

var _toast_t := 0.0
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var _banner_t := 0.0
var chart_islands: Array = []   # discovered island labels for the sea chart
var _prompt_text := "\u0001"
var _help_type := -2
var _help_tween: Tween


func _ready() -> void:
	layer = 10
	underwater = ColorRect.new()
	underwater.color = Color(0.10, 0.42, 0.48, 0.38)
	underwater.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater.visible = false
	add_child(underwater)
	_build_hud()
	_build_menu()
	_build_loading()
	_rebuild_help()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uishot="):
			_menu_shot(a.trim_prefix("--uishot="))


## Dev: `--uishot=DIR` saves the main menu and loading screen, then quits.
func _menu_shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("ui_main_menu.png"))
	show_menu(false)
	set_loading(true, "Laying down sand and stone...", 0.45)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("ui_loading.png"))
	get_tree().quit()


func set_controller(cm: ControllerManager) -> void:
	controller = cm
	_rebuild_help()


func _pad() -> bool:
	return controller != null and controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE


func _glyph(action: StringName, kb: String) -> String:
	return controller.get_glyph(action) if _pad() else kb


# ---------------------------------------------------------------- builders

func _root_control() -> Control:
	var c := Control.new()
	UiTheme.prepare(c)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _label(text: String, variation: StringName = &"", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(parent: Control, variation: StringName = &"Plaque") -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _row(parent: Control, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func _bar(parent: Control, variation: StringName, width := 160) -> ProgressBar:
	var b := ProgressBar.new()
	b.theme_type_variation = variation
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 22)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- main menu

func _build_menu() -> void:
	menu = _root_control()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.10, 0.13, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)

	# The village name sign over the menu board.
	var sign := _panel(col, &"")
	var title := _label("Brine's Hollow", &"Title", 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_child(title)
	var sub := _label("a co-op coastal voxel game", &"Small", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_child(sub)

	var menu_cols := HBoxContainer.new()
	menu_cols.add_theme_constant_override("separation", 14)
	menu_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(menu_cols)

	# --- 1. Left Card: World & Save Selection
	var world_card := _panel(menu_cols, &"Parchment")
	world_card.add_theme_constant_override("separation", 8)
	world_card.custom_minimum_size = Vector2(290, 0)
	var w_title := _label("World & Save", &"InkLabel", 20)
	w_title.add_theme_font_override("font", UiTheme.font(800))
	world_card.add_child(w_title)

	var save_lbl := _label("Select Save or New World:", &"InkLabel", 14)
	world_card.add_child(save_lbl)
	save_select = OptionButton.new()
	save_select.item_selected.connect(_on_save_selected)
	world_card.add_child(save_select)
	delete_world_btn = Button.new()
	delete_world_btn.text = "Delete World"
	delete_world_btn.tooltip_text = "Moves the selected world's save to the recycle bin."
	delete_world_btn.pressed.connect(_on_delete_world_pressed)
	world_card.add_child(delete_world_btn)

	var name_lbl := _label("World Name:", &"InkLabel", 14)
	world_card.add_child(name_lbl)
	world_name_edit = LineEdit.new()
	world_name_edit.text = "hollow"
	world_name_edit.placeholder_text = "world save name"
	world_card.add_child(world_name_edit)

	var seed_lbl := _label("Archipelago Seed:", &"InkLabel", 14)
	world_card.add_child(seed_lbl)
	var seed_row := _row(world_card, 6)
	seed_edit = LineEdit.new()
	seed_edit.text = "1106"
	seed_edit.placeholder_text = "seed number"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_edit)
	var rand_seed_btn := Button.new()
	rand_seed_btn.text = "Random"
	rand_seed_btn.pressed.connect(func() -> void:
		seed_edit.text = str(randi_range(1000, 999999))
	)
	seed_row.add_child(rand_seed_btn)

	save_info_label = _label("", &"InkLabel", 13)
	save_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_card.add_child(save_info_label)

	# --- 2. Center Card: Play / Co-op
	var board := _panel(menu_cols, &"Parchment")
	board.add_theme_constant_override("separation", 12)
	board.custom_minimum_size = Vector2(430, 0)
	for spec in [["Play Solo", func() -> void: solo_pressed.emit()],
			["Host Co-op", func() -> void: host_pressed.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(spec[1])
		board.add_child(b)
	var join_row := _row(board)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "server address"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_edit)
	var jb := Button.new()
	jb.text = "Join"
	jb.custom_minimum_size = Vector2(110, 52)
	jb.pressed.connect(func() -> void: join_pressed.emit(ip_edit.text.strip_edges()))
	join_row.add_child(jb)
	board.add_child(HSeparator.new())
	var low := _row(board)
	for spec in [["Settings", _open_settings], ["Quit", func() -> void: get_tree().quit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		low.add_child(b)
	status_label = _label("", &"InkLabel", 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	board.add_child(status_label)

	# --- 3. Right Card: Mariner Skin & Wardrobe
	var skin_card := _panel(menu_cols, &"Parchment")
	skin_card.add_theme_constant_override("separation", 6)
	skin_card.custom_minimum_size = Vector2(315, 0)
	var s_title := _label("Mariner Skin & Wardrobe", &"InkLabel", 20)
	s_title.add_theme_font_override("font", UiTheme.font(800))
	skin_card.add_child(s_title)

	# Live 3D Character Preview + Preset Row
	var top_skin_row := _row(skin_card, 8)
	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(104, 128)
	vpc.stretch = true
	top_skin_row.add_child(vpc)
	var vp := SubViewport.new()
	vp.size = Vector2i(104, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(vp)
	var p_cam := Camera3D.new()
	p_cam.position = Vector3(0.0, 0.95, 2.25)
	p_cam.rotation = Vector3(-0.08, 0.0, 0.0)
	p_cam.fov = 45.0
	vp.add_child(p_cam)
	var p_light := DirectionalLight3D.new()
	p_light.rotation = Vector3(-0.7, 0.5, 0.0)
	p_light.light_energy = 1.35
	vp.add_child(p_light)
	_preview_model = CharacterModel.new()
	_preview_model.rotation.y = 0.35
	vp.add_child(_preview_model)
	_preview_model.setup(Palette.COAT_A, Palette.HAT_A, menu_customizer)

	var preset_col := VBoxContainer.new()
	preset_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_col.add_theme_constant_override("separation", 6)
	top_skin_row.add_child(preset_col)
	preset_col.add_child(_label("Skin Preset:", &"InkLabel", 14))
	skin_preset_select = OptionButton.new()
	for p_item: Array in [
		["Default Mariner", "default"],
		["North Sea Veteran", "north_sea_veteran"],
		["Young Deckhand", "young_deckhand"],
		["Brine Hermit", "brine_hermit"],
		["Island Botanist", "island_botanist"],
	]:
		skin_preset_select.add_item(p_item[0])
		skin_preset_select.set_item_metadata(skin_preset_select.item_count - 1, p_item[1])
	skin_preset_select.item_selected.connect(func(idx: int) -> void:
		var p_key := String(skin_preset_select.get_item_metadata(idx))
		menu_customizer.apply_preset(p_key)
		_refresh_skin_ui()
	)
	preset_col.add_child(skin_preset_select)

	var rand_skin_btn := Button.new()
	rand_skin_btn.text = "Randomize Skin"
	rand_skin_btn.pressed.connect(func() -> void:
		menu_customizer.randomize_appearance()
		_refresh_skin_ui()
	)
	preset_col.add_child(rand_skin_btn)

	# Cycle rows for Coat, Hat, Skin Tone, Hair Style, Hair Color, Beard Style
	_add_skin_cycle_row(skin_card, &"coat", "Coat", func(d: int) -> void:
		menu_customizer.set_coat(posmod(int(menu_customizer.coat_color) + d, CharacterPalette.CoatColor.size()) as CharacterPalette.CoatColor)
		_refresh_skin_ui()
	)
	_add_skin_cycle_row(skin_card, &"hat", "Hat", func(d: int) -> void:
		menu_customizer.set_hat(posmod(int(menu_customizer.hat_style) + d, CharacterPalette.HatStyle.size()) as CharacterPalette.HatStyle)
		_refresh_skin_ui()
	)
	_add_skin_cycle_row(skin_card, &"skin", "Skin", func(d: int) -> void:
		menu_customizer.set_skin_tone(posmod(int(menu_customizer.skin_tone) + d, CharacterPalette.SkinTone.size()) as CharacterPalette.SkinTone)
		_refresh_skin_ui()
	)
	_add_skin_cycle_row(skin_card, &"hair", "Hair", func(d: int) -> void:
		menu_customizer.set_hair(posmod(int(menu_customizer.hair_style) + d, CharacterPalette.HairStyle.size()) as CharacterPalette.HairStyle, menu_customizer.hair_color)
		_refresh_skin_ui()
	)
	_add_skin_cycle_row(skin_card, &"hair_col", "Dye", func(d: int) -> void:
		var nc := posmod(int(menu_customizer.hair_color) + d, CharacterPalette.HairColor.size()) as CharacterPalette.HairColor
		menu_customizer.set_hair(menu_customizer.hair_style, nc)
		menu_customizer.set_beard(menu_customizer.beard_style, nc)
		_refresh_skin_ui()
	)
	_add_skin_cycle_row(skin_card, &"beard", "Beard", func(d: int) -> void:
		menu_customizer.set_beard(posmod(int(menu_customizer.beard_style) + d, CharacterPalette.BeardStyle.size()) as CharacterPalette.BeardStyle, menu_customizer.beard_color)
		_refresh_skin_ui()
	)

	refresh_menu_saves_and_skin()


func _add_skin_cycle_row(parent: Control, key: StringName, title_txt: String, on_step: Callable) -> void:
	var r := _row(parent, 4)
	var lbl := _label(title_txt + ":", &"InkLabel", 13)
	lbl.custom_minimum_size = Vector2(46, 0)
	r.add_child(lbl)
	var prev_b := Button.new()
	prev_b.text = "<"
	prev_b.custom_minimum_size = Vector2(28, 26)
	prev_b.pressed.connect(func() -> void: on_step.call(-1))
	r.add_child(prev_b)
	var val_lbl := _label("", &"InkLabel", 13)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(val_lbl)
	_skin_labels[key] = val_lbl
	var next_b := Button.new()
	next_b.text = ">"
	next_b.custom_minimum_size = Vector2(28, 26)
	next_b.pressed.connect(func() -> void: on_step.call(1))
	r.add_child(next_b)


func _refresh_skin_ui() -> void:
	var coats := ["Oilskin Yellow", "Navy Blue", "Storm Grey", "Kelp Green", "Coral Rust", "Pitch Black"]
	var hats := ["Bareheaded", "Sou'wester", "Watch Cap", "Fisher Cap", "Bandana"]
	var skins := ["Pale Salt", "Weathered Tan", "Rustic Ochre", "Deep Umber", "Abyssal Dusky"]
	var hairs := ["Bald", "Cropped", "Windswept", "Sailor Bun", "Braided Tides", "Wild Curls"]
	var dyes := ["Raven Black", "Driftwood Grey", "Salt White", "Rust Auburn", "Straw Blonde", "Kelp Green"]
	var beards := ["Clean Shaven", "Stubble", "Mutton Chops", "Full Salt Bush", "Braided Beard", "Anchor Goatee"]
	if _skin_labels.has(&"coat"):
		(_skin_labels[&"coat"] as Label).text = coats[clampi(int(menu_customizer.coat_color), 0, coats.size() - 1)]
	if _skin_labels.has(&"hat"):
		(_skin_labels[&"hat"] as Label).text = hats[clampi(int(menu_customizer.hat_style), 0, hats.size() - 1)]
	if _skin_labels.has(&"skin"):
		(_skin_labels[&"skin"] as Label).text = skins[clampi(int(menu_customizer.skin_tone), 0, skins.size() - 1)]
	if _skin_labels.has(&"hair"):
		(_skin_labels[&"hair"] as Label).text = hairs[clampi(int(menu_customizer.hair_style), 0, hairs.size() - 1)]
	if _skin_labels.has(&"hair_col"):
		(_skin_labels[&"hair_col"] as Label).text = dyes[clampi(int(menu_customizer.hair_color), 0, dyes.size() - 1)]
	if _skin_labels.has(&"beard"):
		(_skin_labels[&"beard"] as Label).text = beards[clampi(int(menu_customizer.beard_style), 0, beards.size() - 1)]
	if _preview_model != null:
		_preview_model.apply_customizer(menu_customizer)


func refresh_menu_saves_and_skin() -> void:
	if save_select == null:
		return
	var m := get_parent()
	if m != null and "session" in m and m.session != null:
		var saved_skin: Dictionary = m.session.load_skin_preference()
		if not saved_skin.is_empty():
			menu_customizer.deserialize(saved_skin)
	_refresh_skin_ui()

	save_select.clear()
	_saved_worlds = Session.list_saved_worlds()
	for w: Dictionary in _saved_worlds:
		save_select.add_item("%s  (Seed %d%s)" % [w.get("name", "world"), int(w.get("seed", 1106)),
				", classic size" if int(w.get("layout", 1)) < VoxelWorld.LAYOUT_NEW else ""])
	save_select.add_item("+ Create New World...")
	save_select.select(0)
	_on_save_selected(0)


func _on_save_selected(idx: int) -> void:
	if world_name_edit == null or seed_edit == null:
		return
	_disarm_delete()
	if delete_world_btn != null:
		delete_world_btn.disabled = idx < 0 or idx >= _saved_worlds.size()
	if idx >= 0 and idx < _saved_worlds.size():
		var w: Dictionary = _saved_worlds[idx]
		world_name_edit.text = String(w.get("id", "hollow"))
		world_name_edit.editable = false
		seed_edit.text = str(int(w.get("seed", 1106)))
		seed_edit.editable = false
		var saved_at := String(w.get("saved_at", ""))
		save_info_label.text = ("Existing save  ·  Last played: %s" % saved_at) if saved_at != "" else "Existing saved world"
	else:
		var next_num := _saved_worlds.size() + 1
		world_name_edit.text = "island_%d" % next_num if next_num > 1 else "hollow"
		world_name_edit.editable = true
		seed_edit.text = str(randi_range(1000, 999999))
		seed_edit.editable = true
		save_info_label.text = "New world: customize name & seed above!"


## Two-step delete: the first press arms the button, the second deletes.
func _on_delete_world_pressed() -> void:
	var idx := save_select.selected if save_select != null else -1
	if idx < 0 or idx >= _saved_worlds.size():
		return
	var w: Dictionary = _saved_worlds[idx]
	if not _delete_armed:
		_delete_armed = true
		delete_world_btn.text = "Really delete '%s'?" % w.get("name", w.get("id", "world"))
		save_info_label.text = "Press again to delete this world. Press anything else to cancel."
		return
	var ok := Session.delete_world(String(w.get("id", "")))
	refresh_menu_saves_and_skin()
	save_info_label.text = ("Deleted '%s'." % w.get("name", "world")) if ok else "Could not delete that world."


func _disarm_delete() -> void:
	_delete_armed = false
	if delete_world_btn != null:
		delete_world_btn.text = "Delete World"


func apply_menu_selections_to_main(main_node: Node) -> void:
	if main_node == null:
		return
	var is_new := save_select == null or save_select.selected >= _saved_worlds.size()
	var w_name := world_name_edit.text.strip_edges().validate_filename() if world_name_edit != null else "hollow"
	if w_name == "":
		w_name = "hollow"
	var s_val: int = int(seed_edit.text) if (seed_edit != null and seed_edit.text.strip_edges().is_valid_int()) else abs(hash(seed_edit.text if seed_edit != null else "1106")) % 1000000
	if "seed_value" in main_node:
		main_node.seed_value = s_val
	if "session" in main_node and main_node.session != null:
		main_node.session.save_skin_preference(menu_customizer.serialize())
		main_node.session.configure_world(w_name, s_val, is_new)


func _open_settings() -> void:
	var m := get_parent()
	if m != null and "settings_menu" in m and m.settings_menu != null:
		m.settings_menu.open_settings()


# ---------------------------------------------------------------- loading

func _build_loading() -> void:
	loading = _root_control()
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	loading.visible = false
	var bg := ColorRect.new()
	bg.color = Color8(24, 52, 62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(center)
	var v := _panel(center, &"")
	v.custom_minimum_size = Vector2(460, 0)
	v.add_theme_constant_override("separation", 12)
	var t := _label("Washing ashore...", &"Header", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = _label("", &"Small", 16)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	loading_bar = _bar(v, &"StaminaBar", 420)
	loading_bar.max_value = 1.0


# ---------------------------------------------------------------- in-game HUD

func _build_hud() -> void:
	hud_root = _root_control()
	hud_root.visible = false

	var cross := TextureRect.new()
	cross.texture = UiTheme.tex("crosshair")
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -16
	cross.offset_top = -16
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(cross)

	# --- top-left: chronometer, tide, weather
	var tl := MarginContainer.new()
	tl.position = Vector2(14, 12)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tl)
	var clock := _panel(tl)
	var r1 := _row(clock)
	phase_icon = UiTheme.icon(ItemIcons.hud_icon("sun"), 36)
	r1.add_child(phase_icon)
	clock_label = _label("08:00", &"Header", 28)
	r1.add_child(clock_label)
	phase_label = _label("DAY", &"Small", 15)
	phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(phase_label)
	var r2 := _row(clock, 6)
	tide_icon = UiTheme.icon(ItemIcons.hud_icon("tide_up"), 26)
	r2.add_child(tide_icon)
	tide_label = _label("", &"Small", 16)
	r2.add_child(tide_label)
	weather_row = _row(clock, 6)
	weather_icon = UiTheme.icon(ItemIcons.hud_icon("clear"), 26)
	weather_row.add_child(weather_icon)
	weather_label = _label("", &"Small", 16)
	weather_row.add_child(weather_label)

	# --- top-right: crew, stats, sea chart
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -360
	tr.offset_right = -14
	tr.offset_top = 12
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tr)
	var crew := _row(tr, 6)
	crew.alignment = BoxContainer.ALIGNMENT_END
	crew.add_child(UiTheme.icon(ItemIcons.hud_icon("crew"), 26))
	peers_label = _label("Solo", &"Small", 16)
	crew.add_child(peers_label)
	fps_label = _label("", &"Small", 14)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.visible = false
	tr.add_child(fps_label)
	chart_frame = PanelContainer.new()
	chart_frame.theme_type_variation = &"Plaque"
	chart_frame.size_flags_horizontal = Control.SIZE_SHRINK_END
	chart_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(chart_frame)
	minimap = Minimap.new()
	chart_frame.add_child(minimap)
	chart_frame.visible = false

	# --- toast banner (top centre)
	var toast_anchor := CenterContainer.new()
	toast_anchor.anchor_right = 1.0
	toast_anchor.offset_top = 80
	toast_anchor.offset_bottom = 140
	toast_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(toast_anchor)
	toast = PanelContainer.new()
	toast.theme_type_variation = &"Plaque"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_anchor.add_child(toast)
	toast_label = _label("", &"", 20)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)
	toast.visible = false

	# --- landfall banner (island names, upper third)
	var banner_anchor := CenterContainer.new()
	banner_anchor.anchor_right = 1.0
	banner_anchor.offset_top = 150
	banner_anchor.offset_bottom = 250
	banner_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(banner_anchor)
	banner = VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_anchor.add_child(banner)
	banner_title = _label("", &"", 40)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_font_override("font", UiTheme.font(800))
	banner_title.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05, 0.9))
	banner_title.add_theme_constant_override("outline_size", 10)
	banner.add_child(banner_title)
	banner_sub = _label("", &"", 18)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05, 0.9))
	banner_sub.add_theme_constant_override("outline_size", 6)
	banner.add_child(banner_sub)
	banner.visible = false

	# --- interaction prompt (just under the crosshair)
	var prompt_anchor := CenterContainer.new()
	prompt_anchor.anchor_top = 0.5
	prompt_anchor.anchor_bottom = 0.5
	prompt_anchor.anchor_right = 1.0
	prompt_anchor.offset_top = 40
	prompt_anchor.offset_bottom = 100
	prompt_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(prompt_anchor)
	prompt_container = HBoxContainer.new()
	prompt_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_anchor.add_child(prompt_container)

	# --- bottom-left: vitality
	var bl := VBoxContainer.new()
	bl.anchor_top = 1.0
	bl.anchor_bottom = 1.0
	bl.offset_left = 14
	bl.offset_bottom = -14
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bl)
	var vit := _panel(bl)
	vitality_panel = vit.get_parent() as PanelContainer
	var hr := _row(vit, 6)
	hr.add_child(UiTheme.icon(ItemIcons.hud_icon("heart"), 26))
	health_bar = _bar(hr, &"HealthBar")
	health_label = _label("", &"Small", 15)
	health_label.custom_minimum_size = Vector2(58, 0)
	hr.add_child(health_label)
	var sr := _row(vit, 6)
	sr.add_child(UiTheme.icon(ItemIcons.hud_icon("stamina"), 26))
	stamina_bar = _bar(sr, &"StaminaBar")
	stamina_label = _label("", &"Small", 15)
	stamina_label.custom_minimum_size = Vector2(58, 0)
	sr.add_child(stamina_label)
	breath_row = _row(vit, 6)
	breath_row.add_child(UiTheme.icon(ItemIcons.hud_icon("breath"), 26))
	breath_bar = _bar(breath_row, &"HealthBar")
	breath_bar.add_theme_stylebox_override("fill", UiTheme.box("bar_fill", 2, 0, 0, Color8(150, 226, 240)))
	breath_row.visible = false
	var fr := _row(vit, 6)
	fr.add_child(UiTheme.icon(ItemIcons.hud_icon("food"), 26))
	stomach_label = _label("", &"Small", 14)
	fr.add_child(stomach_label)
	rested_label = _label("Rested", &"Small", 14)
	rested_label.add_theme_color_override("font_color", UiTheme.TEAL)
	rested_label.visible = false
	vit.add_child(rested_label)

	# --- bottom-centre: tool context plaque + hotbar
	bottom_bar = VBoxContainer.new()
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.offset_bottom = -12
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	bottom_bar.add_theme_constant_override("separation", 6)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bottom_bar)
	var ctx := PanelContainer.new()
	ctx.theme_type_variation = &"Plaque"
	ctx.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ctx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.add_child(ctx)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 8)
	ctx.add_child(ch)
	info_icon = UiTheme.icon(null, 28)
	ch.add_child(info_icon)
	info_label = _label("", &"Small", 16)
	info_label.add_theme_color_override("font_color", UiTheme.CREAM)
	info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(info_label)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(bar)
	for i in Inventory.MAX_HOTBAR_SLOTS:
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"Slot"
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(slot)
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(52, 52)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stack)
		var ic := UiTheme.icon(null, 52)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(ic)
		var cnt := _label("", &"KeyLabel", 13)
		cnt.position = Vector2(26, 30)
		stack.add_child(cnt)
		var key := _label(str(i + 1), &"KeyLabel", 14)
		key.position = Vector2(-4, -8)
		stack.add_child(key)
		slots.append(slot)
		slot_icons.append(ic)
		slot_counts.append(cnt)
		slot_keys.append(key)

	# --- help sheet (F1), rebuilt when the input device changes
	help = PanelContainer.new()
	help.theme_type_variation = &"Parchment"
	help.anchor_top = 0.5
	help.anchor_bottom = 0.5
	help.offset_left = 14
	help.offset_top = -150
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(help)


func _rebuild_help() -> void:
	if help == null:
		return
	var t := controller.current_type if controller != null else -1
	if t == _help_type:
		return
	_help_type = t
	for c in help.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	help.add_child(v)
	var head := _label("Controls   (F1 hides)", &"InkLabel", 20)
	head.add_theme_font_override("font", UiTheme.font(800))
	v.add_child(head)
	var g := GridContainer.new()
	g.columns = 4 if get_viewport().get_visible_rect().size.x >= 1200 else 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var rows: Array
	if _pad():
		rows = [["L Stick", "move"], ["R Stick", "look"], [_glyph(&"jump", "Space"), "jump / swim up"],
			[_glyph(&"use", "LMB"), "use tool / swing"], [_glyph(&"alt_use", "RMB"), "build menu / eat / parry"],
			[_glyph(&"interact", "F"), "interact (hold: pick up)"], ["LB / RB", "hotbar slot"],
			[_glyph(&"inventory_toggle", "I"), "inventory"], ["D-Pad", "cycle item / brush"],
			[_glyph(&"rotate", "R"), "rotate"], ["J", "quest log"], [_glyph(&"menu_toggle", "Esc"), "menu"]]
	else:
		rows = [["WASD", "move"], ["Mouse", "look"], ["Space", "jump / swim up"], ["Shift", "sprint"],
			["LMB", "use tool / swing"], ["RMB", "build menu / eat / parry"], ["F", "interact (hold: pick up)"],
			["1-8", "hotbar slots"], ["I / Tab", "inventory"], ["J", "quest log"], ["B", "build menu (hammer)"],
			["Q / E", "cycle item"], ["Z / X", "brush size"], ["R / G", "rotate / snap"],
			["C", "dodge"], ["Ctrl", "sneak"], ["V", "swap shoulder"], ["T", "fast-forward time"],
			["F3", "stats"], ["Esc", "menu"]]
	for r: Array in rows:
		g.add_child(UiTheme.keycap(r[0]))
		g.add_child(_label(r[1], &"InkLabel", 14))
	for key in slot_keys:
		(key as Label).visible = not _pad()


# ---------------------------------------------------------------- public API

## Prompt text like "F  Board rowboat" or "F  Step off      W/S  row" renders as key caps.
func set_prompt(text: String) -> void:
	if text == _prompt_text:
		return
	_prompt_text = text
	for c in prompt_container.get_children():
		c.queue_free()
	if text == "":
		return
	var plaque := PanelContainer.new()
	plaque.theme_type_variation = &"Plaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_container.add_child(plaque)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	plaque.add_child(row)
	var groups := text.split("    ", false)
	for gi in groups.size():
		var part := groups[gi].strip_edges()
		if part == "":
			continue
		var idx := part.find("  ")
		if idx > 0 and idx <= 12:
			row.add_child(UiTheme.keycap(part.substr(0, idx)))
			row.add_child(_label(part.substr(idx).strip_edges(), &"", 17))
		else:
			row.add_child(_label(part, &"", 17))
		if gi < groups.size() - 1:
			row.add_child(_label("·", &"Small", 17))


## Big centred island name on landfall (fades in, holds, fades out).
func show_banner(title: String, subtitle := "") -> void:
	banner_title.text = title
	banner_sub.text = subtitle
	_banner_t = 4.5


func show_toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 3.2


func show_menu(on: bool, status := "") -> void:
	menu.visible = on
	status_label.text = status
	if on:
		refresh_menu_saves_and_skin()


func set_loading(on: bool, text := "", frac := 0.0) -> void:
	loading.visible = on
	loading_label.text = text
	loading_bar.value = frac


func show_hud(on: bool) -> void:
	hud_root.visible = on
	if on:
		_start_help_fade_timer(10.0)


func _start_help_fade_timer(delay: float = 10.0) -> void:
	if help == null:
		return
	if _help_tween != null and _help_tween.is_valid():
		_help_tween.kill()
	help.visible = true
	help.modulate.a = 1.0
	_help_tween = create_tween()
	_help_tween.tween_interval(delay)
	_help_tween.tween_property(help, "modulate:a", 0.0, 1.5)
	_help_tween.tween_callback(func() -> void: help.visible = false)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F1:
			if _help_tween != null and _help_tween.is_valid():
				_help_tween.kill()
			if help.visible and help.modulate.a > 0.05:
				help.visible = false
				help.modulate.a = 0.0
			else:
				help.visible = true
				help.modulate.a = 1.0
		elif e.keycode == KEY_F3:
			fps_label.visible = not fps_label.visible


func _set_icon(r: TextureRect, key: String) -> void:
	if r.get_meta("k", "") != key:
		r.set_meta("k", key)
		r.texture = ItemIcons.hud_icon(key)


func update_hud(player: Player, sky: SkyCycle, peers_text: String, world: VoxelWorld, cam_under: bool) -> void:
	_toast_t -= get_process_delta_time()
	toast.modulate.a = clampf(_toast_t * 1.5, 0.0, 1.0)
	toast.visible = _toast_t > 0.0
	if banner != null:
		_banner_t -= get_process_delta_time()
		banner.visible = _banner_t > 0.0
		banner.modulate.a = clampf(minf(_banner_t * 1.2, (4.5 - _banner_t) * 3.0), 0.0, 1.0)
	bottom_bar.visible = not player.is_seated()
	underwater.visible = cam_under
	_rebuild_help()

	# --- chronometer
	var t := sky.time_of_day
	var mins := int(t * 24.0 * 60.0)
	clock_label.text = "%02d:%02d" % [mins / 60, mins % 60]
	var phase := "NIGHT" if (t < 0.22 or t > 0.82) else ("DAWN" if t < 0.30 else ("DAY" if t < 0.70 else "DUSK"))
	phase_label.text = phase + ("  >>" if sky.time_scale > 1.0 else "")
	_set_icon(phase_icon, "moon" if phase == "NIGHT" else ("dawn" if phase in ["DAWN", "DUSK"] else "sun"))
	var rel := (sky.water_level_vox - VoxelWorld.SEA_MID) * VoxelWorld.VS
	var rising := sky.tide_trend() > 0
	_set_icon(tide_icon, "tide_up" if rising else "tide_down")
	var state := "high tide" if rel > 0.9 else ("low tide" if rel < -0.9 else ("rising" if rising else "ebbing"))
	tide_label.text = "Tide %+.1f m  ·  %s" % [rel, state]
	weather_row.visible = sky.has_method("weather_label")
	if weather_row.visible:
		var w: String = sky.weather_label()
		weather_label.text = w
		var wl := w.to_lower()
		var wi := "moon" if phase == "NIGHT" else "clear"
		if "storm" in wl: wi = "storm"
		elif "rain" in wl: wi = "rain"
		elif "fog" in wl: wi = "fog"
		elif "overcast" in wl or "cloud" in wl: wi = "cloud"
		_set_icon(weather_icon, wi)
	peers_label.text = peers_text

	# --- vitality
	if player.vitality != null:
		var vit: VitalityController = player.vitality
		health_bar.max_value = vit.get_max_hp()
		health_bar.value = vit.current_hp
		health_label.text = "%d/%d" % [int(ceil(vit.current_hp)), int(round(health_bar.max_value))]
		stamina_bar.max_value = vit.get_max_stamina()
		stamina_bar.value = vit.current_stamina
		stamina_label.text = "%d/%d" % [int(ceil(vit.current_stamina)), int(round(stamina_bar.max_value))]
		stamina_bar.modulate = Color(0.62, 0.70, 0.80) if vit.is_exhausted else Color.WHITE
		var max_b: float = vit.get_max_breath()
		breath_row.visible = cam_under or vit.current_breath < max_b - 0.5
		breath_bar.max_value = max_b
		breath_bar.value = vit.current_breath
		var meals: Array = vit.get_active_meals()
		if meals.is_empty():
			stomach_label.text = "Hungry"
		else:
			var parts := []
			for m in meals:
				parts.append("%s %dm" % [m.name, int(ceil(m.remaining_sec / 60.0))])
			stomach_label.text = "  ·  ".join(parts)
		rested_label.visible = vit.is_rested

	# --- sea chart (only with a chart in the map slot)
	var map_tier := 0
	var map_name := ""
	if player.inventory and player.inventory.is_minimap_enabled():
		var map_def: ItemDef = player.inventory.get_equipped_map_def()
		if map_def:
			map_name = map_def.name
			map_tier = int({&"parchment_shore_chart": 1, &"hydrographic_sea_chart": 2,
				&"master_chronometer_chart": 3}.get(map_def.id, 1))
	chart_frame.visible = map_tier > 0
	if map_tier > 0:
		if not minimap._texture_generated and world != null and world.gen != null:
			minimap.bake_chart_texture(world)
		var lm_list: Array = []
		if world != null and world.gen != null:
			lm_list.assign(world.gen.starter_spawns)
		var boat_pos_list: Array[Vector3] = []
		if player.boat != null:
			boat_pos_list.append(player.boat.position)
		minimap.update_state(map_tier, map_name, player.position,
			player.rig.yaw if player.rig != null else player.facing,
			sky.water_level_vox * VoxelWorld.VS, lm_list, boat_pos_list)
		minimap.island_labels = chart_islands

	# --- hotbar + tool context
	var active_idx: int = player.inventory.active_hotbar_index if player.inventory != null else 0
	for i in slots.size():
		(slots[i] as PanelContainer).theme_type_variation = &"SlotSelected" if i == active_idx else &"Slot"
		if player.inventory != null and i < player.inventory.slots.size():
			var s: ItemSlot = player.inventory.slots[i]
			var ic_rect := slot_icons[i] as TextureRect
			var cnt_lbl := slot_counts[i] as Label
			if not s.is_empty():
				ic_rect.texture = ItemIcons.for_item(s.item_id)
				ic_rect.visible = true
				cnt_lbl.text = str(s.count) if s.count > 1 else ""
			else:
				ic_rect.texture = null
				ic_rect.visible = false
				cnt_lbl.text = ""

	var size_btn := "D-Pad U/D" if _pad() else "Z/X"
	var cycle_btn := "D-Pad L/R" if _pad() else "Q/E"
	var use_btn := _glyph(&"use", "LMB")
	var alt_btn := _glyph(&"alt_use", "RMB")
	var inv_btn := _glyph(&"inventory_toggle", "I")
	var r: int = Player.BRUSHES[player.brush]
	var active_slot: ItemSlot = player.inventory.get_active_item() if player.inventory != null else null
	var active_def: ItemDef = ItemDB.get_item(active_slot.item_id) if (active_slot != null and not active_slot.is_empty()) else null
	var icon: Texture2D = ItemIcons.for_item(active_slot.item_id) if active_def != null else null
	var text := ""
	match player.tool:
		0:
			icon = icon if icon != null else ItemIcons.for_tool(ItemIcons.Tool.PICKAXE)
			text = "%s  ·  Dig brush %d   (%s size, %s inventory)" % [
				active_def.name if active_def else "Pickaxe", r * 2 + 1, size_btn, inv_btn]
		1:
			icon = ItemIcons.for_material(player.current_material())
			var dim_str := "%dx%d" % [r * 2 + 1, r * 2 + 1] if r > 0 else "1x1"
			if player.is_hammer_equipped():
				text = "%s  ·  Size: %s   (%s block, %s size, %s build menu)" % [
					Palette.NAMES[player.current_material()], dim_str, cycle_btn, size_btn, alt_btn]
			else:
				text = "%s  ·  Size: %s   (%s place, %s resize [%s])" % [
					Palette.NAMES[player.current_material()], dim_str, use_btn, alt_btn, size_btn]
		2:
			var pf: Dictionary = Prefabs.all()[player.prefab_id]
			icon = icon if icon != null else ItemIcons.for_tool(ItemIcons.Tool.HAMMER)
			text = "%s   (%s change, %s rotate, snap %s, %s build menu)" % [
				pf.name, cycle_btn, _glyph(&"rotate", "R"), "on" if player.snap else "off", alt_btn]
		3:
			icon = icon if icon != null else ItemIcons.for_tool(ItemIcons.Tool.ROD)
			text = _fishing_text(player, use_btn)
		4:
			icon = icon if icon != null else ItemIcons.for_tool(ItemIcons.Tool.HOE)
			text = "%s  ·  %s till / harvest   %s plant / eat   (%s inventory)" % [
				active_def.name if active_def else "Farm", use_btn, alt_btn, inv_btn]
		5:
			text = "%s  ·  %s swing   %s parry   (%s inventory)" % [
				active_def.name if active_def else "Weapon", use_btn, alt_btn, inv_btn]
		_:
			if active_def != null:
				text = "%s (x%d)   (%s inventory)" % [active_def.name, active_slot.count, inv_btn]
			else:
				text = "Empty Slot %d   (Press %s to open Inventory & configure Hotbar)" % [active_idx + 1, inv_btn]
	var place_text: String = player.placement.hud_text() if player.placement != null else ""
	if place_text != "":
		text = place_text
		icon = ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT)
	info_label.text = text
	info_icon.texture = icon
	info_icon.visible = (icon != null)

	if fps_label.visible:
		var p := player.position / VoxelWorld.VS
		fps_label.text = "%d fps  ·  %dk verts\nvoxel %d, %d, %d" % [
			Engine.get_frames_per_second(), world.stats_vertices / 1000, p.x, p.y, p.z]


func _fishing_text(player: Player, use_btn: String) -> String:
	if player.fishing == null:
		return "Fishing rod"
	match player.fishing.current_state:
		FishingController.State.IDLE:
			return "Fishing rod  ·  aim at water, hold %s to cast" % use_btn
		FishingController.State.CASTING:
			return "Casting...  power %.0f%%  (release %s)" % [player.fishing_cast_power * 100.0, use_btn]
		FishingController.State.WAITING_FOR_BITE:
			return "Bobber out %.1f m  ·  waiting for a bite" % player.fishing.line_distance
		FishingController.State.NIBBLING:
			return "Nibble...  get ready"
		FishingController.State.HOOK_WINDOW:
			return "BITE!  press %s to hook" % use_btn
		FishingController.State.REELING:
			return "Reeling  %.1f m  ·  tension %.0f%%  (pulse %s)" % [
				player.fishing.line_distance, player.fishing.line_tension * 100.0, use_btn]
		FishingController.State.CAUGHT:
			return "Landed it!  (%s to cast again)" % use_btn
		FishingController.State.LOST:
			return "It slipped away  (%s to recast)" % use_btn
	return "Fishing rod"
