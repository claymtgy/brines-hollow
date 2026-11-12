class_name CharacterModel
extends Node3D
## Chunky voxel fisherfolk, built from voxels at 2x the terrain resolution.
## Rigid-part animation: legs, arms, head swing on pivots.
## Supports full character customization (hair, beard, hat, skin, coats)
## and dynamic paperdoll gear (backpacks, diving helm, maritime weaponry).

const U := VoxelWorld.VS * 0.5  # character voxel size (0.09m)
const HEAD_PIVOT := Vector3(0, 11, 0)   # neck, in character voxels above the feet

var coat := Palette.COAT_A
var hat := Palette.HAT_A

var customizer: CharacterCustomizer = null

var body: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D

# Held tools and weapons
var tool_pick: Node3D
var tool_hammer: Node3D
var tool_plan: Node3D
var tool_rod: Node3D
var tool_hoe: Node3D
var tool_cutlass: Node3D
var tool_harpoon: Node3D
var tool_maul: Node3D
var tool_lantern: Node3D
var tool_axe: Node3D
var tool_shovel: Node3D
var tool_bow: Node3D
var tool_flintlock: Node3D

# Paperdoll equipment attachments
var backpack_node: Node3D
var diving_helmet_node: Node3D
var flippers_node: Node3D
var shield_node: Node3D
var offhand_lantern: Node3D

var _phase := 0.0
## Sneaking: hips drop, torso leans in, legs go into a low creeping stride. Set each frame.
var crouching := false
var _crouch := 0.0               # 0 standing .. 1 fully crouched (eased)
const CROUCH_LEAN := 0.5         # torso lean forward (rad)
const CROUCH_STANCE := 0.85      # each leg's angle from vertical in the creeping stride (rad)
var _swing := 0.0
var _swing_step := 0
var _swing_charged := false
var _mat: StandardMaterial3D
var _current_tool_idx := 0
var _cast_anim := 0.0
var _fishing_state := 0
var _fishing_power := 0.0
var _hop_lift := 0.0             # backstep airtime height, applied by _rest_on_ground


static func _grid(sx: int, sy: int, sz: int) -> Prefabs.Grid:
	return Prefabs.Grid.new(sx, sy, sz)


func setup(coat_mat: int = Palette.COAT_A, hat_mat: int = Palette.HAT_A, p_customizer: CharacterCustomizer = null) -> void:
	coat = coat_mat
	hat = hat_mat
	customizer = p_customizer

	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.8

	rebuild()


func apply_customizer(p_customizer: CharacterCustomizer) -> void:
	customizer = p_customizer
	rebuild()


