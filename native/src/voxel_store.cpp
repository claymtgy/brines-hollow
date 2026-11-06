#include "voxel_store.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

std::vector<Color> VoxelStore::pal_colors;
std::vector<float> VoxelStore::pal_variation;
std::vector<uint8_t> VoxelStore::pal_flags;

// ------------------------------------------------------------------ helpers

namespace {

inline int floordiv32(int v) { return v >> 5; } // arithmetic shift == floor for /32
inline int mod32(int v) { return v & 31; }

inline uint32_t hash3(int x, int y, int z) {
	uint64_t h = (uint64_t)(int64_t)x * 374761393ull + (uint64_t)(int64_t)y * 668265263ull + (uint64_t)(int64_t)z * 1442695041ull;
	h = (h ^ (h >> 13)) * 1274126177ull;
	h = h ^ (h >> 16);
	return (uint32_t)(h & 0xFFFF);
}

struct FaceDef {
	int d[3];
	float n[3];
	float c[4][3];
	int ao[4][3][3]; // per corner: side1, side2, corner offsets
};

FaceDef FACES[6];
std::once_flag faces_once;

void init_faces() {
	const int dirs[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
	const int cuv[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
	for (int f = 0; f < 6; f++) {
		FaceDef &fd = FACES[f];
		const int *d = dirs[f];
		int a = d[0] != 0 ? 0 : (d[1] != 0 ? 1 : 2);
		int s = d[a];
		int u = (a + 1) % 3, v = (a + 2) % 3;
		for (int i = 0; i < 3; i++) {
			fd.d[i] = d[i];
			fd.n[i] = (float)d[i];
		}
		for (int k = 0; k < 4; k++) {
			float p[3] = { 0, 0, 0 };
			p[a] = s > 0 ? 1.f : 0.f;
			p[u] = (float)cuv[k][0];
			p[v] = (float)cuv[k][1];
			int su[3] = { 0, 0, 0 }, sv[3] = { 0, 0, 0 };
			su[u] = cuv[k][0] ? 1 : -1;
			sv[v] = cuv[k][1] ? 1 : -1;
			for (int i = 0; i < 3; i++) {
				fd.c[k][i] = p[i];
				fd.ao[k][0][i] = d[i] + su[i];
				fd.ao[k][1][i] = d[i] + sv[i];
				fd.ao[k][2][i] = d[i] + su[i] + sv[i];
			}
		}
		// Godot front faces are clockwise: cross(p1-p0, p2-p0) must point away from the normal.
		float e1[3], e2[3];
		for (int i = 0; i < 3; i++) {
			e1[i] = fd.c[1][i] - fd.c[0][i];
			e2[i] = fd.c[2][i] - fd.c[0][i];
		}
		float cr[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
		if (cr[0] * fd.n[0] + cr[1] * fd.n[1] + cr[2] * fd.n[2] > 0.f) {
			std::swap(fd.c[0], fd.c[3]);
			std::swap(fd.c[1], fd.c[2]);
			std::swap(fd.ao[0], fd.ao[3]);
			std::swap(fd.ao[1], fd.ao[2]);
		}
	}
}

const float AO_LUT[4] = { 0.52f, 0.70f, 0.86f, 1.0f };

struct MeshBuf {
	std::vector<Vector3> v, n;
	std::vector<Color> c;
	std::vector<int32_t> i;

	Variant to_arrays() const {
		if (v.empty()) {
			return Variant();
		}
		PackedVector3Array pv, pn;
		PackedColorArray pc;
		PackedInt32Array pi;
		pv.resize(v.size());
		pn.resize(n.size());
		pc.resize(c.size());
		pi.resize(i.size());
		memcpy(pv.ptrw(), v.data(), v.size() * sizeof(Vector3));
		memcpy(pn.ptrw(), n.data(), n.size() * sizeof(Vector3));
		memcpy(pc.ptrw(), c.data(), c.size() * sizeof(Color));
		memcpy(pi.ptrw(), i.data(), i.size() * sizeof(int32_t));
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = pv;
		arrays[Mesh::ARRAY_NORMAL] = pn;
		arrays[Mesh::ARRAY_COLOR] = pc;
		arrays[Mesh::ARRAY_INDEX] = pi;
		return arrays;
	}
};

} // namespace

// ------------------------------------------------------------------ bindings

void VoxelStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "size", "voxel_size"), &VoxelStore::setup);
	ClassDB::bind_method(D_METHOD("get_size"), &VoxelStore::get_size);
	ClassDB::bind_method(D_METHOD("get_voxel_size"), &VoxelStore::get_voxel_size);
	ClassDB::bind_static_method("VoxelStore", D_METHOD("set_palette", "colors", "variation", "flags"), &VoxelStore::set_palette);
	ClassDB::bind_method(D_METHOD("clear"), &VoxelStore::clear);
	ClassDB::bind_method(D_METHOD("get_voxel", "x", "y", "z"), &VoxelStore::get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "x", "y", "z", "m"), &VoxelStore::set_voxel);
	ClassDB::bind_method(D_METHOD("set_chunk_data", "chunk", "data"), &VoxelStore::set_chunk_data);
	ClassDB::bind_method(D_METHOD("get_chunk_data", "chunk"), &VoxelStore::get_chunk_data);
	ClassDB::bind_method(D_METHOD("get_chunk_coords"), &VoxelStore::get_chunk_coords);
	ClassDB::bind_method(D_METHOD("take_dirty"), &VoxelStore::take_dirty);
	ClassDB::bind_method(D_METHOD("get_chunk_count"), &VoxelStore::get_chunk_count);
	ClassDB::bind_method(D_METHOD("fill_from_columns", "heights", "kinds", "strata", "sea_low", "sea_high", "mats"), &VoxelStore::fill_from_columns);
	ClassDB::bind_method(D_METHOD("dig_sphere", "center", "radius"), &VoxelStore::dig_sphere);
	ClassDB::bind_method(D_METHOD("place_sphere", "center", "radius", "m"), &VoxelStore::place_sphere);
	ClassDB::bind_method(D_METHOD("stamp", "data", "dims", "base"), &VoxelStore::stamp);
	ClassDB::bind_method(D_METHOD("fill_down", "x", "y", "z", "m", "max_depth"), &VoxelStore::fill_down);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "dir", "max_dist", "see_through_foliage"), &VoxelStore::raycast);
	ClassDB::bind_method(D_METHOD("aabb_collides", "min_m", "max_m"), &VoxelStore::aabb_collides);
	ClassDB::bind_method(D_METHOD("mesh_chunk", "chunk"), &VoxelStore::mesh_chunk);
	ClassDB::bind_static_method("VoxelStore", D_METHOD("mesh_grid", "data", "dims", "scale"), &VoxelStore::mesh_grid);
	ClassDB::bind_method(D_METHOD("set_generator", "gen"), &VoxelStore::set_generator);
	ClassDB::bind_method(D_METHOD("generate_column", "col"), &VoxelStore::generate_column);
	ClassDB::bind_method(D_METHOD("is_column_generated", "col"), &VoxelStore::is_column_generated);
	ClassDB::bind_method(D_METHOD("unload_column", "col"), &VoxelStore::unload_column);
	ClassDB::bind_method(D_METHOD("get_generated_columns"), &VoxelStore::get_generated_columns);
	ClassDB::bind_method(D_METHOD("has_chunk", "chunk"), &VoxelStore::has_chunk);
	BIND_CONSTANT(CS);
}

