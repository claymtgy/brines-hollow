class_name HulkLair
extends Node
## The Barnacled Hulk's strand (WorldGen.plan_hulk). Lives at /root/Main/Creatures/Hulk on
## every peer. Host: while the Hulk is unslain, it lies buried on its strand whenever a
## player comes within RAISE_DIST; it rises when someone walks up close. Slain, it stays
## slain for the whole world (world state "hulk"). Everyone hears about it.
## The loose boulders on the rocks above are BoulderEntity; pushing one asks drop_boulder().

const RAISE_DIST := 70.0
const DISCOVER_R := 60.0
const BOULDER_REACH := 14.0     # metres, horizontally, from the boulder to what it lands on
const VS := VoxelWorld.VS

static var current: HulkLair

var net: Node                   # CreatureNet
var rec := {}                   # WorldGen.hulk
var slain := false
var discovered := false         # this character
var _gen: WorldGen


func _ready() -> void:
	name = "Hulk"
	current = self
	var s: Node = net.main.get("session")
	if s != null:
		s.register_state(&"hulk", func() -> Variant: return {"slain": slain},
				func(d: Variant) -> void: slain = d is Dictionary and bool(d.get("slain", false)))


func _sync_gen() -> bool:
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		rec = _gen.hulk
	return not rec.is_empty()


func lair_m() -> Vector3:
	return (rec.lair as Vector3) * VS


func alive() -> BarnacledHulk:
	for c: Creature in net.creatures.values():
		if c is BarnacledHulk and c.state != Creature.State.DEAD:
			return c
	return null


## Host, from CreatureNet._spawn_tick.
func spawn_tick(players: Array) -> void:
	if slain or not _sync_gen() or alive() != null:
		return
	var lm := lair_m()
	for pl: Dictionary in players:
		if Vector2(pl.pos.x - lm.x, pl.pos.z - lm.z).length() < RAISE_DIST:
			net._ensure_column(floori(lm.x / VS), floori(lm.z / VS))
			var h := net.spawn(&"barnacled_hulk", lm + Vector3.UP * 0.5) as BarnacledHulk
			if h != null:
				var g := h.ground_under(h.position, 0.8, 2.0)
				if not is_nan(g):
					h.position.y = g
				h.lair = h.position
				h.home = h.position
				var d: Vector2 = rec.dir
				h.yaw = atan2(d.x, d.y)
				print("[hulk] the Barnacled Hulk lies on its strand")
			return


func on_risen() -> void:
	say("The heap of barnacled planks heaves up out of the sand: the BARNACLED HULK! Its shell turns your blows; find another way.")


## Host: a boulder was pushed off the rocks at `at` (metres). True if it hit the Hulk.
func drop_boulder(at: Vector3, attacker: int) -> bool:
	var h := alive()
	if h == null:
		return false
	var d := Vector2(h.position.x - at.x, h.position.z - at.z).length()
	if d > BOULDER_REACH + h.radius or h.position.y > at.y - 0.8:
		return false
	h.boulder_hit(attacker)
	if h.state == Creature.State.DEAD:
		return true
	say("The boulder smashes into the Hulk's shell! %s" % ("The shell splits wide open!" if h.shell_split() else "It cracks. One more..."))
	return true


func on_slain(h: BarnacledHulk) -> void:
	slain = true
	print("[hulk] slain")
	if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
		hulk_slain.rpc()
	else:
		hulk_slain()
	if h != null:
		pass


@rpc("authority", "call_local", "reliable")
func hulk_slain() -> void:
	slain = true
	if net != null and net.main != null:
		if net.main.player != null and net.main.player.inventory != null:
			net.main.player.inventory.add_item(&"gilded_ship_wheel", 1)
		if net.main.hud != null:
			net.main.hud.show_banner("The Barnacled Hulk is slain", "The Hollow Flats are quiet. Gilded Ship Wheel and Pearl recovered!")


func say(text: String) -> void:
	if net.main.is_net and net.main.multiplayer.multiplayer_peer != null:
		net.cr_toast.rpc(text)
	if net.main.hud != null:
		net.main.hud.show_toast(text)


func _process(_delta: float) -> void:
	if discovered or net == null or net.main.player == null or Engine.get_process_frames() % 30 != 0 or not _sync_gen():
		return
	var pp: Vector3 = net.main.player.position
	var lm := lair_m()
	if Vector2(pp.x - lm.x, pp.z - lm.z).length() < DISCOVER_R:
		discovered = true
		var isle: String = net.main.atlas.name_of(int(rec.island)) if net.main.get("atlas") != null else ""
		net.main.hud.show_banner("The Hulk's Strand", "%s  ·  %s  ·  marked on your chart" % [isle,
				"its bones bleach on the sand" if slain else "something huge lies buried on the flats"])


func chart_labels() -> Array:
	if not discovered or not _sync_gen():
		return []
	return [{"pos": lair_m(), "name": "Hulk's Strand", "camp": true, "cleared": slain}]
