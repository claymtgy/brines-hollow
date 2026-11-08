class_name WildlifeFX
extends Node3D
## Cheap, local-only marks wildlife leaves behind: paw tracks (fade over a few minutes, so
## you can follow a fox back to its den), scattered feathers after a raid, and whale spouts.
## Every peer makes its own from the creatures it sees; nothing here is networked or saved.

const TRACK_LIFE := 240.0
const FEATHER_LIFE := 180.0
const MAX_MARKS := 400

static var current: WildlifeFX = null

var _marks: Array = []        # [node, age, life]
var _track_mat: StandardMaterial3D
var _feather_mat: StandardMaterial3D
var _spout_mat: StandardMaterial3D


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	_track_mat = _mat(Color(0.22, 0.17, 0.12, 0.8))
	_feather_mat = _mat(Color(0.97, 0.96, 0.92, 1.0))
	_spout_mat = _mat(Color(0.92, 0.97, 1.0, 0.75))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _add(node: MeshInstance3D, life: float) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_marks.append([node, 0.0, life])
	while _marks.size() > MAX_MARKS:
		var old: Array = _marks.pop_front()
		(old[0] as Node).queue_free()


## A pair of paw prints at `pos` (ground height), pointing along `yaw`.
func track(pos: Vector3, yaw: float, size: float = 0.07) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.3)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _track_mat
	mi.position = pos + Vector3(0, 0.012, 0)
	mi.rotation.y = yaw
	_add(mi, TRACK_LIFE)


## A little drift of white feathers where a bird was grabbed.
func feathers(pos: Vector3, count: int = 7) -> void:
	for i in count:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.05, 0.11)
		q.orientation = PlaneMesh.FACE_Y
		mi.mesh = q
		mi.material_override = _feather_mat
		var a := randf() * TAU
		var r := randf_range(0.1, 0.9)
		mi.position = pos + Vector3(cos(a) * r, 0.015, sin(a) * r)
		mi.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, 0)
		_add(mi, FEATHER_LIFE)


## A whale's blow: a short-lived column of spray.
func spout(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 0.15
	c.height = 3.0
	mi.mesh = c
	mi.material_override = _spout_mat
	mi.position = pos + Vector3(0, 1.5, 0)
	_add(mi, 2.2)


func _process(delta: float) -> void:
	var i := 0
	while i < _marks.size():
		var m: Array = _marks[i]
		m[1] += delta
		var node := m[0] as MeshInstance3D
		var left: float = float(m[2]) - float(m[1])
		if left <= 0.0:
			node.queue_free()
			_marks.remove_at(i)
			continue
		var fade := minf(20.0, float(m[2]) * 0.5)
		if left < fade:
			node.transparency = 1.0 - left / fade
		i += 1
