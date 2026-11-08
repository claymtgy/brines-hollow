class_name TradeManager
extends Node
## Visiting merchant ships and trading. Lives at /root/Main/Trade.
##
## The ship's voyage is a pure function of the (synced) time of day: it sails in at 07:12,
## docks beside the starter pier 08:38-14:53, and sails off. Every peer computes the same
## motion, so only the merchant's stock / contracts need networking.
## Trades: the client escrows its side, the server validates the merchant side
## (TradeRules) and answers; rejected trades are refunded.

const VS := VoxelWorld.VS
const ARRIVE := 0.30
const DOCKED_FROM := 0.36
const DOCKED_UNTIL := 0.62
const DEPART := 0.68
const TRADE_RANGE := 7.0
const NAMES := ["Raft Peddler Barnaby", "The Gull's Fortune (trade galleon)"]

var main: Node
var merchant: MerchantBoat = null      # authority: the real one; clients: a replica
var ship: Node3D
var ui: TradeUI
var _ready_done := false
var _moor := Vector3.ZERO              # metres, beside the dock end
var _out_a := Vector3.ZERO
var _out_b := Vector3.ZERO
var _was_docked := false
var _visits := 0
var _nonce := 0
var _pending := {}                     # nonce -> escrow record (client side)
var _near := false
## Village traders (NpcVillages): key -> MerchantBoat, and where each one stands (metres).
## `session_key` says who the trade window is open with: "" = the visiting ship.
var traders := {}
var trader_pos := {}
var session_key := ""


func _ready() -> void:
	name = "Trade"
	ui = TradeUI.new()
	ui.trade = self
	add_child(ui)
	if main != null and main.get("session") != null:
		main.session.register_state(&"trade", _save_state, _load_state)


## Persistence: the visit count (which merchant comes next) and, while a ship is docked,
## its stock, prices and contracts, so reloading mid-visit doesn't restock the ship.
func _save_state() -> Dictionary:
	var d := {"visits": _visits}
	var vt := {}
	for k: String in traders:
		vt[k] = TradeRules.serialize_merchant(traders[k])
	d["villages"] = vt
	if merchant != null and is_docked():
		d["merchant"] = TradeRules.serialize_merchant(merchant)
	return d


func _load_state(d: Variant) -> void:
	if not (d is Dictionary):
		return
	_visits = int(d.get("visits", _visits))
	if d.get("villages") is Dictionary:
		for k: String in d.villages:
			traders[k] = TradeRules.deserialize_merchant(d.villages[k])
	if d.get("merchant") is Dictionary:
		merchant = TradeRules.deserialize_merchant(d.merchant)
		_was_docked = true   # this visit already happened: don't spawn a fresh ship
		if ship != null:
			_apply_ship_label()


## The merchant the trade window is dealing with right now.
func current() -> MerchantBoat:
	return merchant if session_key == "" else traders.get(session_key)


## Make sure a village trader exists (same starting wares on every peer; a save or the
## host's stock replaces them).
func ensure_trader(key: String, trader_name: String, style: int, pos: Vector3) -> void:
	trader_pos[key] = pos
	if not traders.has(key):
		traders[key] = village_wares(trader_name, style, hash(key))


static func village_wares(trader_name: String, style: int, h: int) -> MerchantBoat:
	var m := MerchantBoat.new(trader_name, MerchantBoat.MerchantType.RAFT_PEDDLER)
	m.stock = Inventory.new(16)
	m.active_contracts.clear()
	var common := [[&"wood_plank", 30], [&"kelp_frond", 20], [&"shore_hardtack", 6]]
	var by_style := {
		0: [[&"seed_shore_wheat", 12], [&"seed_root_potato", 8], [&"pine_sapling", 4]],
		1: [[&"seed_samphire", 10], [&"smoked_fish_ration", 4], [&"seed_tide_kale", 8]],
		2: [[&"seed_root_potato", 10], [&"pine_sapling", 6], [&"smoked_fish_ration", 3]],
		3: [[&"copper_ore", 12], [&"iron_ingot", 4], [&"sea_brass_ingot", 1]],
		4: [[&"iron_ingot", 5], [&"copper_ore", 8], [&"seed_shore_wheat", 6]],
	}
	var base_price := {
		&"seed_shore_wheat": 2, &"seed_samphire": 3, &"seed_tide_kale": 3, &"seed_root_potato": 4,
		&"wood_plank": 2, &"kelp_frond": 1, &"pine_sapling": 4, &"shore_hardtack": 6,
		&"smoked_fish_ration": 14, &"copper_ore": 4, &"iron_ingot": 15, &"sea_brass_ingot": 25,
	}
	for it: Array in common + by_style.get(style, by_style[0]):
		if ItemDB.get_item(it[0]) == null:
			continue
		m.stock.add_item(it[0], it[1])
		m.selling_prices[it[0]] = base_price.get(it[0], 5)
	return m