// ------------------------------------------------------------------ setup / access

void VoxelStore::setup(const Vector3i &p_size, float p_voxel_size) {
	std::unique_lock lock(mtx);
	size = p_size;
	vs = p_voxel_size;
	chunks.clear();
	gen_cols.clear();
	edited_cols.clear();
}

void VoxelStore::set_palette(const PackedColorArray &colors, const PackedFloat32Array &variation, const PackedByteArray &flags) {
	pal_colors.assign(256, Color(1, 0, 1));
	pal_variation.assign(256, 0.f);
	pal_flags.assign(256, 0);
	for (int i = 0; i < colors.size() && i < 256; i++) {
		pal_colors[i] = colors[i];
	}
	for (int i = 0; i < variation.size() && i < 256; i++) {
		pal_variation[i] = variation[i];
	}
	for (int i = 0; i < flags.size() && i < 256; i++) {
		pal_flags[i] = flags[i];
	}
}

void VoxelStore::clear() {
	std::unique_lock lock(mtx);
	chunks.clear();
	gen_cols.clear();
	edited_cols.clear();
	std::lock_guard dl(dirty_mtx);
	dirty.clear();
}

uint8_t VoxelStore::get_raw(int x, int y, int z) const {
	if (y < 0) {
		return BEDROCK;
	}
	if (!in_bounds(x, y, z)) {
		return 0;
	}
	const uint8_t *ch = chunk_ptr(floordiv32(x), floordiv32(y), floordiv32(z));
	if (!ch) {
		// Not generated yet: answer from the height field so nothing falls through the world.
		if (gen.is_valid() && !gen_cols.count(ckey(floordiv32(x), floordiv32(z)))) {
			return y <= gen->column_height(x, z) ? 2 : 0; // 2 = stone
		}
		return 0;
	}
	return ch[mod32(x) + CS * (mod32(z) + CS * mod32(y))];
}

