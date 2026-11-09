#include "archipelago.h"
#include "voxel_store.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

// ------------------------------------------------------------------ hashing / rng

namespace {

inline uint64_t splitmix(uint64_t x) {
	x += 0x9E3779B97F4A7C15ull;
	x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
	x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
	return x ^ (x >> 31);
}

inline uint64_t hcomb(uint64_t a, int64_t b) { return splitmix(a ^ (uint64_t)(b * 0x632BE59BD9B4E019ll)); }

inline uint32_t vhash(uint64_t seed, int x, int y, int z) {
	return (uint32_t)hcomb(hcomb(hcomb(seed, x), y), z);
}

struct Rng {
	uint64_t s;
	explicit Rng(uint64_t seed) : s(seed ? seed : 1) {}
	uint64_t next() { s = splitmix(s); return s; }
	float f() { return (float)(next() >> 40) / (float)(1ull << 24); }
	float range(float a, float b) { return a + (b - a) * f(); }
	int irange(int a, int b) { return a + (int)(next() % (uint64_t)(b - a + 1)); }
};

inline float smoothstep(float a, float b, float x) {
	float t = std::clamp((x - a) / (b - a), 0.f, 1.f);
	return t * t * (3.f - 2.f * t);
}
inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }

// 3D value noise for leaf-crown wobble.
float vnoise3(uint64_t seed, float x, float y, float z) {
	int xi = (int)std::floor(x), yi = (int)std::floor(y), zi = (int)std::floor(z);
	float fx = x - xi, fy = y - yi, fz = z - zi;
	fx = fx * fx * (3 - 2 * fx);
	fy = fy * fy * (3 - 2 * fy);
	fz = fz * fz * (3 - 2 * fz);
	auto v = [&](int a, int b, int c) { return (vhash(seed, xi + a, yi + b, zi + c) & 0xFFFF) / 32767.5f - 1.f; };
	float x00 = lerpf(v(0, 0, 0), v(1, 0, 0), fx), x10 = lerpf(v(0, 1, 0), v(1, 1, 0), fx);
	float x01 = lerpf(v(0, 0, 1), v(1, 0, 1), fx), x11 = lerpf(v(0, 1, 1), v(1, 1, 1), fx);
	return lerpf(lerpf(x00, x10, fy), lerpf(x01, x11, fy), fz);
}

const float GRAD2[8][2] = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };

// Column buffer: 32 x H x 32, index lx + 32*(lz + 32*y)
struct ColBuf {
	int x0, z0, h;
	uint8_t *d;
	inline bool in(int x, int y, int z) const {
		return x >= x0 && x < x0 + 32 && z >= z0 && z < z0 + 32 && y >= 0 && y < h;
	}
	inline uint8_t &at(int x, int y, int z) { return d[(x - x0) + 32 * ((z - z0) + 32 * y)]; }
	inline void set(int x, int y, int z, uint8_t m) {
		if (in(x, y, z)) at(x, y, z) = m;
	}
	inline void set_air_only(int x, int y, int z, uint8_t m) {
		if (in(x, y, z) && at(x, y, z) == 0) at(x, y, z) = m;
	}
};

} // namespace

// ------------------------------------------------------------------ simplex

void Simplex2::init(uint64_t seed, float p_freq, int p_octaves) {
	freq = p_freq;
	octaves = p_octaves;
	uint8_t p[256];
	for (int i = 0; i < 256; i++) p[i] = (uint8_t)i;
	Rng r(seed);
	for (int i = 255; i > 0; i--) {
		int j = (int)(r.next() % (uint64_t)(i + 1));
		std::swap(p[i], p[j]);
	}
	for (int i = 0; i < 512; i++) perm[i] = p[i & 255];
}

float Simplex2::noise(float x, float y) const {
	const float F2 = 0.366025403f, G2 = 0.211324865f;
	float s = (x + y) * F2;
	int i = (int)std::floor(x + s), j = (int)std::floor(y + s);
	float t = (i + j) * G2;
	float x0 = x - (i - t), y0 = y - (j - t);
	int i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1;
	float x1 = x0 - i1 + G2, y1 = y0 - j1 + G2;
	float x2 = x0 - 1.f + 2.f * G2, y2 = y0 - 1.f + 2.f * G2;
	int ii = i & 255, jj = j & 255;
	float n = 0.f;
	float t0 = 0.5f - x0 * x0 - y0 * y0;
	if (t0 > 0) {
		const float *g = GRAD2[perm[ii + perm[jj]] & 7];
		t0 *= t0;
		n += t0 * t0 * (g[0] * x0 + g[1] * y0);
	}
	float t1 = 0.5f - x1 * x1 - y1 * y1;
	if (t1 > 0) {
		const float *g = GRAD2[perm[ii + i1 + perm[jj + j1]] & 7];
		t1 *= t1;
		n += t1 * t1 * (g[0] * x1 + g[1] * y1);
	}
	float t2 = 0.5f - x2 * x2 - y2 * y2;
	if (t2 > 0) {
		const float *g = GRAD2[perm[ii + 1 + perm[jj + 1]] & 7];
		t2 *= t2;
		n += t2 * t2 * (g[0] * x2 + g[1] * y2);
	}
	return std::clamp(70.f * n, -1.f, 1.f);
}

float Simplex2::fbm(float x, float y) const {
	float sum = 0.f, amp = 1.f, norm = 0.f, f = freq;
	for (int o = 0; o < octaves; o++) {
		sum += amp * noise(x * f, y * f);
		norm += amp;
		amp *= 0.5f;
		f *= 2.f;
	}
	return sum / norm;
}

// ------------------------------------------------------------------ bindings

void ArchipelagoGen::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "seed", "size", "sea_mid", "tide_amp", "mats"), &ArchipelagoGen::configure);
	ClassDB::bind_method(D_METHOD("set_layout", "params"), &ArchipelagoGen::set_layout);
	ClassDB::bind_method(D_METHOD("column_height", "x", "z"), &ArchipelagoGen::column_height);
	ClassDB::bind_method(D_METHOD("column_kind", "x", "z"), &ArchipelagoGen::column_kind);
	ClassDB::bind_method(D_METHOD("column_island", "x", "z"), &ArchipelagoGen::column_island);
	ClassDB::bind_method(D_METHOD("get_islands"), &ArchipelagoGen::get_islands);
	ClassDB::bind_method(D_METHOD("get_cave_sites"), &ArchipelagoGen::get_cave_sites);
	ClassDB::bind_method(D_METHOD("cave_near", "x", "z", "margin"), &ArchipelagoGen::cave_near);
	ClassDB::bind_method(D_METHOD("land_regions", "region_vox"), &ArchipelagoGen::land_regions);
	ClassDB::bind_method(D_METHOD("add_stamp", "data", "dims", "base", "foundation"), &ArchipelagoGen::add_stamp);
	ClassDB::bind_method(D_METHOD("clear_stamps"), &ArchipelagoGen::clear_stamps);
	ClassDB::bind_method(D_METHOD("add_tree_clear", "x", "z", "r"), &ArchipelagoGen::add_tree_clear);
	ClassDB::bind_method(D_METHOD("generate_column_debug", "cx", "cz"), &ArchipelagoGen::generate_column_debug);
	ClassDB::bind_method(D_METHOD("build_lod", "region", "region_vox", "step"), &ArchipelagoGen::build_lod);
}

// ------------------------------------------------------------------ configure

void ArchipelagoGen::set_layout(const Dictionary &d) {
	home_r = (float)d.get("home_r", home_r);
	std_rmin = (float)d.get("std_rmin", std_rmin);
	std_rmax = (float)d.get("std_rmax", std_rmax);
	islet_rmin = (float)d.get("islet_rmin", islet_rmin);
	islet_rmax = (float)d.get("islet_rmax", islet_rmax);
	std_count = (int)d.get("std_count", std_count);
	islet_count = (int)d.get("islet_count", islet_count);
	vscale = (float)d.get("vscale", vscale);
	floor_depth = (float)d.get("floor_depth", floor_depth);
	caves_on = (bool)d.get("caves", caves_on);
}