## Cleans up existing children and completely reconstructs the character voxel hierarchy.
func rebuild() -> void:
	for child in get_children():
		child.queue_free()

	body = Node3D.new()
	add_child(body)

	# Determine palette materials based on customizer or defaults
	var skin_mat: int = Palette.SKIN
	var hair_mat: int = Palette.HANDLE
	var eye_mat: int = Palette.EYE
	var coat_mat: int = coat
	var hat_mat: int = hat
	var hair_st := CharacterPalette.HairStyle.WINDSWEPT
	var beard_st := CharacterPalette.BeardStyle.STUBBLE
	var hat_st := CharacterPalette.HatStyle.SOUWESTER

	if customizer:
		# Skin mapping
		match customizer.skin_tone:
			CharacterPalette.SkinTone.PALE_SALT: skin_mat = Palette.SKIN
			CharacterPalette.SkinTone.WEATHERED_TAN: skin_mat = Palette.SANDSTONE_C
			CharacterPalette.SkinTone.RUSTIC_OCHRE: skin_mat = Palette.SANDSTONE_A
			CharacterPalette.SkinTone.DEEP_UMBER: skin_mat = Palette.TRUNK
			CharacterPalette.SkinTone.ABYSSAL_DUSKY: skin_mat = Palette.GRAVEL

		# Hair color mapping
		match customizer.hair_color:
			CharacterPalette.HairColor.RAVEN_BLACK: hair_mat = Palette.BEDROCK
			CharacterPalette.HairColor.DRIFTWOOD_GREY: hair_mat = Palette.DRIFTWOOD
			CharacterPalette.HairColor.SALT_WHITE: hair_mat = Palette.WHITEWASH
			CharacterPalette.HairColor.RUST_AUBURN: hair_mat = Palette.ROOF_RED
			CharacterPalette.HairColor.STRAW_BLONDE: hair_mat = Palette.FLOWER_Y
			CharacterPalette.HairColor.KELP_GREEN: hair_mat = Palette.KELP

		# Coat color mapping
		match customizer.coat_color:
			CharacterPalette.CoatColor.OILSKIN_YELLOW:
				coat_mat = Palette.COAT_A
				hat_mat = Palette.HAT_A
			CharacterPalette.CoatColor.NAVY_BLUE:
				coat_mat = Palette.TROUSER
				hat_mat = Palette.ROOF_BLUE
			CharacterPalette.CoatColor.STORM_GREY:
				coat_mat = Palette.COBBLE
				hat_mat = Palette.STONE
			CharacterPalette.CoatColor.KELP_GREEN:
				coat_mat = Palette.KELP
				hat_mat = Palette.KELP
			CharacterPalette.CoatColor.CORAL_RUST:
				coat_mat = Palette.ROOF_RED
				hat_mat = Palette.HAT_B
			CharacterPalette.CoatColor.PITCH_BLACK:
				coat_mat = Palette.DARK_WOOD
				hat_mat = Palette.BEDROCK

		hair_st = customizer.hair_style
		beard_st = customizer.beard_style
		hat_st = customizer.hat_style

	# ---------------------------------------------------------------- Torso
	var t := _grid(6, 6, 4)
	t.box(0, 0, 0, 5, 5, 3, coat_mat)
	t.box(0, 0, 0, 5, 0, 3, Palette.DARK_WOOD)      # belt
	t.setv(2, 0, 3, Palette.METAL)                   # buckle
	t.setv(3, 0, 3, Palette.METAL)
	t.box(2, 2, 3, 2, 2, 3, Palette.BUTTON)
	t.box(2, 4, 3, 2, 4, 3, Palette.BUTTON)
	var scarf_mat: int = Palette.HAT_B if coat_mat == Palette.COAT_A else Palette.WHITEWASH
	t.box(0, 5, 0, 5, 5, 3, scarf_mat)              # scarf
	t.setv(4, 4, 3, scarf_mat)
	_part(body, t, Vector3(-3, 5, -2))

	# Backpack node (attached to torso back at Z = -2.5)
	backpack_node = Node3D.new()
	backpack_node.position = Vector3(0, 7.5, -2.5) * U
	body.add_child(backpack_node)
	var bp_grid := _grid(5, 5, 2)
	bp_grid.box(0, 0, 0, 4, 4, 1, Palette.DARK_WOOD)
	bp_grid.box(1, 1, 0, 3, 3, 0, Palette.METAL)
	bp_grid.box(0, 3, 0, 4, 4, 1, Palette.PLANK)
	_part(backpack_node, bp_grid, Vector3(-2.5, -2.5, -1))
	backpack_node.visible = false # Hidden until backpack equipped

	# ---------------------------------------------------------------- Head
	head = Node3D.new()
	head.position = HEAD_PIVOT * U
	body.add_child(head)

	var h := _grid(10, 10, 10)
	# Skin base: 8 wide, 6 high, 7 deep
	h.box(1, 0, 1, 8, 6, 7, skin_mat)

	# Eyes & Cheeks
	h.box(3, 3, 7, 3, 4, 7, eye_mat)
	h.box(6, 3, 7, 6, 4, 7, eye_mat)
	h.setv(2, 2, 7, Palette.CHEEK)
	h.setv(7, 2, 7, Palette.CHEEK)

	# Hair styling
	_build_hair(h, hair_st, hair_mat)

	# Facial hair / Beard styling
	_build_beard(h, beard_st, hair_mat)

	# Hat styling
	_build_hat(h, hat_st, hat_mat)

	_part(head, h, Vector3(-5, 0, -4))

	# Diving Helmet Paperdoll Overlay
	diving_helmet_node = Node3D.new()
	diving_helmet_node.position = Vector3(0, 4.5, 1.5) * U
	head.add_child(diving_helmet_node)
	var helm_grid := _grid(11, 11, 11)
	helm_grid.box(0, 0, 0, 10, 10, 10, Palette.METAL)
	helm_grid.box(1, 1, 1, 9, 9, 9, Palette.AIR)       # Hollow interior
	helm_grid.box(3, 3, 10, 7, 7, 10, Palette.GLOW_TEAL) # Round porthole
	helm_grid.box(2, 2, 10, 8, 2, 10, Palette.DARK_WOOD)  # Brass collar
	helm_grid.box(2, 8, 10, 8, 8, 10, Palette.DARK_WOOD)
	_part(diving_helmet_node, helm_grid, Vector3(-5.5, -5.5, -5.5))
	diving_helmet_node.visible = false

	# ---------------------------------------------------------------- Limbs
	arm_l = _limb(body, Vector3(-4, 10.5, 0), coat_mat, skin_mat, 2, 6, 2, 1)
	arm_r = _limb(body, Vector3(4, 10.5, 0), coat_mat, skin_mat, 2, 6, 2, 1)
	leg_l = _limb(body, Vector3(-1.5, 5, 0), Palette.TROUSER, Palette.BOOT, 3, 5, 3, 2)
	leg_r = _limb(body, Vector3(1.5, 5, 0), Palette.TROUSER, Palette.BOOT, 3, 5, 3, 2)

	# ---------------------------------------------------------------- Tools & Weapons
	_build_tool_arsenal()
	set_tool(_current_tool_idx)
	if _first_person_view:
		_first_person_view = false
		set_first_person_view(true)


