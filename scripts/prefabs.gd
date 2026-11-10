class_name Prefabs
extends RefCounted
## Prefabricated voxel groups. Each prefab is a dense grid (index x + sx*(z + sz*y)),
## with Palette.CLEAR cells meaning "carve to air" (door openings, interiors).
## Front of every prefab faces -Z at rotation 0.


static var _list: Array = []
static var _rot_cache: Dictionary = {}


class Grid:
	var sx: int
	var sy: int
	var sz: int
	var data: PackedByteArray

	func _init(x: int, y: int, z: int) -> void:
		sx = x; sy = y; sz = z
		data = PackedByteArray()
		data.resize(x * y * z)

	func setv(x: int, y: int, z: int, m: int) -> void:
		if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
			return
		data[x + sx * (z + sz * y)] = m

	func getv(x: int, y: int, z: int) -> int:
		if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
			return 0
		return data[x + sx * (z + sz * y)]

	## Inclusive box fill.
	func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					setv(x, y, z, m)


static func all() -> Array:
	if _list.is_empty():
		_build()
	return _list


static func count() -> int:
	return all().size()


## Returns {name, size: Vector3i, anchor: Vector3i, data, lights: [Vector3i], foundation}
## rotated by r * 90 degrees around Y. Cached.
static func rotated(id: int, r: int) -> Dictionary:
	var key := id * 4 + r
	if _rot_cache.has(key):
		return _rot_cache[key]
	var src: Dictionary = all()[id]
	var s: Vector3i = src.size
	var nsx := s.z if r % 2 == 1 else s.x
	var nsz := s.x if r % 2 == 1 else s.z
	var data := PackedByteArray()
	data.resize(nsx * s.y * nsz)
	var sd: PackedByteArray = src.data
	for y in s.y:
		for z in s.z:
			for x in s.x:
				var m := sd[x + s.x * (z + s.z * y)]
				if m == 0:
					continue
				var q := _rot_xz(x, z, s.x, s.z, r)
				data[q.x + nsx * (q.y + nsz * y)] = m
	var a: Vector3i = src.anchor
	var aq := _rot_xz(a.x, a.z, s.x, s.z, r)
	var lights := []
	for l: Vector3i in src.lights:
		var lq := _rot_xz(l.x, l.z, s.x, s.z, r)
		lights.append(Vector3i(lq.x, l.y, lq.y))
	var out := {
		"name": src.name, "size": Vector3i(nsx, s.y, nsz), "anchor": Vector3i(aq.x, a.y, aq.y),
		"data": data, "lights": lights, "foundation": src.foundation,
	}
	_rot_cache[key] = out
	return out


static func _rot_xz(x: int, z: int, sx: int, sz: int, r: int) -> Vector2i:
	match r:
		1: return Vector2i(sz - 1 - z, x)
		2: return Vector2i(sx - 1 - x, sz - 1 - z)
		3: return Vector2i(z, sx - 1 - x)
	return Vector2i(x, z)


static func _add(name: String, g: Grid, anchor: Vector3i, lights: Array = [], foundation := "") -> void:
	_list.append({
		"name": name, "size": Vector3i(g.sx, g.sy, g.sz), "anchor": anchor,
		"data": g.data, "lights": lights, "foundation": foundation,
	})


## ---- Scale rules (voxel = 0.18 m; character 1.8 m tall, ~0.9 m wide at the hat brim) ----
const DOOR_W := 7       # 1.26 m
const DOOR_H := 14      # 2.52 m
const WALL_H := 18      # 3.24 m, single storey
const WALL_W := 12      # 2.16 m wall segment; matches the 6-voxel build grid
const WIN := 5          # 0.9 m window opening
const SILL := 6         # window sill height (1.08 m)
const RAIL_H := 6       # fences / railings (~1.1 m, about waist-chest)


