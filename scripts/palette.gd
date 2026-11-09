class_name Palette
extends RefCounted
## Voxel material palette. Every voxel is one flat color (no textures);
## per-voxel brightness variation is added at mesh time.

enum {
	AIR = 0,
	BEDROCK, STONE, SANDSTONE_A, SANDSTONE_B, SANDSTONE_C,
	SAND, WET_SAND, GRAVEL, DIRT, GRASS, GRASS_DRY,
	PLANK, DARK_WOOD, WHITEWASH, ROOF_RED, ROOF_BLUE,
	BUOY, LANTERN, COBBLE, KELP, LEAVES, LEAVES_DARK, TRUNK,
	FLOWER_Y, FLOWER_P, SHUTTER, GLOW_TEAL, DRIFTWOOD,
	# character materials
	SKIN, EYE, CHEEK, COAT_A, HAT_A, COAT_B, HAT_B, TROUSER, BOOT, METAL, HANDLE, BUTTON,
	# ore veins in cave walls (appended so saved voxel ids never shift)
	COPPER_VEIN, IRON_VEIN,
	# walk-through plants drawn as little crossed sprites (flowers are plants too)
	TUFT_GRASS, TUFT_DRY,
	# calamine (zinc ore for fine sea-brass), in the old brass mines
	CALAMINE,
	COUNT
}

## Special prefab marker: "carve this cell to air".
const CLEAR := 255

static var COLORS: PackedColorArray = PackedColorArray([
	Color8(0, 0, 0),          # AIR
	Color8(58, 52, 60),       # BEDROCK
	Color8(128, 118, 124),    # STONE (grey-mauve)
	Color8(196, 160, 118),    # SANDSTONE_A
	Color8(176, 116, 82),     # SANDSTONE_B (rust)
	Color8(214, 186, 146),    # SANDSTONE_C (pale)
	Color8(232, 214, 172),    # SAND
	Color8(176, 150, 112),    # WET_SAND
	Color8(150, 142, 134),    # GRAVEL
	Color8(124, 92, 66),      # DIRT
	Color8(134, 168, 104),    # GRASS (muted sage)
	Color8(176, 178, 112),    # GRASS_DRY
	Color8(178, 148, 112),    # PLANK (driftwood-ish)
	Color8(84, 64, 52),       # DARK_WOOD (tarred)
	Color8(236, 230, 214),    # WHITEWASH
	Color8(184, 86, 70),      # ROOF_RED (faded)
	Color8(84, 122, 156),     # ROOF_BLUE (faded)
	Color8(236, 124, 52),     # BUOY orange
	Color8(255, 210, 120),    # LANTERN (emissive)
	Color8(150, 146, 140),    # COBBLE
	Color8(70, 100, 62),      # KELP
	Color8(108, 150, 88),     # LEAVES
	Color8(76, 116, 72),      # LEAVES_DARK
	Color8(112, 84, 62),      # TRUNK
	Color8(242, 206, 90),     # FLOWER_Y
	Color8(214, 132, 170),    # FLOWER_P
	Color8(110, 150, 170),    # SHUTTER (faded blue)
	Color8(110, 230, 210),    # GLOW_TEAL (emissive)
	Color8(170, 160, 146),    # DRIFTWOOD (grey bleached)
	Color8(240, 196, 160),    # SKIN
	Color8(40, 34, 40),       # EYE
	Color8(236, 150, 140),    # CHEEK
	Color8(244, 196, 66),     # COAT_A (oilskin yellow)
	Color8(226, 172, 48),     # HAT_A
	Color8(72, 132, 150),     # COAT_B (sea teal)
	Color8(196, 84, 70),      # HAT_B (faded red)
	Color8(62, 74, 102),      # TROUSER (navy)
	Color8(78, 56, 44),       # BOOT
	Color8(160, 166, 172),    # METAL
	Color8(130, 96, 66),      # HANDLE
	Color8(60, 50, 44),       # BUTTON
	Color8(196, 112, 66),     # COPPER_VEIN (green-flecked copper)
	Color8(150, 92, 80),      # IRON_VEIN (rusty red-brown)
	Color8(120, 162, 92),     # TUFT_GRASS
	Color8(186, 182, 112),    # TUFT_DRY
	Color8(132, 178, 170),    # CALAMINE (pale blue-green crust)
])

## How strongly each material's brightness varies voxel-to-voxel.
const VARIATION := [
	0.0, 0.08, 0.13, 0.11, 0.11, 0.10,
	0.09, 0.10, 0.16, 0.13, 0.14, 0.14,
	0.12, 0.10, 0.06, 0.11, 0.11,
	0.06, 0.0, 0.18, 0.14, 0.16, 0.16, 0.13,
	0.06, 0.06, 0.05, 0.0, 0.08,
	0.0, 0.0, 0.0, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.03, 0.03, 0.0,
	0.22, 0.20,
	0.16, 0.14,
	0.24,
]

const NAMES := [
	"Air", "Bedrock", "Stone", "Sandstone", "Rust Sandstone", "Pale Sandstone",
	"Sand", "Wet Sand", "Gravel", "Dirt", "Grass", "Dry Grass",
	"Plank", "Tarred Wood", "Whitewash", "Red Roof", "Blue Roof",
	"Buoy Orange", "Lantern Glow", "Cobble", "Kelp", "Leaves", "Dark Leaves", "Trunk",
	"Yellow Flower", "Pink Flower", "Shutter Blue", "Sea Glow", "Driftwood",
	"Skin", "Eye", "Cheek", "Coat", "Hat", "Coat", "Hat", "Trouser", "Boot", "Metal", "Handle", "Button",
	"Copper Vein", "Brine-Iron Vein", "Grass Tuft", "Dry Grass Tuft",
	"Calamine Vein",
]

## Materials offered in Build mode, in hotbar order.
const BUILDABLE := [
	PLANK, DARK_WOOD, DRIFTWOOD, WHITEWASH, COBBLE, STONE, SANDSTONE_A, SANDSTONE_B,
	SAND, GRAVEL, DIRT, GRASS, ROOF_RED, ROOF_BLUE, SHUTTER, BUOY, LANTERN, GLOW_TEAL, LEAVES,
]

static func is_emissive(m: int) -> bool:
	return m == LANTERN or m == GLOW_TEAL


## Things the camera can pass through (leaves, flowers, kelp).
static func is_foliage(m: int) -> bool:
	return m == LEAVES or m == LEAVES_DARK or m == FLOWER_Y or m == FLOWER_P or m == KELP or m == TUFT_GRASS or m == TUFT_DRY


## Leaf blocks: drawn with small holes so you can see into and through a tree's crown.
static func is_leafy(m: int) -> bool:
	return m == LEAVES or m == LEAVES_DARK


## Flowers and grass tufts: little sprites you walk through, not blocks.
static func is_plant(m: int) -> bool:
	return m == FLOWER_Y or m == FLOWER_P or m == TUFT_GRASS or m == TUFT_DRY
