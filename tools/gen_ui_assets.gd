extends SceneTree
## Generates the pixel-art UI kit into res://assets/ui/ (driftwood, brass, parchment, rope).
##   godot --headless --path . -s tools/gen_ui_assets.gd
## Everything is drawn at 1x in the game palette, then scaled 3x nearest-neighbour so it
## stays crisp and chunky like the voxels. Re-run after tweaking; the PNGs are committed.

const S := 3  # upscale
const OUT := "res://assets/ui/"

var C := {
	"out": Color8(38, 26, 20), "tar": Color8(66, 48, 38), "tar_hi": Color8(96, 71, 54), "tar_lo": Color8(50, 36, 29),
	"plank": Color8(166, 126, 86), "plank_hi": Color8(196, 156, 110), "plank_lo": Color8(134, 98, 66),
	"seam": Color8(96, 68, 46), "brass": Color8(206, 162, 78), "brass_hi": Color8(248, 216, 136),
	"brass_lo": Color8(138, 98, 42), "parch": Color8(238, 224, 190), "parch_lo": Color8(219, 199, 156),
	"parch_edge": Color8(176, 138, 90), "ink": Color8(72, 52, 40), "teal": Color8(104, 214, 196),
	"teal_hi": Color8(196, 250, 238), "rope": Color8(201, 168, 114), "rope_lo": Color8(146, 112, 72),
	"well": Color8(44, 34, 29), "well_lo": Color8(32, 24, 20), "well_hi": Color8(70, 54, 44),
}


func h(x: int, y: int, salt: int = 0) -> float:
	var v := (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	return float(v & 0xffff) / 65535.0


func img(w: int, hh: int) -> Image:
	var i := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	i.fill(Color(0, 0, 0, 0))
	return i


func rect(i: Image, x0: int, y0: int, w: int, hh: int, c: Color) -> void:
	for y in range(y0, y0 + hh):
		for x in range(x0, x0 + w):
			if x >= 0 and y >= 0 and x < i.get_width() and y < i.get_height():
				i.set_pixel(x, y, c)


func frame(i: Image, inset: int, c: Color) -> void:
	var w := i.get_width()
	var hh := i.get_height()
	rect(i, inset, inset, w - inset * 2, 1, c)
	rect(i, inset, hh - 1 - inset, w - inset * 2, 1, c)
	rect(i, inset, inset, 1, hh - inset * 2, c)
	rect(i, w - 1 - inset, inset, 1, hh - inset * 2, c)


func shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)


func save(i: Image, name: String) -> void:
	var big := i.duplicate() as Image
	big.resize(i.get_width() * S, i.get_height() * S, Image.INTERPOLATE_NEAREST)
	big.save_png(OUT + name + ".png")
	print("  ", name, " ", big.get_size())


## Horizontal driftwood planks with grain, filling [x0,y0,w,h).
func planks(i: Image, x0: int, y0: int, w: int, hh: int, base: Color, plank_h: int, salt: int) -> void:
	for y in range(y0, y0 + hh):
		var row := (y - y0) / plank_h
		var tone := 0.92 + h(row, 7, salt) * 0.14
		for x in range(x0, x0 + w):
			# long horizontal grain streaks: value changes every ~7 px along x, per pixel row
			var streak := h((x + row * 5) / 7, y, salt)
			var grain := 1.0 + (0.06 if streak > 0.82 else (-0.05 if streak < 0.14 else 0.0))
			var c := shade(base, tone * grain)
			if (y - y0) % plank_h == plank_h - 1:
				c = shade(base, 0.62)                       # seam
			elif (y - y0) % plank_h == 0:
				c = shade(base, tone * 1.07)                # top edge catch-light
			if h(x, y, salt + 3) > 0.997:
				c = shade(base, 0.72)                       # rare knot
			i.set_pixel(x, y, c)


func rivet(i: Image, x: int, y: int) -> void:
	i.set_pixel(x, y, C.brass_hi)
	i.set_pixel(x + 1, y, C.brass)
	i.set_pixel(x, y + 1, C.brass)
	i.set_pixel(x + 1, y + 1, C.brass_lo)


func corner_brackets(i: Image, inset: int, length: int) -> void:
	var w := i.get_width()
	var hh := i.get_height()
	for k in length:
		for corner in [[inset, inset, 1, 1], [w - 1 - inset, inset, -1, 1], [inset, hh - 1 - inset, 1, -1], [w - 1 - inset, hh - 1 - inset, -1, -1]]:
			var cx: int = corner[0]
			var cy: int = corner[1]
			var dx: int = corner[2]
			var dy: int = corner[3]
			i.set_pixel(cx + dx * k, cy, C.brass_hi if dy > 0 else C.brass)
			i.set_pixel(cx, cy + dy * k, C.brass_hi if dx > 0 else C.brass)
			i.set_pixel(cx + dx * k, cy + dy, C.brass_lo)
			i.set_pixel(cx + dx, cy + dy * k, C.brass_lo)


# ---------------------------------------------------------------- pieces