void ArchipelagoGen::configure(int p_seed, const Vector3i &p_size, float p_sea_mid, float p_tide_amp, const PackedByteArray &mats) {
	seed = splitmix((uint64_t)(int64_t)p_seed * 2654435761ull + 17);
	size = p_size;
	sea_mid = p_sea_mid;
	sea_low = (int)(p_sea_mid - p_tide_amp);
	sea_high = (int)(p_sea_mid + p_tide_amp);
	for (int i = 0; i < M_COUNT && i < mats.size(); i++) M[i] = mats[i];

	n_warp.init(hcomb(seed, 1), 0.006f, 2);
	n_shape.init(hcomb(seed, 2), 0.009f, 3);
	n_hill.init(hcomb(seed, 3), 0.0055f, 3);
	n_cliff.init(hcomb(seed, 4), 0.005f, 2);
	n_detail.init(hcomb(seed, 5), 0.05f, 2);

	islands.clear();
	stacks.clear();
	stamps.clear();
	tree_clear.clear();
	Rng rng(hcomb(seed, 99));
	const float W = (float)size.x, D = (float)size.z;

	// Home island in the middle; R is the outer extent of the island profile (land ~0.6 R).
	islands.push_back({ W * 0.5f, D * 0.5f, home_r, T_HOME, STYLE_FLAT_MEADOW, 0.0f, 0.28f, -0.35f, 0.0f, 0.12f, 0, 0.f });

	auto try_place = [&](int type, float rmin, float rmax, int count, int tries) {
		int placed = 0;
		for (int t = 0; t < tries && placed < count; t++) {
			float R = rng.range(rmin, rmax);
			float x = rng.range(R * 0.7f + 40.f, W - R * 0.7f - 40.f);
			float z = rng.range(R * 0.7f + 40.f, D - R * 0.7f - 40.f);
			bool ok = true;
			for (const Island &o : islands) {
				float dd = std::hypot(x - o.cx, z - o.cz);
				if (dd < (o.R + R) * 0.78f + 60.f) { ok = false; break; }
			}
			if (!ok) continue;
			Island is;
			is.cx = x; is.cz = z; is.R = R; is.type = type;
			is.style = (placed < 5 && type == T_STANDARD) ? placed : rng.irange(0, 4);
			is.rock_bias = (is.style == STYLE_ROCKY_CRAGS) ? 0.55f : (is.style == STYLE_CLIFF_MESA ? 0.25f : (is.style == STYLE_ROLLING_HILLS ? 0.05f : -0.25f));
			is.hill = (is.style == STYLE_SANDY_ATOLL) ? rng.range(0.08f, 0.16f) : ((is.style == STYLE_FLAT_MEADOW) ? rng.range(0.16f, 0.26f) : ((is.style == STYLE_ROLLING_HILLS) ? rng.range(0.40f, 0.58f) : ((is.style == STYLE_ROCKY_CRAGS) ? rng.range(0.55f, 0.78f) : rng.range(0.42f, 0.62f))));
			is.cliff_bias = (is.style == STYLE_SANDY_ATOLL) ? -0.95f : ((is.style == STYLE_FLAT_MEADOW) ? rng.range(-0.75f, -0.45f) : ((is.style == STYLE_ROLLING_HILLS) ? rng.range(-0.35f, -0.10f) : ((is.style == STYLE_ROCKY_CRAGS) ? rng.range(0.18f, 0.38f) : rng.range(0.25f, 0.42f))));
			is.dry_bias = rng.range(-0.25f, 0.35f);
			is.tree_bias = (is.style == STYLE_ROCKY_CRAGS || is.style == STYLE_SANDY_ATOLL) ? rng.range(-0.40f, -0.10f) : rng.range(0.05f, 0.28f);
			is.strata = (is.style == STYLE_ROCKY_CRAGS) ? 3 : ((is.style == STYLE_SANDY_ATOLL) ? 1 : rng.irange(0, 3));
			is.salt = rng.range(0.f, 5000.f);
			islands.push_back(is);
			placed++;
		}
	};
	try_place(T_STANDARD, std_rmin, std_rmax, std_count, 400);   // layout 1: ~80-120 m of land
	try_place(T_ISLET, islet_rmin, islet_rmax, islet_count, 600); // layout 1: ~20-40 m of land

	// Sea stacks near island coasts.
	for (size_t i = 0; i < islands.size(); i++) {
		const Island &is = islands[i];
		int n = is.type == T_HOME ? 6 : (is.type == T_STANDARD ? 3 : 1);
		for (int k = 0; k < n; k++) {
			float ang = rng.range(0.f, 6.2831853f);
			float r = rng.range(0.78f, 0.92f) * is.R;
			stacks.push_back({ is.cx + std::cos(ang) * r, is.cz + std::sin(ang) * r,
					rng.range(5.f, 11.f), rng.range(sea_mid + 14.f * vscale, sea_mid + 34.f * vscale) });
		}
	}

	// Spatial grid for fast lookups.
	grid_w = (std::max(size.x, size.z) + GRID - 1) / GRID;
	grid.assign(grid_w * grid_w, {});
	sgrid.assign(grid_w * grid_w, {});
	for (size_t i = 0; i < islands.size(); i++) {
		const Island &is = islands[i];
		float ext = is.R * 1.3f + 8.f;
		int gx0 = std::max(0, (int)((is.cx - ext) / GRID)), gx1 = std::min(grid_w - 1, (int)((is.cx + ext) / GRID));
		int gz0 = std::max(0, (int)((is.cz - ext) / GRID)), gz1 = std::min(grid_w - 1, (int)((is.cz + ext) / GRID));
		for (int gz = gz0; gz <= gz1; gz++)
			for (int gx = gx0; gx <= gx1; gx++) grid[gx + grid_w * gz].push_back((int)i);
	}
	for (size_t i = 0; i < stacks.size(); i++) {
		const Stack &s = stacks[i];
		float ext = s.r * 1.4f + 2.f;
		int gx0 = std::max(0, (int)((s.x - ext) / GRID)), gx1 = std::min(grid_w - 1, (int)((s.x + ext) / GRID));
		int gz0 = std::max(0, (int)((s.z - ext) / GRID)), gz1 = std::min(grid_w - 1, (int)((s.z + ext) / GRID));
		for (int gz = gz0; gz <= gz1; gz++)
			for (int gx = gx0; gx <= gx1; gx++) sgrid[gx + grid_w * gz].push_back((int)i);
	}
	plan_sea_cave();
	caves.clear();
	cave_sites.clear();
	if (caves_on) plan_caves();
}

// ------------------------------------------------------------------ height field

float ArchipelagoGen::height_f(int x, int z, int *island_out) const {
	const float floor_n = n_detail.fbm((float)x, (float)z);
	const float floor_y = sea_mid - floor_depth;   // layout 1: 9
	float h = floor_y + floor_n * 2.5f;
	int best = -1;
	int gx = std::clamp(x / GRID, 0, grid_w - 1), gz = std::clamp(z / GRID, 0, grid_w - 1);
	if (x >= 0 && z >= 0) {
		for (int id : grid[gx + grid_w * gz]) {
			const Island &is = islands[id];
			float nx = (x - is.cx) / is.R, nz = (z - is.cz) / is.R;
			if (nx * nx + nz * nz > 1.7f) continue;
			float sx = (float)x + is.salt, sz = (float)z - is.salt;
			float ox = n_warp.fbm(sx, sz) * 0.18f;
			float oz = n_warp.fbm(sx + 1000.f, sz - 700.f) * 0.18f;
			float d = std::sqrt((nx + ox) * (nx + ox) + (nz + oz) * (nz + oz)) + n_shape.fbm(sx, sz) * 0.12f;
			float isl = 1.f - smoothstep(0.40f, 0.84f, d);
			if (isl <= 0.f) continue;
			float hs = is.hill;
			float hills = n_hill.fbm(sx, sz) * 0.5f + 0.5f;
			float seafloor = floor_y + floor_n * 2.5f + isl * 6.f;
			float s = smoothstep(0.f, 1.f, isl);
			float gentle = lerpf(seafloor, sea_mid + 8.f + hills * 14.f * hs * vscale + isl * isl * hills * 12.f * hs * vscale, s);
			float cliff_mask = smoothstep(0.02f, 0.30f, n_cliff.fbm(sx, sz) + is.cliff_bias);
			float cliff_h = sea_mid + 18.f * std::min(1.f, hs + 0.35f) * vscale + hills * 18.f * hs * vscale + isl * isl * 10.f * hs * vscale;
			if (is.style == STYLE_CLIFF_MESA) cliff_h = std::min(cliff_h, sea_mid + 22.f * vscale + hills * 3.f);
			float cl = lerpf(seafloor + 5.f, cliff_h, smoothstep(0.28f, 0.34f, isl));
			float t = cl / 7.f;
			cl = (std::floor(t) + smoothstep(0.3f, 0.7f, t - std::floor(t))) * 7.f;
			float hv = lerpf(gentle, cl, cliff_mask);
			if (hv > h) {
				h = hv;
				best = id;
			}
		}
		for (int id : sgrid[gx + grid_w * gz]) {
			const Stack &st = stacks[id];
			float dd = std::hypot(x - st.x, z - st.z);
			float r = st.r * (1.f + 0.3f * n_detail.noise(x * 2.f * 0.05f, z * 2.f * 0.05f));
			if (dd < r) {
				float sh = st.h - std::pow(dd / r, 4.f) * 8.f;
				sh = (std::floor(sh / 6.f) + smoothstep(0.3f, 0.7f, sh / 6.f - std::floor(sh / 6.f))) * 6.f;
				if (sh > h) {
					h = sh;
					best = -2; // stack
				}
			}
		}
	}
	if (island_out) *island_out = best;
	return std::clamp(h, 2.f, (float)size.y - 10.f);
}

