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

	# 1. Exact Item ID Matches (High Priority)
	match id:
		&"sea_iron_ore": return _ore(Color8(185, 75, 55))
		&"copper_ore": return _ore(Color8(225, 130, 60))
		&"calamine_ore": return _ore(Color8(210, 205, 120))
		&"phosphor_cluster": return _ore(Color8(60, 240, 205))
		&"iron_ingot": return _ingot(Color8(195, 205, 215))
		&"sea_brass_ingot": return _ingot(Color8(235, 180, 65))
		&"spring_water": return _flask(Color(0.30, 0.65, 0.85))
		&"fish_oil": return _flask(Color8(245, 185, 45))
		&"salt_milk": return _flask(Color8(248, 248, 242))
		&"sea_egg": return _egg()
		&"sea_wool": return _wool()
		&"down_feather": return _feather()
		&"goat_cheese": return _cheese(false)
		&"aged_brine_cheese": return _cheese(true)
		&"sea_salt": return _salt()
		&"wheat_flour": return _flour()
		&"marsh_honey": return _honey()
		&"beeswax": return _beeswax()
		&"exotic_spice": return _spice()
		&"dye_indigo": return _dye()
		&"shearing_shears": return _shears()
		&"wooden_bucket": return _bucket()
		&"animal_whistle": return _whistle()
		&"masons_chisel": return _chisel()
		&"sovereign_trident": return _trident()
		&"anchor_maul": return _anchor_maul()
		&"hulk_pearl": return _gem_pearl(Color8(240, 245, 255), Color8(180, 220, 255))
		&"abyssal_pearl": return _gem_pearl(Color8(45, 35, 60), Color8(110, 70, 160))
		&"siren_heart": return _siren_heart()
		&"chitin_plate": return _chitin_shell(Color8(140, 95, 75))
		&"abyssal_chitin": return _chitin_shell(Color8(55, 45, 80))
		&"caldera_basalt_plate": return _chitin_shell(Color8(80, 50, 45))
		&"geothermal_core": return _elemental_core(Color8(245, 100, 30))
		&"deluge_core": return _elemental_core(Color8(50, 160, 240))
		&"glacial_tusk": return _tusk()
		&"borean_fur": return _fabric_bolt(Color8(220, 225, 230))
		&"silk_bolt": return _fabric_bolt(Color8(160, 80, 180))
		&"gloom_gland": return _cube(Palette.COLORS[Palette.GLOW_TEAL])
		&"ancient_weapon_fragment": return _broken_blade()
		&"reaver_crest": return _crest(Color8(160, 60, 45))
		&"undertow_crest": return _crest(Color8(70, 150, 190))
		&"gilded_ship_wheel": return _crest(BRASS)
		&"angler_lure": return _lure()
		&"brass_guilder", &"tide_scrip": return _coin()
		&"scented_candle": return _candle()

	# 2. Tools & Weapons
	if "pickaxe" in s: return _tool_tier_img(_draw_tool(Tool.PICKAXE), s)
	if "axe" in s or "hatchet" in s: return _tool_tier_img(_draw_tool(Tool.AXE), s)
	if "shovel" in s: return _tool_tier_img(_draw_tool(Tool.SHOVEL), s)
	if "hammer" in s or "mallet" in s: return _draw_tool(Tool.HAMMER)
	if "hoe" in s: return _tool_tier_img(_draw_tool(Tool.HOE), s)
	if "rod" in s: return _draw_tool(Tool.ROD)
	if "cutlass" in s or "sabre" in s or "sword" in s: return _draw_tool(Tool.CUTLASS)
	if "lance" in s or "harpoon" in s or "spear" in s: return _draw_tool(Tool.HARPOON)
	if "speargun" in s or "net_launcher" in s: return _speargun()
	if "trapper_net" in s or "net" in s: return _net()
	if "staff" in s: return _staff()

	# 3. Placeables / Workstations / Furniture
	if Placeables.BUILTIN.has(id) or def.has_tag("placeable") or def.has_tag("boat_fixture"):
		return _workstation(id)

	# 4. Boats & Boat Kits
	if "skiff" in s or "boat" in s or "barge" in s or "sloop" in s or "schooner" in s:
		return _boat_icon()

	# 5. Seeds & Saplings
	if "seed" in s: return _seed_pouch(tint)
	if "sapling" in s: return _sapling()

	# 6. Charts / Maps / Blueprints
	if "chart" in s or "map" in s or def.category == ItemDef.Category.BLUEPRINT:
		return _chart()

	# 7. Food & Provisions
	if "bread" in s or "hardtack" in s:
		return _bread(s)
	if "ale" in s or "stout" in s or "tea" in s or "brew" in s:
		return _drink(s)
	if "smoked" in s or "roasted" in s:
		return _cooked_meal(s)
	if def.has_tag("crop") or "potato" in s or "samphire" in s or "kale" in s or "wheat" in s or "rye" in s:
		return _veggie(s)
	if def.has_tag("fish") or "mackerel" in s or "salmon" in s or "flounder" in s or "eel" in s or "squid" in s or "ray" in s:
		return _fish(tint)
	if def.has_tag("shellfish") or "crab" in s or "oyster" in s or "clam" in s or "mussel" in s:
		return _shell(tint)

	# 8. Diving gear & Armor
	if "helmet" in s or "rebreather" in s:
		return _diving_helmet()
	if "souwester" in s:
		return _souwester()
	if "boots" in s or "waders" in s or "flippers" in s:
		return _boots(s)

	# 9. Bags & Packs
	if "pack" in s or "sack" in s or "bag" in s or "haversack" in s:
		return _bag(tint)

	# 10. Fallbacks
	match def.category:
		ItemDef.Category.FOOD: return _bowl(tint)
		ItemDef.Category.EQUIPMENT: return _garment(tint)
		ItemDef.Category.TOOL: return _draw_tool(Tool.PICKAXE)
	return _crate()


