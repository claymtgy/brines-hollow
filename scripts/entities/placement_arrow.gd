class_name PlacementArrow
extends MeshInstance3D
## A flat arrow on the ground in front of a placement ghost, pointing out of the side that
## will be the front of what you're about to place (R rotates it with the ghost).
##
## Fronts: voxel blueprints face -Z before rotation (the house door is at z = 1);
## placeable objects face their local +Z (the chest latch, the furnace firebox).

const LIFT := 0.04          # metres above the ghost's base, clear of the ground


func _init() -> void:
	name = "FrontArrow"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = arrow_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true          # stays readable through grass and uneven ground
	m.render_priority = 1
	material_override = m
	visible = false


## Which way a rotated voxel blueprint's front faces (prefab_rot 0..3).
static func prefab_front(rot: int) -> Vector3:
	return [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][posmod(rot, 4)]


## Which way a placeable object's front faces (rotation_steps 0..3).
static func entity_front(rot: int) -> Vector3:
	return [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][posmod(rot, 4)]


## The direction the arrow currently points (world XZ, unit length).
func pointing() -> Vector3:
	var d := global_transform.basis.z
	d.y = 0.0
	return d.normalized()


## Lays the arrow on the ground just outside `box`'s `dir` face, pointing along `dir`.
func show_for(box: AABB, dir: Vector3, color: Color) -> void:
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var half := box.size * 0.5
	var reach := absf(dir.x) * half.x + absf(dir.z) * half.z   # centre to the front face
	var across := absf(dir.z) * box.size.x + absf(dir.x) * box.size.z
	var s := clampf(across * 0.6, 0.75, 1.6)                   # arrow length
	var c := box.get_center()
	global_position = Vector3(c.x, box.position.y + LIFT, c.z) + dir * (reach + 0.1 + s * 0.5)
	global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled(Vector3(s, 1.0, s))
	(material_override as StandardMaterial3D).albedo_color = Color(color, 0.85)
	visible = true


## A flat arrow 1 m long lying in XZ, centred on the origin, pointing +Z.
static func arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tail := -0.5
	var neck := 0.0
	var tip := 0.5
	var shaft := 0.17
	var head := 0.44
	for v: Vector3 in [
		# shaft
		Vector3(-shaft, 0, tail), Vector3(shaft, 0, tail), Vector3(shaft, 0, neck),
		Vector3(-shaft, 0, tail), Vector3(shaft, 0, neck), Vector3(-shaft, 0, neck),
		# head
		Vector3(-head, 0, neck), Vector3(head, 0, neck), Vector3(0, 0, tip),
	]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()