func _build_hair(h: Prefabs.Grid, style: CharacterPalette.HairStyle, hair_mat: int) -> void:
	match style:
		CharacterPalette.HairStyle.BALD:
			# Just subtle hair stubble at lower neck nape
			h.box(2, 0, 1, 7, 1, 1, hair_mat)

		CharacterPalette.HairStyle.CROPPED:
			# Short hair at back and sides
			h.box(1, 1, 1, 8, 6, 2, hair_mat)
			h.box(1, 3, 3, 1, 6, 6, hair_mat)
			h.box(8, 3, 3, 8, 6, 6, hair_mat)
			h.box(1, 6, 1, 8, 6, 7, hair_mat)

		CharacterPalette.HairStyle.WINDSWEPT:
			# Back hair + front sweeping bangs
			h.box(1, 1, 1, 8, 6, 3, hair_mat)
			h.box(1, 3, 4, 1, 6, 6, hair_mat)
			h.box(8, 3, 4, 8, 6, 6, hair_mat)
			h.box(1, 6, 1, 8, 7, 7, hair_mat)
			h.box(2, 5, 7, 5, 6, 8, hair_mat) # Overhanging bang

		CharacterPalette.HairStyle.SAILOR_BUN:
			# Back hair + top knot
			h.box(1, 1, 1, 8, 6, 2, hair_mat)
			h.box(1, 6, 1, 8, 6, 7, hair_mat)
			h.box(3, 7, 1, 6, 9, 3, hair_mat) # Top bun

		CharacterPalette.HairStyle.BRAIDED_TIDES:
			# Braids hanging past shoulders
			h.box(1, 1, 1, 8, 6, 2, hair_mat)
			h.box(0, 0, 3, 1, 5, 4, hair_mat) # Left braid
			h.box(8, 0, 3, 9, 5, 4, hair_mat) # Right braid

		CharacterPalette.HairStyle.WILD_CURLS:
			# Volumetric textured coastal curls
			h.box(0, 2, 0, 9, 7, 3, hair_mat)
			h.box(0, 4, 3, 1, 7, 7, hair_mat)
			h.box(8, 4, 3, 9, 7, 7, hair_mat)
			h.box(1, 7, 1, 8, 8, 8, hair_mat)


func _build_beard(h: Prefabs.Grid, style: CharacterPalette.BeardStyle, hair_mat: int) -> void:
	match style:
		CharacterPalette.BeardStyle.CLEAN_SHAVEN:
			pass

		CharacterPalette.BeardStyle.STUBBLE:
			# Thin jaw outline
			h.box(2, 0, 7, 7, 0, 7, hair_mat)
			h.setv(1, 1, 7, hair_mat)
			h.setv(8, 1, 7, hair_mat)

		CharacterPalette.BeardStyle.MUTTON_CHOPS:
			# Sideburns down to jaw
			h.box(1, 0, 5, 2, 3, 7, hair_mat)
			h.box(7, 0, 5, 8, 3, 7, hair_mat)

		CharacterPalette.BeardStyle.FULL_SALT_BUSH:
			# Full bushy beard protruding forward
			h.box(1, 0, 7, 8, 2, 8, hair_mat)
			h.box(3, 2, 8, 6, 2, 8, hair_mat) # Mustache
			h.box(2, 0, 5, 2, 3, 6, hair_mat)
			h.box(7, 0, 5, 7, 3, 6, hair_mat)

		CharacterPalette.BeardStyle.BRAIDED_BEARD:
			# Chin goatee extending downward
			h.box(3, 0, 7, 6, 1, 8, hair_mat)
			h.box(4, 0, 8, 5, 0, 8, Palette.METAL) # Bone/metal ring

		CharacterPalette.BeardStyle.ANCHOR_GOATEE:
			# Mustache + chin strap
			h.box(3, 2, 7, 6, 2, 8, hair_mat)
			h.box(3, 0, 7, 6, 0, 8, hair_mat)


func _build_hat(h: Prefabs.Grid, style: CharacterPalette.HatStyle, hat_mat: int) -> void:
	match style:
		CharacterPalette.HatStyle.NONE:
			pass

		CharacterPalette.HatStyle.SOUWESTER:
			h.box(1, 6, 1, 8, 8, 7, hat_mat)             # Crown
			h.box(0, 6, 0, 9, 6, 9, hat_mat)             # Wide Brim
			h.box(0, 5, 0, 9, 5, 0, hat_mat)             # Back Neck Flap
			h.box(2, 9, 2, 7, 9, 6, hat_mat)             # Peak

		CharacterPalette.HatStyle.WATCH_CAP:
			# Beanie snug on head with rolled cuff
			h.box(0, 5, 0, 9, 6, 8, hat_mat)             # Rolled cuff
			h.box(1, 7, 1, 8, 8, 7, hat_mat)             # Crown
			h.box(3, 9, 3, 6, 9, 5, hat_mat)

		CharacterPalette.HatStyle.FISHER_CAP:
			# Mariner peaked cap with visor
			h.box(1, 6, 1, 8, 7, 7, hat_mat)
			h.box(1, 5, 7, 8, 5, 9, Palette.DARK_WOOD)   # Leather visor brim

		CharacterPalette.HatStyle.HEADBAND:
			# Sailor's bandana wrapped around forehead
			h.box(0, 5, 0, 9, 5, 8, hat_mat)
			h.box(0, 4, 0, 1, 5, 0, hat_mat)             # Knot tail