## A corked glass flask / bottle (16x16 bounds).
static func _flask(liquid: Color = Color(0.30, 0.62, 0.82), cork: Color = Color8(150, 105, 65)) -> Image:
	var i := _img()
	var glass := Color(0.68, 0.84, 0.90, 0.85)
	_rect(i, 7, 2, 2, 2, cork)
	_rect(i, 7, 4, 2, 3, glass)
	_ellipse(i, 8.0, 10.5, 4.6, 4.2, glass)
	_ellipse(i, 8.0, 11.2, 3.6, 3.0, liquid)
	_px(i, 6, 8, Color(1, 1, 1, 0.85))
	_px(i, 6, 9, Color(1, 1, 1, 0.5))
	return i


static func _ore(tint: Color, rock: Color = Color8(105, 100, 95)) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 9.0, 5.5, 4.5, rock)
	_rect(i, 4, 11, 8, 2, _shade(rock, 0.7))
	_rect(i, 8, 6, 4, 3, tint)
	_rect(i, 5, 8, 3, 3, _shade(tint, 0.85))
	_rect(i, 7, 9, 4, 3, _shade(tint, 1.15))
	_px(i, 9, 6, Color.WHITE)
	_px(i, 6, 8, Color.WHITE)
	return i


static func _ingot(tint: Color) -> Image:
	var i := _img()
	for y in range(4, 8):
		var w := 6 + (y - 4) * 2
		_rect(i, 8 - w / 2, y, w, 1, _shade(tint, 1.25))
	_rect(i, 5, 4, 6, 1, _shade(tint, 1.5))
	for y in range(8, 12):
		_rect(i, 3, y, 10, 1, _shade(tint, 1.0 - (y - 8) * 0.12))
	_line(i, Vector2i(5, 5), Vector2i(8, 5), Color.WHITE)
	return i


static func _egg() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.5, 4.2, 5.2, Color8(238, 230, 212))
	_ellipse(i, 8.0, 10.5, 3.6, 3.0, Color8(208, 196, 174))
	_ellipse(i, 7.0, 6.5, 2.0, 2.4, Color8(255, 252, 245))
	_px(i, 6, 9, Color8(180, 162, 140))
	_px(i, 9, 10, Color8(180, 162, 140))
	_px(i, 10, 7, Color8(180, 162, 140))
	return i