static func _plank_wall(g: Grid) -> void:
	for y in g.sy:
		var m := Palette.DRIFTWOOD if y % 3 == 0 else Palette.PLANK
		g.box(1, y, 0, g.sx - 2, y, 0, m)
	g.box(0, 0, 0, 0, g.sy - 1, 0, Palette.DARK_WOOD)
	g.box(g.sx - 1, 0, 0, g.sx - 1, g.sy - 1, 0, Palette.DARK_WOOD)
	g.box(0, g.sy - 1, 0, g.sx - 1, g.sy - 1, 0, Palette.DARK_WOOD)
	g.box(0, 0, 0, g.sx - 1, 0, 0, Palette.DARK_WOOD)


static func _build() -> void:
	var mid := WALL_W / 2

	# 0: Plank wall
	var g := Grid.new(WALL_W, WALL_H, 1)
	_plank_wall(g)
	_add("Plank Wall", g, Vector3i(mid, 0, 0))

	# 1: Window wall
	g = Grid.new(WALL_W, WALL_H, 1)
	_plank_wall(g)
	var wx0 := (WALL_W - WIN) / 2
	g.box(wx0 - 1, SILL - 1, 0, wx0 + WIN, SILL + WIN, 0, Palette.WHITEWASH)
	g.box(wx0, SILL, 0, wx0 + WIN - 1, SILL + WIN - 1, 0, Palette.CLEAR)
	g.box(wx0 - 1, SILL - 1, 0, wx0 + WIN, SILL - 1, 0, Palette.DARK_WOOD)
	_add("Window Wall", g, Vector3i(mid, 0, 0))

	# 2: Door wall
	g = Grid.new(WALL_W, WALL_H, 1)
	_plank_wall(g)
	var dx0 := (WALL_W - DOOR_W) / 2
	g.box(dx0 - 1, 1, 0, dx0 + DOOR_W, DOOR_H + 1, 0, Palette.DARK_WOOD)
	g.box(dx0, 1, 0, dx0 + DOOR_W - 1, DOOR_H, 0, Palette.CLEAR)
	_add("Door Wall", g, Vector3i(mid, 0, 0))

	# 3: Deck floor
	g = Grid.new(WALL_W, 1, WALL_W)
	for z in WALL_W:
		g.box(0, 0, z, WALL_W - 1, 0, z, Palette.DRIFTWOOD if z % 2 == 0 else Palette.PLANK)
	_add("Deck Floor", g, Vector3i(mid, 0, mid), [], "posts")

	# 4: Stairs (rise 1 voxel per step; auto-step handles it smoothly)
	g = Grid.new(6, 10, 10)
	for k in 10:
		g.box(0, 0, k, 5, k, k, Palette.PLANK)
		g.box(0, k, k, 5, k, k, Palette.DRIFTWOOD)
	_add("Stairs", g, Vector3i(3, 0, 0))

	# 5: Fisher's hut
	_build_hut()

	# 6: Dock (deck 1.8 m wide, 5.8 m long, posts reach 5.8 m down)
	g = Grid.new(10, 34, 32)
	g.box(0, 32, 0, 9, 32, 31, Palette.PLANK)
	for z in range(0, 32, 2):
		g.box(0, 32, z, 9, 32, z, Palette.DRIFTWOOD)
	for z in [0, 10, 20, 31]:
		g.box(0, 0, z, 0, 31, z, Palette.DARK_WOOD)
		g.box(9, 0, z, 9, 31, z, Palette.DARK_WOOD)
	g.box(0, 33, 31, 9, 33, 31, Palette.BUOY)
	for x in [2, 7]:
		g.setv(x, 33, 31, Palette.WHITEWASH)
	g.box(0, 33, 31, 0, 33, 31, Palette.DARK_WOOD)
	g.box(9, 33, 31, 9, 33, 31, Palette.DARK_WOOD)
	_add("Dock", g, Vector3i(5, 32, 0))

	# 7: Lamp post (3.8 m)
	g = Grid.new(3, 21, 3)
	g.box(0, 0, 0, 2, 0, 2, Palette.COBBLE)
	g.box(1, 1, 1, 1, 17, 1, Palette.DARK_WOOD)
	g.setv(1, 18, 1, Palette.LANTERN)
	g.setv(0, 18, 1, Palette.DARK_WOOD)
	g.setv(2, 18, 1, Palette.DARK_WOOD)
	g.setv(1, 18, 0, Palette.DARK_WOOD)
	g.setv(1, 18, 2, Palette.DARK_WOOD)
	g.setv(1, 19, 1, Palette.DARK_WOOD)
	g.setv(1, 20, 1, Palette.METAL)
	_add("Lamp Post", g, Vector3i(1, 0, 1), [Vector3i(1, 18, 1)])

	# 8: Fence
	g = Grid.new(WALL_W, RAIL_H + 1, 1)
	g.box(0, 3, 0, WALL_W - 1, 3, 0, Palette.DRIFTWOOD)
	g.box(0, RAIL_H - 1, 0, WALL_W - 1, RAIL_H - 1, 0, Palette.DRIFTWOOD)
	for x in [0, mid, WALL_W - 1]:
		g.box(x, 0, 0, x, RAIL_H, 0, Palette.DARK_WOOD)
	_add("Fence", g, Vector3i(mid, 0, 0))

	# 9: Stone arch (opening 1.44 m x 2.9 m)
	g = Grid.new(16, 22, 3)
	g.box(0, 0, 0, 15, 21, 2, Palette.COBBLE)
	g.box(4, 0, 0, 11, 15, 2, Palette.CLEAR)
	g.box(5, 16, 0, 10, 16, 2, Palette.CLEAR)
	g.box(6, 17, 0, 9, 17, 2, Palette.CLEAR)
	g.box(0, 21, 0, 15, 21, 2, Palette.SANDSTONE_C)
	_add("Stone Arch", g, Vector3i(8, 0, 1))

	# 10: Fish drying rack
	g = Grid.new(13, 15, 3)
	g.box(0, 0, 1, 0, 14, 1, Palette.DARK_WOOD)
	g.box(12, 0, 1, 12, 14, 1, Palette.DARK_WOOD)
	g.box(0, 14, 1, 12, 14, 1, Palette.DRIFTWOOD)
	for x in [3, 6, 9]:
		g.box(x, 9, 1, x, 13, 1, Palette.METAL)
		g.box(x, 9, 0, x, 11, 2, Palette.METAL)
		g.setv(x - 1, 8, 1, Palette.METAL)
		g.setv(x + 1, 8, 1, Palette.METAL)
	_add("Drying Rack", g, Vector3i(6, 0, 1))

	# 11: Rowboat (1.4 m beam, 3.6 m long)
	g = Grid.new(8, 6, 20)
	g.box(2, 1, 2, 5, 5, 17, Palette.CLEAR)
	g.box(2, 0, 2, 5, 0, 17, Palette.DARK_WOOD)
	g.box(1, 1, 1, 1, 3, 18, Palette.PLANK)
	g.box(6, 1, 1, 6, 3, 18, Palette.PLANK)
	g.box(0, 2, 3, 0, 3, 16, Palette.PLANK)
	g.box(7, 2, 3, 7, 3, 16, Palette.PLANK)
	g.box(0, 3, 3, 0, 3, 16, Palette.ROOF_BLUE)
	g.box(7, 3, 3, 7, 3, 16, Palette.ROOF_BLUE)
	g.box(2, 1, 0, 5, 3, 1, Palette.PLANK)
	g.box(3, 1, 18, 4, 4, 19, Palette.PLANK)
	g.box(3, 5, 19, 4, 5, 19, Palette.DARK_WOOD)
	g.box(2, 2, 6, 5, 2, 6, Palette.DRIFTWOOD)
	g.box(2, 2, 12, 5, 2, 12, Palette.DRIFTWOOD)
	_add("Rowboat", g, Vector3i(4, 0, 10))

	# 13: Pen Fence (appended last: prefab ids are saved in commands): boards right down to the ground (a rail fence lets ducks, foxes and stoats
	# slip under its bottom rail; this one holds every pen animal and keeps raiders out).
	g = Grid.new(WALL_W, RAIL_H + 1, 1)
	g.box(0, 0, 0, WALL_W - 1, 2, 0, Palette.PLANK)
	g.box(0, RAIL_H - 1, 0, WALL_W - 1, RAIL_H - 1, 0, Palette.DRIFTWOOD)
	g.box(0, 3, 0, WALL_W - 1, 3, 0, Palette.DRIFTWOOD)
	for x in [0, WALL_W / 2, WALL_W - 1]:
		g.box(x, 0, 0, x, RAIL_H, 0, Palette.DARK_WOOD)
	_add("Pen Fence", g, Vector3i(WALL_W / 2, 0, 0))


