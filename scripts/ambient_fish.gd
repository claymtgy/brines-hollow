class_name AmbientFishManager
extends Node3D
## Ambient schooling fish that swim under the water surface near the player and boats.
## Purely cosmetic billboard sprites that add life and movement to the shallows.

const FISH_COUNT := 24
const SCHOOL_RADIUS := 24.0

class SwimmingFish:
	var sprite: Sprite3D
	var pos: Vector3
	var vel: Vector3
	var swim_speed: float
	var phase: float
	var dart_t: float = 0.0
	var school_id: int = 0
	var species_id: int = 0
	var ripple_cooldown: float = 0.0

var world: VoxelWorld
var sky: SkyCycle
var player: Player
var _fish: Array[SwimmingFish] = []
var _fish_textures: Array[Texture2D] = []
var _ripple_tex: Texture2D = null
var _ripples: Array[Sprite3D] = []

const MAX_RIPPLES := 12


func setup(p_world: VoxelWorld, p_sky: SkyCycle, p_player: Player) -> void:
	world = p_world
	sky = p_sky
	player = p_player
	_create_fish_textures()
	_create_ripple_texture()
	_create_ripple_pool()
	_spawn_school()


func _create_fish_textures() -> void:
	_fish_textures.clear()
	# 1. Silvery Mackerel / Herring (steel blue & silvery belly)
	_fish_textures.append(_bake_fish_texture(
		Color8(130, 180, 205, 235), Color8(210, 230, 240, 245), Color8(70, 120, 150, 255),
		Color8(20, 30, 45, 255), Color8(100, 160, 190, 180), Color8(255, 255, 255, 0)
	))
	# 2. Coral Clownfish (vibrant orange body with white coral stripes)
	_fish_textures.append(_bake_fish_texture(
		Color8(235, 120, 40, 245), Color8(245, 180, 110, 245), Color8(180, 70, 20, 255),
		Color8(20, 20, 20, 255), Color8(220, 95, 30, 200), Color8(240, 245, 250, 250)
	))
	# 3. Bioluminescent Teal Minnow (glowing cyan / sea-green)
	_fish_textures.append(_bake_fish_texture(
		Color8(40, 210, 180, 245), Color8(140, 250, 230, 250), Color8(20, 130, 120, 255),
		Color8(250, 255, 255, 255), Color8(60, 230, 200, 220), Color8(80, 255, 220, 220)
	))


func _bake_fish_texture(c_body: Color, c_belly: Color, c_back: Color, c_eye: Color, c_fin: Color, c_stripe: Color) -> Texture2D:
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Tail
	img.set_pixel(1, 1, c_fin)
	img.set_pixel(0, 2, c_fin)
	img.set_pixel(1, 3, c_fin)
	img.set_pixel(2, 3, c_body)
	img.set_pixel(1, 4, c_fin)
	img.set_pixel(0, 5, c_fin)
	img.set_pixel(1, 6, c_fin)

	# Body
	for x in range(3, 14):
		var h: int = 2 if (x == 3 or x == 13) else (3 if (x == 4 or x == 12) else 4)
		for dy in range(-h + 1, h):
			var py: int = 4 + dy
			if py >= 0 and py < 8:
				var c := c_belly if dy > 0 else (c_back if dy < 0 else c_body)
				if c_stripe.a > 0 and (x == 7 or x == 10) and absi(dy) < 3:
					c = c_stripe
				img.set_pixel(x, py, c)

	# Snout & Eye
	img.set_pixel(14, 4, c_belly)
	img.set_pixel(12, 3, c_eye)
	# Dorsal & ventral fin
	img.set_pixel(7, 0, c_fin)
	img.set_pixel(8, 1, c_fin)
	img.set_pixel(7, 7, c_fin)

	return ImageTexture.create_from_image(img)


func _create_ripple_texture() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(16.0, 16.0)
	for y in 32:
		for x in 32:
			var d := center.distance_to(Vector2(x, y))
			if d >= 10.0 and d <= 14.5:
				var ring_alpha := 1.0 - absf(d - 12.2) / 2.3
				img.set_pixel(x, y, Color(0.85, 0.95, 1.0, clampf(ring_alpha * 0.65, 0.0, 0.85)))
	_ripple_tex = ImageTexture.create_from_image(img)


func _create_ripple_pool() -> void:
	for i in MAX_RIPPLES:
		var sp := Sprite3D.new()
		sp.texture = _ripple_tex
		sp.axis = Vector3.AXIS_Y
		sp.pixel_size = 0.03
		sp.modulate = Color(1.0, 1.0, 1.0, 0.0)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		add_child(sp)
		_ripples.append(sp)