static func _wool() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 9.0, 5.5, 4.5, Color8(200, 206, 212))
	_ellipse(i, 6.0, 7.0, 2.8, 2.8, Color8(245, 248, 250))
	_ellipse(i, 10.0, 7.0, 2.8, 2.8, Color8(245, 248, 250))
	_ellipse(i, 8.0, 6.0, 3.0, 3.0, Color8(255, 255, 255))
	_ellipse(i, 5.0, 10.0, 2.5, 2.5, Color8(232, 238, 242))
	_ellipse(i, 11.0, 10.0, 2.5, 2.5, Color8(232, 238, 242))
	_ellipse(i, 8.0, 10.0, 3.0, 2.5, Color8(245, 248, 250))
	return i


static func _feather() -> Image:
	var i := _img()
	_line(i, Vector2i(3, 13), Vector2i(13, 3), Color8(225, 220, 205))
	for t in range(4, 12):
		var x := t
		var y := 16 - t
		_line(i, Vector2i(x, y), Vector2i(x - 2, y - 2), Color8(235, 242, 248))
		_line(i, Vector2i(x, y), Vector2i(x + 2, y + 2), Color8(210, 225, 235))
	_px(i, 13, 3, Color8(250, 252, 255))
	return i


static func _cheese(aged: bool = false) -> Image:
	var i := _img()
	var base := Color8(245, 195, 55) if not aged else Color8(225, 140, 35)
	for y in range(8, 12):
		_rect(i, 3, y, 10, 1, _shade(base, 0.75 + (12 - y) * 0.05))
	for y in range(4, 8):
		var w := 4 + (8 - y) * 2
		_rect(i, 8 - w / 2, y, w, 1, _shade(base, 1.15))
	_px(i, 5, 9, _shade(base, 0.55))
	_px(i, 9, 8, _shade(base, 0.55))
	_px(i, 7, 10, _shade(base, 0.55))
	_rect(i, 12, 5, 1, 7, Color8(180, 95, 25))
	return i


static func _bread(type: String) -> Image:
	var i := _img()
	if "hardtack" in type:
		_rect(i, 3, 3, 10, 10, Color8(210, 185, 140))
		_rect(i, 4, 4, 8, 8, Color8(225, 200, 155))
		for py in [5, 8, 11]:
			for px in [5, 8, 11]:
				_px(i, px, py, Color8(145, 115, 75))
		return i
	_ellipse(i, 8.0, 9.5, 6.0, 4.0, Color8(145, 90, 45))
	_ellipse(i, 8.0, 8.5, 5.0, 3.2, Color8(185, 125, 65))
	_line(i, Vector2i(6, 6), Vector2i(7, 9), Color8(230, 190, 140))
	_line(i, Vector2i(9, 6), Vector2i(10, 9), Color8(230, 190, 140))
	return i


static func _veggie(type: String) -> Image:
	var i := _img()
	if "potato" in type:
		_ellipse(i, 8.0, 9.0, 5.2, 4.0, Color8(165, 122, 75))
		_ellipse(i, 7.5, 8.0, 3.5, 2.5, Color8(195, 150, 98))
		_px(i, 5, 8, Color8(115, 80, 45))
		_px(i, 10, 10, Color8(115, 80, 45))
		_px(i, 8, 11, Color8(115, 80, 45))
		return i
	if "samphire" in type:
		_line(i, Vector2i(8, 13), Vector2i(8, 4), Color8(55, 155, 65), 2)
		_line(i, Vector2i(7, 9), Vector2i(4, 7), Color8(75, 180, 85))
		_line(i, Vector2i(9, 8), Vector2i(12, 6), Color8(75, 180, 85))
		_px(i, 8, 3, Color8(130, 220, 105))
		_px(i, 4, 6, Color8(130, 220, 105))
		_px(i, 12, 5, Color8(130, 220, 105))
		return i
	if "kale" in type:
		_ellipse(i, 8.0, 9.0, 5.2, 4.5, Color8(35, 120, 70))
		_ellipse(i, 8.0, 8.0, 4.0, 3.5, Color8(55, 160, 95))
		_line(i, Vector2i(8, 13), Vector2i(8, 6), Color8(170, 215, 160))
		return i
	# Wheat / Rye grain sheaf
	_line(i, Vector2i(8, 14), Vector2i(8, 8), Color8(175, 135, 55))
	_rect(i, 6, 9, 4, 1, Color8(150, 65, 35))
	_ellipse(i, 8.0, 6.0, 3.5, 4.0, Color8(235, 195, 75))
	_px(i, 7, 2, Color8(250, 220, 110))
	_px(i, 9, 2, Color8(250, 220, 110))
	return i


