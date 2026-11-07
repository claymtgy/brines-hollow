extends SceneTree
## Renders every themed control + icons to a PNG for review.
##   godot --path . -s tools/ui_gallery.gd -- --out=/path/gallery.png

func _init() -> void:
	var out := "user://ui_gallery.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	root.size = Vector2i(1280, 800)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	UiTheme.prepare(ui)
	var bg := ColorRect.new()
	bg.color = Color8(78, 138, 150)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var row := HBoxContainer.new()
	row.position = Vector2(30, 30)
	row.add_theme_constant_override("separation", 24)
	ui.add_child(row)

	# Menu panel
	var p := PanelContainer.new()
	row.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(340, 0)
	p.add_child(v)
	var t := Label.new(); t.theme_type_variation = &"Title"; t.text = "Brine's Hollow"
	v.add_child(t)
	var sub := Label.new(); sub.theme_type_variation = &"Small"; sub.text = "a co-op coastal voxel game"
	v.add_child(sub)
	v.add_child(HSeparator.new())
	for s in ["Play Solo", "Host Co-op", "Settings"]:
		var b := Button.new(); b.text = s
		v.add_child(b)
	var dis := Button.new(); dis.text = "Disabled"; dis.disabled = true
	v.add_child(dis)
	var le := LineEdit.new(); le.text = "127.0.0.1"
	v.add_child(le)

	# Settings-like column
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420, 360)
	row.add_child(tabs)
	var g := VBoxContainer.new(); g.name = "Graphics"
	tabs.add_child(g)
	var h1 := Label.new(); h1.theme_type_variation = &"Header"; h1.text = "Quality"
	g.add_child(h1)
	var o := OptionButton.new()
	for n in ["Steam Deck", "Low", "Medium", "High"]:
		o.add_item(n)
	o.selected = 2
	g.add_child(o)
	var c1 := CheckBox.new(); c1.text = "Fade leaves in front of you"; c1.button_pressed = true
	g.add_child(c1)
	var c2 := CheckBox.new(); c2.text = "Invert vertical look"
	g.add_child(c2)
	var sl := HSlider.new(); sl.value = 60; sl.custom_minimum_size = Vector2(300, 24)
	g.add_child(sl)
	var pb := ProgressBar.new(); pb.value = 70; pb.show_percentage = false; pb.custom_minimum_size = Vector2(300, 26)
	g.add_child(pb)
	var k := VBoxContainer.new(); k.name = "Controls"
	tabs.add_child(k)
	var k2 := VBoxContainer.new(); k2.name = "Audio"
	tabs.add_child(k2)

	# Parchment + HUD plaque column
	var col := VBoxContainer.new()
	row.add_child(col)
	var parch := PanelContainer.new(); parch.theme_type_variation = &"Parchment"
	col.add_child(parch)
	var pv := VBoxContainer.new()
	parch.add_child(pv)
	var pl := Label.new(); pl.theme_type_variation = &"InkLabel"; pl.text = "Raft Peddler — wares"
	pl.add_theme_font_size_override("font_size", 22)
	pv.add_child(pl)
	var pl2 := Label.new(); pl2.theme_type_variation = &"InkLabel"; pl2.text = "Smoked Mackerel ......  6 brass\nSea Salt ...............  2 brass"
	pv.add_child(pl2)
	var plaque := PanelContainer.new(); plaque.theme_type_variation = &"Plaque"
	col.add_child(plaque)
	var qv := VBoxContainer.new()
	plaque.add_child(qv)
	var clock := Label.new(); clock.text = "08:24  Morning"; clock.add_theme_font_size_override("font_size", 22)
	qv.add_child(clock)
	var tide := Label.new(); tide.theme_type_variation = &"Small"; tide.text = "Tide rising  +0.4 m   ·   Clear, light wind"
	qv.add_child(tide)
	for b in [["HealthBar", 80], ["StaminaBar", 55], ["FoodBar", 35]]:
		var bar := ProgressBar.new(); bar.theme_type_variation = b[0]; bar.value = b[1]
		bar.show_percentage = false; bar.custom_minimum_size = Vector2(260, 22)
		qv.add_child(bar)

	# Hotbar with icons
	var hb := HBoxContainer.new()
	hb.position = Vector2(200, 640)
	hb.add_theme_constant_override("separation", 6)
	ui.add_child(hb)
	var icons := [ItemIcons.for_tool(ItemIcons.Tool.PICKAXE), ItemIcons.for_tool(ItemIcons.Tool.HAMMER),
		ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT), ItemIcons.for_tool(ItemIcons.Tool.ROD),
		ItemIcons.for_tool(ItemIcons.Tool.HOE), ItemIcons.for_item(&"wood_plank"),
		ItemIcons.for_item(&"seed_shore_wheat"), ItemIcons.for_item(&"roasted_mackerel"),
		ItemIcons.for_item(&"hearty_clam_chowder"), ItemIcons.for_item(&"hydrographic_sea_chart"),
		ItemIcons.for_item(&"cobblestone"), ItemIcons.for_item(&"sand")]
	for idx in icons.size():
		var s := PanelContainer.new()
		s.theme_type_variation = &"SlotSelected" if idx == 1 else &"Slot"
		var tr := TextureRect.new(); tr.texture = icons[idx]
		tr.custom_minimum_size = Vector2(48, 48)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		s.add_child(tr)
		hb.add_child(s)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("[gallery] saved ", out)
	quit()