func _build_tool_arsenal() -> void:
	# 0. Pickaxe
	var pk := _grid(5, 9, 1)
	pk.box(2, 0, 0, 2, 7, 0, Palette.HANDLE)
	pk.box(0, 7, 0, 4, 7, 0, Palette.METAL)
	pk.setv(0, 6, 0, Palette.METAL)
	pk.setv(4, 6, 0, Palette.METAL)
	tool_pick = _tool(pk)

	# 1. Hammer
	var hm := _grid(4, 8, 2)
	hm.box(1, 0, 0, 1, 6, 0, Palette.HANDLE)
	hm.box(0, 6, 0, 3, 7, 1, Palette.METAL)
	tool_hammer = _tool(hm)

	# 2. Blueprint Plan
	var pl := _grid(4, 5, 1)
	pl.box(0, 0, 0, 3, 4, 0, Palette.WHITEWASH)
	pl.box(1, 1, 0, 2, 3, 0, Palette.ROOF_BLUE)
	tool_plan = _tool(pl)

	# 3. Fishing Rod
	var rd := _grid(2, 11, 1)
	rd.box(0, 0, 0, 0, 9, 0, Palette.HANDLE)
	rd.setv(0, 10, 0, Palette.METAL)                  # Guide ring
	rd.setv(1, 2, 0, Palette.METAL)                   # Reel
	tool_rod = _tool(rd)

	# 4. Farming Hoe
	var he := _grid(4, 9, 2)
	he.box(1, 0, 0, 1, 7, 0, Palette.HANDLE)
	he.box(0, 7, 0, 3, 7, 1, Palette.METAL)
	tool_hoe = _tool(he)

	# 5. Corsair Cutlass (Slender curved blade with brass guard)
	var ct := _grid(3, 10, 1)
	ct.box(1, 0, 0, 1, 2, 0, Palette.DARK_WOOD)     # Hilt
	ct.box(0, 2, 0, 2, 2, 0, Palette.FLOWER_Y)       # Brass guard
	ct.box(1, 3, 0, 1, 8, 0, Palette.METAL)          # Steel blade
	ct.setv(2, 7, 0, Palette.METAL)                  # Curved tip
	ct.setv(1, 9, 0, Palette.METAL)
	tool_cutlass = _tool(ct)

	# 6. Barbed Harpoon (Long shaft, metal barb head)
	var hp := _grid(3, 13, 1)
	hp.box(1, 0, 0, 1, 10, 0, Palette.HANDLE)        # Long shaft
	hp.box(0, 10, 0, 2, 11, 0, Palette.METAL)        # Barbs
	hp.setv(1, 12, 0, Palette.METAL)                 # Spear point
	tool_harpoon = _tool(hp)

	# 7. Anchor Maul (Massive block bludgeon)
	var ml := _grid(5, 9, 3)
	ml.box(2, 0, 1, 2, 6, 1, Palette.DARK_WOOD)     # Handle
	ml.box(0, 6, 0, 4, 8, 2, Palette.STONE)         # Heavy stone/iron head
	ml.box(1, 7, 0, 3, 7, 2, Palette.METAL)          # Reinforcing band
	tool_maul = _tool(ml)

	# 8. Phosphor Lantern Staff
	var lt := _grid(3, 10, 3)
	lt.box(1, 0, 1, 1, 7, 1, Palette.HANDLE)
	lt.box(0, 7, 0, 2, 9, 2, Palette.METAL)          # Cage
	lt.setv(1, 8, 1, Palette.LANTERN)                # Glowing core
	tool_lantern = _tool(lt)

	# 9. Hatchet / Axe
	var ax := _grid(4, 9, 1)
	ax.box(1, 0, 0, 1, 7, 0, Palette.HANDLE)
	ax.box(1, 5, 0, 3, 7, 0, Palette.METAL)
	ax.setv(3, 4, 0, Palette.METAL)
	tool_axe = _tool(ax)

	# 10. Shovel
	var sv := _grid(3, 9, 1)
	sv.box(1, 0, 0, 1, 6, 0, Palette.HANDLE)
	sv.box(0, 6, 0, 2, 8, 0, Palette.METAL)
	tool_shovel = _tool(sv)

	# 11. Whittled Shore Bow
	var bw := _grid(3, 11, 2)
	bw.box(1, 0, 0, 1, 10, 0, Palette.DARK_WOOD)
	bw.setv(1, 0, 1, Palette.HANDLE)
	bw.setv(1, 10, 1, Palette.HANDLE)
	bw.box(1, 1, 1, 1, 9, 1, Palette.METAL)
	tool_bow = _tool(bw)

	# 12. Sea-Dog's Flintlock Pistol
	var fl := _grid(3, 7, 2)
	fl.box(1, 0, 0, 1, 3, 1, Palette.DARK_WOOD)
	fl.box(1, 4, 0, 1, 6, 0, Palette.METAL)
	fl.setv(1, 3, 1, Palette.METAL)
	tool_flintlock = _tool(fl)

	# Offhand Boarding Shield (strapped to arm_l)
	var sh := _grid(6, 8, 2)
	sh.box(0, 0, 0, 5, 7, 0, Palette.PLANK)
	sh.box(0, 0, 1, 5, 7, 1, Palette.METAL)
	shield_node = Node3D.new()
	shield_node.position = Vector3(0.5, -3.5, 0) * U
	shield_node.rotation = Vector3(0, PI * 0.5, 0)
	arm_l.add_child(shield_node)
	_part(shield_node, sh, Vector3(-3, -4, -1))
	shield_node.visible = false

	# Offhand Lantern (held in left hand)
	var lt2 := _grid(3, 8, 3)
	lt2.box(1, 0, 1, 1, 5, 1, Palette.HANDLE)
	lt2.box(0, 5, 0, 2, 7, 2, Palette.METAL)
	lt2.setv(1, 6, 1, Palette.LANTERN)
	offhand_lantern = Node3D.new()
	offhand_lantern.position = Vector3(0, -5.5, 0.5) * U
	offhand_lantern.rotation = Vector3(PI * 0.5, 0, 0)
	arm_l.add_child(offhand_lantern)
	_part(offhand_lantern, lt2, Vector3(-1.5, -1, -1.5))
	offhand_lantern.visible = false