bool VoxelStore::set_raw(int x, int y, int z, uint8_t m) {
	if (!in_bounds(x, y, z)) {
		return false;
	}
	ensure_column_locked(floordiv32(x), floordiv32(z));
	int64_t k = key(floordiv32(x), floordiv32(y), floordiv32(z));
	auto it = chunks.find(k);
	uint8_t *ch;
	if (it == chunks.end()) {
		if (m == 0) {
			return false;
		}
		auto mem = std::make_unique<uint8_t[]>(CV);
		memset(mem.get(), 0, CV);
		ch = mem.get();
		chunks.emplace(k, std::move(mem));
	} else {
		ch = it->second.get();
	}
	uint8_t &cell = ch[mod32(x) + CS * (mod32(z) + CS * mod32(y))];
	if (cell == m) {
		return false;
	}
	cell = m;
	edited_cols.insert(ckey(floordiv32(x), floordiv32(z)));
	mark_voxel(x, y, z);
	return true;
}

// ------------------------------------------------------------------ streaming

void VoxelStore::set_generator(const Ref<ArchipelagoGen> &p_gen) {
	std::unique_lock lock(mtx);
	gen = p_gen;
}

void VoxelStore::ensure_column_locked(int cx, int cz) {
	if (!gen.is_valid() || cx < 0 || cz < 0 || cx * CS >= size.x || cz * CS >= size.z) {
		return;
	}
	int64_t ck = ckey(cx, cz);
	if (gen_cols.count(ck)) {
		return;
	}
	std::vector<std::unique_ptr<uint8_t[]>> out;
	gen->generate_column(cx, cz, out);
	for (int cy = 0; cy < (int)out.size(); cy++) {
		if (out[cy] && !chunks.count(key(cx, cy, cz))) {
			chunks.emplace(key(cx, cy, cz), std::move(out[cy]));
		}
	}
	gen_cols.insert(ck);
}

void VoxelStore::ensure_box_locked(int x0, int z0, int x1, int z1) {
	for (int cz = floordiv32(z0); cz <= floordiv32(z1); cz++)
		for (int cx = floordiv32(x0); cx <= floordiv32(x1); cx++) ensure_column_locked(cx, cz);
}

bool VoxelStore::generate_column(const Vector2i &col) {
	if (!gen.is_valid()) {
		return false;
	}
	{
		std::shared_lock lock(mtx);
		if (gen_cols.count(ckey(col.x, col.y))) {
			return false;
		}
	}
	std::vector<std::unique_ptr<uint8_t[]>> out;
	gen->generate_column(col.x, col.y, out);
	std::unique_lock lock(mtx);
	int64_t ck = ckey(col.x, col.y);
	if (gen_cols.count(ck)) {
		return false;
	}
	for (int cy = 0; cy < (int)out.size(); cy++) {
		if (out[cy] && !chunks.count(key(col.x, cy, col.y))) {
			chunks.emplace(key(col.x, cy, col.y), std::move(out[cy]));
		}
	}
	gen_cols.insert(ck);
	return true;
}

bool VoxelStore::is_column_generated(const Vector2i &col) const {
	std::shared_lock lock(mtx);
	return gen_cols.count(ckey(col.x, col.y)) > 0;
}

bool VoxelStore::unload_column(const Vector2i &col) {
	std::unique_lock lock(mtx);
	int64_t ck = ckey(col.x, col.y);
	if (edited_cols.count(ck)) {
		return false;
	}
	const int layers = (size.y + CS - 1) / CS;
	for (int cy = 0; cy < layers; cy++) {
		chunks.erase(key(col.x, cy, col.y));
	}
	gen_cols.erase(ck);
	return true;
}

TypedArray<Vector2i> VoxelStore::get_generated_columns() const {
	std::shared_lock lock(mtx);
	TypedArray<Vector2i> out;
	for (int64_t k : gen_cols) {
		Vector3i c = unkey(k);
		out.push_back(Vector2i(c.x, c.z));
	}
	return out;
}

bool VoxelStore::has_chunk(const Vector3i &c) const {
	std::shared_lock lock(mtx);
	return chunk_ptr(c.x, c.y, c.z) != nullptr;
}

void VoxelStore::mark(int cx, int cy, int cz) {
	if (cx < 0 || cy < 0 || cz < 0 || cx * CS >= size.x || cy * CS >= size.y || cz * CS >= size.z) {
		return;
	}
	std::lock_guard dl(dirty_mtx);
	dirty.insert(key(cx, cy, cz));
}

