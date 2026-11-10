class_name MaelstromSpire
extends Node
## The Maelstrom Spire: Central world vortex and lair of The Tide Sovereign.
## Lives at /root/Main/Creatures/Maelstrom on every peer.
## Manages Sovereign spawning, discovery, and climax victory drops.

const RAISE_DIST := 120.0
const DISCOVER_R := 100.0
const VS := VoxelWorld.VS

static var current: MaelstromSpire

var net: Node                   # CreatureNet
var rec := {}                   # WorldGen.maelstrom_spire
var slain := false
var discovered := false
var _gen: WorldGen


func _ready() -> void:
	name = "Maelstrom"
	current = self
	var s: Node = net.main.get("session") if net != null and net.main != null else null
	if s != null:
		s.register_state(&"maelstrom", func() -> Variant: return {"slain": slain},
				func(d: Variant) -> void: slain = d is Dictionary and bool(d.get("slain", false)))


func _sync_gen() -> bool:
	if net == null or net.main == null:
		return false
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		rec = _gen.get("maelstrom_spire") if "maelstrom_spire" in _gen else {}
	return not rec.is_empty()


func lair_m() -> Vector3:
	return (rec.center as Vector3) * VS if rec.has("center") else Vector3.ZERO


func alive() -> TideSovereign:
	if net == null:
		return null
	for c: Creature in net.creatures.values():
		if c is TideSovereign and c.state != Creature.State.DEAD:
			return c
	return null


func spawn_tick(players: Array) -> void:
	if slain or not _sync_gen() or alive() != null:
		return
	var lm := lair_m()
	if lm == Vector3.ZERO:
		return
	for pl in players:
		if Vector2(pl.pos.x - lm.x, pl.pos.z - lm.z).length() < RAISE_DIST:
			var ts := net.spawn(&"tide_sovereign", lm + Vector3.UP * 3.0) as TideSovereign
			if ts != null:
				ts.lair = lm
				ts.home = lm
				print("[maelstrom] The Tide Sovereign awakens at the Maelstrom Spire")
			break


func check_discovery(player_pos: Vector3) -> void:
	if discovered or not _sync_gen():
		return
	var lm := lair_m()
	if lm != Vector3.ZERO and player_pos.distance_to(lm) < DISCOVER_R:
		discovered = true
		if net != null and net.main != null and net.main.hud != null:
			net.main.hud.show_banner("The Maelstrom Spire", "The world's central hydro-engine vortex. The Tide Sovereign awaits.")


func on_sovereign_slain(attacker_id: int) -> void:
	slain = true
	if net != null and net.main != null and net.main.hud != null:
		net.main.hud.show_banner("THE TIDE SOVEREIGN HAS RESTED!", "The Great Deluge is stilled. Eternal calm settles across the archipelago.")
	var lm := lair_m()
	if net != null and net.main != null and net.main.has_method("spawn_item_drop") and lm != Vector3.ZERO:
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"sovereign_trident", 1)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"deluge_core", 1)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"ancient_weapon_fragment", 4)
