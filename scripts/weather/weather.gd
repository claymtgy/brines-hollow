class_name Weather
extends Node
## Scene side of the weather: evaluates WeatherModel every frame and drives rain,
## lightning, the sea swell, gameplay hooks and ambient audio. Child of SkyCycle ("Sky"),
## so its RPC path is /root/Main/Sky/Weather on every peer.
##
## Authority: the host / dedicated server owns the absolute clock (SkyCycle.day + time).
## Everyone derives identical weather from (seed, absolute time); the host re-sends the
## clock every few seconds and to each joiner, which is all the network traffic it needs.

const SYNC_SEC := 5.0

var sky: SkyCycle
var params := {"state": 0, "cloud": 0.0, "fog": 0.0, "rain": 0.0, "wind": 0.2, "storm": 0.0,
	"wind_dir": Vector2(1, 0), "front": 0}
var wave_time := 0.0          # shared swell clock (shader uniform + wave_height_at)
var sheltered := false        # local player/camera is under a roof or overhang
var lightning := 0.0          # current flash brightness (decays)
var quality := 0.7            # rain density / extras, from the graphics preset
var forced_state := -1        # dev: --weather=storm etc.
var audio: AmbientAudio

var _rain: GPUParticles3D
var _rain_mat: StandardMaterial3D
var _sync_t := 0.0
var _shelter_t := 0.0
var _bolt_t := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Weather"
	_rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			forced_state = WeatherModel.STATE_NAMES.map(func(n: String) -> String: return n.to_lower().split(" ")[0]).find(a.trim_prefix("--weather=").to_lower())
	if DisplayServer.get_name() != "headless":
		_build_rain()
		audio = AmbientAudio.new()
		add_child(audio)
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			weather_sync.rpc_id(id, sky.day, sky.time_of_day))


## Main, if the sky lives under it (tests and tools may host a bare SkyCycle).
func _main() -> Node:
	var m: Node = sky.get_parent() if sky != null else null
	return m if m != null and "world" in m and "player" in m else null


func seed_value() -> int:
	var m := _main()
	return int(m.seed_value) if m != null and "seed_value" in m else 0


func abs_days() -> float:
	return float(sky.day) + sky.time_of_day


## Called by SkyCycle each frame, before it applies sky/light/sea.
var prof_usec := 0
var prof_frames := 0


func update(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_update_inner(delta)
	prof_usec += Time.get_ticks_usec() - _t0
	prof_frames += 1


func _update_inner(delta: float) -> void:
	# Derived from the synced world clock so every peer sees the same swell; wraps every
	# WAVE_LOOP seconds (wave frequencies are chosen to repeat exactly) to keep float precision.
	wave_time = fposmod(abs_days() * SkyCycle.DAY_LENGTH, WeatherModel.WAVE_LOOP)
	params = WeatherModel.sample(seed_value(), abs_days())
	if forced_state >= 0:
		var t: Dictionary = WeatherModel.TARGETS[forced_state]
		for k: String in WeatherModel.KEYS:
			params[k] = t[k]
		params["state"] = forced_state
	_update_quality()
	_update_shelter(delta)
	_update_rain()
	_update_lightning(delta)
	_gameplay(delta)
	if audio != null:
		audio.update(delta, self)
	# Clock sync from the authority.
	var mp := multiplayer
	if mp.multiplayer_peer != null and mp.is_server() and mp.get_peers().size() > 0:
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = SYNC_SEC
			weather_sync.rpc(sky.day, sky.time_of_day)


@rpc("authority", "call_remote", "unreliable")
func weather_sync(day: int, tod: float) -> void:
	sky.day = day
	if absf(sky.time_of_day - tod) > 0.002:
		sky.time_of_day = tod


# ---------------------------------------------------------------- queries

func is_raining() -> bool:
	return params.rain > 0.3


func state_name() -> String:
	return WeatherModel.STATE_NAMES[int(params.state)]


func wave_height_at(pos: Vector3) -> float:
	return WeatherModel.wave_height(Vector2(pos.x, pos.z), wave_time, params.wind, params.wind_dir)


## Push on a floating hull (m/s^2): wind drift, much stronger in storms.
func wind_drift() -> Vector2:
	var w: float = params.wind
	return (params.wind_dir as Vector2) * (w * w * 0.12 + params.storm * 0.25)


# ---------------------------------------------------------------- effects

func _update_quality() -> void:
	var m := _main()
	quality = 0.7
	if m != null and "settings" in m and m.settings != null:
		match int(m.settings.preset):
			GameSettings.Preset.DECK, GameSettings.Preset.LOW: quality = 0.35
			GameSettings.Preset.HIGH: quality = 1.0


func _update_shelter(delta: float) -> void:
	_shelter_t -= delta
	if _shelter_t > 0.0:
		return
	_shelter_t = 0.25
	var m := _main()
	if m == null or m.world == null or not m.world.ready_for_play:
		sheltered = false
		return
	var p: Vector3
	if m.player != null:
		p = m.player.position + Vector3(0, 1.0, 0)
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		p = cam.global_position
	var cell := Vector3i(floori(p.x / VoxelWorld.VS), floori(p.y / VoxelWorld.VS), floori(p.z / VoxelWorld.VS))
	sheltered = WeatherModel.is_sheltered(m.world.get_voxel, cell)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 2400
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.5, 16)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -6, 0)
	_rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.85, 0.92, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	quad.material = mat
	_rain_mat = mat
	_rain.draw_pass_1 = quad
	_rain.emitting = false
	add_child(_rain)