static func _shears() -> Image:
	var i := _img()
	_line(i, Vector2i(3, 3), Vector2i(12, 12), METAL, 1)
	_line(i, Vector2i(12, 3), Vector2i(3, 12), METAL, 1)
	_px(i, 7, 7, BRASS)
	_px(i, 8, 8, BRASS)
	_rect(i, 2, 11, 3, 3, HANDLE)
	_px(i, 3, 12, Color(0, 0, 0, 0))
	_rect(i, 11, 11, 3, 3, HANDLE)
	_px(i, 12, 12, Color(0, 0, 0, 0))
	return i


static func _bucket() -> Image:
	var i := _img()
	for y in range(6, 13):
		var w := 8 + (6 - absi(y - 9)) / 2
		_rect(i, 8 - w / 2, y, w, 1, HANDLE)
	_rect(i, 4, 7, 8, 1, METAL_LO)
	_rect(i, 4, 11, 8, 1, METAL_LO)
	_rect(i, 5, 6, 6, 1, Color8(70, 160, 220))
	_line(i, Vector2i(4, 6), Vector2i(7, 3), METAL)
	_line(i, Vector2i(7, 3), Vector2i(11, 6), METAL)
	return i


static func _whistle() -> Image:
	var i := _img()
	_rect(i, 4, 7, 7, 5, BRASS)
	_rect(i, 11, 8, 3, 3, _shade(BRASS, 1.2))
	_px(i, 9, 7, Color8(50, 35, 20))
	_rect(i, 2, 8, 2, 3, _shade(BRASS, 0.8))
	_px(i, 2, 9, Color(0, 0, 0, 0))
	return i


static func _salt() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 10.0, 5.0, 3.5, Color8(210, 225, 235))
	_ellipse(i, 8.0, 9.0, 4.0, 2.5, Color8(245, 248, 252))
	_px(i, 8, 6, Color.WHITE)
	_px(i, 6, 8, Color.WHITE)
	_px(i, 10, 9, Color.WHITE)
	return i


static func _flour() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 10.0, 5.0, 4.0, Color8(215, 200, 175))
	_rect(i, 6, 4, 4, 3, Color8(195, 175, 145))
	_rect(i, 5, 6, 6, 1, Color8(130, 95, 60))
	_ellipse(i, 8.0, 9.0, 3.0, 2.0, Color8(250, 250, 245))
	return i


static func _honey() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 9.5, 4.8, 4.5, Color8(180, 110, 60))
	_rect(i, 6, 4, 4, 2, Color8(140, 80, 40))
	_ellipse(i, 8.0, 9.0, 3.2, 3.0, Color8(250, 185, 40))
	_line(i, Vector2i(7, 10), Vector2i(7, 13), Color8(250, 185, 40), 2)
	_px(i, 7, 14, Color8(250, 185, 40))
	return i


static func _beeswax() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.5, 5.5, 4.5, Color8(240, 190, 50))
	_rect(i, 4, 9, 8, 3, Color8(200, 150, 35))
	_line(i, Vector2i(6, 6), Vector2i(10, 6), Color8(255, 225, 90))
	_px(i, 7, 8, Color8(200, 140, 30))
	_px(i, 9, 8, Color8(200, 140, 30))
	return i


static func _spice() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 10.0, 5.5, 3.5, Color8(140, 90, 55))
	_ellipse(i, 8.0, 8.5, 4.5, 3.0, Color8(215, 60, 40))
	_px(i, 8, 6, Color8(245, 140, 50))
	_px(i, 7, 7, Color8(245, 140, 50))
	return i


