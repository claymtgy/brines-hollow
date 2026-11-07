class_name GameSettings
extends RefCounted
## Player settings: stored in user://settings.cfg, applied live to the running game.
## Graphics presets are tuned against the performance budget in ROADMAP.md
## (laptop 680M: 60 fps at 1080p; Steam Deck: 40+ fps at 1280x800).

const PATH := "user://settings.cfg"

enum Preset { DECK, LOW, MEDIUM, HIGH, CUSTOM }
const PRESET_NAMES := ["Steam Deck", "Low", "Medium", "High", "Custom"]
enum AA { OFF, FXAA, SMAA, MSAA_2X, MSAA_4X, TAA }
const AA_NAMES := ["Off", "FXAA", "SMAA", "MSAA 2x", "MSAA 4x", "TAA"]
enum Shadows { OFF, LOW, MEDIUM, HIGH }
const SHADOW_NAMES := ["Off", "Low", "Medium", "High"]
enum Upscaler { BILINEAR, FSR1, FSR2 }
const UPSCALER_NAMES := ["Bilinear", "FSR 1", "FSR 2"]
enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }
const WINDOW_NAMES := ["Windowed", "Fullscreen", "Borderless"]

# controls
var mouse_sensitivity := 1.0         # x 0.0026 rad/px
var invert_y := false
var controller_look_speed := 2.6     # rad/s at full stick
var fov := 66.0
var shoulder_right := true
var camera_distance := 5.5
var foliage_fade := true

# graphics
var preset := Preset.MEDIUM
var render_scale := 0.0               # 0 = auto: hold a pixel budget for the preset
var upscaler := Upscaler.FSR1
var aa := AA.FXAA
var shadows := Shadows.MEDIUM
var view_distance := 10              # full-detail radius in chunk columns (~5.8 m each)
var glow := 1                        # 0 off, 1 night only, 2 always
var vsync := true
var max_fps := 0
var window_mode := WindowMode.WINDOWED

# interface
var ui_scale := 1.0

# audio (linear 0..1)
var master_volume := 0.8
var ambience_volume := 0.8
var effects_volume := 0.8

# keyboard rebinds: action -> physical keycode (only actions the player changed)
var key_overrides := {}

const GLOW_NAMES := ["Off", "Night only", "Always"]

# pixel_budget: megapixels rendered in 3D when render scale is Auto (then FSR upscales).
const PRESETS := {
	Preset.DECK:   {"pixel_budget": 0.66, "upscaler": Upscaler.FSR1, "aa": AA.FXAA,    "shadows": Shadows.LOW,    "view_distance": 7,  "glow": 1},
	Preset.LOW:    {"pixel_budget": 0.9,  "upscaler": Upscaler.FSR1, "aa": AA.FXAA,    "shadows": Shadows.LOW,    "view_distance": 7,  "glow": 0},
	Preset.MEDIUM: {"pixel_budget": 1.25, "upscaler": Upscaler.FSR1, "aa": AA.FXAA,    "shadows": Shadows.MEDIUM, "view_distance": 10, "glow": 1},
	Preset.HIGH:   {"pixel_budget": 2.2,  "upscaler": Upscaler.FSR1, "aa": AA.MSAA_2X, "shadows": Shadows.HIGH,   "view_distance": 12, "glow": 2},
}
var pixel_budget := 1.4

const SAVED_FIELDS := ["mouse_sensitivity", "invert_y", "controller_look_speed", "fov", "shoulder_right",
	"camera_distance", "foliage_fade", "preset", "render_scale", "pixel_budget", "upscaler", "aa", "shadows",
	"view_distance", "glow", "vsync", "max_fps", "window_mode", "ui_scale",
	"master_volume", "ambience_volume", "effects_volume"]


static func is_steam_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	var s := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return s == Vector2i(1280, 800) or s == Vector2i(800, 1280)


func apply_preset(p: int) -> void:
	preset = p
	if PRESETS.has(p):
		render_scale = 0.0
		for k in PRESETS[p]:
			set(k, PRESETS[p][k])
	if p == Preset.DECK:
		ui_scale = 1.25


## First run: Steam Deck gets the Deck preset, everything else Medium.
static func load_or_default() -> GameSettings:
	var s := GameSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		s.apply_preset(Preset.DECK if is_steam_deck() else Preset.MEDIUM)
		return s
	for f: String in SAVED_FIELDS:
		s.set(f, cfg.get_value("settings", f, s.get(f)))
	for a: String in cfg.get_section_keys("keys") if cfg.has_section("keys") else []:
		s.key_overrides[a] = int(cfg.get_value("keys", a))
	return s


