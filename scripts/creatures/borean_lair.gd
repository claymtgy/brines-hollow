class_name BoreanLair
extends Node
## The Frost-Shoals lair of Borean Gore-Fin (The Glacial Patriarch).
## Lives at /root/Main/Creatures/Borean on every peer.
## Manages Borean Gore-Fin spawning, discovery, and victory drops.

const RAISE_DIST := 110.0
const DISCOVER_R := 90.0
const VS := VoxelWorld.VS

static var current: BoreanLair

var net: Node                   # CreatureNet
var rec := {}                   # WorldGen.frost_shoals
var slain := false
var discovered := false
var _gen: WorldGen


func _ready() -> void:
	name = "Borean"
	current = self
	var s: Node = net.main.get("session") if net != null and net.main != null else null
	if s != null:
		s.register_state(&"borean", func() -> Variant: return {"slain": slain},
				func(d: Variant) -> void: slain = d is Dictionary and bool(d.get("slain", false)))


func _sync_gen() -> bool:
	if net == null or net.main == null:
		return false
	var w: Node = net.main.get("world")
	if w == null or w.gen == null:
		return false
	if w.gen != _gen:
		_gen = w.gen
		rec = _gen.get("frost_shoals") if "frost_shoals" in _gen else {}
	return not rec.is_empty()


func lair_m() -> Vector3:
	return (rec.lair as Vector3) * VS if rec.has("lair") else Vector3.ZERO


func alive() -> BoreanGoreFin:
	if net == null:
		return null
	for c: Creature in net.creatures.values():
		if c is BoreanGoreFin and c.state != Creature.State.DEAD:
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
			var bg := net.spawn(&"borean_gore_fin", lm + Vector3.DOWN * 2.0) as BoreanGoreFin
			if bg != null:
				bg.lair = lm
				bg.home = lm
				print("[borean] Borean Gore-Fin breaches the Frost-Shoals pack ice")
			break


func check_discovery(player_pos: Vector3) -> void:
	if discovered or not _sync_gen():
		return
	var lm := lair_m()
	if lm != Vector3.ZERO and player_pos.distance_to(lm) < DISCOVER_R:
		discovered = true
		if net != null and net.main != null and net.main.hud != null:
			net.main.hud.show_banner("The Frost-Shoals", "Drifting pack ice and sub-zero waters. Borean Gore-Fin circles.")


func on_borean_slain(attacker_id: int) -> void:
	slain = true
	if net != null and net.main != null and net.main.hud != null:
		net.main.hud.show_banner("The Glacial Patriarch is Conquered!", "The pack ice quiets. Glacial Tusks and Borean Fur awarded.")
	var lm := lair_m()
	if net != null and net.main != null and net.main.has_method("spawn_item_drop") and lm != Vector3.ZERO:
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"glacial_tusk", 2)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"borean_fur", 4)
		net.main.spawn_item_drop(lm + Vector3.UP * 2.0, &"ancient_weapon_fragment", 2)