void VoxelStore::mark_voxel(int x, int y, int z) {
	int cx = floordiv32(x), cy = floordiv32(y), cz = floordiv32(z);
	int lx = mod32(x), ly = mod32(y), lz = mod32(z);
	mark(cx, cy, cz);
	if (lx == 0) mark(cx - 1, cy, cz);
	if (lx == CS - 1) mark(cx + 1, cy, cz);
	if (ly == 0) mark(cx, cy - 1, cz);
	if (ly == CS - 1) mark(cx, cy + 1, cz);
	if (lz == 0) mark(cx, cy, cz - 1);
	if (lz == CS - 1) mark(cx, cy, cz + 1);
}

int VoxelStore::get_voxel(int x, int y, int z) const {
	std::shared_lock lock(mtx);
	return get_raw(x, y, z);
}

bool VoxelStore::set_voxel(int x, int y, int z, int m) {
	std::unique_lock lock(mtx);
	ensure_box_locked(x, z, x, z);
	return set_raw(x, y, z, (uint8_t)m);
}

void VoxelStore::set_chunk_data(const Vector3i &c, const PackedByteArray &data) {
	std::unique_lock lock(mtx);
	int64_t k = key(c.x, c.y, c.z);
	if (data.size() != CV) {
		chunks.erase(k);
		return;
	}
	auto mem = std::make_unique<uint8_t[]>(CV);
	memcpy(mem.get(), data.ptr(), CV);
	chunks[k] = std::move(mem);
}

PackedByteArray VoxelStore::get_chunk_data(const Vector3i &c) const {
	std::shared_lock lock(mtx);
	PackedByteArray out;
	const uint8_t *ch = chunk_ptr(c.x, c.y, c.z);
	if (ch) {
		out.resize(CV);
		memcpy(out.ptrw(), ch, CV);
	}
	return out;
}

TypedArray<Vector3i> VoxelStore::get_chunk_coords() const {
	std::shared_lock lock(mtx);
	TypedArray<Vector3i> out;
	for (const auto &kv : chunks) {
		out.push_back(unkey(kv.first));
	}
	return out;
}

TypedArray<Vector3i> VoxelStore::take_dirty() {
	std::lock_guard dl(dirty_mtx);
	TypedArray<Vector3i> out;
	for (int64_t k : dirty) {
		out.push_back(unkey(k));
	}
	dirty.clear();
	return out;
}

int VoxelStore::get_chunk_count() const {
	std::shared_lock lock(mtx);
	return (int)chunks.size();
}

// ------------------------------------------------------------------ generation

void VoxelStore::fill_from_columns(const PackedInt32Array &heights, const PackedByteArray &kinds,
		const PackedByteArray &strata, int sea_low, int sea_high, const PackedByteArray &mats) {
	// mats: BEDROCK, STONE, SANDSTONE_A, SANDSTONE_B, SANDSTONE_C, SAND, WET_SAND, GRAVEL, DIRT, GRASS, GRASS_DRY
	if (mats.size() < 11 || heights.size() != size.x * size.z) {
		ERR_PRINT("fill_from_columns: bad arguments");
		return;
	}
	enum { M_BEDROCK, M_STONE, M_SA, M_SB, M_SC, M_SAND, M_WET, M_GRAVEL, M_DIRT, M_GRASS, M_GRASS_DRY };
	enum { K_BEACH, K_GRASS, K_ROCK, K_SEABED, K_GRASS_DRY };
	const uint8_t *mt = mats.ptr();
	const int32_t *hp = heights.ptr();
	const uint8_t *kp = kinds.ptr();
	const uint8_t *sp = strata.ptr();
	auto strata_at = [&](int y, int off) -> uint8_t {
		if (y < 12) {
			return mt[M_STONE];
		}
		int band = (int)std::floor((y + off) / 4.0);
		band = ((band % 5) + 5) % 5;
		static const int order[5] = { M_SA, M_SB, M_SC, M_SA, M_STONE };
		return mt[order[band]];
	};
	std::unique_lock lock(mtx);
	const int ncx = (size.x + CS - 1) / CS, ncy = (size.y + CS - 1) / CS, ncz = (size.z + CS - 1) / CS;
	for (int cy = 0; cy < ncy; cy++) {
		for (int cz = 0; cz < ncz; cz++) {
			for (int cx = 0; cx < ncx; cx++) {
				const int y0 = cy * CS, y1 = y0 + CS - 1;
				std::unique_ptr<uint8_t[]> mem;
				for (int lz = 0; lz < CS; lz++) {
					int z = cz * CS + lz;
					if (z >= size.z) break;
					for (int lx = 0; lx < CS; lx++) {
						int x = cx * CS + lx;
						if (x >= size.x) break;
						int ci = x + size.x * z;
						int h = hp[ci];
						if (h < y0) continue;
						if (!mem) {
							mem = std::make_unique<uint8_t[]>(CV);
							memset(mem.get(), 0, CV);
						}
						int k = kp[ci];
						int off = sp[ci];
						int top = std::min(h, y1);
						for (int y = y0; y <= top; y++) {
							int depth = h - y;
							uint8_t m;
							if (y == 0) {
								m = mt[M_BEDROCK];
							} else if (k == K_BEACH) {
								if (depth < 4) {
									m = h < sea_high ? mt[M_WET] : mt[M_SAND];
									if (h < sea_low && hash3(x, y, z) % 7 == 0) m = mt[M_GRAVEL];
								} else {
									m = strata_at(y, off);
								}
							} else if (k == K_GRASS || k == K_GRASS_DRY) {
								if (depth == 0) m = k == K_GRASS_DRY ? mt[M_GRASS_DRY] : mt[M_GRASS];
								else if (depth < 4) m = mt[M_DIRT];
								else m = strata_at(y, off);
							} else if (k == K_SEABED) {
								if (depth < 3) m = hash3(x, y, z) % 5 == 0 ? mt[M_GRAVEL] : mt[M_SAND];
								else m = strata_at(y, off);
							} else {
								m = strata_at(y, off);
							}
							mem[lx + CS * (lz + CS * (y - y0))] = m;
						}
					}
				}
				if (mem) {
					chunks[key(cx, cy, cz)] = std::move(mem);
				}
			}
		}
	}
}