static func _build_hut() -> void:
	# Body x1..24 (4.3 m), z1..18 (3.2 m deep), floor y0, walls y1..WALL_H, gable roof, chimney.
	const X1 := 24
	const Z1 := 18
	const RY := WALL_H + 1                       # first roof row
	var roof_rows := (Z1 + 3) / 2                # rows until the two slopes meet
	var top := RY + roof_rows
	var g := Grid.new(X1 + 2, top + 4, Z1 + 2)
	g.box(2, 1, 2, X1 - 1, top, Z1 - 1, Palette.CLEAR)          # interior air
	g.box(1, 0, 1, X1, 0, Z1, Palette.PLANK)                    # floor
	# walls
	g.box(1, 1, 1, X1, WALL_H, 1, Palette.WHITEWASH)
	g.box(1, 1, Z1, X1, WALL_H, Z1, Palette.WHITEWASH)
	g.box(1, 1, 1, 1, WALL_H, Z1, Palette.WHITEWASH)
	g.box(X1, 1, 1, X1, WALL_H, Z1, Palette.WHITEWASH)
	g.box(1, 1, 1, X1, 2, Z1, Palette.COBBLE)                   # stone footing
	g.box(2, 1, 2, X1 - 1, 2, Z1 - 1, Palette.CLEAR)
	# timber frame
	for x in [1, 13, X1]:
		g.box(x, 1, 1, x, WALL_H, 1, Palette.DARK_WOOD)
		g.box(x, 1, Z1, x, WALL_H, Z1, Palette.DARK_WOOD)
	for z in [1, Z1]:
		g.box(1, 1, z, 1, WALL_H, z, Palette.DARK_WOOD)
		g.box(X1, 1, z, X1, WALL_H, z, Palette.DARK_WOOD)
	g.box(1, WALL_H, 1, X1, WALL_H, 1, Palette.DARK_WOOD)
	g.box(1, WALL_H, Z1, X1, WALL_H, Z1, Palette.DARK_WOOD)
	g.box(1, WALL_H, 1, 1, WALL_H, Z1, Palette.DARK_WOOD)
	g.box(X1, WALL_H, 1, X1, WALL_H, Z1, Palette.DARK_WOOD)
	# door (front, z=1)
	var d0 := 4
	g.box(d0 - 1, 1, 1, d0 + DOOR_W, DOOR_H + 1, 1, Palette.DARK_WOOD)
	g.box(d0, 1, 1, d0 + DOOR_W - 1, DOOR_H, 1, Palette.CLEAR)
	# front window with shutters
	var w0 := 16
	g.box(w0, SILL + 1, 1, w0 + WIN - 1, SILL + WIN, 1, Palette.CLEAR)
	g.box(w0 - 1, SILL + 1, 1, w0 - 1, SILL + WIN, 1, Palette.SHUTTER)
	g.box(w0 + WIN, SILL + 1, 1, w0 + WIN, SILL + WIN, 1, Palette.SHUTTER)
	g.box(w0 - 1, SILL, 1, w0 + WIN, SILL, 1, Palette.DARK_WOOD)
	# side windows
	var sw := (Z1 - WIN) / 2 + 1
	for x in [1, X1]:
		g.box(x, SILL + 1, sw, x, SILL + WIN, sw + WIN - 1, Palette.CLEAR)
		g.box(x, SILL + 1, sw - 1, x, SILL + WIN, sw - 1, Palette.SHUTTER)
		g.box(x, SILL + 1, sw + WIN, x, SILL + WIN, sw + WIN, Palette.SHUTTER)
	# back window
	g.box(8, SILL + 1, Z1, 8 + WIN - 1, SILL + WIN, Z1, Palette.CLEAR)
	g.box(7, SILL + 1, Z1, 7, SILL + WIN, Z1, Palette.SHUTTER)
	g.box(8 + WIN, SILL + 1, Z1, 8 + WIN, SILL + WIN, Z1, Palette.SHUTTER)
	# gable roof, ridge along X, 1-voxel overhang front/back/sides
	for k in roof_rows:
		var y := RY + k
		var zf := k
		var zb := Z1 + 1 - k
		if zb < zf:
			break
		g.box(0, y, zf, X1 + 1, y, zf, Palette.ROOF_RED)
		g.box(0, y, zb, X1 + 1, y, zb, Palette.ROOF_RED)
		if zb - zf > 1:
			g.box(1, y, zf + 1, 1, y, zb - 1, Palette.WHITEWASH)
			g.box(X1, y, zf + 1, X1, y, zb - 1, Palette.WHITEWASH)
	var ridge_z := (Z1 + 1) / 2
	g.box(0, top, ridge_z, X1 + 1, top, ridge_z + 1, Palette.DARK_WOOD)
	g.box(1, top - 3, ridge_z - 1, 1, top - 2, ridge_z + 2, Palette.SHUTTER)   # gable vent
	# chimney
	g.box(19, RY, Z1 - 5, 21, top + 3, Z1 - 3, Palette.COBBLE)
	g.box(19, top + 3, Z1 - 5, 21, top + 3, Z1 - 3, Palette.STONE)
	# lantern hanging from the ridge inside (a lit room can house a drifter)
	var lx := 12
	g.box(lx, WALL_H + 2, ridge_z, lx, top - 1, ridge_z, Palette.METAL)
	g.setv(lx, WALL_H + 1, ridge_z, Palette.LANTERN)
	# lantern beside the door
	g.setv(d0 + DOOR_W + 2, 12, 0, Palette.LANTERN)
	g.setv(d0 + DOOR_W + 2, 13, 0, Palette.DARK_WOOD)
	_add("Fisher's Hut", g, Vector3i((X1 + 2) / 2, 0, (Z1 + 2) / 2), [Vector3i(d0 + DOOR_W + 2, 12, 0), Vector3i(lx, WALL_H + 1, ridge_z)], "solid")



