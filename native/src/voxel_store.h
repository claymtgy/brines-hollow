#pragma once
// Brine's Hollow voxel core: sparse chunk storage, meshing, raycasts, collision, edits.
// Thread-safe: many readers (meshing workers, raycasts) / one writer (edits).

#include "archipelago.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {

class VoxelStore : public RefCounted {
	GDCLASS(VoxelStore, RefCounted);

public:
	static constexpr int CS = 32;               // chunk edge in voxels
	static constexpr int CV = CS * CS * CS;     // voxels per chunk
	static constexpr int PS = CS + 2;           // padded edge
	static constexpr uint8_t CLEAR = 255;       // prefab marker: carve to air
	static constexpr uint8_t BEDROCK = 1;
	enum MatFlags { F_EMISSIVE = 1, F_FOLIAGE = 2 };

private:
	Vector3i size = Vector3i(512, 128, 512);   // world bounds in voxels
	float vs = 0.18f;                           // voxel size in metres

	std::unordered_map<int64_t, std::unique_ptr<uint8_t[]>> chunks;
	mutable std::shared_mutex mtx;

	std::mutex dirty_mtx;
	std::unordered_set<int64_t> dirty;

	Ref<ArchipelagoGen> gen;
	std::unordered_set<int64_t> gen_cols;     // chunk columns that have been generated
	std::unordered_set<int64_t> edited_cols;  // chunk columns touched by edits (never unloaded)
	static inline int64_t ckey(int cx, int cz) { return key(cx, 0, cz); }
	void ensure_column_locked(int cx, int cz);
	void ensure_box_locked(int x0, int z0, int x1, int z1);

	static std::vector<Color> pal_colors;
	static std::vector<float> pal_variation;
	static std::vector<uint8_t> pal_flags;

	static inline int64_t key(int cx, int cy, int cz) {
		return ((int64_t)(cx & 0x1FFFFF) << 42) | ((int64_t)(cy & 0x1FFFFF) << 21) | (int64_t)(cz & 0x1FFFFF);
	}
	static inline int sext21(int64_t v) { return (int)((v & 0x100000) ? (v | ~(int64_t)0x1FFFFF) : v); }
	static inline Vector3i unkey(int64_t k) {
		return Vector3i(sext21((k >> 42) & 0x1FFFFF), sext21((k >> 21) & 0x1FFFFF), sext21(k & 0x1FFFFF));
	}

	inline bool in_bounds(int x, int y, int z) const {
		return x >= 0 && y >= 0 && z >= 0 && x < size.x && y < size.y && z < size.z;
	}
	inline const uint8_t *chunk_ptr(int cx, int cy, int cz) const {
		auto it = chunks.find(key(cx, cy, cz));
		return it == chunks.end() ? nullptr : it->second.get();
	}
	uint8_t get_raw(int x, int y, int z) const;     // caller holds a lock
	bool set_raw(int x, int y, int z, uint8_t m);   // caller holds the unique lock
	void mark(int cx, int cy, int cz);
	void mark_voxel(int x, int y, int z);

protected:
	static void _bind_methods();

public:
	// setup
	void setup(const Vector3i &p_size, float p_voxel_size);
	Vector3i get_size() const { return size; }
	float get_voxel_size() const { return vs; }
	static void set_palette(const PackedColorArray &colors, const PackedFloat32Array &variation, const PackedByteArray &flags);
	void clear();

	// access
	int get_voxel(int x, int y, int z) const;
	bool set_voxel(int x, int y, int z, int m);
	void set_chunk_data(const Vector3i &c, const PackedByteArray &data);
	PackedByteArray get_chunk_data(const Vector3i &c) const;
	TypedArray<Vector3i> get_chunk_coords() const;
	TypedArray<Vector3i> take_dirty();
	int get_chunk_count() const;

	// streaming / on-demand generation
	void set_generator(const Ref<ArchipelagoGen> &p_gen);
	bool generate_column(const Vector2i &col);           // thread-safe; false if already generated
	bool is_column_generated(const Vector2i &col) const;
	bool unload_column(const Vector2i &col);             // drops unedited data; false if kept
	TypedArray<Vector2i> get_generated_columns() const;
	bool has_chunk(const Vector3i &c) const;
	static Color palette_color(int m) { return (m >= 0 && m < (int)pal_colors.size()) ? pal_colors[m] : Color(1, 0, 1); }

	// generation helper: fill terrain from per-column heights / kinds / strata
	void fill_from_columns(const PackedInt32Array &heights, const PackedByteArray &kinds,
			const PackedByteArray &strata, int sea_low, int sea_high, const PackedByteArray &mats);

	// edits
	Dictionary dig_sphere(const Vector3i &c, int r);
	int place_sphere(const Vector3i &c, int r, int m);
	void stamp(const PackedByteArray &data, const Vector3i &dims, const Vector3i &base);
	int fill_down(int x, int y, int z, int m, int max_depth);

	// queries
	Dictionary raycast(const Vector3 &origin, const Vector3 &dir, float max_dist, bool see_through_foliage) const;
	bool aabb_collides(const Vector3 &min_m, const Vector3 &max_m) const;

	// meshing
	Array mesh_chunk(const Vector3i &c) const;
	static Array mesh_grid(const PackedByteArray &data, const Vector3i &dims, float scale);
	static Array build_mesh(const uint8_t *P, int px, int py, int pz, float scale, int wx, int wy, int wz);
	// Greedy-merged faces; colour variation is left to the shader (vertex alpha = variation amount).
	static Array build_mesh_greedy(const uint8_t *P, int px, int py, int pz, float scale);
};

} // namespace godot