// ------------------------------------------------------------------ edits

Dictionary VoxelStore::dig_sphere(const Vector3i &c, int r) {
	std::unique_lock lock(mtx);
	ensure_box_locked(c.x - r, c.z - r, c.x + r, c.z + r);
	int counts[256] = { 0 };
	int n = 0;
	int r2 = r * r + r;
	for (int y = -r; y <= r; y++) {
		for (int z = -r; z <= r; z++) {
			for (int x = -r; x <= r; x++) {
				if (x * x + y * y + z * z > r2) continue;
				int px = c.x + x, py = c.y + y, pz = c.z + z;
				if (py <= 0) continue;
				uint8_t m = get_raw(px, py, pz);
				if (m == 0) continue;
				counts[m]++;
				n++;
				set_raw(px, py, pz, 0);
			}
		}
	}
	int best = 0;
	for (int m = 1; m < 256; m++) {
		if (counts[m] > counts[best]) best = m;
	}
	Dictionary d;
	d["count"] = n;
	d["mat"] = n > 0 ? best : 0;
	return d;
}

int VoxelStore::place_sphere(const Vector3i &c, int r, int m) {
	std::unique_lock lock(mtx);
	ensure_box_locked(c.x - r, c.z - r, c.x + r, c.z + r);
	int n = 0;
	int r2 = r * r + r;
	for (int y = -r; y <= r; y++) {
		for (int z = -r; z <= r; z++) {
			for (int x = -r; x <= r; x++) {
				if (x * x + y * y + z * z > r2) continue;
				int px = c.x + x, py = c.y + y, pz = c.z + z;
				if (get_raw(px, py, pz) == 0 && set_raw(px, py, pz, (uint8_t)m)) n++;
			}
		}
	}
	return n;
}

void VoxelStore::stamp(const PackedByteArray &data, const Vector3i &dims, const Vector3i &base) {
	if (data.size() != dims.x * dims.y * dims.z) {
		ERR_PRINT("stamp: data size mismatch");
		return;
	}
	std::unique_lock lock(mtx);
	ensure_box_locked(base.x, base.z, base.x + dims.x - 1, base.z + dims.z - 1);
	const uint8_t *d = data.ptr();
	for (int y = 0; y < dims.y; y++) {
		for (int z = 0; z < dims.z; z++) {
			for (int x = 0; x < dims.x; x++) {
				uint8_t m = d[x + dims.x * (z + dims.z * y)];
				if (m == 0) continue;
				set_raw(base.x + x, base.y + y, base.z + z, m == CLEAR ? 0 : m);
			}
		}
	}
}