static func _dye() -> Image:
	var i := _img()
	_rect(i, 4, 5, 8, 8, Color8(35, 55, 130))
	_rect(i, 5, 3, 6, 2, Color8(130, 90, 60))
	_rect(i, 5, 6, 6, 3, Color8(55, 85, 185))
	_px(i, 6, 7, Color8(110, 145, 235))
	return i


static func _cooked_meal(type: String) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 9.0, 5.8, 3.2, Color8(210, 125, 55))
	_ellipse(i, 8.0, 8.5, 4.8, 2.2, Color8(235, 155, 80))
	_line(i, Vector2i(6, 7), Vector2i(7, 11), Color8(100, 48, 20))
	_line(i, Vector2i(9, 7), Vector2i(10, 11), Color8(100, 48, 20))
	_px(i, 11, 8, Color8(110, 200, 80))
	return i


static func _drink(type: String) -> Image:
	var i := _img()
	if "ale" in type or "stout" in type:
		_rect(i, 5, 6, 6, 7, Color8(120, 75, 40))
		_rect(i, 11, 7, 2, 4, Color8(100, 60, 30))
		_px(i, 11, 8, Color(0, 0, 0, 0))
		_ellipse(i, 8.0, 5.2, 3.6, 2.0, Color8(250, 245, 225))
		_px(i, 6, 6, Color8(250, 245, 225))
		return i
	_ellipse(i, 8.0, 9.5, 4.5, 3.5, Color8(220, 225, 228))
	_ellipse(i, 8.0, 8.5, 3.5, 1.8, Color8(90, 150, 80) if "tea" in type else Color8(110, 65, 35))
	_px(i, 7, 4, Color(1, 1, 1, 0.6))
	_px(i, 9, 3, Color(1, 1, 1, 0.6))
	return i


static func _gem_pearl(pearl_color: Color, glow: Color) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.0, 5.5, 5.5, glow)
	_ellipse(i, 8.0, 8.0, 4.0, 4.0, pearl_color)
	_ellipse(i, 7.0, 6.5, 1.8, 1.8, Color.WHITE)
	return i


static func _siren_heart() -> Image:
	var i := _img()
	_ellipse(i, 6.0, 7.0, 3.2, 3.2, Color8(235, 40, 100))
	_ellipse(i, 10.0, 7.0, 3.2, 3.2, Color8(235, 40, 100))
	for y in range(7, 14):
		var w := 14 - y
		_rect(i, 8 - w, y, w * 2, 1, Color8(200, 20, 80))
	_px(i, 6, 6, Color8(255, 170, 210))
	return i


static func _chitin_shell(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.5, 5.5, 4.5, c)
	for y in [6, 8, 10]:
		_line(i, Vector2i(4, y), Vector2i(12, y), _shade(c, 0.7))
	_ellipse(i, 8.0, 7.5, 3.5, 2.5, _shade(c, 1.25))
	return i


static func _elemental_core(glow: Color) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.0, 5.5, 5.5, glow)
	_ellipse(i, 8.0, 8.0, 3.5, 3.5, Color8(255, 255, 255))
	_line(i, Vector2i(5, 5), Vector2i(11, 11), _shade(glow, 1.3), 1)
	_line(i, Vector2i(11, 5), Vector2i(5, 11), _shade(glow, 0.8), 1)
	return i


static func _tusk() -> Image:
	var i := _img()
	_line(i, Vector2i(4, 13), Vector2i(12, 4), Color8(240, 235, 220), 2)
	_px(i, 13, 3, Color8(255, 252, 245))
	_px(i, 3, 14, Color8(170, 150, 130))
	return i


static func _fabric_bolt(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.5, 5.5, 3.8, c)
	_rect(i, 3, 8, 10, 3, _shade(c, 0.8))
	_rect(i, 7, 6, 2, 6, Color8(240, 200, 80))
	return i


static func _broken_blade() -> Image:
	var i := _img()
	_line(i, Vector2i(4, 12), Vector2i(12, 4), METAL, 2)
	_line(i, Vector2i(11, 5), Vector2i(9, 3), METAL_LO, 2)
	_px(i, 3, 13, HANDLE)
	return i