func _part(parent: Node3D, g: Prefabs.Grid, offset_u: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, _mat, _mat)
	mi.position = offset_u * U
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot_u: Vector3, upper: int, lower: int, w: int, hgt: int, d: int, lower_h: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_u * U
	parent.add_child(pivot)
	var g := _grid(w, hgt, d)
	g.box(0, 0, 0, w - 1, hgt - 1, d - 1, upper)
	g.box(0, 0, 0, w - 1, lower_h - 1, d - 1, lower)
	_part(pivot, g, Vector3(-w * 0.5, -hgt, -d * 0.5))
	return pivot


func _tool(g: Prefabs.Grid) -> Node3D:
	var n := Node3D.new()
	# Hand is at bottom of arm; tool points forward out of the fist.
	n.position = Vector3(0, -5.5, 0.5) * U
	n.rotation = Vector3(PI * 0.5, 0, 0)
	arm_r.add_child(n)
	_part(n, g, Vector3(-g.sx * 0.5, -1, -g.sz * 0.5))
	return n


func set_tool(i: int) -> void:
	_current_tool_idx = i
	if tool_pick == null:
		return
	tool_pick.visible = (i == 0)
	tool_hammer.visible = (i == 1)
	tool_plan.visible = (i == 2)
	if tool_rod: tool_rod.visible = (i == 3)
	if tool_hoe: tool_hoe.visible = (i == 4)
	if tool_cutlass: tool_cutlass.visible = (i == 5)
	if tool_harpoon: tool_harpoon.visible = (i == 6)
	if tool_maul: tool_maul.visible = (i == 7)
	if tool_lantern: tool_lantern.visible = (i == 8)
	if tool_axe: tool_axe.visible = (i == 9)
	if tool_shovel: tool_shovel.visible = (i == 10)
	if tool_bow: tool_bow.visible = (i == 11)
	if tool_flintlock: tool_flintlock.visible = (i == 12)


func set_backpack_visible(is_visible: bool) -> void:
	if backpack_node:
		backpack_node.visible = is_visible


func set_diving_helmet_visible(is_visible: bool) -> void:
	if diving_helmet_node:
		diving_helmet_node.visible = is_visible


func set_shield_visible(is_visible: bool) -> void:
	if shield_node:
		shield_node.visible = is_visible


func set_offhand_lantern_visible(is_visible: bool) -> void:
	if offhand_lantern:
		offhand_lantern.visible = is_visible


## Shows worn gear on the model (backpack, diving helmet, shield / lantern).
## One mapping for the player in the world and the Pack page preview.
func apply_equipment(inv: Inventory) -> void:
	if inv == null:
		return
	var pack: ItemSlot = inv.equipment.get(&"backpack", null)
	set_backpack_visible(pack != null and not pack.is_empty())
	var head: ItemSlot = inv.equipment.get(&"head", null)
	set_diving_helmet_visible(head != null and (head.item_id == &"deep_diving_helmet" or head.item_id == &"diving_rebreather"))
	var acc: ItemSlot = inv.equipment.get(&"accessory", null)
	var acc_def: ItemDef = ItemDB.get_item(acc.item_id) if acc != null and not acc.is_empty() else null
	set_shield_visible(acc_def != null and acc_def.has_tag("shield"))
	set_offhand_lantern_visible(acc_def != null and acc_def.has_tag("light"))


func animate_bow_draw(charge: float) -> void:
	if charge < 0.0:
		return
	var c := clampf(charge, 0.0, 1.0)
	arm_l.rotation.x = -1.45
	arm_l.rotation.y = 0.20
	arm_l.rotation.z = -0.15
	arm_r.rotation.x = -1.20 - c * 0.25
	arm_r.rotation.y = -0.40 * c
	arm_r.rotation.z = 0.50 * c


func swing() -> void:
	_swing = 1.0
	_swing_step = 0
	_swing_charged = false


func swing_attack(step: int = 1, is_charged: bool = false, is_thrust: bool = false) -> void:
	swing()
	_swing_charged = is_charged
	if is_thrust:
		_swing_step = 4
	elif is_charged or step == 3:
		_swing_step = 3
	else:
		_swing_step = step if step >= 1 and step <= 2 else 1


