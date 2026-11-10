class_name BlueprintCatalog
extends RefCounted
## Standalone file catalog for saving, loading, and sharing architectural blueprints (.bhbp).
## Prepares player creations for local file sharing and future Steam Workshop publishing.

const BLUEPRINT_DIR := "user://blueprints/"
const FORMAT_IDENTIFIER := "brines_hollow_blueprint_v1"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(BLUEPRINT_DIR):
		DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)


## Exports a voxel schematic to a standalone .bhbp blueprint file.
static func export_blueprint(
	bp_name: String,
	author: String,
	dimensions: Vector3i,
	voxels: Array,
	materials_cost: Dictionary = {}
) -> Dictionary:
	ensure_dir()
	var safe_name := bp_name.validate_filename().to_lower().replace(" ", "_")
	if safe_name.is_empty():
		safe_name = "unnamed_blueprint"
	var file_path := BLUEPRINT_DIR + safe_name + ".bhbp"

	# If materials not provided, calculate from voxels
	var req_materials: Dictionary = materials_cost.duplicate()
	if req_materials.is_empty():
		req_materials = calculate_materials_from_voxels(voxels)

	var payload := {
		"format": FORMAT_IDENTIFIER,
		"version": 1,
		"name": bp_name,
		"author": author if not author.is_empty() else "Wayfarer",
		"created_at": Time.get_datetime_string_from_system(),
		"dimensions": [dimensions.x, dimensions.y, dimensions.z],
		"materials": req_materials,
		"voxel_count": voxels.size(),
		"voxels": voxels
	}

	var json_str := JSON.stringify(payload, "  ")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "error": "Failed to create blueprint file"}

	file.store_string(json_str)
	file.close()

	return {
		"success": true,
		"path": file_path,
		"filename": safe_name + ".bhbp",
		"name": bp_name,
		"materials": req_materials
	}


## Loads and validates a blueprint file from disk.
static func import_blueprint(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"success": false, "error": "File does not exist: %s" % file_path}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "Cannot open blueprint file"}

	var json_str := file.get_as_text()
	file.close()

	var test_json := JSON.new()
	var parse_err := test_json.parse(json_str)
	if parse_err != OK:
		return {"success": false, "error": "Invalid blueprint JSON format"}

	var data: Variant = test_json.data
	if not (data is Dictionary) or data.get("format") != FORMAT_IDENTIFIER:
		return {"success": false, "error": "Unsupported blueprint file schema"}

	return {
		"success": true,
		"name": String(data.get("name", "Unknown")),
		"author": String(data.get("author", "Unknown")),
		"created_at": String(data.get("created_at", "")),
		"dimensions": Vector3i(
			int(data["dimensions"][0]) if data.has("dimensions") and data["dimensions"].size() >= 3 else 1,
			int(data["dimensions"][1]) if data.has("dimensions") and data["dimensions"].size() >= 3 else 1,
			int(data["dimensions"][2]) if data.has("dimensions") and data["dimensions"].size() >= 3 else 1
		),
		"materials": data.get("materials", {}),
		"voxels": data.get("voxels", [])
	}


## Lists all local blueprints found in user://blueprints/.
static func list_local_blueprints() -> Array[Dictionary]:
	ensure_dir()
	var list: Array[Dictionary] = []
	var dir := DirAccess.open(BLUEPRINT_DIR)
	if dir == null:
		return list

	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and (fname.ends_with(".bhbp") or fname.ends_with(".json")):
			var full_path := BLUEPRINT_DIR + fname
			var bp := import_blueprint(full_path)
			if bp.get("success", false):
				bp["file_path"] = full_path
				bp["filename"] = fname
				list.append(bp)
		fname = dir.get_next()
	dir.list_dir_end()
	return list


## Converts voxel palette IDs to required construction item materials.
static func calculate_materials_from_voxels(voxels: Array) -> Dictionary:
	var counts: Dictionary = {}
	for v in voxels:
		var mat_id: int = 0
		if v is Dictionary:
			mat_id = int(v.get("mat", 0))
		elif v is Array and v.size() >= 4:
			mat_id = int(v[3])

		var item_name := &"stone"
		match mat_id:
			Palette.PLANK, Palette.DARK_WOOD, Palette.TRUNK:
				item_name = &"wood_plank"
			Palette.BEDROCK, Palette.STONE, Palette.COBBLE:
				item_name = &"stone"
			Palette.SAND, Palette.WET_SAND:
				item_name = &"sand"
			Palette.DRIFTWOOD:
				item_name = &"driftwood"
			Palette.ROOF_RED, Palette.ROOF_BLUE:
				item_name = &"sea_wool"
			Palette.METAL:
				item_name = &"iron_ingot"
			Palette.GLOW_TEAL:
				item_name = &"sea_glass"

		counts[item_name] = counts.get(item_name, 0) + 1

	return counts