static func _crest(c: Color) -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.0, 5.5, 5.5, c)
	_ellipse(i, 8.0, 8.0, 3.5, 3.5, _shade(c, 0.7))
	_px(i, 8, 8, _shade(c, 1.4))
	return i


static func _lure() -> Image:
	var i := _img()
	_line(i, Vector2i(8, 2), Vector2i(8, 7), Color8(100, 110, 120))
	_ellipse(i, 8.0, 10.0, 3.5, 3.5, Color8(70, 240, 220))
	_px(i, 8, 9, Color.WHITE)
	return i


static func _candle() -> Image:
	var i := _img()
	_rect(i, 6, 6, 4, 7, Color8(240, 235, 215))
	_line(i, Vector2i(8, 4), Vector2i(8, 6), Color8(60, 45, 30))
	_ellipse(i, 8.0, 3.0, 1.5, 2.0, Color8(255, 200, 50))
	_px(i, 8, 3, Color8(255, 245, 150))
	return i


static func _chisel() -> Image:
	var i := _img()
	_line(i, Vector2i(4, 12), Vector2i(8, 8), HANDLE, 2)
	_line(i, Vector2i(8, 8), Vector2i(13, 3), METAL, 2)
	_line(i, Vector2i(12, 2), Vector2i(14, 4), METAL_LO, 1)
	return i


static func _trident() -> Image:
	var i := _img()
	_line(i, Vector2i(3, 13), Vector2i(9, 7), HANDLE, 2)
	_line(i, Vector2i(9, 7), Vector2i(13, 3), BRASS, 2)
	_line(i, Vector2i(7, 5), Vector2i(11, 1), BRASS, 1)
	_line(i, Vector2i(11, 9), Vector2i(15, 5), BRASS, 1)
	_line(i, Vector2i(7, 5), Vector2i(11, 9), BRASS, 1)
	return i


static func _anchor_maul() -> Image:
	var i := _img()
	_line(i, Vector2i(3, 13), Vector2i(11, 5), HANDLE, 2)
	_ellipse(i, 11.0, 5.0, 3.5, 3.5, METAL)
	_ellipse(i, 11.0, 5.0, 1.5, 1.5, Color(0, 0, 0, 0))
	_line(i, Vector2i(9, 7), Vector2i(13, 3), METAL, 2)
	return i


static func _speargun() -> Image:
	var i := _img()
	_line(i, Vector2i(2, 11), Vector2i(13, 4), HANDLE, 2)
	_line(i, Vector2i(12, 4), Vector2i(14, 3), METAL, 2)
	_rect(i, 4, 11, 2, 3, HANDLE_LO)
	return i


static func _net() -> Image:
	var i := _img()
	_rect(i, 3, 3, 10, 10, Color(0, 0, 0, 0))
	for y in [4, 7, 10]:
		_line(i, Vector2i(3, y), Vector2i(12, y), Color8(190, 170, 130))
	for x in [4, 7, 10]:
		_line(i, Vector2i(x, 3), Vector2i(x, 12), Color8(190, 170, 130))
	_px(i, 3, 3, METAL)
	_px(i, 12, 3, METAL)
	_px(i, 3, 12, METAL)
	_px(i, 12, 12, METAL)
	return i


static func _staff() -> Image:
	var i := _img()
	_line(i, Vector2i(3, 13), Vector2i(11, 5), HANDLE, 2)
	_ellipse(i, 12.0, 4.0, 2.5, 2.5, Color8(80, 240, 210))
	_px(i, 12, 4, Color.WHITE)
	return i


static func _diving_helmet() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 8.0, 5.5, 5.5, BRASS)
	_rect(i, 3, 10, 10, 3, _shade(BRASS, 0.8))
	_ellipse(i, 8.0, 8.0, 2.8, 2.8, Color8(100, 200, 230))
	_px(i, 7, 7, Color.WHITE)
	return i


static func _souwester() -> Image:
	var i := _img()
	_ellipse(i, 8.0, 7.0, 4.5, 3.5, Color8(230, 180, 40))
	_line(i, Vector2i(2, 10), Vector2i(14, 10), Color8(195, 145, 25), 2)
	_line(i, Vector2i(2, 11), Vector2i(5, 13), Color8(180, 130, 20), 2)
	return i


