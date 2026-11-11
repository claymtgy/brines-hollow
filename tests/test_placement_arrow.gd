extends SceneTree
## The placement arrow points out of the front of whatever you're about to place, for every rotation.

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Placement front arrow ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Which way the bottom step of the rotated Stairs blueprint lies from its centre.
func _stairs_front(rot: int) -> Vector3:
	var id := -1
	for i in Prefabs.all().size():
		if Prefabs.all()[i].name == "Stairs":
			id = i
	var pf := Prefabs.rotated(id, rot)
	var s: Vector3i = pf.size
	var data: PackedByteArray = pf.data
	var low := Vector2.ZERO
	var n := 0
	for z in s.z:
		for x in s.x:
			var h := 0
			for y in s.y:
				if data[x + s.x * (z + s.z * y)] != 0:
					h = y + 1
			if h == 1:   # the bottom step: one voxel tall
				low += Vector2(x + 0.5, z + 0.5)
				n += 1
	low /= n
	var d := low - Vector2(s.x, s.z) * 0.5
	return Vector3(d.x, 0, d.y).normalized()


func _run() -> void:
	for r in 4:
		var want := _stairs_front(r)
		check("Blueprint rot %d: arrow points to the stairs' bottom step" % r,
			PlacementArrow.prefab_front(r).dot(want) > 0.9)

	# Objects: front is local +Z (the chest latch), turned by rotation_steps.
	for r in 4:
		var e := WorldEntity.new(&"test", "Test", Vector3i.ZERO)
		e.rotation_steps = r
		e.rotation.y = r * PI * 0.5
		var front := (e.basis * Vector3.BACK).normalized()
		check("Object rot %d: arrow matches the object's turned front" % r,
			PlacementArrow.entity_front(r).dot(front) > 0.99)
		e.free()

	# The arrow itself: outside the front face, flat, pointing out.
	var a := PlacementArrow.new()
	root.add_child(a)
	await process_frame
	var box := AABB(Vector3(2, 1, 3), Vector3(1.0, 0.45, 2.0))
	for r in 4:
		var dir := PlacementArrow.entity_front(r)
		a.show_for(box, dir, Color.GREEN)
		var off := a.global_position - box.get_center()
		var face := absf(dir.x) * box.size.x * 0.5 + absf(dir.z) * box.size.z * 0.5
		check("Arrow %d points the right way" % r, a.pointing().dot(dir) > 0.99)
		check("Arrow %d sits past the front face" % r, off.dot(dir) > face)
		check("Arrow %d lies at the base" % r, absf(a.global_position.y - (box.position.y + PlacementArrow.LIFT)) < 0.001)
	check("Arrow shows in the ghost's colour", a.visible
		and (a.material_override as StandardMaterial3D).albedo_color.g > 0.9)

	# Object placement controller owns one and hides it with the ghost.
	var p := Player.new()
	root.add_child(p)
	var pc := PlacementController.new()
	root.add_child(pc)
	pc.setup(p)
	await process_frame
	check("Placement controller makes an arrow", pc.arrow != null and pc.arrow.is_inside_tree())
	pc.arrow.visible = true
	pc.update_ghost()
	check("Nothing to place: arrow hidden with the ghost", not pc.arrow.visible)
	check("Player has a blueprint arrow", p._ghost_arrow != null and not p._ghost_arrow.visible)
	a.queue_free()

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