## Rig sign conventions: +rotation.x on the body pitches it forward (face toward the ground);
## -rotation.x on a limb swings it forward. The model faces +Z.
## prog 0..1 drives one dodge; prog < 0 resets the pose for the regular animator.
func animate_dodge(prog: float, is_hop: bool = false) -> void:
	if body == null or head == null or leg_l == null or leg_r == null or arm_l == null or arm_r == null:
		return
	if prog < 0.0 or prog > 1.0:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
		body.scale = Vector3.ONE
		head.rotation = Vector3.ZERO
		head.position = HEAD_PIVOT * U
		head.scale = Vector3.ONE
		for limb: Node3D in [leg_l, leg_r, arm_l, arm_r]:
			limb.rotation = Vector3.ZERO
		return
	if is_hop:
		_pose_backstep(prog)
	else:
		_pose_roll(prog)
	_rest_on_ground()


## Forward tuck-and-roll: dive with arms out, curl into a ball and tumble once over the
## shoulder, plant into a low split-stance crouch, then rise.
func _pose_roll(p: float) -> void:
	var dive := smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.1, 0.28, p))
	var tuck := smoothstep(0.06, 0.24, p) * (1.0 - smoothstep(0.6, 0.78, p))
	var land := smoothstep(0.6, 0.78, p) * (1.0 - smoothstep(0.84, 1.0, p))
	var spin := TAU * smoothstep(0.06, 0.74, p)   # one full forward somersault

	body.rotation = Vector3(spin + 0.45 * dive + 0.42 * land, 0.0, 0.28 * sin(spin * 0.5) * tuck)
	body.scale = Vector3(1.0 + 0.05 * tuck, 1.0 - 0.14 * tuck, 1.0 + 0.05 * tuck)   # curl up
	# Spin about the curled body's middle (torso centre), not the feet.
	var centre := Vector3(0.0, 8.0 * U, 0.0)
	body.position = Vector3(0.0, 0.0, -(body.basis * centre).z)

	# Chin to chest (head pulled down into the shoulders so the ball stays round), then eyes up.
	head.rotation = Vector3(1.35 * tuck + 0.2 * dive - 0.45 * land, 0.0, 0.0)
	# The chibi head is as long as the torso, so it also sinks into the collar and shrinks a
	# touch while curled; at roll speed this reads as a tight tuck rather than a headstand.
	head.position = (HEAD_PIVOT + Vector3(0.0, -4.5, 1.0) * tuck) * U
	head.scale = Vector3.ONE * (1.0 - 0.15 * tuck)
	# Knees to chest in the tuck; one leg forward / one back when landing.
	leg_l.rotation = Vector3(-2.15 * tuck + (-0.85 - 0.42) * land - 0.25 * dive, 0.0, 0.0)
	leg_r.rotation = Vector3(-2.15 * tuck + (0.85 - 0.42) * land + 0.3 * dive, 0.0, 0.0)
	# Reach out into the dive, hug the shins through the tumble, brace forward on landing.
	var arm_x := -2.2 * dive - 1.15 * tuck - 0.6 * land
	arm_l.rotation = Vector3(arm_x, 0.0, -0.1 * dive - 0.35 * tuck - 0.25 * land)
	arm_r.rotation = Vector3(arm_x, 0.0, 0.1 * dive + 0.35 * tuck + 0.25 * land)


## No direction held: a quick crouched backstep hop, torso braced forward, guard up.
func _pose_backstep(p: float) -> void:
	var crouch := smoothstep(0.0, 0.18, p) * (1.0 - smoothstep(0.75, 1.0, p))
	var air := sin(clampf((p - 0.12) / 0.6, 0.0, 1.0) * PI)
	body.scale = Vector3.ONE
	body.rotation = Vector3(0.32 * crouch, 0.0, 0.0)
	body.position = Vector3.ZERO
	head.rotation = Vector3(-0.25 * crouch, 0.0, 0.0)
	head.position = HEAD_PIVOT * U
	head.scale = Vector3.ONE
	# Bent-knee stance; feet swing forward while airborne (body travels backward).
	leg_l.rotation = Vector3(-0.32 * crouch - 0.55 * air, 0.0, 0.0)
	leg_r.rotation = Vector3(0.25 * crouch - 0.3 * air, 0.0, 0.0)
	arm_l.rotation = Vector3(-1.0 * crouch, 0.0, -0.3 * crouch)
	arm_r.rotation = Vector3(-1.15 * crouch, 0.0, 0.3 * crouch)
	_hop_lift = 0.38 * air   # added on top of ground contact


## Drop / raise the body so its lowest point touches the ground (model origin = feet),
## so the roll stays in contact with the floor instead of floating or sinking.
func _rest_on_ground() -> void:
	var lift := _hop_lift
	_hop_lift = 0.0
	body.position.y = 0.0
	var bx := body.transform
	var lowest := INF
	var back := -3.6 if (backpack_node != null and backpack_node.visible) else -2.0
	for x: float in [-3.0, 3.0]:
		for y: float in [5.0, 11.0]:
			for z: float in [back, 2.2]:
				lowest = minf(lowest, (bx * (Vector3(x, y, z) * U)).y)
	var hx := bx * head.transform
	for x: float in [-4.0, 4.0]:
		for y: float in [0.0, 8.5]:
			for z: float in [-4.0, 4.5]:
				lowest = minf(lowest, (hx * (Vector3(x, y, z) * U)).y)
	for leg: Node3D in [leg_l, leg_r]:
		var lx := bx * leg.transform
		for z: float in [-1.5, 1.5]:
			lowest = minf(lowest, (lx * (Vector3(0.0, -5.0, z) * U)).y)
	for arm: Node3D in [arm_l, arm_r]:
		lowest = minf(lowest, ((bx * arm.transform) * (Vector3(0.0, -6.0, 0.0) * U)).y)
	body.position.y = -lowest + lift