int VoxelStore::fill_down(int x, int y, int z, int m, int max_depth) {
	std::unique_lock lock(mtx);
	ensure_box_locked(x, z, x, z);
	int n = 0;
	for (int k = 0; k < max_depth; k++) {
		if (y - k < 1 || get_raw(x, y - k, z) != 0) break;
		set_raw(x, y - k, z, (uint8_t)m);
		n++;
	}
	return n;
}

// ------------------------------------------------------------------ queries

Dictionary VoxelStore::raycast(const Vector3 &origin, const Vector3 &dir, float max_dist, bool see_through_foliage) const {
	std::shared_lock lock(mtx);
	Vector3 o = origin / vs;
	Vector3 d = dir.normalized();
	int cell[3] = { (int)std::floor(o.x), (int)std::floor(o.y), (int)std::floor(o.z) };
	int step[3];
	double t_max[3], t_delta[3];
	for (int a = 0; a < 3; a++) {
		double da = d[a];
		step[a] = da > 0 ? 1 : (da < 0 ? -1 : 0);
		if (std::abs(da) < 1e-9) {
			t_max[a] = INFINITY;
			t_delta[a] = INFINITY;
		} else {
			double next_b = (double)(cell[a] + (step[a] > 0 ? 1 : 0));
			t_max[a] = (next_b - o[a]) / da;
			t_delta[a] = std::abs(1.0 / da);
		}
	}
	int normal[3] = { 0, 0, 0 };
	double max_t = max_dist / vs;
	double t = 0.0;
	while (t <= max_t) {
		uint8_t m = get_raw(cell[0], cell[1], cell[2]);
		if (m != 0 && !(see_through_foliage && (pal_flags.size() > m) && (pal_flags[m] & F_FOLIAGE))) {
			Dictionary hit;
			hit["cell"] = Vector3i(cell[0], cell[1], cell[2]);
			hit["normal"] = Vector3i(normal[0], normal[1], normal[2]);
			hit["dist"] = t * vs;
			return hit;
		}
		int a = (t_max[0] < t_max[1] && t_max[0] < t_max[2]) ? 0 : (t_max[1] < t_max[2] ? 1 : 2);
		cell[a] += step[a];
		t = t_max[a];
		t_max[a] += t_delta[a];
		normal[0] = normal[1] = normal[2] = 0;
		normal[a] = -step[a];
		if (cell[1] < -2 || cell[1] > size.y + 2) {
			break;
		}
	}
	return Dictionary();
}

bool VoxelStore::aabb_collides(const Vector3 &min_m, const Vector3 &max_m) const {
	std::shared_lock lock(mtx);
	int x0 = (int)std::floor(min_m.x / vs), x1 = (int)std::floor(max_m.x / vs);
	int y0 = (int)std::floor(min_m.y / vs), y1 = (int)std::floor(max_m.y / vs);
	int z0 = (int)std::floor(min_m.z / vs), z1 = (int)std::floor(max_m.z / vs);
	for (int y = y0; y <= y1; y++) {
		for (int z = z0; z <= z1; z++) {
			for (int x = x0; x <= x1; x++) {
				if (get_raw(x, y, z) != 0) return true;
			}
		}
	}
	return false;
}

// ------------------------------------------------------------------ meshing

Array VoxelStore::mesh_chunk(const Vector3i &c) const {
	std::vector<uint8_t> P((size_t)PS * PS * PS);
	const int gx0 = c.x * CS, gy0 = c.y * CS, gz0 = c.z * CS;
	{
		std::shared_lock lock(mtx);
		size_t o = 0;
		for (int py = -1; py <= CS; py++) {
			int gy = gy0 + py;
			for (int pz = -1; pz <= CS; pz++) {
				int gz = gz0 + pz;
				P[o] = get_raw(gx0 - 1, gy, gz);
				if (gy < 0) {
					memset(&P[o + 1], BEDROCK, CS);
				} else if (gy >= size.y || gz < 0 || gz >= size.z) {
					memset(&P[o + 1], 0, CS);
				} else {
					const uint8_t *ch = chunk_ptr(c.x, floordiv32(gy), floordiv32(gz));
					if (ch) {
						memcpy(&P[o + 1], ch + CS * (mod32(gz) + CS * mod32(gy)), CS);
					} else {
						memset(&P[o + 1], 0, CS);
					}
				}
				P[o + CS + 1] = get_raw(gx0 + CS, gy, gz);
				o += PS;
			}
		}
	}
	return build_mesh_greedy(P.data(), PS, PS, PS, vs);
}

