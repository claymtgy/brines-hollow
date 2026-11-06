#pragma once
// Brine's Hollow archipelago generator.
// Pure function of (seed, chunk column): any column can be generated in any order on any
// thread and every client/server gets identical voxels. Cross-chunk features (trees,
// boulders, the sea cave, starter structures) come from seed-derived feature lists and are
// stamped into whichever column they overlap.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <memory>
#include <vector>

namespace godot {

struct Simplex2 {
	uint8_t perm[512];
	float freq = 0.01f;
	int octaves = 1;
	void init(uint64_t seed, float p_freq, int p_octaves);
	float noise(float x, float y) const;   // [-1, 1]
	float fbm(float x, float y) const;     // [-1, 1]
};

class ArchipelagoGen : public RefCounted {
	GDCLASS(ArchipelagoGen, RefCounted);

public:
	static constexpr int CS = 32;
	static constexpr int FC = 64;          // feature cell size (voxels)
	static constexpr int FEATURE_MARGIN = 18;
	static constexpr uint8_t CLEAR = 255;

	enum Kind { K_BEACH, K_GRASS, K_ROCK, K_SEABED, K_GRASS_DRY };
	enum IslandType { T_HOME, T_STANDARD, T_ISLET };
	enum Mat {
		M_BEDROCK, M_STONE, M_SA, M_SB, M_SC, M_SAND, M_WET, M_GRAVEL, M_DIRT, M_GRASS, M_GRASS_DRY,
		M_KELP, M_LEAVES, M_LEAVES_DARK, M_TRUNK, M_FLOWER_Y, M_FLOWER_P, M_DRIFTWOOD, M_GLOW, M_COBBLE, M_DARK_WOOD,
		M_COUNT
	};

	struct Island {
		float cx, cz, R;
		int type;
		float hill;          // height scale
		float cliff_bias;    // + more cliffs
		float dry_bias;      // + more dry grass
		float tree_bias;     // + more trees
		int strata;          // strata palette variant
		float salt;          // noise offset
	};
	struct Stack { float x, z, r, h; };
	struct Sphere { float x, y, z, r; };
	struct Stamp {
		std::vector<uint8_t> data;
		Vector3i dims, base;
		int foundation; // 0 none, 1 solid, 2 posts
	};
	struct Tree { int x, y, z, type, tall; float r; };

private:
	uint64_t seed = 1;
	Vector3i size = Vector3i(5632, 128, 5632);
	float sea_mid = 30.f;
	int sea_low = 23, sea_high = 37;
	uint8_t M[M_COUNT] = {};

	Simplex2 n_warp, n_shape, n_hill, n_cliff, n_detail;
	std::vector<Island> islands;
	std::vector<Stack> stacks;
	std::vector<std::vector<int>> grid;    // island ids per GRID cell
	std::vector<std::vector<int>> sgrid;   // stack ids per GRID cell
	int grid_w = 1;
	static constexpr int GRID = 512;

	std::vector<Sphere> cave;
	Vector3i cave_min, cave_max;
	std::vector<Stamp> stamps;

	float height_f(int x, int z, int *island) const;
	int kind_at(int x, int z, int h, int island, const int *nb_h) const;
	uint8_t strata_at(int y, int off, int variant) const;
	int strata_off(int x, int z) const;
	void plan_sea_cave();
	void trees_in_cell(int fx, int fz, std::vector<Tree> &out) const;

public:
	static void _bind_methods();

	void configure(int p_seed, const Vector3i &p_size, float p_sea_mid, float p_tide_amp, const PackedByteArray &mats);

	// queries (thread-safe)
	int column_height(int x, int z) const;
	int column_kind(int x, int z) const;
	int column_island(int x, int z) const;
	Array get_islands() const;
	TypedArray<Vector2i> land_regions(int region_vox) const;

	// starter structures etc. (call before streaming starts)
	void add_stamp(const PackedByteArray &data, const Vector3i &dims, const Vector3i &base, int foundation);
	void clear_stamps() { stamps.clear(); }

	// generation (thread-safe). out[cy] is null for all-air layers.
	void generate_column(int cx, int cz, std::vector<std::unique_ptr<uint8_t[]>> &out) const;
	Array generate_column_debug(int cx, int cz) const;

	// distant detail
	Array build_lod(const Vector2i &region, int region_vox, int step) const;
};

} // namespace godot
