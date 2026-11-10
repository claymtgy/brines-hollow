class_name SirenLair
extends Node
## The Abyssal Siren's trench (Murk-Reef Biome Boss).
## Lives at /root/Main/Creatures/Siren on every peer.
## Manages Siren spawning, trench discovery, and victory announcements.

const RAISE_DIST := 85.0
const DISCOVER_R := 70.0
const VS := VoxelWorld.VS

static var current: SirenLair

var net: Node                   # CreatureNet
var rec := {}                   # WorldGen.siren
var slain := false
var discovered := false
var _gen: WorldGen


func _ready() -> void:
	name = "Siren"
	current = self
	var s: Node = net.main.get("session") if net != null and net.main != null else null
	if s != null:
		s.register_state(&"siren", func() -> Variant: return {"slain": slain},
				func(d: Variant) -> void: slain = d is Dictionary and bool(d.get("slain", false)))


func _sync_gen() -> bool:
	if net == null or net.main == null:
		return false
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		rec = _gen.get("siren") if "siren" in _gen else {}
	return not rec.is_empty()


func lair_m() -> Vector3:
	return (rec.lair as Vector3) * VS if rec.has("lair") else Vector3.ZERO


func alive() -> AbyssalSiren:
	if net == null:
		return null
	for c: Creature in net.creatures.values():
		if c is AbyssalSiren and c.state != Creature.State.DEAD:
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
			var s := net.spawn(&"abyssal_siren", lm + Vector3.DOWN * 8.0) as AbyssalSiren
			if s != null:
				s.lair = lm
				s.home = lm
				print("[siren] The Abyssal Siren stirs in the Murk-Reef depths")
			break


func check_discovery(player_pos: Vector3) -> void:
	if discovered or not _sync_gen():
		return
	var lm := lair_m()
	if lm != Vector3.ZERO and player_pos.distance_to(lm) < DISCOVER_R:
		discovered = true
		if net != null and net.main != null and net.main.hud != null:
			net.main.hud.show_banner("The Murk-Reef", "Drowned kelp trenches. The Abyssal Siren lurks below.")


func on_siren_slain(attacker_id: int) -> void:
	slain = true
	if net != null and net.main != null and net.main.hud != null:
		net.main.hud.show_banner("The Abyssal Siren is calmed", "The Murk-Reef depths are still. Its heart goes to whoever struck last.")