Array VoxelStore::mesh_grid(const PackedByteArray &data, const Vector3i &dims, float scale) {
	const int px = dims.x + 2, py = dims.y + 2, pz = dims.z + 2;
	std::vector<uint8_t> P((size_t)px * py * pz, 0);
	if (data.size() == dims.x * dims.y * dims.z) {
		const uint8_t *d = data.ptr();
		for (int y = 0; y < dims.y; y++)
			for (int z = 0; z < dims.z; z++)
				for (int x = 0; x < dims.x; x++) {
					uint8_t m = d[x + dims.x * (z + dims.z * y)];
					if (m != 0 && m != CLEAR) P[(x + 1) + px * ((z + 1) + pz * (y + 1))] = m;
				}
	}
	return build_mesh(P.data(), px, py, pz, scale, 0, 0, 0);
}

Array VoxelStore::build_mesh(const uint8_t *P, int px, int py, int pz, float scale, int wx, int wy, int wz) {
	std::call_once(faces_once, init_faces);
	const int ys = px * pz;
	int noff[6];
	int aooff[6][12];
	for (int f = 0; f < 6; f++) {
		const FaceDef &fd = FACES[f];
		noff[f] = fd.d[0] + px * fd.d[2] + ys * fd.d[1];
		for (int k = 0; k < 4; k++)
			for (int j = 0; j < 3; j++) {
				const int *o = fd.ao[k][j];
				aooff[f][k * 3 + j] = o[0] + px * o[2] + ys * o[1];
			}
	}
	const bool have_pal = !pal_colors.empty();
	MeshBuf out[2];
	out[0].v.reserve(16384);
	for (int y = 1; y < py - 1; y++) {
		for (int z = 1; z < pz - 1; z++) {
			int i = 1 + px * (z + pz * y);
			for (int x = 1; x < px - 1; x++, i++) {
				uint8_t m = P[i];
				if (m == 0) continue;
				bool have_color = false;
				Color base;
				for (int f = 0; f < 6; f++) {
					if (P[i + noff[f]] != 0) continue;
					if (!have_color) {
						have_color = true;
						float var = have_pal ? pal_variation[m] : 0.f;
						float b = 1.0f + ((float)hash3(wx + x - 1, wy + y - 1, wz + z - 1) / 65535.f - 0.5f) * 2.f * var;
						base = have_pal ? pal_colors[m] : Color(1, 0, 1);
						base.r *= b;
						base.g *= b;
						base.b *= b;
						base.a = 1.f;
					}
					int ao[4];
					const int *ofs = aooff[f];
					for (int k = 0; k < 4; k++) {
						int s1 = P[i + ofs[k * 3]] != 0;
						int s2 = P[i + ofs[k * 3 + 1]] != 0;
						int cc = P[i + ofs[k * 3 + 2]] != 0;
						ao[k] = (s1 && s2) ? 0 : 3 - (s1 + s2 + cc);
					}
					const bool emissive = have_pal && (pal_flags[m] & F_EMISSIVE);
					MeshBuf &mb = out[emissive ? 1 : 0];
					const FaceDef &fd = FACES[f];
					int32_t bi = (int32_t)mb.v.size();
					Vector3 nrm(fd.n[0], fd.n[1], fd.n[2]);
					for (int k = 0; k < 4; k++) {
						mb.v.emplace_back((x - 1 + fd.c[k][0]) * scale, (y - 1 + fd.c[k][1]) * scale, (z - 1 + fd.c[k][2]) * scale);
						mb.n.push_back(nrm);
						float a = emissive ? 1.f : AO_LUT[ao[k]];
						mb.c.emplace_back(base.r * a, base.g * a, base.b * a, 1.f);
					}
					if (ao[0] + ao[2] < ao[1] + ao[3]) {
						const int32_t t[6] = { bi + 1, bi + 2, bi + 3, bi + 1, bi + 3, bi };
						mb.i.insert(mb.i.end(), t, t + 6);
					} else {
						const int32_t t[6] = { bi, bi + 1, bi + 2, bi, bi + 2, bi + 3 };
						mb.i.insert(mb.i.end(), t, t + 6);
					}
				}
			}
		}
	}
	Array res;
	res.push_back(out[0].to_arrays());
	res.push_back(out[1].to_arrays());
	return res;
}