func _update_rain() -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d()
	var r: float = params.rain
	var on := r > 0.05 and cam != null
	if on:
		var w: Vector2 = params.wind_dir
		var wind: float = params.wind
		# Lead the emitter upwind so slanted drops land around the camera.
		_rain.global_position = cam.global_position + Vector3(-w.x * wind * 4.0, 11.0, -w.y * wind * 4.0)
		(_rain.process_material as ParticleProcessMaterial).direction = Vector3(w.x * wind * 0.45, -1, w.y * wind * 0.45)
		# Unshaded drops: dim them with the ambient light so night rain isn't glowing white.
		var lit := lerpf(1.0, 0.3, sky.night_factor()) + lightning * 0.8
		_rain_mat.albedo_color = Color(0.78 * lit, 0.85 * lit, 0.92 * lit, 0.32 * clampf(lit, 0.5, 1.0))
		# Indoors: no drops in front of the lens (the roof still gets wet outside).
		_rain.amount_ratio = clampf(r * quality * (0.15 if sheltered else 1.0), 0.0, 1.0)
	if _rain.emitting != on:
		_rain.emitting = on


func _update_lightning(delta: float) -> void:
	lightning = maxf(0.0, lightning - delta * 5.0)
	if params.storm < 0.6 or sky.night_factor() < 0.3:
		return
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		_bolt_t = _rng.randf_range(4.0, 14.0)
		lightning = _rng.randf_range(0.6, 1.0)
		if audio != null:
			audio.thunder(_rng.randf_range(0.4, 2.8))


## Storm hardship (opt-in danger): rough seas and gale-force headwinds tire you outdoors.
func _gameplay(delta: float) -> void:
	var m := _main()
	if m == null or m.player == null or params.storm < 0.5 or sheltered:
		return
	var p = m.player
	if not ("vitality" in p) or p.vitality == null or not p.input_enabled:
		return
	if p.swimming:
		p.vitality.drain_stamina_continuous(3.0 * params.storm, delta)
	elif Input.is_action_pressed("sprint") and p.horizontal_speed > 5.5:
		p.vitality.drain_stamina_continuous(3.0 * params.storm, delta)


# ---------------------------------------------------------------- persistence

func serialize() -> Dictionary:
	return {"day": sky.day}


func deserialize(d: Dictionary) -> void:
	sky.day = int(d.get("day", sky.day))


# ---------------------------------------------------------------- dev screenshots
#   --weathershot=DIR   one image per weather state (day), plus a storm at night

func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weathershot="):
			_weather_shots.call_deferred(a.trim_prefix("--weathershot="))
		elif a.begins_with("--day="):
			sky.day = int(a.trim_prefix("--day="))       # dev: jump the weather clock
		elif a.begins_with("--weathercheck"):
			_weather_check.call_deferred()


## Dev: print the weather a few seconds in, so host / client / server logs can be compared.
func _weather_check() -> void:
	await get_tree().create_timer(9.0).timeout
	print("[weathercheck] %s day=%d tod=%.3f front=%d state=%s rain=%.2f wind_dir=%s" % [
		"server" if multiplayer.multiplayer_peer != null and multiplayer.is_server() else "client",
		sky.day, sky.time_of_day, int(params.front), state_name(), params.rain, str(params.wind_dir)])
	get_tree().quit()


func _weather_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var m := _main()
	while m == null or m.player == null or not m.world.ready_for_play:
		await get_tree().process_frame
		m = _main()
	m.player.input_enabled = false
	m.hud.help.visible = false
	# Turn toward the most open water so the sea is in frame.
	var best_yaw := 0.0
	var best := -1.0
	for k in 24:
		var yaw := k * TAU / 24.0
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var water := 0
		for d: float in [8.0, 16.0, 30.0]:
			var q: Vector3 = m.player.position + fwd * d
			if m.world.get_voxel(floori(q.x / VoxelWorld.VS), floori(sky.water_level_vox), floori(q.z / VoxelWorld.VS)) == 0:
				water += 1
		if water > best:
			best = water
			best_yaw = yaw
	m.rig.yaw = best_yaw
	m.rig.pitch = -0.18
	var shots := [["clear", 0, 0.45], ["overcast", 1, 0.45], ["fog", 2, 0.33], ["rain", 3, 0.45],
		["storm", 4, 0.45], ["storm_night", 4, 0.88]]
	for s: Array in shots:
		forced_state = s[1]
		sky.time_of_day = s[2]
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("weather_%s.png" % s[0]))
		print("[weathershot] ", s[0], "  sheltered=", sheltered, " wave=%.2f" % wave_height_at(m.player.position),
			"  weather+audio update avg %.3f ms" % (prof_usec / 1000.0 / maxf(prof_frames, 1)),
			"  audio bake %d ms, players %d" % [audio.bake_ms if audio else -1, audio._players.size() if audio else -1])
		prof_usec = 0
		prof_frames = 0
	get_tree().quit()
