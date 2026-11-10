class_name CalderaLair
extends Node
## The Caldera Shell's hydrothermal trench (Biome 3 Boss).
## Lives at /root/Main/Creatures/Caldera on every peer.
## Manages Caldera Shell spawning, discovery, and victory drops.

const RAISE_DIST := 95.0
const DISCOVER_R := 80.0
const VS := VoxelWorld.VS

static var current: CalderaLair

var net: Node                   # CreatureNet
var rec := {}                   # WorldGen.sunken_ruins
var slain := false
var discovered := false
var _gen: WorldGen


func _ready() -> void:
	name = "Caldera"
	current = self
	var s: Node = net.main.get("session") if net != null and net.main != null else null
	if s != null:
		s.register_state(&"caldera", func() -> Variant: return {"slain": slain},
				func(d: Variant) -> void: slain = d is Dictionary and bool(d.get("slain", false)))


func _sync_gen() -> bool:
	if net == null or net.main == null:
		return false
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		rec = _gen.get("sunken_ruins") if "sunken_ruins" in _gen else {}
	return not rec.is_empty()


func lair_m() -> Vector3:
	return (rec.center as Vector3) * VS if rec.has("center") else Vector3.ZERO


func alive() -> CalderaShell:
	if net == null:
		return null
	for c: Creature in net.creatures.values():
		if c is CalderaShell and c.state != Creature.State.DEAD:
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
			var cs := net.spawn(&"caldera_shell", lm + Vector3.UP * 4.0) as CalderaShell
			if cs != null:
				cs.lair = lm
				cs.home = lm
				print("[caldera] The Caldera Shell emerges from the hydrothermal vents")
			break


func check_discovery(player_pos: Vector3) -> void:
	if discovered or not _sync_gen():
		return
	var lm := lair_m()
	if lm != Vector3.ZERO and player_pos.distance_to(lm) < DISCOVER_R:
		discovered = true
		if net != null and net.main != null and net.main.hud != null:
			net.main.hud.show_banner("The Basalt Skerries & Sunken Ruins", "Hydrothermal vents hiss in the deep. The Caldera Shell stirs.")


func on_caldera_slain(attacker_id: int) -> void:
	slain = true
	if net != null and net.main != null and net.main.hud != null:
		net.main.hud.show_banner("The Caldera Shell is Shattered!", "The boiling vents subside. Basalt Plates and a Geothermal Core are granted.")
	var lm := lair_m()
	if net != null and net.main != null and net.main.has_method("spawn_item_drop") and lm != Vector3.ZERO:
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"geothermal_core", 1)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"caldera_basalt_plate", 4)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"ancient_weapon_fragment", 2)