static func _boots(s: String) -> Image:
	var i := _img()
	var c := Color8(110, 75, 45)
	if "ice" in s or "lead" in s:
		c = METAL_LO
	elif "flipper" in s:
		c = Color8(50, 120, 150)
	_rect(i, 4, 5, 4, 7, c)
	_rect(i, 4, 10, 7, 3, c)
	return i


static func _workstation(tag: StringName) -> Image:
	var i := _img()
	var s := String(tag)
	if s == "workbench":
		_rect(i, 3, 6, 10, 3, Color8(160, 115, 70))
		_rect(i, 4, 9, 2, 5, Color8(115, 80, 50))
		_rect(i, 10, 9, 2, 5, Color8(115, 80, 50))
		_rect(i, 11, 4, 2, 2, METAL)
		return i
	if s == "campfire":
		_line(i, Vector2i(3, 12), Vector2i(12, 12), HANDLE, 2)
		_ellipse(i, 8.0, 8.0, 4.0, 4.0, Color8(230, 70, 30))
		_ellipse(i, 8.0, 8.0, 2.6, 2.8, Color8(250, 150, 30))
		_ellipse(i, 8.0, 9.0, 1.5, 1.8, Color8(255, 235, 80))
		return i
	if s == "furnace":
		_ellipse(i, 8.0, 8.0, 5.5, 5.5, Color8(125, 120, 115))
		_rect(i, 3, 10, 10, 4, Color8(100, 95, 90))
		_rect(i, 6, 8, 4, 5, Color8(240, 90, 20))
		_rect(i, 7, 9, 2, 3, Color8(255, 220, 80))
		return i
	if s == "anvil":
		_rect(i, 3, 5, 10, 3, METAL)
		_rect(i, 1, 5, 2, 2, METAL_LO)
		_rect(i, 6, 8, 4, 3, METAL_LO)
		_rect(i, 4, 11, 8, 3, METAL_LO)
		return i
	if s == "saltery":
		_rect(i, 3, 7, 10, 6, HANDLE)
		_ellipse(i, 8.0, 7.0, 4.5, 2.5, Color8(245, 250, 255))
		_px(i, 7, 6, Color.WHITE)
		return i
	if s == "smokehouse":
		_rect(i, 4, 7, 8, 7, Color8(130, 90, 60))
		_line(i, Vector2i(3, 7), Vector2i(8, 3), Color8(95, 60, 40), 2)
		_line(i, Vector2i(8, 3), Vector2i(13, 7), Color8(95, 60, 40), 2)
		_px(i, 8, 2, Color8(190, 195, 200))
		_px(i, 9, 1, Color8(170, 175, 180))
		return i
	if s == "hearth_pot":
		_ellipse(i, 8.0, 9.0, 4.5, 3.5, Color8(55, 60, 65))
		_ellipse(i, 8.0, 8.0, 3.5, 1.5, Color8(190, 110, 40))
		_line(i, Vector2i(4, 12), Vector2i(5, 9), Color8(40, 45, 50))
		_line(i, Vector2i(12, 12), Vector2i(11, 9), Color8(40, 45, 50))
		return i
	if s == "stone_well":
		_rect(i, 4, 8, 8, 6, Color8(135, 130, 125))
		_rect(i, 3, 3, 10, 2, HANDLE)
		_line(i, Vector2i(4, 5), Vector2i(4, 8), HANDLE)
		_line(i, Vector2i(11, 5), Vector2i(11, 8), HANDLE)
		_rect(i, 7, 5, 2, 2, HANDLE_LO)
		return i
	if s == "feed_trough":
		_rect(i, 3, 8, 10, 5, HANDLE)
		_rect(i, 4, 7, 8, 2, Color8(235, 195, 75))
		_rect(i, 3, 13, 2, 1, HANDLE_LO)
		_rect(i, 11, 13, 2, 1, HANDLE_LO)
		return i
	if s == "poultry_coop":
		_line(i, Vector2i(3, 13), Vector2i(8, 4), HANDLE, 2)
		_line(i, Vector2i(8, 4), Vector2i(13, 13), HANDLE, 2)
		_rect(i, 6, 9, 4, 4, Color8(50, 35, 25))
		_px(i, 8, 11, Color.WHITE)
		return i
	if "barrel" in s or "cask" in s:
		_ellipse(i, 8.0, 9.0, 5.0, 5.5, Color8(150, 105, 65))
		_rect(i, 4, 4, 8, 1, Color8(120, 80, 50))
		_rect(i, 4, 13, 8, 1, Color8(120, 80, 50))
		_rect(i, 3, 6, 10, 1, METAL_LO)
		_rect(i, 3, 11, 10, 1, METAL_LO)
		return i
	if "chest" in s or "storage_crate" in s or "cargo_crate" in s:
		_rect(i, 3, 7, 10, 7, Color8(155, 110, 70))
		_rect(i, 3, 5, 10, 3, Color8(175, 125, 80))
		_rect(i, 7, 7, 2, 3, BRASS)
		return i
	if "crab_pot" in s or "trap" in s:
		_ellipse(i, 8.0, 9.0, 5.5, 4.5, Color8(180, 145, 95))
		for y in [7, 9, 11]:
			_line(i, Vector2i(4, y), Vector2i(12, y), Color8(120, 90, 55))
		_ellipse(i, 8.0, 6.0, 2.0, 1.2, Color8(60, 45, 30))
		return i
	if "lantern" in s or "brazier" in s or "candle" in s:
		var glow := Color8(80, 245, 210) if "phosphor" in s else Color8(255, 220, 100)
		_rect(i, 5, 5, 6, 7, Color8(70, 75, 80))
		_rect(i, 6, 6, 4, 5, glow)
		_rect(i, 7, 3, 2, 2, Color8(90, 95, 100))
		return i
	if "diving_bell" in s:
		_ellipse(i, 8.0, 8.0, 5.5, 5.5, BRASS)
		_rect(i, 3, 10, 10, 3, _shade(BRASS, 0.8))
		_ellipse(i, 8.0, 8.0, 2.5, 2.5, Color8(120, 210, 230))
		return i
	if "wheel" in s or "mill" in s or "sawmill" in s:
		_ellipse(i, 8.0, 8.0, 5.5, 5.5, HANDLE)
		_ellipse(i, 8.0, 8.0, 2.5, 2.5, HANDLE_LO)
		_line(i, Vector2i(8, 2), Vector2i(8, 14), HANDLE_LO)
		_line(i, Vector2i(2, 8), Vector2i(14, 8), HANDLE_LO)
		return i
	if "sawhorse" in s or "station" in s:
		_rect(i, 3, 6, 10, 2, HANDLE)
		_line(i, Vector2i(4, 8), Vector2i(2, 13), HANDLE, 2)
		_line(i, Vector2i(11, 8), Vector2i(13, 13), HANDLE, 2)
		return i
	if "bed" in s or "cot" in s:
		_rect(i, 3, 6, 10, 7, Color8(140, 95, 60))
		_rect(i, 3, 6, 4, 7, Color8(240, 235, 225))
		_rect(i, 7, 6, 6, 7, Color8(70, 105, 150))
		return i
	if "bell" in s:
		_ellipse(i, 8.0, 8.0, 4.5, 5.0, BRASS)
		_rect(i, 3, 11, 10, 2, _shade(BRASS, 1.2))
		return i
	return _crate()


## A little sailing boat: hull, mast, striped sail.
static func _boat_icon() -> Image:
	var i := _img()
	_rect(i, 2, 11, 12, 2, Color8(120, 84, 56))
	_rect(i, 3, 13, 10, 1, Color8(90, 62, 42))
	_rect(i, 2, 10, 12, 1, Color8(70, 110, 160))
	_line(i, Vector2i(8, 2), Vector2i(8, 10), Color8(90, 62, 42))
	for y in range(3, 10):
		var w := 9 - y
		var c := Color8(236, 230, 214) if (y / 2) % 2 == 0 else Color8(190, 70, 60)
		_line(i, Vector2i(9, y), Vector2i(9 + maxi(0, 10 - y - 1), y), c)
	return i


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