## Open the trade window with a village trader (NpcVillages calls this on F).
func open_village(key: String) -> void:
	if not traders.has(key):
		return
	session_key = key
	ui.open()


func is_authority() -> bool:
	return not main.is_net or main.multiplayer.multiplayer_peer == null or main.multiplayer.is_server()


func _try_init() -> void:
	if _ready_done or main.world == null or not main.world.ready_for_play or main.world.gen == null:
		return
	var st: Dictionary = main.world.gen.starter
	if st.is_empty():
		return
	_ready_done = true
	var dock: Vector2i = st.dock_o
	var fwd: Vector2i = st.front
	var side: Vector2i = st.side
	var end := dock + fwd * 30 - side * 12        # alongside the pier's seaward end
	_moor = Vector3(end.x * VS, 0.0, end.y * VS)
	var f := Vector3(fwd.x, 0, fwd.y)
	var s := Vector3(side.x, 0, side.y)
	_out_a = _moor + f * 90.0 - s * 40.0
	_out_b = _moor + f * 90.0 + s * 40.0
	ship = _build_ship()
	add_child(ship)
	ship.visible = false
	if main.multiplayer != null:
		main.multiplayer.peer_connected.connect(_on_peer_connected)


func is_docked() -> bool:
	var t: float = main.sky.time_of_day
	return t >= DOCKED_FROM and t < DOCKED_UNTIL


func trade_point() -> Vector3:
	return _moor


# ---------------------------------------------------------------- voyage

func _process(_delta: float) -> void:
	if main == null:
		return
	_try_init()
	if not _ready_done:
		return
	_update_ship()
	var docked := is_docked()
	if docked and not _was_docked and is_authority():
		_new_visit()
	if not docked and _was_docked:
		if ui.visible and session_key == "":
			ui.close()
		if is_authority():
			merchant = null
	_was_docked = docked
	_update_prompt()


func _update_ship() -> void:
	var t: float = main.sky.time_of_day
	var water: float = main.sky.water_level_m()
	if t < ARRIVE or t >= DEPART:
		ship.visible = false
		return
	ship.visible = true
	var p: Vector3
	var look: Vector3
	if t < DOCKED_FROM:
		var k := smoothstep(0.0, 1.0, (t - ARRIVE) / (DOCKED_FROM - ARRIVE))
		p = _out_a.lerp(_moor, k)
		look = _moor - _out_a
	elif t < DOCKED_UNTIL:
		p = _moor
		look = _moor - _out_a
	else:
		var k := smoothstep(0.0, 1.0, (t - DOCKED_UNTIL) / (DEPART - DOCKED_UNTIL))
		p = _moor.lerp(_out_b, k)
		look = _out_b - _moor
	var bob := sin(Time.get_ticks_msec() / 900.0) * 0.06
	if main.sky.has_method("wave_offset_at"):   # weather swell (agent D), when merged
		var w = main.sky.wave_offset_at(Vector3(p.x, water, p.z))
		if w is float:
			bob += w
	ship.position = Vector3(p.x, water - 0.35 + bob, p.z)
	ship.rotation = Vector3(sin(Time.get_ticks_msec() / 1300.0) * 0.02, atan2(look.x, look.z), sin(Time.get_ticks_msec() / 1100.0) * 0.03)


func _new_visit() -> void:
	_visits += 1
	var kind := MerchantBoat.MerchantType.TRADE_GALLEON if _visits % 2 == 0 else MerchantBoat.MerchantType.RAFT_PEDDLER
	merchant = MerchantBoat.new(NAMES[1] if kind == MerchantBoat.MerchantType.TRADE_GALLEON else NAMES[0], kind)
	_broadcast_stock()
	_toast_all("%s has docked at the pier" % merchant.merchant_name)