func panel_wood() -> void:
	var i := img(32, 32)
	var stain: Color = C.tar_hi.lerp(C.plank, 0.18)          # dark stained driftwood
	planks(i, 4, 4, 24, 24, stain, 6, 1)
	rect(i, 4, 4, 24, 1, shade(stain, 0.6))              # inner shadow under the frame
	rect(i, 4, 4, 1, 24, shade(stain, 0.75))
	for k in [1, 2, 3]:
		frame(i, k, C.tar)
	frame(i, 1, C.tar_hi)
	rect(i, 2, 30, 28, 1, C.tar_lo)
	frame(i, 0, C.out)
	corner_brackets(i, 1, 6)
	for p in [[2, 2], [28, 2], [2, 28], [28, 28]]:
		rivet(i, p[0], p[1])
	save(i, "panel_wood")


func panel_parchment() -> void:
	var i := img(32, 32)
	for y in 32:
		for x in 32:
			var edge := mini(mini(x, y), mini(31 - x, 31 - y))
			var n := h(x, y, 5)
			var c: Color = C.parch.lerp(C.parch_lo, n * 0.5)
			if edge < 4:
				c = c.lerp(C.parch_edge, (4 - edge) / 5.0 * (0.6 + n * 0.4))
			if h(x / 4, y / 4, 9) > 0.93:
				c = c.lerp(C.parch_edge, 0.18)                # faint stains
			i.set_pixel(x, y, c)
	# ragged outline: skip some edge pixels, ink the rest
	for k in 32:
		for e in [[k, 0], [k, 31], [0, k], [31, k]]:
			if h(e[0], e[1], 11) > 0.2:
				i.set_pixel(e[0], e[1], C.ink)
			else:
				i.set_pixel(e[0], e[1], Color(0, 0, 0, 0))
	for c in [[0, 0], [31, 0], [0, 31], [31, 31]]:
		i.set_pixel(c[0], c[1], Color(0, 0, 0, 0))
	save(i, "panel_parchment")


func plaque() -> void:
	var i := img(24, 24)
	planks(i, 2, 2, 20, 20, C.tar_hi, 5, 2)
	frame(i, 1, C.brass)
	rect(i, 1, 1, 22, 1, C.brass_hi)
	rect(i, 1, 22, 22, 1, C.brass_lo)
	frame(i, 0, C.out)
	for p in [[2, 2], [20, 2], [2, 20], [20, 20]]:
		rivet(i, p[0], p[1])
	# slight transparency so the world shows through on the HUD
	for y in 24:
		for x in 24:
			var c := i.get_pixel(x, y)
			if c.a > 0 and x > 2 and y > 2 and x < 21 and y < 21:
				c.a = 0.9
				i.set_pixel(x, y, c)
	save(i, "plaque")


func button(name: String, base: Color, pressed: bool, rim: Color) -> void:
	var i := img(24, 24)
	planks(i, 1, 1, 22, 22, base, 11, 4)
	if pressed:
		rect(i, 1, 1, 22, 2, shade(base, 0.6))
		rect(i, 1, 21, 22, 1, shade(base, 1.15))
	else:
		rect(i, 1, 1, 22, 1, shade(base, 1.22))
		rect(i, 1, 21, 22, 2, shade(base, 0.6))
	frame(i, 0, C.out)
	frame(i, 1, Color(rim, 0.55))
	for p in [[3, 3], [19, 3], [3, 18], [19, 18]]:
		if pressed:
			rivet(i, p[0], p[1] + 1)
		else:
			rivet(i, p[0], p[1])
	save(i, name)


func focus_ring() -> void:
	var i := img(24, 24)
	frame(i, 0, C.teal)
	frame(i, 1, Color(C.teal_hi, 0.85))
	frame(i, 2, Color(C.teal, 0.35))
	for c in [[0, 0], [23, 0], [0, 23], [23, 23], [1, 1], [22, 1], [1, 22], [22, 22]]:
		i.set_pixel(c[0], c[1], C.teal_hi)
	save(i, "focus")


func slot(name: String, selected: bool) -> void:
	var i := img(24, 24)
	rect(i, 3, 3, 18, 18, C.well)
	rect(i, 3, 3, 18, 2, C.well_lo)                      # inset shadow
	rect(i, 3, 3, 2, 18, C.well_lo)
	rect(i, 3, 20, 18, 1, C.well_hi)
	rect(i, 20, 3, 1, 18, C.well_hi)
	var rim: Color = C.brass if selected else C.tar
	for k in [1, 2]:
		frame(i, k, rim)
	rect(i, 1, 1, 22, 1, C.brass_hi if selected else C.tar_hi)
	rect(i, 1, 22, 22, 1, C.brass_lo if selected else C.tar_lo)
	frame(i, 0, C.out)
	if selected:
		for c in [[3, 3], [20, 3], [3, 20], [20, 20]]:
			i.set_pixel(c[0], c[1], C.teal_hi)
	save(i, name)


