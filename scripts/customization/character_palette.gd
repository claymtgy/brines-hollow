class_name CharacterPalette
extends RefCounted
## Color palettes and style enumerations for Brine's Hollow character customization.
## Coastal, nautical, and weathered tones that complement the game's voxel aesthetic.

enum SkinTone {
	PALE_SALT,        ## Fair, wind-burned coastal skin
	WEATHERED_TAN,    ## Sun-baked sailor tan
	RUSTIC_OCHRE,     ## Warm golden brown
	DEEP_UMBER,       ## Rich dark sea timber
	ABYSSAL_DUSKY     ## Muted slate-ash undertone
}

enum HairColor {
	RAVEN_BLACK,      ## Tar black
	DRIFTWOOD_GREY,   ## Bleached silvery grey
	SALT_WHITE,       ## Pure elder white
	RUST_AUBURN,      ## Weathered copper red
	STRAW_BLONDE,     ## Flaxen shore grass
	KELP_GREEN        ## Occult brine-stained green
}

enum HairStyle {
	BALD,             ## Shaved scalp
	CROPPED,          ## Practical short deck crop
	WINDSWEPT,        ## Side-swept stormy bangs
	SAILOR_BUN,       ## High bun tied with cord
	BRAIDED_TIDES,    ## Twin braided sea locks
	WILD_CURLS        ## Unruly coastal curls
}

enum BeardStyle {
	CLEAN_SHAVEN,     ## Bare face
	STUBBLE,          ## Sea-salt 5 o'clock shadow
	MUTTON_CHOPS,     ## Classic 19th-century naval sideburns
	FULL_SALT_BUSH,   ## Thick captain's beard
	BRAIDED_BEARD,    ## Braided chin beard with bone rings
	ANCHOR_GOATEE     ## Trimmed anchor-shaped chin strap
}

enum HatStyle {
	NONE,             ## Bareheaded
	SOUWESTER,        ## Classic oilskin sou'wester with storm neck-flap
	WATCH_CAP,        ## Woolen watch cap (beanie)
	FISHER_CAP,       ## Peaked skipper / mariner cap
	HEADBAND          ## Sailor's folded bandana
}

enum CoatColor {
	OILSKIN_YELLOW,   ## Classic hazard yellow
	NAVY_BLUE,        ## Deep maritime navy
	STORM_GREY,       ## Foggy overcast grey
	KELP_GREEN,       ## Dried marsh green
	CORAL_RUST,       ## Faded orange terracotta
	PITCH_BLACK       ## Waterproof pitch-coated wool
}

enum EyeColor {
	DARK_PEAT,        ## Deep dark brown
	SEA_TEAL,         ## Piercing maritime teal
	AMBER_DRIFT,      ## Golden amber
	STORM_GREY        ## Slate cold grey
}

## Color definitions mapped to Godot Color values
const SKIN_COLORS: Dictionary = {
	SkinTone.PALE_SALT: Color8(245, 212, 184),
	SkinTone.WEATHERED_TAN: Color8(218, 168, 128),
	SkinTone.RUSTIC_OCHRE: Color8(178, 126, 88),
	SkinTone.DEEP_UMBER: Color8(118, 76, 52),
	SkinTone.ABYSSAL_DUSKY: Color8(148, 138, 142)
}

const HAIR_COLORS: Dictionary = {
	HairColor.RAVEN_BLACK: Color8(36, 32, 34),
	HairColor.DRIFTWOOD_GREY: Color8(158, 154, 150),
	HairColor.SALT_WHITE: Color8(232, 230, 226),
	HairColor.RUST_AUBURN: Color8(172, 82, 54),
	HairColor.STRAW_BLONDE: Color8(224, 192, 118),
	HairColor.KELP_GREEN: Color8(78, 114, 82)
}

const COAT_COLORS: Dictionary = {
	CoatColor.OILSKIN_YELLOW: Color8(244, 196, 66),
	CoatColor.NAVY_BLUE: Color8(54, 76, 112),
	CoatColor.STORM_GREY: Color8(118, 124, 132),
	CoatColor.KELP_GREEN: Color8(72, 108, 80),
	CoatColor.CORAL_RUST: Color8(196, 96, 76),
	CoatColor.PITCH_BLACK: Color8(42, 40, 44)
}

const EYE_COLORS: Dictionary = {
	EyeColor.DARK_PEAT: Color8(40, 34, 40),
	EyeColor.SEA_TEAL: Color8(68, 162, 168),
	EyeColor.AMBER_DRIFT: Color8(214, 148, 48),
	EyeColor.STORM_GREY: Color8(140, 152, 164)
}

static func get_skin_color(tone: SkinTone) -> Color:
	return SKIN_COLORS.get(tone, SKIN_COLORS[SkinTone.PALE_SALT])

static func get_hair_color(c: HairColor) -> Color:
	return HAIR_COLORS.get(c, HAIR_COLORS[HairColor.RAVEN_BLACK])

static func get_coat_color(c: CoatColor) -> Color:
	return COAT_COLORS.get(c, COAT_COLORS[CoatColor.OILSKIN_YELLOW])

static func get_eye_color(c: EyeColor) -> Color:
	return EYE_COLORS.get(c, EYE_COLORS[EyeColor.DARK_PEAT])
