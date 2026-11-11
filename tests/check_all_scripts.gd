extends SceneTree
## Comprehensive script compiler sweep across all scripts in res://scripts/

var passed := 0
var failed := 0
var failed_files: Array[String] = []

func _initialize() -> void:
	print("==================================================")
	print("Scanning all scripts in res://scripts/ for errors...")
	print("==================================================")

	var files: Array[String] = []
	_scan_dir("res://scripts", files)
	files.sort()

	print("Found %d scripts to compile and verify." % files.size())

	for file_path in files:
		var script_res = load(file_path)
		if script_res == null:
			failed += 1
			failed_files.append(file_path)
			push_error("Failed to load/compile: " + file_path)
			print("  [FAIL] %s" % file_path)
		elif not (script_res is GDScript):
			failed += 1
			failed_files.append(file_path)
			push_error("Not a GDScript: " + file_path)
			print("  [FAIL] Not a GDScript: %s" % file_path)
		else:
			passed += 1

	print("==================================================")
	print("Compiler sweep results: %d / %d passed." % [passed, files.size()])
	if failed > 0:
		print("FAILED SCRIPTS (%d):" % failed)
		for f in failed_files:
			print("  - ", f)
		print("==================================================")
		quit(1)
	else:
		print("All scripts compiled with 0 errors!")
		print("==================================================")
		quit(0)


func _scan_dir(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := path + "/" + file_name
			if dir.current_is_dir():
				_scan_dir(full_path, out)
			elif file_name.ends_with(".gd"):
				out.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