func bars() -> void:
	var i := img(16, 10)
	rect(i, 2, 2, 12, 6, C.well)
	rect(i, 2, 2, 12, 1, C.well_lo)
	frame(i, 1, C.brass)
	rect(i, 1, 1, 14, 1, C.brass_hi)
	rect(i, 1, 8, 14, 1, C.brass_lo)
	frame(i, 0, C.out)
	save(i, "bar_bg")
	var f := img(8, 6)
	for y in 6:
		var k := 1.25 if y == 0 else (1.0 if y < 4 else 0.78)
		rect(f, 0, y, 8, 1, shade(Color(0.82, 0.82, 0.82), k))
	save(f, "bar_fill")


func tabs() -> void:
	var a := img(24, 16)
	rect(a, 1, 1, 22, 15, C.parch)
	for y in 16:
		for x in 24:
			if a.get_pixel(x, y).a > 0:
				a.set_pixel(x, y, C.parch.lerp(C.parch_lo, h(x, y, 21) * 0.5))
	rect(a, 0, 1, 1, 15, C.ink)
	rect(a, 23, 1, 1, 15, C.ink)
	rect(a, 1, 0, 22, 1, C.ink)
	save(a, "tab_selected")
	var b := img(24, 16)
	planks(b, 1, 2, 22, 14, C.tar_hi, 5, 8)
	rect(b, 0, 2, 1, 14, C.out)
	rect(b, 23, 2, 1, 14, C.out)
	rect(b, 1, 1, 22, 1, C.out)
	rect(b, 1, 15, 22, 1, C.out)
	save(b, "tab_unselected")
	var c := img(24, 16)
	planks(c, 1, 2, 22, 14, shade(C.tar_hi, 1.3), 5, 8)
	rect(c, 0, 2, 1, 14, C.out)
	rect(c, 23, 2, 1, 14, C.out)
	rect(c, 1, 1, 22, 1, C.out)
	rect(c, 1, 15, 22, 1, C.out)
	save(c, "tab_hover")


func checks() -> void:
	for on in [false, true]:
		var i := img(12, 12)
		rect(i, 2, 2, 8, 8, C.well)
		frame(i, 1, C.brass)
		rect(i, 1, 1, 10, 1, C.brass_hi)
		frame(i, 0, C.out)
		if on:
			for p in [[3, 6], [4, 7], [5, 8], [6, 7], [7, 6], [8, 5], [8, 4], [4, 6], [5, 7], [6, 6], [7, 5]]:
				i.set_pixel(p[0], p[1], C.teal_hi if p[1] < 6 else C.teal)
		save(i, "check_on" if on else "check_off")


func slider_parts() -> void:
	var t := img(16, 6)
	for y in range(1, 5):
		for x in 16:
			t.set_pixel(x, y, C.rope if (x + y) % 4 < 2 else C.rope_lo)
	rect(t, 0, 0, 16, 1, C.out)
	rect(t, 0, 5, 16, 1, C.out)
	save(t, "rope_track")
	for hl in [false, true]:
		var g := img(10, 12)
		var b: Color = C.brass_hi if hl else C.brass
		rect(g, 1, 1, 8, 10, b)
		rect(g, 1, 1, 8, 1, C.brass_hi)
		rect(g, 1, 10, 8, 1, C.brass_lo)
		rect(g, 4, 3, 2, 6, C.brass_lo)
		frame(g, 0, C.out)
		save(g, "knob_hl" if hl else "knob")
	var d := img(16, 4)
	for x in 16:
		d.set_pixel(x, 1, C.rope if x % 3 != 0 else C.rope_lo)
		d.set_pixel(x, 2, C.rope_lo if x % 3 != 1 else C.rope)
	save(d, "rope_divider")


func misc() -> void:
	var a := img(9, 6)
	for y in 4:
		for x in range(y, 9 - y):
			a.set_pixel(x, y + 1, C.brass if y > 0 else C.brass_hi)
	save(a, "arrow_down")
	var w := img(16, 16)
	rect(w, 2, 2, 12, 12, C.well)
	rect(w, 2, 2, 12, 1, C.well_lo)
	frame(w, 1, C.tar)
	frame(w, 0, C.out)
	save(w, "well")
	var sg := img(8, 16)
	planks(sg, 1, 1, 6, 14, C.plank, 4, 13)
	frame(sg, 0, C.out)
	save(sg, "scroll_grabber")
	var ch := img(11, 11)
	for k in [[5, 0], [5, 1], [5, 9], [5, 10], [0, 5], [1, 5], [9, 5], [10, 5]]:
		ch.set_pixel(k[0], k[1], Color(1, 0.95, 0.85, 0.95))
	ch.set_pixel(5, 5, C.teal_hi)
	for k in [[4, 5], [6, 5], [5, 4], [5, 6]]:
		ch.set_pixel(k[0], k[1], Color(0, 0, 0, 0.45))
	save(ch, "crosshair")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("[ui] generating kit into ", OUT)
	panel_wood()
	panel_parchment()
	plaque()
	button("button", C.plank, false, C.brass)
	button("button_hover", C.plank_hi, false, C.brass_hi)
	button("button_pressed", C.plank_lo, true, C.brass)
	button("button_disabled", Color8(130, 122, 112), false, Color8(120, 110, 100))
	focus_ring()
	slot("slot", false)
	slot("slot_selected", true)
	bars()
	tabs()
	checks()
	slider_parts()
	misc()
	quit()
