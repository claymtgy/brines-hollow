class_name ItemIcons
extends RefCounted
## Procedural pixel-art icons (16x16 art, shown at 3x) so slots show pictures, not words.
## Voxel materials become little isometric blocks in their palette colour; everything
## else gets a sprite chosen from its id / tags / category, tinted per item.
##   ItemIcons.for_item(&"wood_plank")   ItemIcons.for_tool(ItemIcons.Tool.PICKAXE)

enum Tool { PICKAXE, HAMMER, BLUEPRINT, ROD, HOE, CUTLASS, HARPOON, AXE, SHOVEL }

const N := 16
const OUTLINE := Color8(30, 20, 15)
const HANDLE := Color8(140, 98, 62)
const HANDLE_LO := Color8(98, 66, 42)
const METAL := Color8(188, 196, 204)
const METAL_LO := Color8(120, 128, 140)
const BRASS := Color8(214, 168, 80)
const PARCH := Color8(236, 222, 186)
const INK := Color8(70, 96, 150)

static var _cache := {}


static func for_item(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	ItemDB.init_db()
	var def: ItemDef = ItemDB.get_item(id)
	var tex := _finish(_draw_item(def, id))
	_cache[id] = tex
	return tex


static func for_tool(t: int) -> Texture2D:
	var key := "tool_%d" % t
	if _cache.has(key):
		return _cache[key]
	var tex := _finish(_draw_tool(t))
	_cache[key] = tex
	return tex


static func for_material(m: int) -> Texture2D:
	var key := "mat_%d" % m
	if _cache.has(key):
		return _cache[key]
	var tex := _finish(_cube(Palette.COLORS[m] if m < Palette.COLORS.size() else Color.MAGENTA))
	_cache[key] = tex
	return tex


# ---------------------------------------------------------------- drawing

static func _img() -> Image:
	var i := Image.create(N, N, false, Image.FORMAT_RGBA8)
	i.fill(Color(0, 0, 0, 0))
	return i


static func _px(i: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < N and y < N:
		i.set_pixel(x, y, c)


static func _line(i: Image, a: Vector2i, b: Vector2i, c: Color, thick := 1) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for s in steps + 1:
		var t := float(s) / maxf(1.0, steps)
		var p := Vector2(a).lerp(Vector2(b), t).round()
		for dy in thick:
			for dx in thick:
				_px(i, int(p.x) + dx, int(p.y) + dy, c)


static func _rect(i: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(i, x, y, c)


static func _ellipse(i: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in N:
		for x in N:
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(i, x, y, c)


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)


## Dark outline around every opaque shape + a soft drop shadow, then 3x nearest upscale.
static func _finish(i: Image) -> Texture2D:
	var o := _img()
	for y in N:
		for x in N:
			if i.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N and i.get_pixel(q.x, q.y).a > 0.0:
					o.set_pixel(x, y, OUTLINE)
					break
	for y in N:
		for x in N:
			var c := i.get_pixel(x, y)
			if c.a > 0.0:
				o.set_pixel(x, y, c)
	o.resize(N * UiTheme.PX, N * UiTheme.PX, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(o)


static func _hue(id: StringName) -> Color:
	var h := absi(hash(String(id))) % 360
	return Color.from_hsv(h / 360.0, 0.45, 0.85)


## Isometric voxel block (top lit, left mid, right shade).
static func _cube(c: Color) -> Image:
	var i := _img()
	var top := [Vector2(8, 1), Vector2(15, 4.5), Vector2(8, 8), Vector2(1, 4.5)]
	var left := [Vector2(1, 4.5), Vector2(8, 8), Vector2(8, 15), Vector2(1, 11.5)]
	var right := [Vector2(8, 8), Vector2(15, 4.5), Vector2(15, 11.5), Vector2(8, 15)]
	for y in N:
		for x in N:
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, PackedVector2Array(top)):
				_px(i, x, y, _shade(c, 1.18))
			elif Geometry2D.is_point_in_polygon(p, PackedVector2Array(left)):
				_px(i, x, y, _shade(c, 0.92))
			elif Geometry2D.is_point_in_polygon(p, PackedVector2Array(right)):
				_px(i, x, y, _shade(c, 0.68))
	_line(i, Vector2i(8, 8), Vector2i(8, 14), _shade(c, 0.55))
	return i


static func _draw_tool(t: int) -> Image:
	var i := _img()
	match t:
		Tool.PICKAXE:
			_line(i, Vector2i(3, 13), Vector2i(10, 6), HANDLE, 2)
			_line(i, Vector2i(5, 3), Vector2i(9, 4), METAL, 2)
			_line(i, Vector2i(9, 4), Vector2i(13, 8), METAL, 2)
			_line(i, Vector2i(13, 8), Vector2i(13, 11), METAL_LO)
			_line(i, Vector2i(5, 3), Vector2i(3, 4), METAL_LO)
		Tool.HAMMER:
			_line(i, Vector2i(3, 13), Vector2i(9, 7), HANDLE, 2)
			_rect(i, 8, 2, 6, 4, METAL)
			_rect(i, 8, 5, 6, 1, METAL_LO)
			_rect(i, 13, 2, 1, 4, METAL_LO)
		Tool.BLUEPRINT:
			_rect(i, 3, 3, 10, 10, Color8(96, 140, 190))
			for y in [5, 8, 11]:
				_line(i, Vector2i(4, y), Vector2i(11, y), Color8(214, 232, 248))
			_line(i, Vector2i(7, 4), Vector2i(7, 12), Color8(214, 232, 248))
			_rect(i, 2, 2, 12, 1, PARCH)
			_rect(i, 2, 13, 12, 1, PARCH)
		Tool.ROD:
			_line(i, Vector2i(2, 14), Vector2i(13, 2), HANDLE)
			_line(i, Vector2i(2, 14), Vector2i(5, 11), HANDLE_LO, 2)
			_line(i, Vector2i(13, 2), Vector2i(13, 10), Color8(230, 230, 220))
			_px(i, 13, 11, Color8(236, 124, 52))
			_ellipse(i, 6, 11, 1.6, 1.6, BRASS)
		Tool.HOE:
			_line(i, Vector2i(3, 13), Vector2i(10, 4), HANDLE, 2)
			_line(i, Vector2i(10, 3), Vector2i(13, 5), METAL, 2)
			_line(i, Vector2i(13, 5), Vector2i(13, 8), METAL_LO, 2)
		Tool.CUTLASS:
			_line(i, Vector2i(4, 12), Vector2i(12, 3), METAL, 2)
			_line(i, Vector2i(2, 11), Vector2i(6, 14), BRASS, 1)
			_line(i, Vector2i(2, 14), Vector2i(4, 12), HANDLE, 2)
		Tool.HARPOON:
			_line(i, Vector2i(2, 14), Vector2i(12, 4), HANDLE)
			_line(i, Vector2i(12, 4), Vector2i(14, 2), METAL, 2)
			_px(i, 11, 3, METAL)
			_px(i, 13, 5, METAL)
		Tool.AXE:
			_line(i, Vector2i(3, 13), Vector2i(11, 5), HANDLE, 2)
			_rect(i, 8, 2, 5, 5, METAL)
			_line(i, Vector2i(12, 2), Vector2i(14, 6), METAL, 2)
			_line(i, Vector2i(13, 3), Vector2i(14, 7), METAL_LO)
		Tool.SHOVEL:
			_line(i, Vector2i(3, 13), Vector2i(9, 7), HANDLE, 2)
			_ellipse(i, 11.5, 4.5, 3.2, 3.2, METAL)
			_line(i, Vector2i(9, 6), Vector2i(13, 2), METAL_LO)
	return i


static func _tool_tier_img(base_img: Image, s: String) -> Image:
	var head_hi := METAL
	var head_lo := METAL_LO
	if "driftwood" in s or "wood" in s:
		head_hi = Color8(184, 152, 114)
		head_lo = Color8(136, 106, 76)
	elif "stone" in s:
		head_hi = Color8(146, 138, 134)
		head_lo = Color8(102, 94, 92)
	elif "copper" in s or "brass" in s:
		head_hi = Color8(224, 144, 82)
		head_lo = Color8(168, 96, 48)
	else:
		return base_img
	for y in N:
		for x in N:
			var c := base_img.get_pixel(x, y)
			if c.is_equal_approx(METAL):
				base_img.set_pixel(x, y, head_hi)
			elif c.is_equal_approx(METAL_LO):
				base_img.set_pixel(x, y, head_lo)
	return base_img


static func _draw_item(def: ItemDef, id: StringName) -> Image:
	if def == null:
		return _crate()
	if def.voxel_mat >= 0:
		return _cube(Palette.COLORS[def.voxel_mat])
	var s := String(id)
	var tint := _hue(id)
	if "pickaxe" in s: return _tool_tier_img(_draw_tool(Tool.PICKAXE), s)
	if "axe" in s or "hatchet" in s: return _tool_tier_img(_draw_tool(Tool.AXE), s)
	if "shovel" in s: return _tool_tier_img(_draw_tool(Tool.SHOVEL), s)
	if "hammer" in s or "mallet" in s or "maul" in s: return _draw_tool(Tool.HAMMER)
	if "rod" in s: return _draw_tool(Tool.ROD)
	if "hoe" in s: return _tool_tier_img(_draw_tool(Tool.HOE), s)
	if "cutlass" in s or "sword" in s or "knife" in s: return _draw_tool(Tool.CUTLASS)
	if "harpoon" in s or "spear" in s: return _draw_tool(Tool.HARPOON)
	if "seed" in s: return _seed_pouch(tint)
	if "sapling" in s: return _sapling()
	if "chart" in s or "map" in s or def.category == ItemDef.Category.BLUEPRINT: return _chart()
	if def.has_tag("fish") or "fish" in s or "mackerel" in s or "cod" in s or "salmon" in s or "flounder" in s: return _fish(tint)
	if "crab" in s or "oyster" in s or "clam" in s or "mussel" in s: return _shell(tint)
	if "brass" in s or "scrip" in s or "coin" in s: return _coin()
	if "pack" in s or "sack" in s or "bag" in s: return _bag(tint)
	match def.category:
		ItemDef.Category.FOOD: return _bowl(tint)
		ItemDef.Category.EQUIPMENT: return _garment(tint)
		ItemDef.Category.TOOL: return _draw_tool(Tool.PICKAXE)
	return _crate()


static func _crate() -> Image:
	var i := _img()
	_rect(i, 2, 4, 12, 10, Color8(166, 126, 86))
	for y in [4, 8, 13]:
		_rect(i, 2, y, 12, 1, Color8(110, 78, 52))
	_line(i, Vector2i(2, 4), Vector2i(13, 13), Color8(120, 86, 56))
	return i


static func _seed_pouch(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8, 10, 5.5, 4.5, Color8(196, 170, 124))
	_rect(i, 6, 3, 4, 3, Color8(176, 150, 108))
	_rect(i, 5, 5, 6, 1, Color8(120, 90, 60))
	for p in [Vector2i(6, 9), Vector2i(9, 10), Vector2i(7, 12), Vector2i(10, 8)]:
		_px(i, p.x, p.y, _shade(c, 0.7))
	return i


static func _fish(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 7, 8, 5.5, 3.2, c)
	_ellipse(i, 7, 9, 4.5, 1.6, _shade(c, 1.2))
	for p in [Vector2i(12, 8), Vector2i(13, 7), Vector2i(13, 9), Vector2i(14, 6), Vector2i(14, 10), Vector2i(14, 8)]:
		_px(i, p.x, p.y, _shade(c, 0.8))
	_px(i, 4, 7, OUTLINE)
	return i


static func _shell(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8, 9, 6, 4.5, _shade(c, 0.9))
	for x in [4, 6, 8, 10, 12]:
		_line(i, Vector2i(8, 13), Vector2i(x, 5), _shade(c, 0.7))
	return i


static func _bowl(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8, 8, 6, 2.2, _shade(c, 1.05))
	for y in range(8, 13):
		var w := 6 - (y - 8)
		_rect(i, 8 - w, y, w * 2, 1, Color8(150, 104, 66) if y > 8 else _shade(c, 0.9))
	_px(i, 6, 4, Color(1, 1, 1, 0.6))
	_px(i, 9, 3, Color(1, 1, 1, 0.5))
	return i


static func _chart() -> Image:
	var i := _img()
	_rect(i, 2, 3, 12, 10, PARCH)
	_line(i, Vector2i(3, 9), Vector2i(7, 6), INK)
	_line(i, Vector2i(7, 6), Vector2i(12, 8), INK)
	_px(i, 10, 5, Color8(200, 60, 50))
	_rect(i, 1, 3, 1, 10, Color8(200, 180, 140))
	_rect(i, 14, 3, 1, 10, Color8(200, 180, 140))
	return i


static func _coin() -> Image:
	var i := _img()
	_ellipse(i, 8, 8, 5.5, 5.5, BRASS)
	_ellipse(i, 8, 8, 3.5, 3.5, _shade(BRASS, 1.15))
	_rect(i, 7, 6, 2, 4, _shade(BRASS, 0.7))
	return i


static func _bag(c: Color) -> Image:
	var i := _img()
	_rect(i, 3, 5, 10, 9, _shade(c, 0.75))
	_rect(i, 3, 5, 10, 3, _shade(c, 0.9))
	_rect(i, 6, 2, 4, 3, HANDLE)
	_px(i, 8, 9, BRASS)
	return i


static func _garment(c: Color) -> Image:
	var i := _img()
	_rect(i, 4, 4, 8, 10, c)
	_rect(i, 2, 4, 2, 5, c)
	_rect(i, 12, 4, 2, 5, c)
	_rect(i, 6, 3, 4, 2, _shade(c, 0.7))
	_line(i, Vector2i(8, 5), Vector2i(8, 13), _shade(c, 0.75))
	return i


# ---------------------------------------------------------------- HUD glyphs

## Small pixel glyphs for the HUD (no emoji: the bundled font has none).
## Names: sun, moon, dawn, tide_up, tide_down, clear, cloud, rain, storm, fog, heart,
##        stamina, breath, food, crew, wind
static func hud_icon(name: String) -> Texture2D:
	var key := "hud_" + name
	if _cache.has(key):
		return _cache[key]
	var i := _img()
	var sun := Color8(250, 204, 92)
	var cloud := Color8(226, 232, 236)
	var cloud_dk := Color8(150, 160, 172)
	var water := Color8(96, 196, 206)
	match name:
		"sun", "clear":
			_ellipse(i, 8, 8, 3.6, 3.6, sun)
			for d: Vector2i in [Vector2i(0, -6), Vector2i(0, 6), Vector2i(-6, 0), Vector2i(6, 0), Vector2i(-4, -4), Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4)]:
				_px(i, 8 + d.x, 8 + d.y, sun)
		"moon":
			_ellipse(i, 8, 8, 5, 5, Color8(232, 236, 250))
			_ellipse(i, 10.5, 6.5, 4.2, 4.2, Color(0, 0, 0, 0))
			for y in N:
				for x in N:
					var dx := x + 0.5 - 10.5
					var dy := y + 0.5 - 6.5
					if dx * dx + dy * dy <= 17.0:
						i.set_pixel(x, y, Color(0, 0, 0, 0))
		"dawn":
			_ellipse(i, 8, 11, 4.5, 4.5, Color8(246, 160, 96))
			_rect(i, 0, 11, N, 5, Color(0, 0, 0, 0))
			_rect(i, 1, 11, 14, 1, water)
			_rect(i, 3, 13, 10, 1, water)
		"tide_up", "tide_down":
			for x in N:
				var y := 10 + int(round(sin(x * 0.8) * 1.2))
				_rect(i, x, y, 1, N - y, water)
				_px(i, x, y, Color8(220, 246, 246))
			var up := name == "tide_up"
			var ay := 2 if up else 6
			for k in 3:
				_rect(i, 8 - k, ay + (k if up else 2 - k), 1 + k * 2, 1, Color8(250, 240, 210))
		"cloud":
			_ellipse(i, 6, 9, 4, 3, cloud)
			_ellipse(i, 10, 8, 4.5, 3.5, cloud)
			_rect(i, 3, 11, 11, 1, cloud_dk)
		"rain", "storm":
			_ellipse(i, 6, 6, 4, 3, cloud_dk if name == "storm" else cloud)
			_ellipse(i, 10, 5, 4.5, 3.5, cloud_dk if name == "storm" else cloud)
			for p: Vector2i in [Vector2i(4, 11), Vector2i(8, 12), Vector2i(12, 11), Vector2i(6, 14), Vector2i(10, 14)]:
				_px(i, p.x, p.y, water)
			if name == "storm":
				_line(i, Vector2i(9, 9), Vector2i(7, 12), sun)
				_line(i, Vector2i(7, 12), Vector2i(9, 12), sun)
				_line(i, Vector2i(9, 12), Vector2i(7, 15), sun)
		"fog":
			for y in [5, 8, 11]:
				_line(i, Vector2i(2 + (y % 3), y), Vector2i(13 - (y % 2), y), cloud)
		"wind":
			_line(i, Vector2i(2, 6), Vector2i(11, 6), cloud)
			_px(i, 12, 5, cloud)
			_line(i, Vector2i(2, 10), Vector2i(13, 10), cloud)
			_px(i, 14, 11, cloud)
		"heart":
			_ellipse(i, 5.5, 6.5, 3, 3, Color8(226, 84, 74))
			_ellipse(i, 10.5, 6.5, 3, 3, Color8(226, 84, 74))
			for y in range(7, 14):
				var w := 14 - y
				_rect(i, 8 - w, y, w * 2, 1, Color8(226, 84, 74))
			_px(i, 5, 5, Color8(255, 190, 180))
		"stamina":
			for p: Array in [[9, 1, 6, 6], [7, 6, 5, 2], [5, 8, 6, 7]]:
				_line(i, Vector2i(p[0], p[1]), Vector2i(p[2], p[3]), Color8(246, 206, 82), 2)
		"breath":
			_ellipse(i, 6, 10, 3, 3, Color8(170, 230, 240))
			_ellipse(i, 11, 5, 2.2, 2.2, Color8(170, 230, 240))
			_px(i, 5, 9, Color8(255, 255, 255))
			_px(i, 10, 4, Color8(255, 255, 255))
		"food":
			return _finish_cache(key, _bowl(Color8(236, 180, 96)))
		"crew":
			_ellipse(i, 5, 5, 2.5, 2.5, Color8(240, 200, 160))
			_rect(i, 2, 8, 6, 6, Color8(244, 196, 66))
			_ellipse(i, 11, 5, 2.5, 2.5, Color8(240, 200, 160))
			_rect(i, 8, 8, 6, 6, Color8(72, 132, 150))
	return _finish_cache(key, i)


static func _finish_cache(key: String, i: Image) -> Texture2D:
	var t := _finish(i)
	_cache[key] = t
	return t


static func _sapling() -> Image:
	var i := _img()
	var dirt := Color8(116, 82, 54)
	var trunk := Color8(138, 96, 58)
	var needle_dk := Color8(48, 118, 66)
	var needle_hi := Color8(86, 168, 88)
	_rect(i, 5, 13, 6, 2, dirt)
	_rect(i, 7, 8, 2, 5, trunk)
	_rect(i, 4, 8, 8, 2, needle_dk)
	_rect(i, 5, 5, 6, 3, needle_hi)
	_rect(i, 6, 3, 4, 2, needle_dk)
	_rect(i, 7, 1, 2, 2, needle_hi)
	return i