int ArchipelagoGen::column_height(int x, int z) const {
	return (int)std::lround(height_f(x, z, nullptr));
}

int ArchipelagoGen::column_island(int x, int z) const {
	int id;
	height_f(x, z, &id);
	return id;
}

int ArchipelagoGen::kind_at(int x, int z, int h, int island, const int *nb) const {
	int slope = 0;
	for (int i = 0; i < 4; i++) slope = std::max(slope, std::abs(nb[i] - h));
	int k = K_GRASS;
	if (h < sea_low - 5) k = K_SEABED;
	else if (slope >= 4 || (island >= 0 && islands[island].rock_bias > 0.3f && h > sea_high + 2 && n_detail.fbm(x * 0.25f, z * 0.25f) > 0.12f)) k = K_ROCK;
	else if (h <= sea_high + 3) k = K_BEACH;
	if (k == K_GRASS) {
		float dry_bias = island >= 0 ? islands[island].dry_bias : 0.f;
		if (n_detail.fbm(x * 0.4f, z * 0.4f) > 0.35f - dry_bias) k = K_GRASS_DRY;
	}
	return k;
}

int ArchipelagoGen::column_kind(int x, int z) const {
	int id;
	int h = (int)std::lround(height_f(x, z, &id));
	int nb[4] = { column_height(x + 2, z), column_height(x - 2, z), column_height(x, z + 2), column_height(x, z - 2) };
	return kind_at(x, z, h, id, nb);
}

int ArchipelagoGen::strata_off(int x, int z) const {
	return (int)((n_detail.fbm(x * 0.3f, z * 0.3f) * 0.5f + 0.5f) * 6.f);
}

uint8_t ArchipelagoGen::strata_at(int y, int off, int variant) const {
	if (y < 12) return M[M_STONE];
	static const int orders[4][5] = {
		{ M_SA, M_SB, M_SC, M_SA, M_STONE },     // classic
		{ M_SC, M_SC, M_SA, M_SB, M_STONE },     // pale
		{ M_SB, M_SB, M_SA, M_STONE, M_SB },     // rust
		{ M_STONE, M_SA, M_STONE, M_SC, M_STONE } // grey
	};
	int band = (int)std::floor((y + off) / 4.0);
	band = ((band % 5) + 5) % 5;
	return M[orders[std::clamp(variant, 0, 3)][band]];
}

Array ArchipelagoGen::get_islands() const {
	Array out;
	for (const Island &is : islands) {
		Dictionary d;
		d["center"] = Vector2(is.cx, is.cz);
		d["radius"] = is.R;
		d["type"] = is.type;
		d["style"] = is.style;
		static const char *snames[5] = { "Flat Meadow", "Sandy Atoll", "Rolling Hills", "Rocky Crags", "Cliff Mesa" };
		d["style_name"] = snames[std::clamp(is.style, 0, 4)];
		out.push_back(d);
	}
	return out;
}

TypedArray<Vector2i> ArchipelagoGen::land_regions(int region_vox) const {
	TypedArray<Vector2i> out;
	int nx = (size.x + region_vox - 1) / region_vox, nz = (size.z + region_vox - 1) / region_vox;
	for (int rz = 0; rz < nz; rz++) {
		for (int rx = 0; rx < nx; rx++) {
			float x0 = rx * region_vox, z0 = rz * region_vox, x1 = x0 + region_vox, z1 = z0 + region_vox;
			bool near = false;
			for (const Island &is : islands) {
				float ext = is.R * 1.0f;
				if (is.cx + ext > x0 && is.cx - ext < x1 && is.cz + ext > z0 && is.cz - ext < z1) { near = true; break; }
			}
			for (const Stack &s : stacks) {
				if (s.x + s.r > x0 && s.x - s.r < x1 && s.z + s.r > z0 && s.z - s.r < z1) { near = true; break; }
			}
			if (!near) continue;
			bool land = false;
			for (int z = (int)z0; z < (int)z1 && !land; z += 8)
				for (int x = (int)x0; x < (int)x1 && !land; x += 8)
					if (column_height(x, z) > sea_low - 3) land = true;
			if (land) out.push_back(Vector2i(rx, rz));
		}
	}
	return out;
}

// ------------------------------------------------------------------ sea cave

void ArchipelagoGen::plan_sea_cave() {
	cave.clear();
	const Island &home = islands[0];
	Rng rng(hcomb(seed, 777));
	for (int attempt = 0; attempt < 60; attempt++) {
		float ang = rng.range(0.f, 6.2831853f);
		float dx = std::cos(ang), dz = std::sin(ang);
		float hx = NAN, hz = NAN;
		for (float s = home.R * 0.95f; s > home.R * 0.15f; s -= 1.f) {
			float px = home.cx + dx * s, pz = home.cz + dz * s;
			int h = column_height((int)px, (int)pz);
			if (h > sea_mid + 14) { hx = px; hz = pz; break; }
			if (h > sea_high + 2) break; // gentle shore, not a cliff
		}
		if (std::isnan(hx)) continue;
		float px = hx + dx * 6.f, py = sea_mid - 3.f, pz = hz + dz * 6.f;
		float hdx = -dx, hdz = -dz;
		const int length = 70;
		for (int i = 0; i < length; i++) {
			float r = 6.5f + std::sin(i * 0.21f) * 1.5f;
			if (i > length - 10) r = 10.5f;
			cave.push_back({ px, py, pz, r });
			float rot = rng.range(-0.12f, 0.12f);
			float nx = hdx * std::cos(rot) - hdz * std::sin(rot);
			float nz = hdx * std::sin(rot) + hdz * std::cos(rot);
			hdx = nx; hdz = nz;
			px += hdx * 1.5f; pz += hdz * 1.5f; py += 0.06f;
		}
		break;
	}
	cave_min = Vector3i(1 << 30, 1 << 30, 1 << 30);
	cave_max = Vector3i(-(1 << 30), -(1 << 30), -(1 << 30));
	for (const Sphere &s : cave) {
		int r = (int)std::ceil(s.r) + 2;
		cave_min = Vector3i(std::min(cave_min.x, (int)s.x - r), std::min(cave_min.y, (int)s.y - r), std::min(cave_min.z, (int)s.z - r));
		cave_max = Vector3i(std::max(cave_max.x, (int)s.x + r), std::max(cave_max.y, (int)s.y + r), std::max(cave_max.z, (int)s.z + r));
	}
}

// ------------------------------------------------------------------ cave systems (layout 2+)

void ArchipelagoGen::finish_cave(CaveSys &c) {
	c.lo = Vector3i(1 << 30, 1 << 30, 1 << 30);
	c.hi = Vector3i(-(1 << 30), -(1 << 30), -(1 << 30));
	for (const Blob &b : c.blobs) {
		int r = (int)std::ceil(b.r) + 2, ry = (int)std::ceil(b.r * b.ys) + 2;
		c.lo = Vector3i(std::min(c.lo.x, (int)b.x - r), std::min(c.lo.y, (int)b.y - ry), std::min(c.lo.z, (int)b.z - r));
		c.hi = Vector3i(std::max(c.hi.x, (int)b.x + r), std::max(c.hi.y, (int)b.y + ry), std::max(c.hi.z, (int)b.z + r));
	}
}

