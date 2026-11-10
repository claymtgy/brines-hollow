class_name AmbientFishManager
extends Node3D
## Ambient schooling fish that swim under the water surface near the player.
## Purely cosmetic billboard sprites that add life and movement to the shallows.

const FISH_COUNT := 18
const SCHOOL_RADIUS := 22.0

class SwimmingFish:
	var sprite: Sprite3D
	var pos: Vector3
	var vel: Vector3
	var swim_speed: float
	var phase: float
	var dart_t: float = 0.0
	var school_id: int = 0

var world: VoxelWorld
var sky: SkyCycle
var player: Player
var _fish: Array[SwimmingFish] = []
var _fish_tex: Texture2D = null


func setup(p_world: VoxelWorld, p_sky: SkyCycle, p_player: Player) -> void:
	world = p_world
	sky = p_sky
	player = p_player
	_create_fish_texture()
	_spawn_school()


func _create_fish_texture() -> void:
	# Clean silvery-blue sea fish sprite with fins
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c_body := Color8(130, 180, 205, 235)
	var c_belly := Color8(210, 230, 240, 245)
	var c_back := Color8(70, 120, 150, 255)
	var c_eye := Color8(20, 30, 45, 255)
	var c_fin := Color8(100, 160, 190, 180)

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
				img.set_pixel(x, py, c)

	# Snout & Eye
	img.set_pixel(14, 4, c_belly)
	img.set_pixel(12, 3, c_eye)
	# Dorsal & ventral fin
	img.set_pixel(7, 0, c_fin)
	img.set_pixel(8, 1, c_fin)
	img.set_pixel(7, 7, c_fin)

	_fish_tex = ImageTexture.create_from_image(img)


func _spawn_school() -> void:
	for i in FISH_COUNT:
		var sf := SwimmingFish.new()
		var sp := Sprite3D.new()
		sp.texture = _fish_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sp.pixel_size = 0.024
		sp.modulate = Color(0.85, 0.95, 1.0, 0.88)
		sp.no_depth_test = false
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)

		sf.sprite = sp
		sf.swim_speed = randf_range(1.4, 2.4)
		sf.phase = randf() * TAU
		sf.school_id = i % 3
		var spawn_ref: Vector3 = player.position if player != null else Vector3(128.0, 0.0, 128.0)
		sf.pos = _find_water_spot(spawn_ref)
		sf.vel = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * sf.swim_speed
		sf.sprite.position = sf.pos
		_fish.append(sf)


func _find_water_spot(origin: Vector3) -> Vector3:
	var water_y := sky.water_level_m() if sky != null else 18.0
	for _attempt in 8:
		var ang := randf() * TAU
		var dist := randf_range(4.0, SCHOOL_RADIUS)
		var p := origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		p.y = water_y - randf_range(0.4, 2.2)
		return p
	return origin + Vector3(0, -1.0, 0)


func _process(delta: float) -> void:
	if player == null or sky == null:
		return

	var p_pos := player.position
	var water_y := sky.water_level_m()

	for f in _fish:
		f.phase += delta * (4.5 if f.dart_t > 0.0 else 2.2)
		if f.dart_t > 0.0:
			f.dart_t -= delta

		# Check distance to player
		var d_to_p := f.pos.distance_to(p_pos)
		if d_to_p > SCHOOL_RADIUS + 12.0:
			f.pos = _find_water_spot(p_pos)
			f.vel = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * f.swim_speed
			f.sprite.position = f.pos
			continue

		# Dart away if player splashes close
		if d_to_p < 2.8 and f.dart_t <= 0.0:
			f.dart_t = 1.8
			var away := (f.pos - p_pos)
			away.y = 0.0
			f.vel = (away.normalized() + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))).normalized() * (f.swim_speed * 2.8)

		# Steer forward with gentle wandering
		var steer := Vector3(sin(f.phase * 0.7), 0.0, cos(f.phase * 0.8)) * 0.35
		f.vel = (f.vel + steer * delta).normalized() * (f.swim_speed * (2.2 if f.dart_t > 0.0 else 1.0))

		# Bound depth in water
		var target_y := clampf(f.pos.y + sin(f.phase * 1.2) * 0.02, water_y - 3.5, water_y - 0.25)
		f.pos += Vector3(f.vel.x, 0, f.vel.z) * delta
		f.pos.y = lerpf(f.pos.y, target_y, delta * 2.0)

		# Sprite orientation & tail swish
		f.sprite.position = f.pos
		f.sprite.flip_h = (f.vel.x < 0.0)
		f.sprite.rotation.y = sin(f.phase * 2.5) * 0.18
