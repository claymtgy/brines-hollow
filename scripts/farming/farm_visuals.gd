class_name FarmVisuals
extends Node3D
## 3D visual representation for all tilled soil plots (CropPlot) in FarmManager.
## Renders ploughed furrow beds whose color reflects hydration and salinity,
## plus 3D growing crop shoots and mature harvestable plants.

const VS := VoxelWorld.VS
const PLOT_SIZE_M := VS * 2.8  # ~0.50m x 0.50m garden bed patch (3x3 voxels)

var farm: FarmManager = null
var world: VoxelWorld = null

## Vector3i -> Dictionary {"root": Node3D, "soil_mat": StandardMaterial3D, "salt_node": Node3D, "crop_root": Node3D, "last_stage": int, "last_crop": StringName, "last_hydro": float, "last_sal": float}
var _plot_nodes: Dictionary = {}


func setup(p_farm: FarmManager, p_world: VoxelWorld = null) -> void:
	farm = p_farm
	world = p_world


func _process(_delta: float) -> void:
	if farm == null:
		return

	# Remove visual nodes for plots that no longer exist
	for pos_key in _plot_nodes.keys():
		if not farm.plots.has(pos_key):
			var entry: Dictionary = _plot_nodes[pos_key]
			if is_instance_valid(entry["root"]):
				(entry["root"] as Node3D).queue_free()
			_plot_nodes.erase(pos_key)

	# Create or update visual nodes for active plots
	for pos: Vector3i in farm.plots.keys():
		var plot: CropPlot = farm.plots[pos]
		if not _plot_nodes.has(pos):
			_create_plot_visual(pos, plot)
		else:
			_update_plot_visual(pos, plot)


func _create_plot_visual(pos: Vector3i, plot: CropPlot) -> void:
	var root := Node3D.new()
	root.name = "TilledPlot_%d_%d_%d" % [pos.x, pos.y, pos.z]
	add_child(root)
	root.global_position = Vector3(float(pos.x) + 0.5, float(pos.y) + 1.0, float(pos.z) + 0.5) * VS

	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.38, 0.24, 0.14)
	soil_mat.roughness = 0.92

	# Base tilled soil bed pad
	var base_mi := MeshInstance3D.new()
	var base_bm := BoxMesh.new()
	base_bm.size = Vector3(PLOT_SIZE_M, 0.035, PLOT_SIZE_M)
	base_bm.material = soil_mat
	base_mi.mesh = base_bm
	base_mi.position = Vector3(0.0, 0.017, 0.0)
	root.add_child(base_mi)

	# 4 parallel ploughed furrow ridges
	for i in 4:
		var ridge_mi := MeshInstance3D.new()
		var ridge_bm := BoxMesh.new()
		ridge_bm.size = Vector3(PLOT_SIZE_M * 0.92, 0.042, PLOT_SIZE_M * 0.15)
		ridge_bm.material = soil_mat
		ridge_mi.mesh = ridge_bm
		var z_off := lerpf(-PLOT_SIZE_M * 0.34, PLOT_SIZE_M * 0.34, float(i) / 3.0)
		ridge_mi.position = Vector3(0.0, 0.042, z_off)
		root.add_child(ridge_mi)

	# Salt crust flecks node (visible when salinity is high)
	var salt_node := Node3D.new()
	salt_node.name = "SaltCrust"
	root.add_child(salt_node)
	var salt_mat := StandardMaterial3D.new()
	salt_mat.albedo_color = Color(0.90, 0.92, 0.94)
	salt_mat.roughness = 0.65
	for i in 4:
		var fleck_mi := MeshInstance3D.new()
		var fleck_bm := BoxMesh.new()
		fleck_bm.size = Vector3(PLOT_SIZE_M * 0.72, 0.012, 0.025)
		fleck_bm.material = salt_mat
		fleck_mi.mesh = fleck_bm
		var z_off := lerpf(-PLOT_SIZE_M * 0.34, PLOT_SIZE_M * 0.34, float(i) / 3.0)
		fleck_mi.position = Vector3(0.0, 0.065, z_off)
		salt_node.add_child(fleck_mi)

	var crop_root := Node3D.new()
	crop_root.name = "CropRoot"
	root.add_child(crop_root)

	_plot_nodes[pos] = {
		"root": root,
		"soil_mat": soil_mat,
		"salt_node": salt_node,
		"crop_root": crop_root,
		"last_stage": -1,
		"last_crop": &"",
		"last_hydro": -1.0,
		"last_sal": -1.0
	}
	_update_plot_visual(pos, plot)


