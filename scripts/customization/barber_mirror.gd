class_name BarberMirror
extends RefCounted
## Station/interface for players to modify their appearance at a Standing Mirror or Town Barber.
## Provides structured methods to cycle styles, preview modifications, and commit appearance changes.

signal customization_opened()
signal customization_closed()
signal appearance_modified()

var customizer: CharacterCustomizer = null
var preview_model: CharacterModel = null
var is_active: bool = false


func _init(p_customizer: CharacterCustomizer = null, p_model: CharacterModel = null) -> void:
	customizer = p_customizer if p_customizer else CharacterCustomizer.new()
	preview_model = p_model
	if customizer and preview_model:
		customizer.appearance_changed.connect(_on_appearance_changed)


func open_station() -> void:
	is_active = true
	customization_opened.emit()


func close_station() -> void:
	is_active = false
	customization_closed.emit()


func cycle_skin(dir: int = 1) -> void:
	var total := CharacterPalette.SkinTone.size()
	var next_val := posmod(int(customizer.skin_tone) + dir, total)
	customizer.set_skin_tone(next_val as CharacterPalette.SkinTone)
	appearance_modified.emit()


func cycle_hair_style(dir: int = 1) -> void:
	var total := CharacterPalette.HairStyle.size()
	var next_val := posmod(int(customizer.hair_style) + dir, total)
	customizer.set_hair(next_val as CharacterPalette.HairStyle, customizer.hair_color)
	appearance_modified.emit()


func cycle_hair_color(dir: int = 1) -> void:
	var total := CharacterPalette.HairColor.size()
	var next_val := posmod(int(customizer.hair_color) + dir, total)
	customizer.set_hair(customizer.hair_style, next_val as CharacterPalette.HairColor)
	appearance_modified.emit()


func cycle_beard_style(dir: int = 1) -> void:
	var total := CharacterPalette.BeardStyle.size()
	var next_val := posmod(int(customizer.beard_style) + dir, total)
	customizer.set_beard(next_val as CharacterPalette.BeardStyle, customizer.beard_color)
	appearance_modified.emit()


func cycle_hat_style(dir: int = 1) -> void:
	var total := CharacterPalette.HatStyle.size()
	var next_val := posmod(int(customizer.hat_style) + dir, total)
	customizer.set_hat(next_val as CharacterPalette.HatStyle)
	appearance_modified.emit()


func cycle_coat_color(dir: int = 1) -> void:
	var total := CharacterPalette.CoatColor.size()
	var next_val := posmod(int(customizer.coat_color) + dir, total)
	customizer.set_coat(next_val as CharacterPalette.CoatColor)
	appearance_modified.emit()


func apply_preset(name: String) -> void:
	customizer.apply_preset(name)
	appearance_modified.emit()


func randomize_appearance() -> void:
	customizer.randomize_appearance()
	appearance_modified.emit()


func _on_appearance_changed() -> void:
	if preview_model:
		preview_model.apply_customizer(customizer)
