class_name SkyCycle
extends Node3D
## Day/night + tide clock. Sunny & faded palette, sea-tinted fog.
## One in-game day = DAY_LENGTH seconds; two tides per day.

const DAY_LENGTH := 720.0

var time_of_day := 0.34       # 0..1 (0.25 = sunrise, 0.5 = noon, 0.75 = sunset)
var day := 0                  # whole days since world creation (weather schedule clock)
var weather: Weather
var time_scale := 1.0
var glow_mode := 1            # 0 off, 1 night only, 2 always (set by GameSettings)
var water_level_vox := VoxelWorld.SEA_MID

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var water: MeshInstance3D
var water_mat: ShaderMaterial

# Keyframes: [t, sky_top, horizon, light_color, light_energy, fog, ambient_energy]
var _keys := [
	[0.00, Color("0d1b30"), Color("1e3350"), Color("8ea6da"), 0.28, Color("15263c"), 0.35],
	[0.21, Color("1a2d4a"), Color("3b4a68"), Color("9aa8d6"), 0.25, Color("2a3a55"), 0.35],
	[0.27, Color("7d97c0"), Color("f3b88e"), Color("ffc796"), 0.85, Color("d8b39a"), 0.65],
	[0.36, Color("78acd8"), Color("d6e8ec"), Color("fff0d8"), 1.20, Color("bfdbe0"), 0.85],
	[0.50, Color("6ea8d8"), Color("d2e7ee"), Color("fff5e4"), 1.30, Color("bcd9e0"), 0.90],
	[0.66, Color("79a8d2"), Color("dfe6e0"), Color("ffe8c8"), 1.15, Color("c8dade"), 0.85],
	[0.74, Color("6474a8"), Color("f3a173"), Color("ff9f6a"), 0.75, Color("d89c86"), 0.60],
	[0.80, Color("23324f"), Color("5a4a66"), Color("a59ad0"), 0.28, Color("2e3550"), 0.38],
	[1.00, Color("0d1b30"), Color("1e3350"), Color("8ea6da"), 0.28, Color("15263c"), 0.35],
]


const BASE_FOG := 0.0004
const BASE_SATURATION := 0.92


func _ready() -> void:
	name = "Sky"  # fixed node path for the Weather RPCs (/root/Main/Sky/Weather)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	add_child(sun)

	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12
	sky_mat.ground_bottom_color = Color("1c4a58")
	sky_mat.energy_multiplier = 1.0
	# Cloud layer: a soft noise panorama faded in by the weather's cloud cover.
	var cover := NoiseTexture2D.new()
	cover.width = 512
	cover.height = 256
	cover.seamless = true
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.012
	cn.fractal_octaves = 4
	cover.noise = cn
	cover.color_ramp = Gradient.new()
	cover.color_ramp.set_offset(0, 0.45)
	cover.color_ramp.set_color(0, Color(1, 1, 1, 0))
	cover.color_ramp.set_offset(1, 0.8)
	cover.color_ramp.set_color(1, Color(1, 1, 1, 1))
	sky_mat.sky_cover = cover
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# Cheaper glow: stop the blur chain at level 4 (default goes to 5).
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.0)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.20
	env.fog_depth_begin = 50.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Water: one big plane that rises and falls with the tide.
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	nt.noise = fn
	water_mat.set_shader_parameter("noise_tex", nt)
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	pm.subdivide_width = 300
	pm.subdivide_depth = 300
	water = MeshInstance3D.new()
	water.mesh = pm
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(VoxelWorld.WX * 0.5, 0, VoxelWorld.WZ * 0.5) * VoxelWorld.VS
	add_child(water)
	weather = Weather.new()
	weather.sky = self
	add_child(weather)
	_apply()


## Tide: two cycles per day. Returns water level in voxels.
func tide_level(t: float) -> float:
	return VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP * sin(t * TAU * 2.0 + 0.6)


## +1 rising, -1 falling.
func tide_trend() -> int:
	return 1 if cos(time_of_day * TAU * 2.0 + 0.6) > 0.0 else -1


func water_level_m() -> float:
	return water_level_vox * VoxelWorld.VS


# ---- weather queries (used by farming, boats, HUD, audio)

func is_raining() -> bool:
	return weather != null and weather.is_raining()


## Swell height at a world position (metres), matching the water shader.
func wave_offset_at(pos: Vector3) -> float:
	return weather.wave_height_at(pos) if weather != null else 0.0


func wind_drift() -> Vector2:
	return weather.wind_drift() if weather != null else Vector2.ZERO


func sea_roughness() -> float:
	return weather.params.wind if weather != null else 0.2


func weather_label() -> String:
	if weather == null:
		return ""
	return "%s, wind %d%%" % [weather.state_name(), int(weather.params.wind * 100.0)]


## True while the sun is meaningfully up (used by farming, fishing, salt pans).
func is_day() -> bool:
	return night_factor() < 0.5


func night_factor() -> float:
	var e := sin((time_of_day - 0.25) * TAU)  # sun elevation proxy
	return clampf(1.0 - (e + 0.15) / 0.3, 0.0, 1.0)


var _sky_t := -1.0
var _sky_cloud := -1.0


func _process(delta: float) -> void:
	var t := time_of_day + delta * time_scale / DAY_LENGTH
	if t >= 1.0:
		day += 1
	time_of_day = fposmod(t, 1.0)
	if weather != null:
		weather.update(delta * time_scale)
	_apply()
	# The sea follows the camera (snapped so the vertex waves don't swim).
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		water.position.x = snappedf(cam.global_position.x, 16.0)
		water.position.z = snappedf(cam.global_position.z, 16.0)