func cast_line() -> void:
	_cast_anim = 1.0


func set_fishing_state(state: int, power: float) -> void:
	_fishing_state = state
	_fishing_power = clampf(power, 0.0, 1.0)


var _first_person_view := false


func set_first_person_view(fp: bool) -> void:
	if _first_person_view == fp:
		return
	_first_person_view = fp
	if head != null:
		head.visible = not fp
	if body != null and body.get_child_count() > 0 and body.get_child(0) is MeshInstance3D:
		(body.get_child(0) as MeshInstance3D).visible = not fp
	if arm_l != null:
		arm_l.visible = not fp
	if leg_l != null:
		leg_l.visible = not fp
	if leg_r != null:
		leg_r.visible = not fp
	if arm_r != null:
		arm_r.position = (Vector3(3.4, 15.6, 2.6) if fp else Vector3(4.0, 10.5, 0.0)) * U


## speed: horizontal m/s. Call every frame.
func animate(delta: float, speed: float, on_ground: bool, swimming: bool) -> void:
	_crouch = move_toward(_crouch, 1.0 if crouching and on_ground and not swimming else 0.0, delta * 6.0)
	var moving := clampf(speed / 4.5, 0.0, 1.4)
	_phase += delta * (4.0 + speed * (1.9 + 2.2 * _crouch))   # short, quick creeping steps
	var s := sin(_phase)
	var target_leg := s * 0.75 * moving
	var bob := absf(cos(_phase)) * 0.05 * moving
	var arm_l_x := -s * 0.6 * moving
	var arm_r_x := s * 0.6 * moving
	var arm_spread := 0.08
	if swimming:
		target_leg = s * 0.35
		arm_l_x = -1.6 + sin(_phase * 0.7) * 0.6
		arm_r_x = -1.6 - sin(_phase * 0.7) * 0.6
		arm_spread = 0.5
		bob = sin(_phase * 0.5) * 0.04
	elif not on_ground:
		target_leg = 0.35
		arm_l_x = -0.5
		arm_r_x = -0.5
		arm_spread = 0.5
	elif moving < 0.05:
		bob = sin(_phase * 0.35) * 0.012  # idle breathing
	var arm_r_y := 0.0
	var arm_r_z := arm_spread
	var body_twist := 0.0
	var arm_thrust_z := 0.0
	var body_lean := 0.0

	# action swing overrides the right arm & upper body
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta * (3.4 if _swing_step == 3 else 4.6))
		var k := _swing
		var p := 1.0 - _swing
		if _swing_step == 0:
			arm_r_x = -0.3 - 2.2 * sin(k * PI) * (0.6 + 0.4 * k)
		elif _swing_step == 1:
			# Combo 1: Horizontal right-to-left forehand slash
			arm_r_x = -0.55 - 0.35 * sin(p * PI)
			arm_r_y = lerpf(0.9, -1.2, sin(p * PI * 0.5))
			arm_r_z = 0.28 * sin(p * PI)
			body_twist = lerpf(0.2, -0.28, p)
		elif _swing_step == 2:
			# Combo 2: Upward diagonal backhand slash
			arm_r_x = lerpf(0.35, -1.75, sin(p * PI * 0.6))
			arm_r_y = lerpf(-0.85, 0.75, p)
			arm_r_z = -0.38 * sin(p * PI)
			body_twist = lerpf(-0.22, 0.22, p)
		elif _swing_step == 3:
			# Combo 3 / Charged / Maul: Heavy overhead cleave with full body commitment
			if p < 0.32:
				var wp := p / 0.32
				arm_r_x = lerpf(-0.3, -2.45, wp)
				arm_l_x = lerpf(-0.3, -2.1, wp)
				body_lean = lerpf(0.0, -0.25, wp)
			else:
				var sp := (p - 0.32) / 0.68
				arm_r_x = lerpf(-2.45, 0.5, sin(sp * PI * 0.5))
				arm_l_x = lerpf(-2.1, 0.35, sin(sp * PI * 0.5))
				body_lean = lerpf(-0.25, 0.38, sin(sp * PI * 0.5))
		elif _swing_step == 4:
			# Harpoon: Linear high-speed thrust
			var thrust_p := sin(p * PI)
			arm_r_x = -1.55
			arm_r_y = 0.05
			arm_r_z = 0.0
			arm_thrust_z = 4.2 * thrust_p
			body_lean = 0.22 * thrust_p
	var body_lean_val: float = 0.9 if swimming else (body_lean + 0.06 * moving)
	if _current_tool_idx == 3:
		if _cast_anim > 0.0:
			_cast_anim = maxf(0.0, _cast_anim - delta * 2.4)
			var p := 1.0 - _cast_anim
			if p < 0.35:
				var wt := p / 0.35
				arm_r_x = lerpf(0.85, -1.55, sin(wt * PI * 0.5))
				body_lean_val = lerpf(-0.16, 0.22, wt)
			else:
				var ft := (p - 0.35) / 0.65
				arm_r_x = lerpf(-1.55, -0.78, smoothstep(0.0, 1.0, ft))
				body_lean_val = lerpf(0.22, 0.04, ft)
			arm_l_x = -0.45
		elif _fishing_state == 1: # CASTING (winding up)
			arm_r_x = lerpf(-0.35, 0.95, _fishing_power)
			arm_l_x = lerpf(-0.15, -0.55, _fishing_power)
			body_lean_val = lerpf(0.0, -0.16, _fishing_power)
		elif _fishing_state == 2 or _fishing_state == 3 or _fishing_state == 4: # WAITING / NIBBLING / HOOK_WINDOW
			var twitch := sin(_phase * 6.0) * 0.12 if _fishing_state >= 3 else sin(_phase * 0.8) * 0.03
			arm_r_x = -0.78 + twitch
			arm_l_x = -0.45
		elif _fishing_state == 5: # REELING
			arm_r_x = -0.95 + sin(_phase * 2.4) * 0.32
			arm_l_x = -0.82 + cos(_phase * 5.0) * 0.24
			body_lean_val = -0.08 + sin(_phase * 2.4) * 0.06
	var f := 1.0 - exp(-delta * 14.0)
	var leg_l_x := target_leg
	var leg_r_x := -target_leg
	if _crouch > 0.0:
		# Low creeping stride: one leg forward, one back (feet stay on the ground with the hips
		# down), a small swing while moving. Legs hang off the torso, so undo its lean.
		var c := smoothstep(0.0, 1.0, _crouch)
		var stride := s * 0.3 * moving
		leg_l_x = lerpf(target_leg, -CROUCH_STANCE + stride - CROUCH_LEAN, c)
		leg_r_x = lerpf(-target_leg, CROUCH_STANCE - stride - CROUCH_LEAN, c)
		if _swing <= 0.0:
			arm_l_x = lerpf(arm_l_x, -0.55 - s * 0.15 * moving, c)
			arm_r_x = lerpf(arm_r_x, -0.55 + s * 0.15 * moving, c)
		body_lean_val = lerpf(body_lean_val, CROUCH_LEAN + body_lean, c)
		bob *= 1.0 - 0.6 * c
	leg_l.rotation.x = lerpf(leg_l.rotation.x, leg_l_x, f)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, leg_r_x, f)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, arm_l_x, f)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_r_x, f * (2.0 if _swing > 0.0 else 1.0))
	arm_r.rotation.y = lerpf(arm_r.rotation.y, arm_r_y, f * (2.0 if _swing > 0.0 else 1.0))
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -arm_spread, f)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, arm_r_z, f * (2.0 if _swing > 0.0 else 1.0))
	var cs := smoothstep(0.0, 1.0, _crouch)
	body.position.y = bob - crouch_drop() * cs
	head.rotation.x = lerpf(head.rotation.x, 0.15 if swimming else -CROUCH_LEAN * 0.7 * cs, f)   # eyes up while crouched
	body.rotation.x = lerpf(body.rotation.x, body_lean_val, f)
	body.rotation.y = lerpf(body.rotation.y, body_twist, f * (2.0 if _swing > 0.0 else 1.0))
	if _swing_step == 4 or arm_thrust_z > 0.0:
		var base_pos := (Vector3(3.4, 15.6, 2.6) if _first_person_view else Vector3(4.0, 10.5, 0.0)) * U
		arm_r.position = base_pos + Vector3(0, 0, arm_thrust_z * U)