func _spawn_ripple(pos: Vector3) -> void:
	for sp in _ripples:
		if not sp.visible or sp.modulate.a <= 0.02:
			sp.position = pos
			sp.scale = Vector3.ONE * 0.4
			sp.modulate.a = 0.65
			sp.visible = true
			var tw := create_tween()
			tw.tween_property(sp, "scale", Vector3.ONE * 2.2, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(sp, "modulate:a", 0.0, 1.2)
			tw.tween_callback(func() -> void: if is_instance_valid(sp): sp.visible = false)
			break


func _spawn_school() -> void:
	for i in FISH_COUNT:
		var sf := SwimmingFish.new()
		var sp := Sprite3D.new()
		sf.species_id = i % _fish_textures.size()
		sp.texture = _fish_textures[sf.species_id]
		sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sp.pixel_size = 0.022 if sf.species_id == 2 else 0.026
		sp.modulate = Color(0.9, 0.95, 1.0, 0.92)
		sp.no_depth_test = false
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)

		sf.sprite = sp
		sf.swim_speed = randf_range(1.5, 2.6)
		sf.phase = randf() * TAU
		sf.school_id = i % 4
		var spawn_ref: Vector3 = player.position if player != null else Vector3(128.0, 0.0, 128.0)
		sf.pos = _find_water_spot(spawn_ref)
		sf.vel = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * sf.swim_speed
		sf.sprite.position = sf.pos
		_fish.append(sf)


func _find_water_spot(origin: Vector3) -> Vector3:
	var water_y := sky.water_level_m() if sky != null else 18.0
	for _attempt in 8:
		var ang := randf() * TAU
		var dist := randf_range(3.5, SCHOOL_RADIUS)
		var p := origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		p.y = water_y - randf_range(0.35, 2.6)
		return p
	return origin + Vector3(0, -1.0, 0)


func _process(delta: float) -> void:
	if player == null or sky == null:
		return

	var p_pos := player.position
	var water_y := sky.water_level_m()
	var in_boat: bool = player.is_seated() and player.boat != null
	var boat_pos: Vector3 = player.boat.position if in_boat else Vector3.ZERO
	var boat_speed: float = player.boat.vel.length() if (in_boat and "vel" in player.boat) else 0.0

	for f in _fish:
		f.phase += delta * (4.8 if f.dart_t > 0.0 else 2.2)
		if f.dart_t > 0.0:
			f.dart_t -= delta
		if f.ripple_cooldown > 0.0:
			f.ripple_cooldown -= delta

		# Distance check
		var d_to_p := f.pos.distance_to(p_pos)
		if d_to_p > SCHOOL_RADIUS + 14.0:
			f.pos = _find_water_spot(p_pos)
			f.vel = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * f.swim_speed
			f.sprite.position = f.pos
			continue

		# React & dart away from swimmer or fast boats
		var threat_pos := boat_pos if in_boat else p_pos
		var d_to_threat := f.pos.distance_to(threat_pos)
		var threat_dist := 5.2 if (in_boat and boat_speed > 2.0) else 2.9
		if d_to_threat < threat_dist and f.dart_t <= 0.0:
			f.dart_t = 2.0
			var away := (f.pos - threat_pos)
			away.y = 0.0
			f.vel = (away.normalized() + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))).normalized() * (f.swim_speed * 2.9)
			if f.ripple_cooldown <= 0.0:
				f.ripple_cooldown = 1.4
				_spawn_ripple(Vector3(f.pos.x, water_y + 0.02, f.pos.z))

		# Steer forward with gentle wandering schooling
		var steer := Vector3(sin(f.phase * 0.7 + f.school_id), 0.0, cos(f.phase * 0.8 + f.school_id)) * 0.4
		f.vel = (f.vel + steer * delta).normalized() * (f.swim_speed * (2.2 if f.dart_t > 0.0 else 1.0))

		# Bound depth in water
		var target_y := clampf(f.pos.y + sin(f.phase * 1.3) * 0.02, water_y - 3.2, water_y - 0.22)
		f.pos += Vector3(f.vel.x, 0, f.vel.z) * delta
		f.pos.y = lerpf(f.pos.y, target_y, delta * 2.2)

		# Surface ripple when near water surface
		if (water_y - f.pos.y) < 0.4 and f.ripple_cooldown <= 0.0 and randf() < 0.04:
			f.ripple_cooldown = randf_range(3.0, 6.0)
			_spawn_ripple(Vector3(f.pos.x, water_y + 0.02, f.pos.z))

		# Sprite orientation & tail swish
		f.sprite.position = f.pos
		f.sprite.flip_h = (f.vel.x < 0.0)
		f.sprite.rotation.y = sin(f.phase * 2.6) * 0.18