// Tidal sea caves bored into cliff faces (mouth at sea level: it floods at high tide and
// opens at low tide), climbing to a sandy grotto; karst caverns of several chambers under
// high ground, joined by passages, with one passage out to the hillside.
void ArchipelagoGen::plan_caves() {
	Rng rng(hcomb(seed, 0xCA7E5));
	for (int i = 0; i < (int)islands.size(); i++) {
		const Island &is = islands[i];
		if (is.type == T_ISLET) continue;

		// --- Tidal sea caves
		int want = is.type == T_HOME ? 2 : 1, made = 0;
		for (int attempt = 0; attempt < 240 && made < want; attempt++) {
			float ang = rng.range(0.f, 6.2831853f);
			float dx = std::cos(ang), dz = std::sin(ang);
			float hx = NAN, hz = NAN;
			for (float s = is.R * 0.95f; s > is.R * 0.15f; s -= 1.f) {
				float px = is.cx + dx * s, pz = is.cz + dz * s;
				int h = column_height((int)px, (int)pz);
				if (h > sea_high + 10) { hx = px; hz = pz; break; }
				if (h > sea_high + 3) break;   // a gentle shore, not a cliff
			}
			if (std::isnan(hx)) continue;
			CaveSys c;
			c.kind = CAVE_TIDAL;
			c.island = i;
			// The mouth opens onto water: start out where the seabed is below the passage floor
			// (a cliff behind a high beach would otherwise leave the mouth buried in sand).
			float out_d = -1.f;
			for (float s = 2.f; s <= 40.f; s += 1.f) {
				if (column_height((int)(hx + dx * s), (int)(hz + dz * s)) < sea_low - 1) { out_d = s + 2.f; break; }
			}
			if (out_d < 0.f) continue;
			float px = hx + dx * out_d, py = sea_mid - 1.f, pz = hz + dz * out_d;
			float hdx = -dx, hdz = -dz;
			bool ok = true;
			const int inside = (int)(out_d / 1.5f) + 6;   // steps before the passage is under the cliff
			for (int k = 0; k < 38 + inside; k++) {
				float r = 5.f + std::sin(k * 0.27f) * 0.8f;
				c.blobs.push_back({ px, py, pz, r, 1.f });
				if (k > inside && column_height((int)px, (int)pz) < py + r + 2) { ok = false; break; }
				float rot = rng.range(-0.15f, 0.15f);
				float nx = hdx * std::cos(rot) - hdz * std::sin(rot);
				float nz = hdx * std::sin(rot) + hdz * std::cos(rot);
				hdx = nx;
				hdz = nz;
				px += hdx * 1.5f;
				pz += hdz * 1.5f;
				if (k >= inside - 4) py += 0.26f;   // level until under the cliff, then climb
			}
			if (!ok) continue;
			// Grotto: a wide, low chamber whose sandy floor the high tide just reaches.
			float gr = rng.range(9.f, 12.f);
			float gy = sea_high - 2.f + gr * 0.6f;
			if (column_height((int)px, (int)pz) < gy + gr * 0.6f + 3.f) continue;
			c.blobs.push_back({ px, gy, pz, gr, 0.6f });
			cave_sites.push_back({ Vector3i((int)px, (int)std::ceil(gy), (int)pz), CAVE_TIDAL, i });
			finish_cave(c);
			caves.push_back(std::move(c));
			made++;
		}

		// --- Karst caverns
		int kwant = is.type == T_HOME ? 2 : 1, kmade = 0;
		const float floor_y = (float)sea_high + 3.f;
		auto fits = [&](float cx, float cz, float r, float ys) {
			float top = floor_y + 2.f * r * ys;
			for (int k = 0; k < 9; k++) {
				float a = k * 0.785398f, rr = k == 8 ? 0.f : r * 0.85f;
				if (column_height((int)(cx + std::cos(a) * rr), (int)(cz + std::sin(a) * rr)) < top + 6.f) return false;
			}
			return true;
		};
		for (int attempt = 0; attempt < 160 && kmade < kwant; attempt++) {
			float ang = rng.range(0.f, 6.2831853f), dist = rng.range(0.f, 0.5f) * is.R;
			float x = is.cx + std::cos(ang) * dist, z = is.cz + std::sin(ang) * dist;
			float r0 = rng.range(10.f, 14.f);
			if (!fits(x, z, r0, 0.55f)) continue;
			CaveSys c;
			c.kind = CAVE_KARST;
			c.island = i;
			std::vector<Blob> ch;
			ch.push_back({ x, floor_y + r0 * 0.55f, z, r0, 0.55f });
			int n = rng.irange(2, 3);
			float dir = rng.range(0.f, 6.2831853f);
			for (int k = 0; k < n; k++) {
				const Blob prev = ch.back();
				for (int t = 0; t < 8; t++) {
					float a = dir + rng.range(-1.1f, 1.1f);
					float r = rng.range(7.f, 11.f);
					float d = prev.r + r + rng.range(6.f, 14.f);
					float nx = prev.x + std::cos(a) * d, nz = prev.z + std::sin(a) * d;
					if (!fits(nx, nz, r, 0.55f)) continue;
					// Passage between the chambers, at walking height.
					int steps = (int)(d / 1.2f);
					for (int s = 0; s <= steps; s++) {
						float f = (float)s / (float)std::max(1, steps);
						c.blobs.push_back({ lerpf(prev.x, nx, f), floor_y + 3.f + std::sin(f * 3.14159f) * 1.5f, lerpf(prev.z, nz, f), 3.3f, 1.f });
					}
					ch.push_back({ nx, floor_y + r * 0.55f, nz, r, 0.55f });
					dir = a;
					break;
				}
			}
			// Entrance: from the last chamber, climb outward until the passage breaks the surface.
			const Blob last = ch.back();
			float ex = last.x, ez = last.z, ey = floor_y + 3.f;
			float edx = last.x - is.cx, edz = last.z - is.cz;
			float el = std::sqrt(edx * edx + edz * edz);
			if (el < 1.f) { edx = 1.f; edz = 0.f; el = 1.f; }
			edx /= el;
			edz /= el;
			bool opened = false;
			std::vector<Blob> tunnel;
			for (int s = 0; s < 150; s++) {
				tunnel.push_back({ ex, ey, ez, 3.4f, 1.f });
				if (ey > column_height((int)ex, (int)ez) + 1.f) { opened = true; break; }
				float rot = rng.range(-0.12f, 0.12f);
				float nx = edx * std::cos(rot) - edz * std::sin(rot);
				float nz = edx * std::sin(rot) + edz * std::cos(rot);
				edx = nx;
				edz = nz;
				ex += edx * 1.3f;
				ez += edz * 1.3f;
				if (ey < column_height((int)ex, (int)ez) - 6.f) ey += 0.5f;   // climb while deep underground
			}
			if (!opened) continue;
			for (const Blob &b : ch) c.blobs.push_back(b);
			for (const Blob &b : tunnel) c.blobs.push_back(b);
			// Stalactites (len > 0) and stalagmites (len < 0) in each chamber.
			for (const Blob &b : ch) {
				int nd = rng.irange(6, 12);
				for (int k = 0; k < nd; k++) {
					float a = rng.range(0.f, 6.2831853f), rr = std::sqrt(rng.f()) * b.r * 0.75f;
					int len = rng.irange(2, 7);
					if (rng.f() < 0.35f) len = -std::max(1, len / 2);
					c.drips.push_back({ (int)(b.x + std::cos(a) * rr), (int)(b.z + std::sin(a) * rr), len, b.y });
				}
			}
			cave_sites.push_back({ Vector3i((int)x, (int)std::ceil(ch[0].y), (int)z), CAVE_KARST, i });
			finish_cave(c);
			caves.push_back(std::move(c));
			kmade++;
		}
	}
}

Array ArchipelagoGen::get_cave_sites() const {
	Array out;
	for (const CaveSite &s : cave_sites) {
		Dictionary d;
		d["pos"] = s.pos;
		d["kind"] = s.kind;
		d["island"] = s.island;
		out.push_back(d);
	}
	return out;
}

bool ArchipelagoGen::cave_near(int x, int z, int margin) const {
	for (const CaveSys &c : caves)
		if (x >= c.lo.x - margin && x <= c.hi.x + margin && z >= c.lo.z - margin && z <= c.hi.z + margin) return true;
	return false;
}

// ------------------------------------------------------------------ features