Array VoxelStore::build_mesh_greedy(const uint8_t *P, int px, int py, int pz, float scale) {
	std::call_once(faces_once, init_faces);
	const int ys = px * pz;
	const int D[3] = { px - 2, py - 2, pz - 2 };
	const bool have_pal = !pal_colors.empty();
	MeshBuf out[2];
	out[0].v.reserve(8192);
	std::vector<uint32_t> mask;
	for (int f = 0; f < 6; f++) {
		const FaceDef &fd = FACES[f];
		const int a = fd.d[0] != 0 ? 0 : (fd.d[1] != 0 ? 1 : 2);
		const int s = fd.d[a];
		const int u = (a + 1) % 3, v = (a + 2) % 3;
		const int noff = fd.d[0] + px * fd.d[2] + ys * fd.d[1];
		int aooff[12];
		for (int k = 0; k < 4; k++)
			for (int j = 0; j < 3; j++) {
				const int *o = fd.ao[k][j];
				aooff[k * 3 + j] = o[0] + px * o[2] + ys * o[1];
			}
		// corner k sits at (cu,cv) in the face's u/v parameter space
		int cu[4], cv[4];
		for (int k = 0; k < 4; k++) {
			cu[k] = fd.c[k][u] > 0.5f ? 1 : 0;
			cv[k] = fd.c[k][v] > 0.5f ? 1 : 0;
		}
		const int DU = D[u], DV = D[v];
		mask.assign((size_t)DU * DV, 0);
		for (int sl = 0; sl < D[a]; sl++) {
			// build the mask: key = material | ao corners (2 bits each) << 8
			bool any = false;
			for (int iv = 0; iv < DV; iv++) {
				for (int iu = 0; iu < DU; iu++) {
					int c[3];
					c[a] = sl; c[u] = iu; c[v] = iv;
					int i = (c[0] + 1) + px * ((c[2] + 1) + pz * (c[1] + 1));
					uint8_t m = P[i];
					uint32_t key = 0;
					if (m != 0 && P[i + noff] == 0) {
						key = m;
						for (int k = 0; k < 4; k++) {
							int s1 = P[i + aooff[k * 3]] != 0;
							int s2 = P[i + aooff[k * 3 + 1]] != 0;
							int cc = P[i + aooff[k * 3 + 2]] != 0;
							int ao = (s1 && s2) ? 0 : 3 - (s1 + s2 + cc);
							key |= (uint32_t)ao << (8 + 2 * k);
						}
						any = true;
					}
					mask[iu + DU * iv] = key;
				}
			}
			if (!any) continue;
			// greedy merge
			for (int iv = 0; iv < DV; iv++) {
				for (int iu = 0; iu < DU;) {
					uint32_t key = mask[iu + DU * iv];
					if (!key) { iu++; continue; }
					int w = 1;
					while (iu + w < DU && mask[iu + w + DU * iv] == key) w++;
					int h = 1;
					bool grow = true;
					while (iv + h < DV && grow) {
						for (int k = 0; k < w; k++)
							if (mask[iu + k + DU * (iv + h)] != key) { grow = false; break; }
						if (grow) h++;
					}
					for (int y2 = 0; y2 < h; y2++)
						for (int x2 = 0; x2 < w; x2++) mask[iu + x2 + DU * (iv + y2)] = 0;
					// emit
					uint8_t m = key & 0xFF;
					int ao[4];
					for (int k = 0; k < 4; k++) ao[k] = (key >> (8 + 2 * k)) & 3;
					const bool emissive = have_pal && (pal_flags[m] & F_EMISSIVE);
					MeshBuf &mb = out[emissive ? 1 : 0];
					Color base = have_pal ? pal_colors[m] : Color(1, 0, 1);
					float var = have_pal ? pal_variation[m] : 0.f;
					int32_t bi = (int32_t)mb.v.size();
					Vector3 nrm(fd.n[0], fd.n[1], fd.n[2]);
					for (int k = 0; k < 4; k++) {
						float p[3];
						p[a] = (float)(sl + (s > 0 ? 1 : 0));
						p[u] = (float)(iu + cu[k] * w);
						p[v] = (float)(iv + cv[k] * h);
						mb.v.emplace_back(p[0] * scale, p[1] * scale, p[2] * scale);
						mb.n.push_back(nrm);
						float af = emissive ? 1.f : AO_LUT[ao[k]];
						mb.c.emplace_back(base.r * af, base.g * af, base.b * af, var);
					}
					if (ao[0] + ao[2] < ao[1] + ao[3]) {
						const int32_t t[6] = { bi + 1, bi + 2, bi + 3, bi + 1, bi + 3, bi };
						mb.i.insert(mb.i.end(), t, t + 6);
					} else {
						const int32_t t[6] = { bi, bi + 1, bi + 2, bi, bi + 2, bi + 3 };
						mb.i.insert(mb.i.end(), t, t + 6);
					}
					iu += w;
				}
			}
		}
	}
	Array res;
	res.push_back(out[0].to_arrays());
	res.push_back(out[1].to_arrays());
	return res;
}
