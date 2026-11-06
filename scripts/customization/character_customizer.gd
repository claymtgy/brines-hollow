class_name CharacterCustomizer
extends RefCounted
## Manages character visual customizations (hair, beard, skin, wardrobe, eyes).
## Supports serialization, randomizer, presets, and notifies listeners of changes.

signal appearance_changed()

var skin_tone: CharacterPalette.SkinTone = CharacterPalette.SkinTone.WEATHERED_TAN
var hair_style: CharacterPalette.HairStyle = CharacterPalette.HairStyle.WINDSWEPT
var hair_color: CharacterPalette.HairColor = CharacterPalette.HairColor.RAVEN_BLACK
var beard_style: CharacterPalette.BeardStyle = CharacterPalette.BeardStyle.STUBBLE
var beard_color: CharacterPalette.HairColor = CharacterPalette.HairColor.RAVEN_BLACK
var hat_style: CharacterPalette.HatStyle = CharacterPalette.HatStyle.SOUWESTER
var coat_color: CharacterPalette.CoatColor = CharacterPalette.CoatColor.OILSKIN_YELLOW
var eye_color: CharacterPalette.EyeColor = CharacterPalette.EyeColor.SEA_TEAL

## Dirt/weathering intensity 0.0 (pristine) to 1.0 (grimy deep-sea deckhand)
var weathering: float = 0.2


func _init() -> void:
	pass


func set_skin_tone(tone: CharacterPalette.SkinTone) -> void:
	skin_tone = tone
	appearance_changed.emit()


func set_hair(style: CharacterPalette.HairStyle, color: CharacterPalette.HairColor) -> void:
	hair_style = style
	hair_color = color
	appearance_changed.emit()


func set_beard(style: CharacterPalette.BeardStyle, color: CharacterPalette.HairColor) -> void:
	beard_style = style
	beard_color = color
	appearance_changed.emit()


func set_hat(style: CharacterPalette.HatStyle) -> void:
	hat_style = style
	appearance_changed.emit()


func set_coat(color: CharacterPalette.CoatColor) -> void:
	coat_color = color
	appearance_changed.emit()


func set_eye_color(c: CharacterPalette.EyeColor) -> void:
	eye_color = c
	appearance_changed.emit()


func set_weathering(w: float) -> void:
	weathering = clampf(w, 0.0, 1.0)
	appearance_changed.emit()


# -------------------------------------------------------------------------
# Archetype Presets
# -------------------------------------------------------------------------

