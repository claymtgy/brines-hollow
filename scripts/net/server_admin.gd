class_name ServerAdmin
extends Node
## Dedicated Server Admin Dashboard & Slash Command Dispatcher.
## Provides live server telemetry, weather forecasting, and administrative operations.

signal command_executed(command: String, caller_id: int, success: bool, message: String)

var main: Node
var _start_time_msec: int = 0


func _init(p_main: Node = null) -> void:
	main = p_main
	_start_time_msec = Time.get_ticks_msec()


func _ready() -> void:
	name = "ServerAdmin"


## Returns live server performance, world status, and connected player telemetry.
func get_telemetry() -> Dictionary:
	var uptime := (Time.get_ticks_msec() - _start_time_msec) / 1000.0
	var sky: SkyCycle = _get_sky()

	var day_val: int = sky.day if sky != null else 0
	var time_val: float = sky.time_of_day if sky != null else 0.5
	var tide_val: float = sky.water_level_vox if sky != null else VoxelWorld.SEA_MID
	var is_eq: bool = sky.is_equinox_tide() if sky != null else false
	var is_fest: bool = sky.is_floating_lantern_festival() if sky != null else false

	var weather_label := "Calm"
	if sky != null and sky.weather != null:
		weather_label = sky.weather_label()

	var player_count := 1
	var session: Session = _get_session()
	if session != null and session.get("_peer_keys") != null:
		player_count = maxi(1, session._peer_keys.size())

	return {
		"uptime_sec": uptime,
		"player_count": player_count,
		"tps": Performance.get_monitor(Performance.TIME_FPS),
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"day": day_val,
		"time_of_day": time_val,
		"tide_vox": tide_val,
		"is_equinox": is_eq,
		"is_lantern_festival": is_fest,
		"weather": weather_label,
		"deluge_calmed": WeatherModel.deluge_calmed
	}


## Computes a deterministic weather forecast for upcoming weather fronts.
func get_weather_forecast(front_count: int = 5) -> Array[Dictionary]:
	var forecast: Array[Dictionary] = []
	var sky: SkyCycle = _get_sky()
	var current_day := float(sky.day if sky != null else 0) + (sky.time_of_day if sky != null else 0.0)

	var cur_f := maxf(current_day, 0.0) / WeatherModel.FRONT_DAYS
	var cur_i := int(floor(cur_f))
	var world_seed := 1337
	var session: Session = _get_session()
	if session != null and session.get("main") != null and "world_seed" in session.main:
		world_seed = session.main.world_seed

	for idx in front_count:
		var front_idx := cur_i + idx
		var state := WeatherModel.front_state(world_seed, front_idx)
		var state_str: String = WeatherModel.STATE_NAMES[state] if state >= 0 and state < WeatherModel.STATE_NAMES.size() else "Clear"
		var front_time := front_idx * WeatherModel.FRONT_DAYS
		forecast.append({
			"front_index": front_idx,
			"front_day": front_time,
			"state": state,
			"state_name": state_str,
			"is_storm": (state == WeatherModel.State.STORM and not WeatherModel.deluge_calmed)
		})
	return forecast