## The starter hut as a new castaway finds it: a storm took a corner of the roof and the back
## wall, and the shutters with them. Returns the cells to clear, relative to the stamped hut's
## base (origin - rotated anchor), for rotation `r`. Lanterns and their chains are left alone.
static func hut_ruin_cells(r: int) -> Array[Vector3i]:
	const HUT := 5
	const X1 := 24
	const Z1 := 18
	const RY := WALL_H + 1
	var src: Dictionary = all()[HUT]
	var s: Vector3i = src.size
	var sd: PackedByteArray = src.data
	var out: Array[Vector3i] = []
	for y in s.y:
		for z in s.z:
			for x in s.x:
				var m := sd[x + s.x * (z + s.z * y)]
				if m == 0 or m == Palette.CLEAR or m == Palette.LANTERN or m == Palette.METAL:
					continue
				var h := ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 0xFF
				var gone := false
				if m == Palette.SHUTTER:
					gone = true
				elif y >= RY:
					# A ragged hole through the roof over the back-right of the hut.
					var edge := 13 + (h % 3)
					var chimney := m == Palette.COBBLE or m == Palette.STONE   # the stack still stands
					gone = not chimney and x >= edge and x <= X1 - 1 and z >= 4 + (h % 2)
				elif y >= 3:
					# The back-right corner of the walls has come down, raggedly.
					var corner := (z == Z1 and x >= 16) or (x == X1 and z >= 9)
					gone = corner and y >= 3 + (h % 6)
				if gone:
					var q := _rot_xz(x, z, s.x, s.z, r)
					out.append(Vector3i(q.x, y, q.y))
	return out