func apply_preset(preset_name: String) -> void:
	match preset_name.to_lower():
		"north_sea_veteran":
			skin_tone = CharacterPalette.SkinTone.WEATHERED_TAN
			hair_style = CharacterPalette.HairStyle.CROPPED
			hair_color = CharacterPalette.HairColor.SALT_WHITE
			beard_style = CharacterPalette.BeardStyle.FULL_SALT_BUSH
			beard_color = CharacterPalette.HairColor.SALT_WHITE
			hat_style = CharacterPalette.HatStyle.WATCH_CAP
			coat_color = CharacterPalette.CoatColor.NAVY_BLUE
			eye_color = CharacterPalette.EyeColor.STORM_GREY
			weathering = 0.65

		"young_deckhand":
			skin_tone = CharacterPalette.SkinTone.PALE_SALT
			hair_style = CharacterPalette.HairStyle.WINDSWEPT
			hair_color = CharacterPalette.HairColor.STRAW_BLONDE
			beard_style = CharacterPalette.BeardStyle.CLEAN_SHAVEN
			beard_color = CharacterPalette.HairColor.STRAW_BLONDE
			hat_style = CharacterPalette.HatStyle.SOUWESTER
			coat_color = CharacterPalette.CoatColor.OILSKIN_YELLOW
			eye_color = CharacterPalette.EyeColor.SEA_TEAL
			weathering = 0.15

		"brine_hermit":
			skin_tone = CharacterPalette.SkinTone.ABYSSAL_DUSKY
			hair_style = CharacterPalette.HairStyle.WILD_CURLS
			hair_color = CharacterPalette.HairColor.KELP_GREEN
			beard_style = CharacterPalette.BeardStyle.BRAIDED_BEARD
			beard_color = CharacterPalette.HairColor.KELP_GREEN
			hat_style = CharacterPalette.HatStyle.HEADBAND
			coat_color = CharacterPalette.CoatColor.KELP_GREEN
			eye_color = CharacterPalette.EyeColor.AMBER_DRIFT
			weathering = 0.85

		"island_botanist":
			skin_tone = CharacterPalette.SkinTone.RUSTIC_OCHRE
			hair_style = CharacterPalette.HairStyle.SAILOR_BUN
			hair_color = CharacterPalette.HairColor.RUST_AUBURN
			beard_style = CharacterPalette.BeardStyle.ANCHOR_GOATEE
			beard_color = CharacterPalette.HairColor.RUST_AUBURN
			hat_style = CharacterPalette.HatStyle.FISHER_CAP
			coat_color = CharacterPalette.CoatColor.CORAL_RUST
			eye_color = CharacterPalette.EyeColor.DARK_PEAT
			weathering = 0.25

		_:
			# Default starter
			skin_tone = CharacterPalette.SkinTone.WEATHERED_TAN
			hair_style = CharacterPalette.HairStyle.WINDSWEPT
			hair_color = CharacterPalette.HairColor.RAVEN_BLACK
			beard_style = CharacterPalette.BeardStyle.STUBBLE
			beard_color = CharacterPalette.HairColor.RAVEN_BLACK
			hat_style = CharacterPalette.HatStyle.SOUWESTER
			coat_color = CharacterPalette.CoatColor.OILSKIN_YELLOW
			eye_color = CharacterPalette.EyeColor.SEA_TEAL
			weathering = 0.2

	appearance_changed.emit()


func randomize_appearance(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	skin_tone = rng.randi_range(0, CharacterPalette.SkinTone.size() - 1) as CharacterPalette.SkinTone
	hair_style = rng.randi_range(0, CharacterPalette.HairStyle.size() - 1) as CharacterPalette.HairStyle
	hair_color = rng.randi_range(0, CharacterPalette.HairColor.size() - 1) as CharacterPalette.HairColor
	beard_style = rng.randi_range(0, CharacterPalette.BeardStyle.size() - 1) as CharacterPalette.BeardStyle
	beard_color = hair_color # natural match by default
	hat_style = rng.randi_range(0, CharacterPalette.HatStyle.size() - 1) as CharacterPalette.HatStyle
	coat_color = rng.randi_range(0, CharacterPalette.CoatColor.size() - 1) as CharacterPalette.CoatColor
	eye_color = rng.randi_range(0, CharacterPalette.EyeColor.size() - 1) as CharacterPalette.EyeColor
	weathering = rng.randf_range(0.0, 0.7)

	appearance_changed.emit()


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"skin_tone": skin_tone,
		"hair_style": hair_style,
		"hair_color": hair_color,
		"beard_style": beard_style,
		"beard_color": beard_color,
		"hat_style": hat_style,
		"coat_color": coat_color,
		"eye_color": eye_color,
		"weathering": weathering
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	skin_tone = data.get("skin_tone", skin_tone) as CharacterPalette.SkinTone
	hair_style = data.get("hair_style", hair_style) as CharacterPalette.HairStyle
	hair_color = data.get("hair_color", hair_color) as CharacterPalette.HairColor
	beard_style = data.get("beard_style", beard_style) as CharacterPalette.BeardStyle
	beard_color = data.get("beard_color", beard_color) as CharacterPalette.HairColor
	hat_style = data.get("hat_style", hat_style) as CharacterPalette.HatStyle
	coat_color = data.get("coat_color", coat_color) as CharacterPalette.CoatColor
	eye_color = data.get("eye_color", eye_color) as CharacterPalette.EyeColor
	weathering = float(data.get("weathering", weathering))
	appearance_changed.emit()