func _apply() -> void:
	var t := time_of_day
	var a: Array = _keys[0]
	var b: Array = _keys[1]
	for i in range(_keys.size() - 1):
		if t >= _keys[i][0] and t <= _keys[i + 1][0]:
			a = _keys[i]
			b = _keys[i + 1]
			break
	var f: float = (t - a[0]) / maxf(0.0001, b[0] - a[0])
	f = smoothstep(0.0, 1.0, f)
	var top: Color = (a[1] as Color).lerp(b[1], f)
	var hor: Color = (a[2] as Color).lerp(b[2], f)
	var w: Dictionary = weather.params if weather != null else {"cloud": 0.0, "fog": 0.0, "rain": 0.0, "wind": 0.2, "storm": 0.0, "wind_dir": Vector2(1, 0)}
	var cloud: float = w.cloud
	var storm: float = w.storm
	# Overcast: desaturate toward a soft sea-grey, storms darken further.
	var lum_t := top.get_luminance()
	var lum_h := hor.get_luminance()
	top = top.lerp(Color(lum_t * 0.9, lum_t * 0.95, lum_t * 1.02), cloud * 0.8) * (1.0 - storm * 0.4)
	hor = hor.lerp(Color(lum_h * 0.92, lum_h * 0.96, lum_h), cloud * 0.75) * (1.0 - storm * 0.3)
	top.a = 1.0
	hor.a = 1.0
	# Sky colour changes force a radiance re-bake, so only push them occasionally.
	if absf(t - _sky_t) > 0.002 or _sky_t < 0.0 or absf(cloud - _sky_cloud) > 0.02:
		_sky_t = t
		_sky_cloud = cloud
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = hor
		sky_mat.ground_horizon_color = hor.lerp(Color("2f6f78"), 0.4)
		var cov := Color(1, 1, 1).lerp(Color(0.45, 0.48, 0.52), storm) * lerpf(1.0, 0.25, night_factor())
		cov.a = clampf(cloud * 1.1 - 0.05, 0.0, 1.0)
		sky_mat.sky_cover_modulate = cov
	sun.light_color = (a[3] as Color).lerp(b[3], f)
	sun.light_energy = lerpf(a[4], b[4], f) * (1.0 - cloud * 0.6)
	sun.shadow_opacity = 1.0 - cloud * 0.55
	var fog_col: Color = (a[5] as Color).lerp(b[5], f)
	var fl := fog_col.get_luminance()
	env.fog_light_color = fog_col.lerp(Color(fl, fl * 1.02, fl * 1.05), cloud * 0.6)
	env.fog_density = BASE_FOG + (w.fog as float) * 0.020 + (w.rain as float) * 0.002
	env.fog_depth_begin = lerpf(55.0, 10.0, clampf((w.fog as float) * 1.5, 0.0, 1.0))
	var fog_on: bool = true
	var parent_node := get_parent()
	if parent_node != null and parent_node.get("settings") != null and "fog" in parent_node.settings:
		fog_on = bool(parent_node.settings.fog)
	env.fog_enabled = fog_on
	env.ambient_light_energy = lerpf(a[6], b[6], f) * (1.0 - cloud * 0.2)
	# Wet, rainy days look a little duller; lightning briefly floods the scene.
	var flash: float = weather.lightning if weather != null else 0.0
	env.adjustment_saturation = BASE_SATURATION - (w.rain as float) * 0.18
	env.adjustment_brightness = 1.0 - (w.rain as float) * 0.06 + flash * 0.9
	var vol: bool = weather != null and weather.quality >= 1.0 and (w.fog as float) > 0.25
	env.volumetric_fog_enabled = vol
	if vol:
		env.volumetric_fog_density = (w.fog as float) * 0.012

	# Sun arc (tilted so shadows are long and warm); moon takes over at night.
	var night := night_factor()
	var ang := (t - 0.25) * TAU
	var dir := Vector3(cos(ang), sin(ang), 0.35).normalized()
	if night > 0.5:
		dir = Vector3(-cos(ang), -sin(ang), -0.25).normalized()
	dir.y = maxf(dir.y, 0.18)
	sun.look_at_from_position(Vector3.ZERO, -dir.normalized(), Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)

	water_level_vox = tide_level(t)
	# Storm surge: a stormy high tide comes in a little higher.
	var tide_rel := (water_level_vox - VoxelWorld.SEA_MID) / VoxelWorld.TIDE_AMP
	water_level_vox += WeatherModel.surge_vox(storm, tide_rel)
	water.position.y = water_level_vox * VoxelWorld.VS
	var lm := lerpf(1.0, 0.35, night) * (1.0 - cloud * 0.25)
	water_mat.set_shader_parameter("light_mult", lm)
	water_mat.set_shader_parameter("wave_amp", WeatherModel.swell_amp(w.wind))
	water_mat.set_shader_parameter("wave_dir", w.wind_dir)
	water_mat.set_shader_parameter("wave_time", weather.wave_time if weather != null else 0.0)
	water_mat.set_shader_parameter("roughness", w.wind)
	water_mat.set_shader_parameter("storm", storm)

	# Lamps only exist in the lighting pass after dusk; by day they cost ~1.3 ms of GPU
	# for no visible effect.
	var lamp_e := night * 2.4
	var lamps_on := lamp_e > 0.03
	for l in get_tree().get_nodes_in_group("lamps"):
		(l as OmniLight3D).light_energy = lamp_e
		(l as OmniLight3D).visible = lamps_on
	# Glow mainly makes lanterns and sea-glow bloom; "night only" skips it by day.
	env.glow_enabled = glow_mode == 2 or (glow_mode == 1 and night > 0.15)