void ArchipelagoGen::trees_in_cell(int fx, int fz, std::vector<Tree> &out) const {
	for (int sz = 0; sz < 3; sz++) {
		for (int sx = 0; sx < 3; sx++) {
			Rng r(hcomb(hcomb(hcomb(seed, 0x7EE5), fx * 3 + sx), fz * 3 + sz));
			int x = fx * FC + sx * 21 + r.irange(3, 18);
			int z = fz * FC + sz * 21 + r.irange(3, 18);
			if (x < 8 || z < 8 || x >= size.x - 8 || z >= size.z - 8) continue;
			float accept = r.f();
			float roll = r.f();
			int id;
			int h = (int)std::lround(height_f(x, z, &id));
			if (id < 0 || h < sea_high + 5) continue;
			const Island &is = islands[id];
			if (n_hill.fbm(x * 1.7f + 500.f, z * 1.7f) < 0.12f - is.tree_bias) continue;
			if (accept > 0.85f) continue;
			int nb[4] = { column_height(x + 2, z), column_height(x - 2, z), column_height(x, z + 2), column_height(x, z - 2) };
			int k = kind_at(x, z, h, id, nb);
			if (k != K_GRASS && k != K_GRASS_DRY) continue;
			bool cleared = false;
			for (const Vector3i &tc : tree_clear) {
				int dx = x - tc.x, dz = z - tc.y;
				if (dx * dx + dz * dz <= tc.z * tc.z) { cleared = true; break; }
			}
			if (cleared) continue;
			Tree t;
			t.x = x; t.z = z; t.y = h + 1;
			if (roll < 0.40f) { t.type = 0; t.tall = r.irange(26, 36); t.r = 0; }
			else if (roll < 0.75f) { t.type = 1; t.tall = r.irange(13, 18); t.r = r.range(6.5f, 8.5f); }
			else { t.type = 2; t.tall = 0; t.r = r.range(2.8f, 4.2f); }
			out.push_back(t);
		}
	}
}

void ArchipelagoGen::add_stamp(const PackedByteArray &data, const Vector3i &dims, const Vector3i &base, int foundation) {
	if (data.size() != dims.x * dims.y * dims.z) {
		ERR_PRINT("add_stamp: data size mismatch");
		return;
	}
	Stamp s;
	s.data.assign(data.ptr(), data.ptr() + data.size());
	s.dims = dims;
	s.base = base;
	s.foundation = foundation;
	stamps.push_back(std::move(s));
}

// ------------------------------------------------------------------ column generation