## Parses and executes an administrative command string.
func execute_command(command_str: String, caller_id: int = 1) -> Dictionary:
	var trimmed := command_str.strip_edges()
	if not trimmed.begins_with("/"):
		trimmed = "/" + trimmed

	var parts := trimmed.split(" ", false)
	if parts.is_empty():
		return _result(false, "Empty command", "")

	var cmd := parts[0].to_lower()
	var args := parts.slice(1)

	match cmd:
		"/help":
			var msg := "Commands: /help, /status, /time <noon|dusk|night|0-1>, /weather <clear|storm|fog>, /festival, /deluge, /save, /give <item_id> [count]"
			return _result(true, msg, cmd)

		"/status":
			var t := get_telemetry()
			var msg := "Status: Uptime %.1fs | %d Players | Day %d (%.2f) | Tide: %.2fvox | Weather: %s | Deluge Calmed: %s" % [
				t["uptime_sec"], t["player_count"], t["day"], t["time_of_day"], t["tide_vox"], t["weather"], str(t["deluge_calmed"])
			]
			return _result(true, msg, cmd)

		"/time":
			if args.is_empty():
				return _result(false, "Usage: /time <morning|noon|dusk|night|0.0-1.0>", cmd)
			var sky := _get_sky()
			if sky == null:
				return _result(false, "SkyCycle not found", cmd)

			var sub := args[0].to_lower()
			match sub:
				"morning", "dawn":
					sky.time_of_day = 0.25
				"noon", "midday":
					sky.time_of_day = 0.50
				"dusk", "sunset":
					sky.time_of_day = 0.75
				"night", "midnight":
					sky.time_of_day = 0.00
				_:
					if sub.is_valid_float():
						sky.time_of_day = clampf(sub.to_float(), 0.0, 1.0)
					else:
						return _result(false, "Invalid time value: %s" % sub, cmd)
			return _result(true, "Time set to %.2f (Day %d)" % [sky.time_of_day, sky.day], cmd)

		"/festival":
			var sky := _get_sky()
			if sky != null:
				sky.festival_active = not sky.festival_active
				var state_str := "ACTIVE (Spring Tide Equinox × 1.6 amplitude)" if sky.festival_active else "DEACTIVATED"
				return _result(true, "Tidal Festival %s" % state_str, cmd)
			return _result(false, "SkyCycle not found", cmd)

		"/deluge":
			WeatherModel.deluge_calmed = not WeatherModel.deluge_calmed
			var state_str := "CALMED (Grand Equilibrium)" if WeatherModel.deluge_calmed else "ACTIVE (Catastrophic storms restored)"
			return _result(true, "World Deluge state: %s" % state_str, cmd)

		"/weather":
			if args.is_empty():
				return _result(false, "Usage: /weather <clear|storm|fog|rain>", cmd)
			var w_sub := args[0].to_lower()
			var sky := _get_sky()
			if sky != null and sky.weather != null:
				match w_sub:
					"clear":
						sky.weather.params = {"cloud": 0.0, "fog": 0.0, "rain": 0.0, "wind": 0.1, "storm": 0.0}
					"storm":
						sky.weather.params = {"cloud": 1.0, "fog": 0.1, "rain": 1.0, "wind": 1.0, "storm": 1.0}
					"fog":
						sky.weather.params = {"cloud": 0.5, "fog": 0.9, "rain": 0.0, "wind": 0.05, "storm": 0.0}
					"rain":
						sky.weather.params = {"cloud": 0.8, "fog": 0.1, "rain": 0.8, "wind": 0.5, "storm": 0.0}
					_:
						return _result(false, "Unknown weather: %s" % w_sub, cmd)
				return _result(true, "Weather set to %s" % w_sub, cmd)
			return _result(false, "Weather controller not found", cmd)

		"/save":
			var session := _get_session()
			if session != null and session.has_method("save"):
				session.save()
				return _result(true, "World save completed successfully", cmd)
			return _result(true, "Save triggered (simulated)", cmd)

		"/give":
			if args.is_empty():
				return _result(false, "Usage: /give <item_id> [count]", cmd)
			var item_id := StringName(args[0])
			var count := int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 1
			if not ItemDB.has_item(item_id):
				return _result(false, "Unknown item id: %s" % item_id, cmd)

			var p: Player = _get_player()
			if p != null and p.inventory != null:
				p.inventory.add_item(item_id, count)
				return _result(true, "Granted %d %s to player" % [count, item_id], cmd)
			return _result(false, "Player inventory not found", cmd)

		_:
			return _result(false, "Unknown command: %s. Type /help for assistance." % cmd, cmd)


func _result(success: bool, message: String, cmd: String) -> Dictionary:
	command_executed.emit(cmd, 1, success, message)
	return {
		"success": success,
		"message": message,
		"command": cmd
	}


func _get_sky() -> SkyCycle:
	if main != null:
		if main.get("sky") is SkyCycle:
			return main.get("sky")
		if main.has_meta("sky") and main.get_meta("sky") is SkyCycle:
			return main.get_meta("sky")
	var em := EntityManager.current
	if em != null and em.main != null:
		if em.main.get("sky") is SkyCycle:
			return em.main.get("sky")
		if em.main.has_meta("sky") and em.main.get_meta("sky") is SkyCycle:
			return em.main.get_meta("sky")
	return null


func _get_session() -> Session:
	if main != null:
		if main.get("session") is Session:
			return main.get("session")
		if main.has_meta("session") and main.get_meta("session") is Session:
			return main.get_meta("session")
	var em := EntityManager.current
	if em != null and em.main != null:
		if em.main.get("session") is Session:
			return em.main.get("session")
		if em.main.has_meta("session") and em.main.get_meta("session") is Session:
			return em.main.get_meta("session")
	return null


func _get_player() -> Player:
	if main != null:
		if main.get("player") is Player:
			return main.get("player")
		if main.has_meta("player") and main.get_meta("player") is Player:
			return main.get_meta("player")
	var em := EntityManager.current
	if em != null and em.main != null:
		if em.main.get("player") is Player:
			return em.main.get("player")
		if em.main.has_meta("player") and em.main.get_meta("player") is Player:
			return em.main.get_meta("player")
	return null