## How far the hips sit below standing when fully crouched, so the feet touch the ground.
static func crouch_drop() -> float:
	var hip := 5.0 * U   # leg pivot height; legs are as long as that
	return hip * cos(CROUCH_LEAN) - hip * cos(CROUCH_STANCE)


## How much lower the eyes are when fully crouched (for the camera).
static func crouch_eye_drop() -> float:
	var eye := 1.5
	return eye - eye * cos(CROUCH_LEAN) + crouch_drop()


## Seated pose for boats: thighs forward, arms reaching for the oars.
## row_phase drives the stroke; row_power 0..1 blends from resting to full rowing.
func animate_seated(delta: float, row_phase: float, row_power: float) -> void:
	var f := 1.0 - exp(-delta * 12.0)
	var pull := sin(row_phase)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.45, f)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.45, f)
	var arm := -1.25 + pull * 0.45 * row_power
	arm_l.rotation.x = lerpf(arm_l.rotation.x, lerpf(-0.9, arm, row_power), f)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, lerpf(-0.9, arm, row_power), f)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.25, f)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.25, f)
	body.position.y = 0.0
	body.rotation.x = lerpf(body.rotation.x, -pull * 0.16 * row_power, f)
	head.rotation.x = lerpf(head.rotation.x, pull * 0.08 * row_power, f)
	set_tool(-1)