void ArchipelagoGen::generate_column(int cx, int cz, std::vector<std::unique_ptr<uint8_t[]>> &out) const {
	const int H = size.y;
	const int layers = (H + CS - 1) / CS;
	const int x0 = cx * CS, z0 = cz * CS;
	out.clear();
	out.resize(layers);
	if (x0 < 0 || z0 < 0 || x0 >= size.x || z0 >= size.z) return;

	std::vector<uint8_t> buf((size_t)CS * CS * H, 0);
	ColBuf cb{ x0, z0, H, buf.data() };

	// Heights over a padded patch for slope-based kinds.
	const int P = CS + 4;
	int hp[P * P];
	int ip[P * P];
	for (int pz = 0; pz < P; pz++)
		for (int px = 0; px < P; px++) {
			int id;
			hp[px + P * pz] = (int)std::lround(height_f(x0 + px - 2, z0 + pz - 2, &id));
			ip[px + P * pz] = id;
		}

	// Base terrain + per-column details (flowers, kelp).
	for (int lz = 0; lz < CS; lz++) {
		for (int lx = 0; lx < CS; lx++) {
			int x = x0 + lx, z = z0 + lz;
			if (x >= size.x || z >= size.z) continue;
			int pi = (lx + 2) + P * (lz + 2);
			int h = std::min(hp[pi], H - 1);
			int id = ip[pi];
			int nb[4] = { hp[pi + 2], hp[pi - 2], hp[pi + 2 * P], hp[pi - 2 * P] };
			int k = kind_at(x, z, h, id, nb);
			int off = strata_off(x, z);
			int variant = id >= 0 ? islands[id].strata : 0;
			for (int y = 0; y <= h; y++) {
				int depth = h - y;
				uint8_t m;
				if (y == 0) m = M[M_BEDROCK];
				else if (k == K_BEACH) {
					if (depth < 4) {
						m = h < sea_high ? M[M_WET] : M[M_SAND];
						if (h < sea_low && vhash(seed, x, y, z) % 7 == 0) m = M[M_GRAVEL];
					} else m = strata_at(y, off, variant);
				} else if (k == K_GRASS || k == K_GRASS_DRY) {
					if (depth == 0) m = k == K_GRASS_DRY ? M[M_GRASS_DRY] : M[M_GRASS];
					else if (depth < 4) m = M[M_DIRT];
					else m = strata_at(y, off, variant);
				} else if (k == K_SEABED) {
					if (depth < 3) m = vhash(seed, x, y, z) % 5 == 0 ? M[M_GRAVEL] : M[M_SAND];
					else m = strata_at(y, off, variant);
				} else m = strata_at(y, off, variant);
				cb.at(x, y, z) = m;
			}
			uint32_t hh = vhash(seed ^ 0xF10, x, 0, z);
			if ((k == K_GRASS || k == K_GRASS_DRY) && h + 2 < H && hh % 1000 < 34) {
				uint32_t roll = (hh >> 10) % 100;
				if (roll < 12) cb.at(x, h + 1, z) = M[M_FLOWER_Y];
				else if (roll < 20) cb.at(x, h + 1, z) = M[M_FLOWER_P];
				else if (roll < 75) cb.at(x, h + 1, z) = M[M_TUFT];
				else {
					cb.at(x, h + 1, z) = M[M_TUFT_DRY];
					if ((hh >> 20) % 10 < 4) cb.at(x, h + 2, z) = M[M_TUFT_DRY];
				}
			}
			if (h < sea_low - 6 && h >= 4 && hh % 1000 >= 990) {
				int tall = 2 + (int)((hh >> 12) % (uint32_t)std::max(2, sea_low - 5 - h - 1));
				for (int y = h + 1; y < h + 1 + tall && y < H; y++) cb.at(x, y, z) = M[M_KELP];
			}
		}
	}

	// Cross-chunk features from feature cells overlapping this column (+margin), fixed order.
	const int fx0 = (x0 - FEATURE_MARGIN) >= 0 ? (x0 - FEATURE_MARGIN) / FC : -1;
	const int fz0 = (z0 - FEATURE_MARGIN) >= 0 ? (z0 - FEATURE_MARGIN) / FC : -1;
	const int fx1 = (x0 + CS + FEATURE_MARGIN) / FC, fz1 = (z0 + CS + FEATURE_MARGIN) / FC;
	std::vector<Tree> trees;
	for (int fz = fz0; fz <= fz1; fz++) {
		for (int fx = fx0; fx <= fx1; fx++) {
			if (fx < 0 || fz < 0) continue;
			// Boulders and driftwood
			Rng r(hcomb(hcomb(hcomb(seed, 0xB01D), fx), fz));
			{
				int bx = fx * FC + r.irange(0, FC - 1), bz = fz * FC + r.irange(0, FC - 1);
				float br = r.range(2.0f, 5.0f);
				bool stone = r.f() < 0.7f;
				if (bx < size.x && bz < size.z && bx + 8 >= x0 && bx - 8 < x0 + CS && bz + 8 >= z0 && bz - 8 < z0 + CS) {
					int k = column_kind(bx, bz);
					if (k == K_BEACH || k == K_ROCK || ((k == K_GRASS || k == K_GRASS_DRY) && r.f() < 0.28f)) {
						int bh = column_height(bx, bz);
						float cy = bh + br * 0.4f;
						int ir = (int)std::ceil(br);
						for (int y = -ir; y <= ir; y++)
							for (int z = -ir; z <= ir; z++)
								for (int x = -ir; x <= ir; x++) {
									if (x * x + y * y + z * z > br * br) continue;
									int py = (int)cy + y;
									if (py < 1) continue;
									cb.set(bx + x, py, bz + z, stone ? M[M_STONE] : M[M_GRAVEL]);
								}
					}
				}
			}
			{
				bool want = r.f() < 0.35f;
				int lx = fx * FC + r.irange(0, FC - 1), lz = fz * FC + r.irange(0, FC - 1);
				bool along_x = r.f() < 0.5f;
				int len = r.irange(6, 14);
				if (want && lx + 16 >= x0 && lx - 2 < x0 + CS && lz + 16 >= z0 && lz - 2 < z0 + CS && lx < size.x && lz < size.z) {
					int h = column_height(lx, lz);
					if (column_kind(lx, lz) == K_BEACH && h >= sea_high - 1 && h <= sea_high + 3) {
						for (int j = 0; j < len; j++) {
							int px = lx + (along_x ? j : 0), pz = lz + (along_x ? 0 : j);
							if (!cb.in(px, 1, pz) && !(j % 4 == 1)) continue;
							int gh = column_height(px, pz);
							cb.set(px, gh + 1, pz, M[M_DRIFTWOOD]);
							if (j % 4 == 1) {
								int qx = px + (along_x ? 0 : 1), qz = pz + (along_x ? 1 : 0);
								cb.set(qx, column_height(qx, qz) + 1, qz, M[M_DRIFTWOOD]);
							}
						}
					}
				}
			}
			trees_in_cell(fx, fz, trees);
		}
	}
	for (const Tree &t : trees) {
		if (t.x + FEATURE_MARGIN < x0 || t.x - FEATURE_MARGIN >= x0 + CS || t.z + FEATURE_MARGIN < z0 || t.z - FEATURE_MARGIN >= z0 + CS) continue;
		// Every tree is its own shape: a seeded lean, a curving trunk, a lopsided crown.
		Rng tr(hcomb(hcomb(hcomb(seed, 0x7A3E), t.x), t.z));
		const float la = tr.f() * 6.2831853f;
		const float lean = t.type == 0 ? tr.range(0.0f, 0.07f) : tr.range(0.06f, 0.24f);
		const float ldx = std::cos(la) * lean, ldz = std::sin(la) * lean;
		// Trunk offset at height k: bends more towards the top, capped to stay in the margin.
		auto bend = [&](int k, int &ox, int &oz) {
			float sc = (float)k * (1.f + (float)k * 0.03f);
			ox = (int)std::lround(std::clamp(ldx * sc, -4.f, 4.f));
			oz = (int)std::lround(std::clamp(ldz * sc, -4.f, 4.f));
		};
		auto trunk = [&](int tall) {
			for (int k = 0; k < tall; k++) {
				int ox, oz;
				bend(k, ox, oz);
				const int w = (k > tall * 3 / 4 && t.type != 0) ? 2 : 3;   // tapers near the top
				for (int dz = 0; dz < w; dz++)
					for (int dx = 0; dx < w; dx++) cb.set(t.x + ox + dx, t.y + k, t.z + oz + dz, M[M_TRUNK]);
			}
			// a root or two splaying out at the foot
			const int roots = tr.irange(1, 3);
			for (int rI = 0; rI < roots; rI++) {
				const float a = tr.f() * 6.2831853f;
				const int len = tr.irange(2, 3);
				for (int k = 1; k <= len; k++)
					cb.set(t.x + 1 + (int)std::lround(std::cos(a) * (1.5f + k)), t.y + (k == 1 ? 0 : -1), t.z + 1 + (int)std::lround(std::sin(a) * (1.5f + k)), M[M_TRUNK]);
			}
		};
		// A wobbly, slightly squashed ball of leaves; darker leaves come in clumps.
		auto blob = [&](float cx, float cy, float cz, float r, float squash, float wobble) {
			const int ir = (int)std::ceil(r + wobble);
			for (int dy = -ir; dy <= ir; dy++)
				for (int dz = -ir; dz <= ir; dz++)
					for (int dx = -ir; dx <= ir; dx++) {
						const int px = (int)std::floor(cx) + dx, py = (int)std::floor(cy) + dy, pz = (int)std::floor(cz) + dz;
						if (!cb.in(px, py, pz)) continue;
						const float fy = (float)dy * (dy < 0 ? squash : 1.f);
						const float q = std::sqrt((float)(dx * dx) + fy * fy + (float)(dz * dz));
						const float wob = vnoise3(seed ^ 0x1EAF, px * 0.21f, py * 0.21f, pz * 0.21f) * wobble;
						if (q > r + wob) continue;
						const bool dark = vnoise3(seed ^ 0xDA4C, px * 0.17f, py * 0.17f, pz * 0.17f) < -0.12f;
						cb.set_air_only(px, py, pz, dark ? M[M_LEAVES_DARK] : M[M_LEAVES]);
					}
		};
		// A one-voxel branch from (ax, ay, az) to (bx, by, bz).
		auto branch = [&](float ax, float ay, float az, float bx, float by, float bz) {
			const float len = std::sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay) + (bz - az) * (bz - az));
			const int n = std::max(1, (int)std::ceil(len * 1.5f));
			for (int k = 0; k <= n; k++) {
				const float f = (float)k / n;
				cb.set((int)std::floor(ax + (bx - ax) * f), (int)std::floor(ay + (by - ay) * f), (int)std::floor(az + (bz - az) * f), M[M_TRUNK]);
			}
		};
		if (t.type == 0) {
			// Pine: tiers of ragged, off-centre discs around a slightly leaning trunk.
			trunk(t.tall - 2);
			const int top = t.y + t.tall;
			int layer = 0;
			float tier_k = tr.range(0.85f, 1.15f);
			for (int yy = top; yy > t.y + 5; yy--) {
				if (layer % 4 == 0) tier_k = tr.range(0.78f, 1.18f);   // each tier its own width
				float r = ((top - yy) * 0.33f + 1.5f) * tier_k;
				if (layer % 4 == 3) r *= 0.7f;
				r = std::min(r, 12.0f);
				layer++;
				int ox, oz;
				bend(yy - t.y, ox, oz);
				const float jx = vnoise3(seed ^ 0x9E1, t.x * 0.3f, yy * 0.35f, t.z * 0.3f) * 1.3f;
				const float jz = vnoise3(seed ^ 0x9E2, t.x * 0.3f, yy * 0.35f, t.z * 0.3f) * 1.3f;
				const float ccx = t.x + 1.f + ox + jx, ccz = t.z + 1.f + oz + jz;
				const int ir = (int)std::ceil(r * 1.2f);
				for (int dz = -ir; dz <= ir; dz++)
					for (int dx = -ir; dx <= ir; dx++) {
						const int px = (int)std::floor(ccx) + dx, pz = (int)std::floor(ccz) + dz;
						const float fx = px + 0.5f - ccx, fz = pz + 0.5f - ccz;
						// ragged rim: the edge wanders in and out around the tier
						const float rim = r * (1.f + 0.22f * vnoise3(seed ^ 0x5EED, px * 0.45f, yy * 0.6f, pz * 0.45f));
						if (fx * fx + fz * fz <= rim * rim) {
							const bool tip = fx * fx + fz * fz > (rim - 1.f) * (rim - 1.f) && vhash(seed, px, yy, pz) % 5 == 0;
							cb.set_air_only(px, yy, pz, tip ? M[M_LEAVES] : M[M_LEAVES_DARK]);
						}
					}
			}
		} else if (t.type == 1) {
			// Broadleaf: a leaning trunk, a main crown pushed off-centre, and two to four
			// side clumps on branches at different heights.
			trunk(t.tall);
			int ox, oz;
			bend(t.tall, ox, oz);
			const float tx = t.x + 1.f + ox, tz = t.z + 1.f + oz, ty = (float)(t.y + t.tall);
			const float mx = tx + tr.range(-1.5f, 1.5f), mz = tz + tr.range(-1.5f, 1.5f), my = ty + 3.f + tr.range(-1.f, 1.f);
			const int lumps = tr.irange(2, 4);
			float a = tr.f() * 6.2831853f;
			for (int l = 0; l < lumps; l++) {
				a += tr.range(1.3f, 2.6f);
				const float dist = t.r * tr.range(0.45f, 0.75f);
				const float lr = t.r * tr.range(0.42f, 0.62f);
				const float lx = mx + std::cos(a) * dist, lz = mz + std::sin(a) * dist;
				const float ly = my + tr.range(-0.45f, 0.2f) * t.r;
				const float by = ty - tr.range(2.f, 6.f);
				int bx, bz;
				bend((int)(by - t.y), bx, bz);
				branch(t.x + 1.f + bx, by, t.z + 1.f + bz, lx, ly - lr * 0.4f, lz);
				blob(lx, ly, lz, lr, 1.4f, 1.3f);
			}
			blob(mx, my, mz, t.r * tr.range(0.82f, 0.95f), 1.3f, 1.7f);
		} else {
			// Bush: a squat clump with a lopsided second lobe.
			const float a = tr.f() * 6.2831853f;
			const float cx = t.x + 0.5f, cz = t.z + 0.5f, cy = (float)(t.y + 1);
			blob(cx, cy, cz, t.r, 1.6f, 0.9f);
			blob(cx + std::cos(a) * t.r * 0.7f, cy - 0.5f, cz + std::sin(a) * t.r * 0.7f, t.r * tr.range(0.55f, 0.8f), 1.6f, 0.9f);
		}
	}

	// Sea cave: carve, then sprinkle bioluminescence on the walls.
	if (!cave.empty() && cave_max.x >= x0 && cave_min.x < x0 + CS && cave_max.z >= z0 && cave_min.z < z0 + CS) {
		for (const Sphere &s : cave) {
			int ir = (int)std::ceil(s.r);
			if (s.x + ir < x0 || s.x - ir >= x0 + CS || s.z + ir < z0 || s.z - ir >= z0 + CS) continue;
			float r2 = s.r * s.r;
			for (int y = -ir; y <= ir; y++)
				for (int z = -ir; z <= ir; z++)
					for (int x = -ir; x <= ir; x++) {
						if (x * x + y * y + z * z > r2) continue;
						int px = (int)s.x + x, py = (int)s.y + y, pz = (int)s.z + z;
						if (py < 1) continue;
						cb.set(px, py, pz, 0);
					}
		}
		int ylo = std::max(4, cave_min.y), yhi = std::min(H - 1, cave_max.y);
		for (int z = std::max(z0, cave_min.z); z < std::min(z0 + CS, cave_max.z + 1); z++)
			for (int x = std::max(x0, cave_min.x); x < std::min(x0 + CS, cave_max.x + 1); x++)
				for (int y = ylo; y <= yhi; y++) {
					if (cb.at(x, y, z) == 0 || vhash(seed ^ 0x6110, x, y, z) % 10 != 0) continue;
					float best = 1e9f;
					for (const Sphere &s : cave) {
						float d = std::sqrt((x + 0.5f - s.x) * (x + 0.5f - s.x) + (y + 0.5f - s.y) * (y + 0.5f - s.y) + (z + 0.5f - s.z) * (z + 0.5f - s.z)) - s.r;
						best = std::min(best, d);
						if (best < 0.f) break;
					}
					if (best >= 0.f && best < 1.3f) cb.at(x, y, z) = M[M_GLOW];
				}
	}

	// Cave systems (layout 2+): carve, hang stalactites, then dress the walls with ore veins,
	// glowing moss and (in tidal grottos) sand.
	for (const CaveSys &c : caves) {
		if (c.hi.x < x0 || c.lo.x >= x0 + CS || c.hi.z < z0 || c.lo.z >= z0 + CS) continue;
		for (const Blob &b : c.blobs) {
			int ir = (int)std::ceil(b.r), iry = (int)std::ceil(b.r * b.ys);
			if (b.x + ir < x0 || b.x - ir >= x0 + CS || b.z + ir < z0 || b.z - ir >= z0 + CS) continue;
			const float r2 = b.r * b.r, iys = 1.f / b.ys;
			const int bx = (int)std::floor(b.x), by = (int)std::floor(b.y), bz = (int)std::floor(b.z);
			for (int y = -iry; y <= iry; y++) {
				int py = by + y;
				if (py < 2 || py >= H) continue;
				float fy = y * iys;
				for (int z = -ir; z <= ir; z++) {
					int pz = bz + z;
					if (pz < z0 || pz >= z0 + CS) continue;
					for (int x = -ir; x <= ir; x++) {
						int px = bx + x;
						if (px < x0 || px >= x0 + CS) continue;
						if ((float)(x * x + z * z) + fy * fy > r2) continue;
						cb.at(px, py, pz) = 0;
					}
				}
			}
		}
		for (const Drip &d : c.drips) {
			// The tip column plus a thicker base; each voxel column is scanned on its own so
			// a formation that straddles two chunk columns comes out the same in both.
			static const int OFF[5][2] = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
			int full = d.len > 0 ? d.len : -d.len;
			for (int o = 0; o < 5; o++) {
				int x = d.x + OFF[o][0], z = d.z + OFF[o][1];
				if (!cb.in(x, 1, z)) continue;
				int len = o == 0 ? full : full / 3;
				if (len <= 0) continue;
				int y = (int)d.top;
				if (y < 2 || y >= H - 1 || cb.at(x, y, z) != 0) continue;
				if (d.len > 0) {
					while (y < H - 1 && cb.at(x, y, z) == 0) y++;
					if (y >= H - 1) continue;
					for (int k = 1; k <= len && y - k > 1 && cb.at(x, y - k, z) == 0; k++) cb.at(x, y - k, z) = M[M_STONE];
				} else {
					while (y > 1 && cb.at(x, y, z) == 0) y--;
					for (int k = 1; k <= len && y + k < H && cb.at(x, y + k, z) == 0; k++) cb.at(x, y + k, z) = M[M_STONE];
				}
			}
		}
	}
	for (const CaveSys &c : caves) {
		if (c.hi.x < x0 || c.lo.x >= x0 + CS || c.hi.z < z0 || c.lo.z >= z0 + CS) continue;
		const int xa = std::max(x0, c.lo.x), xb = std::min(x0 + CS - 1, c.hi.x);
		const int za = std::max(z0, c.lo.z), zb = std::min(z0 + CS - 1, c.hi.z);
		const int ya = std::max(2, c.lo.y), yb = std::min(H - 2, c.hi.y);
		const bool karst = c.kind == CAVE_KARST;
		for (int z = za; z <= zb; z++)
			for (int x = xa; x <= xb; x++) {
				const int hcol = hp[(x - x0 + 2) + P * (z - z0 + 2)];
				for (int y = ya; y <= std::min(yb, hcol - 2); y++) {
					uint8_t &m = cb.at(x, y, z);
					if (m == 0 || m == M[M_COPPER] || m == M[M_IRON] || m == M[M_GLOW]) continue;
					bool up = cb.at(x, y + 1, z) == 0;
					bool side = up || cb.at(x, y - 1, z) == 0 || (x > x0 && cb.at(x - 1, y, z) == 0) || (x < x0 + CS - 1 && cb.at(x + 1, y, z) == 0) ||
							(z > z0 && cb.at(x, y, z - 1) == 0) || (z < z0 + CS - 1 && cb.at(x, y, z + 1) == 0);
					if (!side) continue;
					uint32_t hv = vhash(seed ^ 0xCA7E, x, y, z);
					uint32_t cell = vhash(seed ^ 0x0E5E, x >> 2, y >> 2, z >> 2);
					if ((int)(cell % 100) < (karst ? 16 : 8) && hv % 3 != 0) {
						bool iron = (int)((cell >> 8) % 100) < (karst ? 40 : 15);
						m = iron ? M[M_IRON] : M[M_COPPER];
						continue;
					}
					if (!karst && up && y >= sea_low && y <= sea_high + 4) {
						m = hv % 6 == 0 ? M[M_GRAVEL] : M[M_SAND];
						continue;
					}
					if ((int)(hv % 100) < (karst ? (up ? 6 : 2) : 9)) m = M[M_GLOW];
				}
			}
	}

	// Starter structures and other registered stamps (last, so they win).
	for (const Stamp &st : stamps) {
		const Vector3i &b = st.base, &d = st.dims;
		if (b.x + d.x < x0 || b.x >= x0 + CS || b.z + d.z < z0 || b.z >= z0 + CS) continue;
		for (int y = 0; y < d.y; y++)
			for (int z = 0; z < d.z; z++)
				for (int x = 0; x < d.x; x++) {
					uint8_t m = st.data[x + d.x * (z + d.z * y)];
					if (m == 0) continue;
					cb.set(b.x + x, b.y + y, b.z + z, m == CLEAR ? 0 : m);
				}
		auto fill_down = [&](int x, int z, uint8_t m) {
			if (!cb.in(x, 1, z)) return;
			int th = column_height(x, z);
			for (int k = 0; k < 24; k++) {
				int y = b.y - 1 - k;
				if (y < 1 || y <= th) break;
				cb.set(x, y, z, m);
			}
		};
		if (st.foundation == 1) {
			for (int z = 0; z < d.z; z++)
				for (int x = 0; x < d.x; x++) {
					uint8_t m = st.data[x + d.x * z];
					if (m != 0 && m != CLEAR) fill_down(b.x + x, b.z + z, M[M_COBBLE]);
				}
		} else if (st.foundation == 2) {
			const int cxs[4] = { 0, d.x - 1, 0, d.x - 1 }, czs[4] = { 0, 0, d.z - 1, d.z - 1 };
			for (int i = 0; i < 4; i++) fill_down(b.x + cxs[i], b.z + czs[i], M[M_DARK_WOOD]);
		}
	}

	// Split into 32^3 chunks.
	for (int cy = 0; cy < layers; cy++) {
		const uint8_t *src = buf.data() + (size_t)cy * CS * CS * CS;
		int ylim = std::min(CS, H - cy * CS);
		bool any = false;
		for (size_t i = 0; i < (size_t)CS * CS * ylim; i++) {
			if (src[i]) { any = true; break; }
		}
		if (!any) continue;
		auto mem = std::make_unique<uint8_t[]>(CS * CS * CS);
		memset(mem.get(), 0, CS * CS * CS);
		memcpy(mem.get(), src, (size_t)CS * CS * ylim);
		out[cy] = std::move(mem);
	}
}