func _build_ship() -> Node3D:
	# ~2.5 m beam, 6.5 m long, mast + striped sail; built from terrain-scale voxels.
	var g := Prefabs.Grid.new(14, 40, 36)
	g.box(3, 0, 3, 10, 0, 32, Palette.DARK_WOOD)                 # keel
	for z in range(2, 34):
		var w := 6 if z > 4 and z < 30 else 4
		g.box(7 - w, 1, z, 7 - w, 4, z, Palette.PLANK)
		g.box(6 + w, 1, z, 6 + w, 4, z, Palette.PLANK)
		g.box(8 - w, 1, z, 5 + w, 1, z, Palette.DARK_WOOD)
	g.box(1, 4, 5, 1, 4, 29, Palette.ROOF_BLUE)
	g.box(12, 4, 5, 12, 4, 29, Palette.ROOF_BLUE)
	g.box(5, 1, 34, 8, 5, 35, Palette.PLANK)                     # bow
	g.box(3, 1, 0, 10, 6, 2, Palette.DARK_WOOD)                  # stern cabin
	g.box(4, 7, 0, 9, 7, 2, Palette.ROOF_RED)
	g.box(7, 2, 18, 7, 38, 18, Palette.DARK_WOOD)                # mast
	g.box(1, 14, 19, 13, 36, 19, Palette.WHITEWASH)              # sail
	for y in range(18, 34, 6):
		g.box(1, y, 19, 13, y + 1, 19, Palette.ROOF_RED)
	g.box(3, 2, 22, 5, 4, 24, Palette.PLANK)                     # cargo crates
	g.box(9, 2, 10, 11, 3, 12, Palette.BUOY)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	var root := Node3D.new()
	root.name = "MerchantShip"
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	mi.position = Vector3(-7, 0, -18) * VS
	root.add_child(mi)
	var lbl := Label3D.new()
	lbl.name = "Name"
	lbl.position = Vector3(0, 7.6, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.pixel_size = 0.005
	lbl.text = "Merchant"
	root.add_child(lbl)
	var qlbl := Label3D.new()
	qlbl.name = "QuestMarker"
	qlbl.position = Vector3(0, 8.8, 0)
	qlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	qlbl.font_size = 110
	qlbl.outline_size = 18
	qlbl.pixel_size = 0.005
	qlbl.modulate = UiTheme.BRASS
	qlbl.no_depth_test = true
	root.add_child(qlbl)
	return root


# ---------------------------------------------------------------- interaction

func _update_prompt() -> void:
	_near = false
	var p: Player = main.player
	if p == null or merchant == null or not is_docked() or p.is_seated() or ui.visible:
		return
	if Vector2(p.position.x - _moor.x, p.position.z - _moor.z).length() > TRADE_RANGE:
		return
	_near = true
	main.hud.set_prompt("F  Trade with %s" % merchant.merchant_name)


func _unhandled_input(e: InputEvent) -> void:
	if not _near or not e.is_action_pressed("interact"):
		return
	if main.player == null or not main.player.input_enabled:
		return
	get_viewport().set_input_as_handled()
	session_key = ""
	ui.open()


func _toast_all(text: String) -> void:
	main.hud.show_toast(text)
	print("[trade] ", text)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		trade_event.rpc(text)


# ---------------------------------------------------------------- requests (client side)

func request_buy(item: StringName, count: int) -> void:
	var inv: Inventory = main.player.inventory
	var m := current()
	if m == null:
		return
	var cost := TradeRules.price_to_buy(m, item, count)
	if cost <= 0 or not m.stock.has_item(item, count):
		return
	if not inv.has_item(&"brass_guilder", cost):
		main.hud.show_toast("Not enough brass (need %d)" % cost)
		return
	inv.remove_item(&"brass_guilder", cost)        # escrow
	_send({"k": "buy", "item": item, "n": count, "paid": cost})


func request_sell(item: StringName, count: int) -> void:
	var inv: Inventory = main.player.inventory
	var m := current()
	if m == null or not m.buying_prices.has(item) or not inv.has_item(item, count):
		return
	inv.remove_item(item, count)                   # escrow
	_send({"k": "sell", "item": item, "n": count})


func request_fulfill(contract_id: StringName) -> void:
	var inv: Inventory = main.player.inventory
	if current() == null:
		return
	for c: TradeContract in current().active_contracts:
		if c.id == contract_id and not c.is_fulfilled:
			if not c.can_fulfill(inv):
				main.hud.show_toast("Missing goods for this manifest")
				return
			for item in c.required_items:
				inv.remove_item(StringName(item), int(c.required_items[item]))   # escrow
			_send({"k": "fulfill", "item": contract_id, "reqs": c.required_items.duplicate()})
			return


func _send(req: Dictionary) -> void:
	_nonce += 1
	req["nonce"] = _nonce
	req["v"] = session_key
	_pending[_nonce] = req
	if is_authority():
		_server_handle(req, main.multiplayer.get_unique_id() if main.is_net else 1)
	else:
		trade_req.rpc_id(1, req)


func _apply_result(nonce: int, ok: bool, amount: int, scrip: int) -> void:
	var req: Dictionary = _pending.get(nonce, {})
	_pending.erase(nonce)
	if req.is_empty() or main.player == null:
		return
	var inv: Inventory = main.player.inventory
	var item := StringName(req.get("item", ""))
	match String(req.k):
		"buy":
			if ok:
				inv.add_item(item, int(req.n))
				main.hud.show_toast("Bought %d %s for %d brass" % [req.n, _item_name(item), amount])
			else:
				inv.add_item(&"brass_guilder", int(req.paid))
				main.hud.show_toast("Sold out - brass refunded")
		"sell":
			if ok:
				inv.add_item(&"brass_guilder", amount)
				main.hud.show_toast("Sold %d %s for %d brass" % [req.n, _item_name(item), amount])
			else:
				inv.add_item(item, int(req.n))
		"fulfill":
			if ok:
				inv.add_item(&"brass_guilder", amount)
				if scrip > 0:
					inv.add_item(&"tide_scrip", scrip)
				main.hud.show_toast("Manifest shipped: +%d brass, +%d tide scrip" % [amount, scrip])
			else:
				for it in req.reqs:
					inv.add_item(StringName(it), int(req.reqs[it]))
				main.hud.show_toast("That manifest was already filled - goods returned")
	ui.refresh()


static func _item_name(id: StringName) -> String:
	var d: ItemDef = ItemDB.get_item(id)
	return d.name if d != null else String(id)


# ---------------------------------------------------------------- server side

func _server_handle(req: Dictionary, peer: int) -> void:
	var ok := false
	var amount := 0
	var scrip := 0
	var v := String(req.get("v", ""))
	var m: MerchantBoat = merchant if v == "" else traders.get(v)
	var open := is_docked() if v == "" else true
	if m != null and open and _requester_near(peer, v):
		var item := StringName(req.get("item", ""))
		var n := int(req.get("n", 0))
		match String(req.get("k", "")):
			"buy":
				var cost := TradeRules.server_buy(m, item, n)
				# the client must have escrowed at least the real price
				ok = cost >= 0 and int(req.get("paid", 0)) >= cost
				if cost >= 0 and not ok:
					m.stock.add_item(item, n)
				amount = cost
			"sell":
				amount = TradeRules.server_sell(m, item, n)
				ok = amount >= 0
			"fulfill":
				var r := TradeRules.server_fulfill(m, item)
				ok = not r.is_empty()
				amount = int(r.get("brass", 0))
				scrip = int(r.get("scrip", 0))
	var nonce := int(req.get("nonce", 0))
	if not main.is_net or peer == main.multiplayer.get_unique_id():
		_apply_result(nonce, ok, amount, scrip)
	else:
		trade_result.rpc_id(peer, nonce, ok, amount, scrip)
	if ok:
		_broadcast_stock(v)


func _requester_near(peer: int, v := "") -> bool:
	var pos := Vector3.INF
	if not main.is_net or peer == main.multiplayer.get_unique_id():
		pos = main.player.position if main.player != null else Vector3.INF
	elif main.remotes.has(peer):
		pos = main.remotes[peer].position
	var at: Vector3 = _moor if v == "" else trader_pos.get(v, Vector3.INF)
	return Vector2(pos.x - at.x, pos.z - at.z).length() <= TRADE_RANGE + 4.0


func _broadcast_stock(v := "") -> void:
	if v != "":
		ui.refresh()
		if main.is_net and main.multiplayer.multiplayer_peer != null and traders.has(v):
			village_stock.rpc(v, TradeRules.serialize_merchant(traders[v]))
		return
	_apply_ship_label()
	ui.refresh()
	if main.is_net and main.multiplayer.multiplayer_peer != null and merchant != null:
		merchant_stock.rpc(TradeRules.serialize_merchant(merchant))


func _apply_ship_label() -> void:
	if ship != null and merchant != null:
		(ship.get_node("Name") as Label3D).text = merchant.merchant_name
		var qmarker := ship.get_node_or_null("QuestMarker") as Label3D
		if qmarker != null:
			qmarker.text = _get_merchant_quest_marker()


func _get_merchant_quest_marker() -> String:
	if main == null or main.quests == null or merchant == null:
		return ""
	var qm: QuestManager = main.quests
	var m_name := merchant.merchant_name.to_lower()
	for qd in qm.active_quests.values():
		if qm.paused_reward_quests.has(qd.id) and qd.giver_name.to_lower().contains(m_name):
			return "?"
		var all_other_done := true
		var talk_found := false
		for s in qd.steps:
			if not s.is_completed:
				if s.type == QuestDef.ObjectiveType.TALK_TO and m_name.contains(String(s.target_id).to_lower()):
					talk_found = true
				else:
					all_other_done = false
		if talk_found and all_other_done:
			return "?"
	for qd in qm.available_quests.values():
		if qd.giver_name.to_lower().contains("barnaby") and m_name.contains("barnaby"):
			return "!"
		if m_name.contains(qd.giver_name.to_lower()):
			return "!"
	return ""


func _on_peer_connected(id: int) -> void:
	if main.multiplayer.is_server() and merchant != null and is_docked():
		merchant_stock.rpc_id(id, TradeRules.serialize_merchant(merchant))
	if main.multiplayer.is_server():
		for k: String in traders:
			village_stock.rpc_id(id, k, TradeRules.serialize_merchant(traders[k]))


@rpc("any_peer", "call_remote", "reliable")
func trade_req(req: Dictionary) -> void:
	if is_authority():
		_server_handle(req, main.multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func trade_result(nonce: int, ok: bool, amount: int, scrip: int) -> void:
	_apply_result(nonce, ok, amount, scrip)


@rpc("authority", "call_remote", "reliable")
func merchant_stock(d: Dictionary) -> void:
	merchant = TradeRules.deserialize_merchant(d)
	_apply_ship_label()
	ui.refresh()


@rpc("authority", "call_remote", "reliable")
func village_stock(k: String, d: Dictionary) -> void:
	traders[k] = TradeRules.deserialize_merchant(d)
	ui.refresh()


@rpc("authority", "call_remote", "reliable")
func trade_event(text: String) -> void:
	main.hud.show_toast(text)


# ---------------------------------------------------------------- dev check

## --tradecheck: jump to the docked merchant, sell, buy, fill a manifest.
func run_check() -> void:
	while not _ready_done or main.player == null:
		await get_tree().process_frame
	main.sky.time_of_day = 0.40
	_visits = 1   # next visit is the galleon (has manifests)
	await get_tree().create_timer(1.0).timeout
	main.player.position = _moor + Vector3(0, 6, 0)
	var inv: Inventory = main.player.inventory
	inv.add_item(&"silver_mackerel", 5)
	inv.add_item(&"smoked_fish_ration", 10)
	await get_tree().create_timer(0.5).timeout
	print("[tradecheck] docked=%s merchant=%s brass=%d" % [is_docked(), merchant.merchant_name if merchant else "none", inv.get_item_count(&"brass_guilder")])
	request_sell(&"silver_mackerel", 5)
	await get_tree().create_timer(0.3).timeout
	var b := inv.get_item_count(&"brass_guilder")
	print("[tradecheck] after selling 5 mackerel: brass=%d" % b)
	request_fulfill(&"manifest_cured_fish")
	await get_tree().create_timer(0.3).timeout
	print("[tradecheck] manifest: brass=%d scrip=%d fish=%d" % [inv.get_item_count(&"brass_guilder"), inv.get_item_count(&"tide_scrip"), inv.get_item_count(&"smoked_fish_ration")])
	var item: StringName = merchant.stock.slots[0].item_id if not merchant.stock.slots[0].is_empty() else &""
	if item != &"":
		var stock_before := merchant.stock.get_item_count(item)
		request_buy(item, 1)
		await get_tree().create_timer(0.3).timeout
		print("[tradecheck] bought 1 %s: brass=%d have=%d merchant stock %d -> %d" % [item, inv.get_item_count(&"brass_guilder"),
			inv.get_item_count(item), stock_before, merchant.stock.get_item_count(item)])
	request_fulfill(&"manifest_cured_fish")
	await get_tree().create_timer(0.3).timeout
	print("[tradecheck] second manifest attempt (should refuse): scrip=%d" % inv.get_item_count(&"tide_scrip"))
	get_tree().quit()
