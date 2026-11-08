class_name VillageBellEntity
extends WorldEntity
## Harbour Bell: a bronze bell on a timber frame, the village's alarm.
##   Raids   When a fox, stoat, shore rat or sea eagle comes for anything within RAID_RANGE,
##           the bell tolls by itself. Everyone hears it (3D sound, louder near it) and a
##           beacon marks where the trouble is for BEACON_TIME seconds.
##   By hand Press F to ring it: it calls every player over (beacon on the bell) and the din
##           sends any raider within SCARE_RANGE running.
## Rings are host-authoritative and reach clients as a one-off RPC (CreatureNet.cr_bell),
## never through saved state, so loading a world or joining doesn't replay old alarms.

const U := VoxelWorld.VS * 0.5
const RAID_RANGE := 90.0
const SCARE_RANGE := 25.0
const BEACON_TIME := 25.0
const RING_TIME := 4.0
const COOLDOWN := 6.0

static var _toll: AudioStreamWAV

var ring_seq := 0               # rings so far this session
var alarm_at := Vector3.INF     # where the beacon points
var alarm_text := ""
var _ring_t := 0.0
var _beacon_t := 0.0
var _cool_t := 0.0
var _phase := 0.0
var _bell: Node3D
var _beacon: Node3D
var _beacon_label: Label3D
var _audio: AudioStreamPlayer3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"village_bell", "Harbour Bell", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"village_bell"
	size = Vector3(10, 26, 6) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(12, 26, 6)
	g.box(0, 0, 0, 11, 0, 5, Palette.COBBLE)            # plinth
	g.box(1, 1, 2, 2, 23, 3, Palette.DARK_WOOD)          # uprights
	g.box(9, 1, 2, 10, 23, 3, Palette.DARK_WOOD)
	g.box(0, 24, 1, 11, 25, 4, Palette.DARK_WOOD)        # headstock beam
	g.box(1, 4, 2, 10, 4, 3, Palette.PLANK)              # brace
	_mesh_instance = _voxel_model(g)
	_bell = Node3D.new()
	_bell.position = Vector3(0, 23.0 * U, 0)
	add_child(_bell)
	var bg := Prefabs.Grid.new(7, 9, 7)
	for y in 9:
		var r := 1.4 + float(8 - y) * 0.26 if y < 8 else 1.2
		for z in 7:
			for x in 7:
				var d := Vector2(x - 3, z - 3).length()
				if d <= r and (y >= 7 or d > r - 1.3):
					bg.setv(x, y, z, Palette.FLOWER_Y if y > 0 else Palette.SANDSTONE_B)   # bronze, darker lip
	bg.box(3, 1, 3, 3, 4, 3, Palette.METAL)              # clapper
	var bm := _voxel_model(bg)
	bm.reparent(_bell, false)
	bm.position = Vector3(-3.5, -9.0, -3.5) * U
	var rope := Prefabs.Grid.new(1, 14, 1)
	rope.box(0, 0, 0, 0, 13, 0, Palette.GRASS_DRY)
	var rm := _voxel_model(rope)
	rm.position = Vector3(3.0, 1.0, 0.5) * U
	# The beacon: a tall shaft of light over the trouble, top-level so it can be anywhere.
	_beacon = Node3D.new()
	_beacon.top_level = true
	_beacon.visible = false
	add_child(_beacon)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.25
	cyl.height = 30.0
	shaft.mesh = cyl
	shaft.position.y = 15.0
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1.0, 0.75, 0.3, 0.35)
	sm.no_depth_test = true
	shaft.material_override = sm
	_beacon.add_child(shaft)
	_beacon_label = Label3D.new()
	_beacon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_label.no_depth_test = true
	_beacon_label.fixed_size = true
	_beacon_label.pixel_size = 0.0015
	_beacon_label.font_size = 28
	_beacon_label.outline_size = 8
	_beacon_label.modulate = Color(1.0, 0.85, 0.5)
	_beacon_label.position.y = 3.0
	_beacon.add_child(_beacon_label)
	_audio = AudioStreamPlayer3D.new()
	_audio.position = _bell.position
	_audio.unit_size = 18.0
	_audio.max_distance = 220.0
	_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	if AudioServer.get_bus_index("Effects") != -1:
		_audio.bus = "Effects"
	add_child(_audio)


