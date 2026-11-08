class_name IslandAtlas
extends RefCounted
## Names and discovery for the archipelago's islands.
## The native generator places the islands (home island, five larger islands in different
## styles, a scatter of islets and sea stacks, open sea between). This gives each one a
## seeded name that every player in the world agrees on, works out which island a spot is
## on, and tracks which islands the local player has set foot on (saved with their
## character in that world). Discovered islands are named on the sea chart.

const HOME_NAME := "Brine's Hollow"
const PREFIXES := ["Gullwing", "Saltmarsh", "Cormorant", "Kittiwake", "Dunlin", "Selkie",
	"Wrack", "Barnacle", "Driftwood", "Lantern", "Tern", "Gannet", "Shearwater", "Oyster",
	"Brackwater", "Mussel", "Skua", "Petrel", "Limpet", "Curlew", "Sandpiper", "Whelk",
	"Bladderwrack", "Fulmar", "Plover", "Eider", "Scoter", "Razorbill"]
## Suffix by island style (see ArchipelagoGen::IslandStyle), then islets.
const STYLE_SUFFIX := {
	0: ["Holm", "Meads", "Green"],          # flat meadow
	1: ["Cay", "Atoll", "Sands"],           # sandy atoll
	2: ["Downs", "Knolls", "Rise"],         # rolling hills
	3: ["Crags", "Tors", "Scar"],           # rocky crags
	4: ["Table", "Bluff", "Mesa"],          # cliff mesa
}
const ISLET_SUFFIX := ["Skerry", "Rock", "Eyot", "Stack", "Islet"]
const TYPE_HOME := 0
const TYPE_STANDARD := 1
const TYPE_ISLET := 2

var islands: Array = []          # [{name, style, style_name, type, center: Vector3 (m), radius_m}]
var discovered := {}             # island index -> true (local player)
var _height: Callable            # (x, z) -> voxel height of the column
var _island: Callable            # (x, z) -> island index (-1 sea, -2 sea stack)
var _sea_vox := 30.0
var _source: Object              # keeps the generator behind the callables alive
var current := -1                # island the player is on right now (-1 at sea)


## `raw` is ArchipelagoGen.get_islands(); `height` / `island` are column queries in voxels.
func setup(raw: Array, world_seed: int, height: Callable, island: Callable, sea_vox: float) -> void:
	_height = height
	_island = island
	_source = height.get_object()
	_sea_vox = sea_vox
	islands = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x51A7D
	var pool := PREFIXES.duplicate()
	for i in pool.size():                       # seeded shuffle
		var j := rng.randi_range(i, pool.size() - 1)
		var t: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var used := {}
	for i in raw.size():
		var r: Dictionary = raw[i]
		var type := int(r.get("type", TYPE_STANDARD))
		var style := int(r.get("style", 0))
		var nm := HOME_NAME
		if type != TYPE_HOME:
			var pre: String = pool[(i - 1) % pool.size()]
			var suf_list: Array = ISLET_SUFFIX if type == TYPE_ISLET else STYLE_SUFFIX.get(style, ["Isle"])
			var suf: String = suf_list[rng.randi() % suf_list.size()]
			nm = "%s %s" % [pre, suf]
			var n := 2
			while used.has(nm):
				nm = "%s %s %s" % [pre, suf, ["", "", "Minor", "Lesser", "Outer", "Far"][mini(n, 5)]]
				n += 1
		used[nm] = true
		var c: Vector2 = r.get("center", Vector2.ZERO)
		islands.append({
			"name": nm,
			"style": style,
			"style_name": "Islet" if type == TYPE_ISLET else ("Home island" if type == TYPE_HOME else String(r.get("style_name", ""))),
			"type": type,
			"center": Vector3(c.x * VoxelWorld.VS, 0.0, c.y * VoxelWorld.VS),
			"radius_m": float(r.get("radius", 0.0)) * VoxelWorld.VS * 0.6,
		})


## Index of the island whose land is under `pos` (metres), or -1 at sea / on a sea stack.
func island_at(pos: Vector3) -> int:
	if islands.is_empty() or not _island.is_valid():
		return -1
	var x := floori(pos.x / VoxelWorld.VS)
	var z := floori(pos.z / VoxelWorld.VS)
	if float(_height.call(x, z)) < _sea_vox:
		return -1
	var id := int(_island.call(x, z))
	return id if id >= 0 and id < islands.size() else -1


func name_of(idx: int) -> String:
	return String(islands[idx].name) if idx >= 0 and idx < islands.size() else ""


func is_discovered(idx: int) -> bool:
	return discovered.has(idx)


func discovered_count() -> int:
	return discovered.size()


## Call a few times a second with the player's position. Returns an event when the player
## steps onto a different island: {"idx", "name", "style", "new"} (new = first visit), else {}.
func update(pos: Vector3) -> Dictionary:
	var idx := island_at(pos)
	if idx == current:
		return {}
	current = idx
	if idx < 0:
		return {}
	var fresh := not discovered.has(idx)
	discovered[idx] = true
	return {"idx": idx, "name": name_of(idx), "style": islands[idx].style_name, "new": fresh}


## Discovered islands as chart labels: [{"pos": Vector3, "name": String, "home": bool}].
func chart_labels() -> Array:
	var out: Array = []
	for idx: int in discovered:
		if idx < islands.size():
			out.append({"pos": islands[idx].center, "name": islands[idx].name, "home": islands[idx].type == TYPE_HOME})
	return out


func serialize() -> Array:
	return discovered.keys()


func deserialize(data: Variant) -> void:
	discovered = {}
	if data is Array:
		for k in data:
			discovered[int(k)] = true
	current = -1