func save() -> void:
	var cfg := ConfigFile.new()
	for f: String in SAVED_FIELDS:
		cfg.set_value("settings", f, get(f))
	for a: String in key_overrides:
		cfg.set_value("keys", a, key_overrides[a])
	cfg.save(PATH)


## Auto (render_scale == 0): render about `pixel_budget` megapixels whatever the window
## size, so a bigger window or monitor doesn't silently blow the GPU budget.
func effective_render_scale(vp: Viewport) -> float:
	if render_scale > 0.0:
		return render_scale
	# Physical window pixels: the visible rect shrinks with UI scale, the 3D render doesn't.
	var size := Vector2(vp.get_window().size) if vp.get_window() != null else vp.get_visible_rect().size
	var mp := size.x * size.y / 1.0e6
	if mp <= 0.0:
		return 1.0
	return clampf(sqrt(pixel_budget / mp), 0.5, 1.0)


## Pushes every setting into the running game. Safe to call any time (menu, startup).
func apply(main: Node) -> void:
	var vp: Viewport = main.get_viewport()
	# --- camera / controls
	var rig: CameraRig = main.rig
	if rig != null:
		rig.sensitivity = 0.0026 * mouse_sensitivity
		rig.invert_y = invert_y
		rig.controller_look_speed = controller_look_speed
		rig.foliage_fade = foliage_fade
		rig.shoulder = absf(rig.shoulder) * (1.0 if shoulder_right else -1.0)
		rig.dist = camera_distance
		if rig.cam != null:
			rig.cam.fov = fov
	# --- resolution scaling + anti-aliasing
	vp.scaling_3d_scale = effective_render_scale(vp)
	match upscaler:
		Upscaler.BILINEAR: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		Upscaler.FSR1: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		Upscaler.FSR2: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	match aa:
		AA.FXAA: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AA.SMAA: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		AA.MSAA_2X: vp.msaa_3d = Viewport.MSAA_2X
		AA.MSAA_4X: vp.msaa_3d = Viewport.MSAA_4X
		AA.TAA: vp.use_taa = true
	if upscaler == Upscaler.FSR2:
		vp.use_taa = false  # FSR2 does its own temporal AA
	# --- shadows
	var sky: SkyCycle = main.sky
	if sky != null:
		var sun := sky.sun
		sun.shadow_enabled = shadows != Shadows.OFF
		match shadows:
			Shadows.LOW:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				sun.directional_shadow_max_distance = 30.0
				RenderingServer.directional_shadow_atlas_set_size(2048, true)
			Shadows.MEDIUM:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				sun.directional_shadow_max_distance = 45.0
				RenderingServer.directional_shadow_atlas_set_size(4096, true)
			Shadows.HIGH:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				sun.directional_shadow_max_distance = 70.0
				RenderingServer.directional_shadow_atlas_set_size(4096, true)
		sky.glow_mode = glow
	# --- view distance
	var world: VoxelWorld = main.world
	if world != null and world.mesh_radius != view_distance:
		world.mesh_radius = view_distance
		if world.has_method("_refresh_want") and world.ready_for_play:
			world._refresh_want(true)
	# --- display (skipped headless)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		match window_mode:
			WindowMode.WINDOWED: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			WindowMode.FULLSCREEN: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			WindowMode.BORDERLESS: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		main.get_tree().root.content_scale_factor = ui_scale
	Engine.max_fps = max_fps
	# --- audio buses (Ambience / Effects are created by AmbientAudio)
	AmbientAudio.ensure_buses()
	for pair in [["Master", master_volume], ["Ambience", ambience_volume], ["Effects", effects_volume]]:
		var bi := AudioServer.get_bus_index(pair[0])
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(float(pair[1]), 0.0001)))
			AudioServer.set_bus_mute(bi, float(pair[1]) <= 0.001)
	apply_keys()


var _default_keys := {}   # action -> [physical keycodes], captured before any override


## Keyboard rebinds: replaces the keyboard events of overridden actions, keeps gamepad events.
func apply_keys() -> void:
	if _default_keys.is_empty():
		for action: StringName in InputMap.get_actions():
			var codes := []
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					codes.append(ev.physical_keycode)
			if not codes.is_empty():
				_default_keys[String(action)] = codes
	for action: String in key_overrides:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var k := InputEventKey.new()
		k.physical_keycode = key_overrides[action]
		InputMap.action_add_event(action, k)


func reset_keys() -> void:
	key_overrides.clear()
	for action: String in _default_keys:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		for code: int in _default_keys[action]:
			var k := InputEventKey.new()
			k.physical_keycode = code
			InputMap.action_add_event(action, k)
	save()
