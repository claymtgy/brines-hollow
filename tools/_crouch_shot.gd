extends SceneTree
## Temp: standing vs crouched side by side.
var out := ""
var frames := 0
var a: CharacterModel
var b: CharacterModel
var c: CharacterModel

func _init() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	root.size = Vector2i(1200, 700)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color8(150, 185, 205)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color8(200, 180, 140)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	a = CharacterModel.new(); root.add_child(a); a.setup(); a.position = Vector3(-1.1, 0, 0)
	b = CharacterModel.new(); root.add_child(b); b.setup(); b.position = Vector3(0, 0, 0); b.crouching = true
	c = CharacterModel.new(); root.add_child(c); c.setup(); c.position = Vector3(1.1, 0, 0); c.crouching = true
	for m in [a, b, c]:
		m.rotation.y = PI * 0.5   # face +x: side view
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.9, 3.6)
	cam.fov = 45
	root.add_child(cam)
	process_frame.connect(_tick)

func _tick() -> void:
	frames += 1
	a.animate(1.0 / 60.0, 0.0, true, false)
	b.animate(1.0 / 60.0, 0.0, true, false)
	c.animate(1.0 / 60.0, 1.6, true, false)
	if frames == 90:
		root.get_texture().get_image().save_png(out)
		quit()