func _update_plot_visual(pos: Vector3i, plot: CropPlot) -> void:
	var entry: Dictionary = _plot_nodes[pos]
	var hydro := clampf(plot.hydration, 0.0, 1.0)
	var sal := clampf(plot.salinity, 0.0, 1.0)

	if absf(hydro - float(entry["last_hydro"])) > 0.02 or absf(sal - float(entry["last_sal"])) > 0.02:
		entry["last_hydro"] = hydro
		entry["last_sal"] = sal
		var soil_mat: StandardMaterial3D = entry["soil_mat"]
		var dry_col := Color(0.40, 0.26, 0.15)
		var wet_col := Color(0.20, 0.12, 0.07)
		soil_mat.albedo_color = dry_col.lerp(wet_col, hydro)
		soil_mat.roughness = lerpf(0.94, 0.48, hydro)
		var salt_node: Node3D = entry["salt_node"]
		salt_node.visible = sal >= 0.45

	if int(entry["last_stage"]) != plot.current_stage or entry["last_crop"] != plot.crop_id:
		entry["last_stage"] = plot.current_stage
		entry["last_crop"] = plot.crop_id
		_rebuild_crop_mesh(entry["crop_root"] as Node3D, plot)


func _rebuild_crop_mesh(crop_root: Node3D, plot: CropPlot) -> void:
	for c in crop_root.get_children():
		c.queue_free()
	if plot.is_empty() or plot.current_stage <= 0:
		return

	var def: CropDef = CropDB.get_crop(plot.crop_id)
	var max_stages: int = maxi(2, def.growth_stages if def != null else 4)
	var frac := clampf(float(plot.current_stage) / float(max_stages), 0.25, 1.0)
	var mature := plot.is_mature()

	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.32, 0.68, 0.28) if not mature else Color(0.42, 0.72, 0.26)
	stem_mat.roughness = 0.8

	var fruit_col := Color(0.88, 0.74, 0.24)  # default golden wheat
	if String(plot.crop_id).contains("samphire"):
		stem_mat.albedo_color = Color(0.22, 0.64, 0.46)
		fruit_col = Color(0.34, 0.85, 0.58)
	elif String(plot.crop_id).contains("beet") or String(plot.crop_id).contains("root"):
		fruit_col = Color(0.76, 0.20, 0.32)
	elif String(plot.crop_id).contains("kale") or String(plot.crop_id).contains("kelp"):
		fruit_col = Color(0.24, 0.58, 0.36)

	var fruit_mat := StandardMaterial3D.new()
	fruit_mat.albedo_color = fruit_col
	fruit_mat.roughness = 0.65

	var offsets := [
		Vector3(-0.11, 0.0, -0.11),
		Vector3(0.11, 0.0, -0.11),
		Vector3(-0.11, 0.0, 0.11),
		Vector3(0.11, 0.0, 0.11),
	]
	var h := lerpf(0.08, 0.34, frac)
	var w := lerpf(0.035, 0.075, frac)
	for off: Vector3 in offsets:
		var stalk := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(w, h, w)
		sbm.material = stem_mat
		stalk.mesh = sbm
		stalk.position = off + Vector3(0.0, 0.05 + h * 0.5, 0.0)
		crop_root.add_child(stalk)

		if mature:
			var head_mi := MeshInstance3D.new()
			var hbm := BoxMesh.new()
			hbm.size = Vector3(w * 1.45, 0.085, w * 1.45)
			hbm.material = fruit_mat
			head_mi.mesh = hbm
			head_mi.position = off + Vector3(0.0, 0.05 + h + 0.03, 0.0)
			crop_root.add_child(head_mi)
