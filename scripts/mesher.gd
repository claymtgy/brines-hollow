class_name Mesher
extends RefCounted
## Thin wrapper over the native mesher (VoxelStore.mesh_grid) for small standalone
## models: characters, tools, prefab ghosts. Terrain chunks mesh via VoxelStore.mesh_chunk.


static func hash3(x: int, y: int, z: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0xFFFF


## Build an ArrayMesh from a dense grid (index x + sx*(z + sz*y)); CLEAR cells are skipped.
static func mesh_from_grid(data: PackedByteArray, sx: int, sy: int, sz: int, scale: float,
		mat: Material, emissive_mat: Material) -> ArrayMesh:
	var res: Array = VoxelStore.mesh_grid(data, Vector3i(sx, sy, sz), scale)
	var mesh := ArrayMesh.new()
	if res[0] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	if res[1] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[1])
		mesh.surface_set_material(mesh.get_surface_count() - 1, emissive_mat)
	return mesh