Array ArchipelagoGen::generate_column_debug(int cx, int cz) const {
	std::vector<std::unique_ptr<uint8_t[]>> out;
	generate_column(cx, cz, out);
	Array a;
	for (auto &c : out) {
		PackedByteArray p;
		if (c) {
			p.resize(CS * CS * CS);
			memcpy(p.ptrw(), c.get(), CS * CS * CS);
		}
		a.push_back(p);
	}
	return a;
}

// ------------------------------------------------------------------ distant detail

Array ArchipelagoGen::build_lod(const Vector2i &region, int region_vox, int step) const {
	const int n = region_vox / step;
	const int N = n + 2;
	const int rx0 = region.x * region_vox, rz0 = region.y * region_vox;
	const int sea_cut = sea_low - 3;
	std::vector<int> hs(N * N);
	std::vector<Color> cols(N * N);

	// Trees that could cover this region, for canopy silhouettes.
	std::vector<Tree> trees;
	for (int fz = std::max(0, (rz0 - FEATURE_MARGIN) / FC); fz <= (rz0 + region_vox + FEATURE_MARGIN) / FC; fz++)
		for (int fx = std::max(0, (rx0 - FEATURE_MARGIN) / FC); fx <= (rx0 + region_vox + FEATURE_MARGIN) / FC; fx++)
			trees_in_cell(fx, fz, trees);

	auto palc = [](uint8_t m) { return VoxelStore::palette_color(m); };
	const Color leaves = palc(M[M_LEAVES]);
	const Color leaves_dark = palc(M[M_LEAVES_DARK]);
	const int q = std::max(1, step / 4);   // sub-sample offset inside the cell
	for (int j = 0; j < N; j++) {
		for (int i = 0; i < N; i++) {
			const int cx = rx0 + (i - 1) * step + step / 2, cz = rz0 + (j - 1) * step + step / 2;
			// 2x2 sub-samples: averaged height keeps silhouettes smooth at coarse steps.
			const int sx[4] = { cx - q, cx + q, cx - q, cx + q }, sz[4] = { cz - q, cz - q, cz + q, cz + q };
			int sum = 0, hmax = -1000, hmin = 1000, best_id = -1, hi_k = 0;
			for (int k = 0; k < 4; k++) {
				int id;
				int hk = (int)std::lround(height_f(sx[k], sz[k], &id));
				sum += hk;
				if (hk > hmax) { hmax = hk; hi_k = k; best_id = id; }
				hmin = std::min(hmin, hk);
			}
			int h = (int)std::lround(sum / 4.0f);
			if (h < sea_cut) {
				hs[i + N * j] = -1000;
				continue;
			}
			const int x = sx[hi_k], z = sz[hi_k];
			int nb[4] = { column_height(x + 2, z), column_height(x - 2, z), column_height(x, z + 2), column_height(x, z - 2) };
			int k = kind_at(x, z, hmax, best_id, nb);
			if (hmax - hmin > std::max(5, step)) k = K_ROCK;
			int variant = best_id >= 0 ? islands[best_id].strata : 0;
			uint8_t top;
			switch (k) {
				case K_BEACH: top = h < sea_high ? M[M_WET] : M[M_SAND]; break;
				case K_GRASS: top = M[M_GRASS]; break;
				case K_GRASS_DRY: top = M[M_GRASS_DRY]; break;
				case K_SEABED: top = M[M_SAND]; break;
				default: top = strata_at(h, strata_off(x, z), variant); break;
			}
			Color c = palc(top);
			// Tree canopies: tint toward foliage and lift a little by coverage (no pillars).
			int covered = 0, dark = 0;
			for (int sk = 0; sk < 4; sk++) {
				for (const Tree &t : trees) {
					float tr = t.type == 0 ? t.tall * 0.25f : t.r;
					float dx = sx[sk] - (t.x + 1.f), dz = sz[sk] - (t.z + 1.f);
					if (dx * dx + dz * dz <= tr * tr) {
						covered++;
						if (t.type == 0) dark++;
						break;
					}
				}
			}
			if (covered > 0) {
				float f = covered / 4.f;
				Color lc = dark * 2 >= covered ? leaves_dark : leaves;
				c = c.lerp(lc, std::min(1.f, f * 1.2f));
				h += (int)std::lround(f * std::min(8, step));
			}
			float b = 1.f + ((float)(vhash(seed, cx, h, cz) & 0xFFFF) / 65535.f - 0.5f) * 0.12f;
			hs[i + N * j] = h;
			cols[i + N * j] = Color(c.r * b, c.g * b, c.b * b, 1.f);
		}
	}

	std::vector<Vector3> v, nrm;
	std::vector<Color> vc;
	std::vector<int32_t> idx;
	const float vs = 0.18f;
	const float s = step * vs;
	auto quad = [&](Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 normal, Color col) {
		// a,b,c,d clockwise as seen from the front (normal side)
		int32_t bi = (int32_t)v.size();
		v.push_back(a); v.push_back(b); v.push_back(c); v.push_back(d);
		for (int k = 0; k < 4; k++) { nrm.push_back(normal); vc.push_back(col); }
		const int32_t t[6] = { bi, bi + 1, bi + 2, bi, bi + 2, bi + 3 };
		idx.insert(idx.end(), t, t + 6);
	};
	for (int j = 1; j <= n; j++) {
		for (int i = 1; i <= n; i++) {
			int h = hs[i + N * j];
			if (h == -1000) continue;
			Color c = cols[i + N * j];
			float x0 = (i - 1) * s, z0 = (j - 1) * s, x1 = x0 + s, z1 = z0 + s;
			float yt = (h + 1) * vs;
			// top (+Y): clockwise seen from above
			quad(Vector3(x0, yt, z0), Vector3(x1, yt, z0), Vector3(x1, yt, z1), Vector3(x0, yt, z1), Vector3(0, 1, 0), c);
			Color sc(c.r * 0.72f, c.g * 0.70f, c.b * 0.68f, 1.f);
			auto side_h = [&](int ii, int jj) {
				int nh = hs[ii + N * jj];
				return nh == -1000 ? sea_cut - 4 : nh;
			};
			int nh;
			if ((nh = side_h(i + 1, j)) < h) { float yb = (nh + 1) * vs; quad(Vector3(x1, yt, z0), Vector3(x1, yb, z0), Vector3(x1, yb, z1), Vector3(x1, yt, z1), Vector3(1, 0, 0), sc); }
			if ((nh = side_h(i - 1, j)) < h) { float yb = (nh + 1) * vs; quad(Vector3(x0, yt, z1), Vector3(x0, yb, z1), Vector3(x0, yb, z0), Vector3(x0, yt, z0), Vector3(-1, 0, 0), sc); }
			if ((nh = side_h(i, j + 1)) < h) { float yb = (nh + 1) * vs; quad(Vector3(x1, yt, z1), Vector3(x1, yb, z1), Vector3(x0, yb, z1), Vector3(x0, yt, z1), Vector3(0, 0, 1), sc); }
			if ((nh = side_h(i, j - 1)) < h) { float yb = (nh + 1) * vs; quad(Vector3(x0, yt, z0), Vector3(x0, yb, z0), Vector3(x1, yb, z0), Vector3(x1, yt, z0), Vector3(0, 0, -1), sc); }
		}
	}
	if (v.empty()) return Array();
	PackedVector3Array pv, pn;
	PackedColorArray pc;
	PackedInt32Array pi;
	pv.resize(v.size()); pn.resize(nrm.size()); pc.resize(vc.size()); pi.resize(idx.size());
	memcpy(pv.ptrw(), v.data(), v.size() * sizeof(Vector3));
	memcpy(pn.ptrw(), nrm.data(), nrm.size() * sizeof(Vector3));
	memcpy(pc.ptrw(), vc.data(), vc.size() * sizeof(Color));
	memcpy(pi.ptrw(), idx.data(), idx.size() * sizeof(int32_t));
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = pv;
	arrays[Mesh::ARRAY_NORMAL] = pn;
	arrays[Mesh::ARRAY_COLOR] = pc;
	arrays[Mesh::ARRAY_INDEX] = pi;
	return arrays;
}