## A struck bronze bell: inharmonic partials with long, staggered decays.
static func toll_stream() -> AudioStreamWAV:
	if _toll != null:
		return _toll
	var rate := 22050
	var n := int(rate * 2.8)
	var data := PackedByteArray()
	data.resize(n * 2)
	var base := 392.0
	var partials := [[0.5, 0.35, 2.4], [1.0, 0.5, 1.6], [1.19, 0.3, 1.2], [1.5, 0.22, 0.9],
			[2.0, 0.18, 0.7], [2.5, 0.1, 0.5], [3.0, 0.06, 0.35]]
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for p: Array in partials:
			v += sin(TAU * base * float(p[0]) * t) * float(p[1]) * exp(-t / float(p[2]))
		v *= minf(1.0, t * 400.0)          # tiny attack, no click
		data.encode_s16(i * 2, int(clampf(v * 0.55, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	_toll = w
	return w


## True while the bell is swinging.
func is_ringing() -> bool:
	return _ring_t > 0.0


func beacon_active() -> bool:
	return _beacon_t > 0.0 and alarm_at != Vector3.INF


func can_ring() -> bool:
	return _cool_t <= 0.0


## Authority: toll the bell and mark `at`. Everyone sees and hears it via the state broadcast.
func ring(at: Vector3, text: String) -> bool:
	if not can_ring():
		return false
	ring_seq += 1
	alarm_at = at
	alarm_text = text
	_cool_t = COOLDOWN
	_start_ring()
	var w := WildlifeDirector.current
	if w != null and w.net != null and w.net.has_method("broadcast_bell"):
		w.net.broadcast_bell(grid_coord, at, text)
	return true


func _start_ring() -> void:
	_ring_t = RING_TIME
	_beacon_t = BEACON_TIME
	if _audio != null and is_inside_tree():
		_audio.stream = toll_stream()
		_audio.play()
	if _beacon != null and alarm_at != Vector3.INF:
		_beacon.global_position = alarm_at
		_beacon_label.text = alarm_text


func _process(dt: float) -> void:
	_cool_t = maxf(0.0, _cool_t - dt)
	if _bell == null:
		_ring_t = maxf(0.0, _ring_t - dt)
		_beacon_t = maxf(0.0, _beacon_t - dt)
		return
	if _ring_t > 0.0:
		var before := _ring_t
		_ring_t = maxf(0.0, _ring_t - dt)
		_phase += dt * 5.0
		_bell.rotation.x = sin(_phase) * 0.6 * (_ring_t / RING_TIME + 0.2)
		# A fresh toll on each big swing.
		if floori(before / 1.3) != floori(_ring_t / 1.3) and _ring_t > 0.3 and _audio != null and is_inside_tree():
			_audio.play()
	else:
		_bell.rotation.x = lerpf(_bell.rotation.x, 0.0, 1.0 - exp(-dt * 3.0))
	if _beacon_t > 0.0:
		_beacon_t = maxf(0.0, _beacon_t - dt)
		_beacon.visible = alarm_at != Vector3.INF
		_beacon_label.modulate.a = clampf(_beacon_t / 4.0, 0.0, 1.0)
	elif _beacon != null:
		_beacon.visible = false


# ---------------------------------------------------------------- interaction

func get_interaction_prompt(_player: Player) -> String:
	if not can_ring():
		return "Harbour Bell (still humming)"
	return "F  Ring the harbour bell (calls everyone, scares off nearby raiders)  ·  hold F to pick up"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if manager != null:
		manager.request_action(self, &"ring", {})


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action != &"ring":
		return {}
	if not ring(position + Vector3.UP * 2.0, "Harbour Bell"):
		return {"toast": "The bell is still humming."}
	var w := WildlifeDirector.current
	var scared := 0
	if w != null:
		scared = w.bell_scare(position, SCARE_RANGE)
		w.alert("The harbour bell is ringing! Everyone to the bell!")
	return {"toast": "You ring the bell. %s" % ("The raider bolts!" if scared > 0 else "It rings out across the island.")}


## Clients: the host rang this bell (see CreatureNet.cr_bell).
func play_ring(at: Vector3, text: String) -> void:
	ring_seq += 1
	alarm_at = at
	alarm_text = text
	_cool_t = COOLDOWN
	_start_ring()
