class_name Minimap
extends Control
## Diegetic Nautical Parchment Minimap for Brine's Hollow.
## Activates only when a nautical chart is equipped in the dedicated map equipment slot.
## Tier 1 (Parchment Shore Chart): Coastline silhouette, player position, cardinal compass rose.
## Tier 2 (Hydrographic Sea Chart): Bathymetric depth contours, intertidal tide line, boat markers.
## Tier 3 (Master Chronometer Chart): Topography elevation rings, landmark pins, peer pings, soundings.

const CREAM := Color(0.96, 0.92, 0.82)
const PARCHMENT_BG := Color(0.91, 0.86, 0.74, 0.96)
const PARCHMENT_BORDER := Color(0.26, 0.19, 0.14, 0.90)
const BRASS_ACCENT := Color(0.85, 0.65, 0.28)
const SEA_COLOR := Color(0.50, 0.62, 0.70)
const INTERTIDAL_COLOR := Color(0.68, 0.68, 0.58)
const BEACH_COLOR := Color(0.86, 0.80, 0.66)
const GRASS_COLOR := Color(0.74, 0.80, 0.66)
const ROCK_COLOR := Color(0.64, 0.58, 0.50)
const PEAK_COLOR := Color(0.50, 0.46, 0.40)

var chart_tier: int = 0 ## 0 = unequipped / disabled, 1 = Tier 1, 2 = Tier 2, 3 = Tier 3
var chart_name: String = ""

var player_pos: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var water_level: float = 0.0
var world_size_m: Vector2 = Vector2(414.0, 414.0)

var chart_texture: ImageTexture
var _texture_generated: bool = false
var _texture_size: int = 128

var landmarks: Array[Dictionary] = []
var boats: Array[Vector3] = []
var peer_positions: Array[Vector3] = []

var depth_sounding: float = 0.0

var _readout_label: Label
var _tier_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(190, 220)
	size = Vector2(190, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tier_label = Label.new()
	_tier_label.position = Vector2(0, 0)
	_tier_label.size = Vector2(190, 18)
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_font_size_override("font_size", 11)
	_tier_label.add_theme_color_override("font_color", BRASS_ACCENT)
	_tier_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_tier_label.add_theme_constant_override("outline_size", 4)
	add_child(_tier_label)

	_readout_label = Label.new()
	_readout_label.position = Vector2(0, 192)
	_readout_label.size = Vector2(190, 24)
	_readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout_label.add_theme_font_size_override("font_size", 10)
	_readout_label.add_theme_color_override("font_color", CREAM)
	_readout_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_readout_label.add_theme_constant_override("outline_size", 4)
	add_child(_readout_label)


## Generates a 128x128 topographical chart texture from the VoxelWorld terrain column heights.
func bake_chart_texture(world: VoxelWorld) -> void:
	if world == null or world.gen == null:
		return

	var gen: WorldGen = world.gen
	var img := Image.create(_texture_size, _texture_size, false, Image.FORMAT_RGBA8)

	var wx: int = VoxelWorld.WX
	var wz: int = VoxelWorld.WZ
	world_size_m = Vector2(wx * VoxelWorld.VS, wz * VoxelWorld.VS)

	var sea_mid: float = VoxelWorld.SEA_MID
	var sea_low: float = VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP
	var sea_high: float = VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP

	for pz in range(_texture_size):
		var vz: int = int((float(pz) / float(_texture_size)) * float(wz))
		for px in range(_texture_size):
			var vx: int = int((float(px) / float(_texture_size)) * float(wx))
			var h: int = gen.col_h(vx, vz)
			var col: Color

			if h < sea_low:
				# Deep ocean / benthic floor
				col = SEA_COLOR
			elif h <= sea_high:
				# Intertidal littoral zone
				col = INTERTIDAL_COLOR
			elif h <= sea_high + 4:
				# Coastal sandy beach
				col = BEACH_COLOR
			elif h <= sea_high + 16:
				# Grassy coastal meadow
				col = GRASS_COLOR
			elif h <= sea_high + 30:
				# Rocky limestone bluff / cliff
				col = ROCK_COLOR
			else:
				# High mountain crest
				col = PEAK_COLOR

			img.set_pixel(px, pz, col)

	chart_texture = ImageTexture.create_from_image(img)
	_texture_generated = true
	queue_redraw()


## Updates chart tier, player position, tide, and landmarks.
func update_state(
	p_tier: int,
	p_name: String,
	p_player_pos: Vector3,
	p_yaw: float,
	p_water_level: float,
	p_landmarks: Array[Dictionary] = [],
	p_boats: Array[Vector3] = [],
	p_peers: Array[Vector3] = []
) -> void:
	var prev_tier: int = chart_tier
	chart_tier = p_tier
	chart_name = p_name
	player_pos = p_player_pos
	player_yaw = p_yaw
	water_level = p_water_level
	landmarks = p_landmarks
	boats = p_boats
	peer_positions = p_peers

	visible = (chart_tier > 0)
	if not visible:
		return

	_tier_label.text = chart_name.to_upper()

	depth_sounding = maxf(0.0, water_level - player_pos.y)
	if chart_tier == 1:
		_readout_label.text = "Shore Chart • %s" % _get_compass_bearing(player_yaw)
	elif chart_tier == 2:
		_readout_label.text = "Depth: %.1fm • %s" % [depth_sounding, _get_compass_bearing(player_yaw)]
	else:
		_readout_label.text = "X:%.0f Z:%.0f Alt:%.0fm • %s" % [
			player_pos.x, player_pos.z, player_pos.y, _get_compass_bearing(player_yaw)
		]

	queue_redraw()


func _get_compass_bearing(yaw: float) -> String:
	# In Brine's Hollow: -Z is North, +Z is South, +X is East, -X is West.
	var fwd_x: float = -sin(yaw)
	var fwd_z: float = -cos(yaw)
	var ang_rad: float = atan2(fwd_x, -fwd_z)
	var deg: float = fposmod(rad_to_deg(ang_rad), 360.0)
	if deg >= 337.5 or deg < 22.5: return "N"
	elif deg < 67.5: return "NE"
	elif deg < 112.5: return "E"
	elif deg < 157.5: return "SE"
	elif deg < 202.5: return "S"
	elif deg < 247.5: return "SW"
	elif deg < 292.5: return "W"
	else: return "NW"


func _draw() -> void:
	if chart_tier <= 0:
		return

	var map_center := Vector2(95, 105)
	var map_radius := 80.0

	# 1. Outer Brass & Stitched Leather Bezel
	draw_circle(map_center, map_radius + 6.0, PARCHMENT_BORDER)
	draw_circle(map_center, map_radius + 4.0, BRASS_ACCENT)
	draw_circle(map_center, map_radius + 1.0, PARCHMENT_BORDER)
	draw_circle(map_center, map_radius, PARCHMENT_BG)

	# 2. Island Chart Texture
	if chart_texture != null:
		var rect := Rect2(map_center - Vector2(map_radius, map_radius), Vector2(map_radius * 2.0, map_radius * 2.0))
		draw_texture_rect(chart_texture, rect, false, Color(1, 1, 1, 0.85))

	# 3. Inner Vignette Ring to blend with parchment bezel
	draw_arc(map_center, map_radius - 1.0, 0.0, TAU, 48, PARCHMENT_BORDER, 2.0, true)

	# 4. Bathymetric & Intertidal Tide Line (Tier 2+)
	if chart_tier >= 2:
		# Draw subtle tide water level contour ring
		var max_high: float = (VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP) * VoxelWorld.VS
		var tide_rel: float = clampf(water_level / max_high, 0.5, 1.0)
		draw_arc(map_center, map_radius * 0.72 * tide_rel, 0.0, TAU, 32, Color(0.25, 0.55, 0.70, 0.4), 1.5, true)

	# 5. Boat Markers (Tier 2+)
	if chart_tier >= 2:
		for b_pos in boats:
			var b_uv := _world_to_minimap(b_pos, map_center, map_radius)
			if b_uv.distance_to(map_center) <= map_radius - 2.0:
				draw_circle(b_uv, 3.5, Color(0.2, 0.1, 0.05, 0.9))
				draw_circle(b_uv, 2.2, Color(0.9, 0.6, 0.2))
				draw_string(ThemeDB.fallback_font, b_uv + Vector2(-3, -4), "⚓", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.15, 0.1, 0.05))

	# 6. Landmark Pins (Tier 3)
	if chart_tier >= 3:
		for lm in landmarks:
			var lm_pos: Vector3 = lm.get("pos", Vector3.ZERO)
			var lm_uv := _world_to_minimap(lm_pos, map_center, map_radius)
			if lm_uv.distance_to(map_center) <= map_radius - 4.0:
				draw_circle(lm_uv, 3.0, Color(0.85, 0.25, 0.25, 0.9))
				draw_circle(lm_uv, 1.5, Color(1, 1, 1))

	# 7. Co-op Peer Markers (Tier 3)
	if chart_tier >= 3:
		for peer_pos in peer_positions:
			var p_uv := _world_to_minimap(peer_pos, map_center, map_radius)
			if p_uv.distance_to(map_center) <= map_radius - 2.0:
				draw_circle(p_uv, 3.0, Color(0.2, 0.75, 0.9, 0.9))
				draw_circle(p_uv, 1.5, Color(1, 1, 1))

	# 8. Compass Rose & Cardinal Ticks
	var north_pt := map_center + Vector2(0, -map_radius + 4.0)
	var south_pt := map_center + Vector2(0, map_radius - 4.0)
	var east_pt := map_center + Vector2(map_radius - 4.0, 0)
	var west_pt := map_center + Vector2(-map_radius + 4.0, 0)

	draw_line(north_pt, north_pt + Vector2(0, 5), Color(0.85, 0.25, 0.25), 2.0)
	draw_line(south_pt, south_pt + Vector2(0, -5), PARCHMENT_BORDER, 1.5)
	draw_line(east_pt, east_pt + Vector2(-5, 0), PARCHMENT_BORDER, 1.5)
	draw_line(west_pt, west_pt + Vector2(5, 0), PARCHMENT_BORDER, 1.5)

	draw_string(ThemeDB.fallback_font, north_pt + Vector2(-4, 13), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.85, 0.25, 0.25))

	# 9. Player Chevron Indicator
	var player_uv := _world_to_minimap(player_pos, map_center, map_radius)
	if player_uv.distance_to(map_center) <= map_radius:
		_draw_player_chevron(player_uv, player_yaw)


func _draw_player_chevron(center_pos: Vector2, yaw: float) -> void:
	var fwd := Vector2(sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)

	var p_tip := center_pos + fwd * 7.0
	var p_left := center_pos - fwd * 4.0 - right * 4.5
	var p_right := center_pos - fwd * 4.0 + right * 4.5
	var p_notch := center_pos - fwd * 1.5

	var chevron_pts := PackedVector2Array([p_tip, p_right, p_notch, p_left])

	# Dark outline
	draw_colored_polygon(chevron_pts, Color(0.15, 0.1, 0.05, 0.9))
	# Inner golden needle
	var inner_tip := center_pos + fwd * 5.5
	var inner_left := center_pos - fwd * 3.0 - right * 3.0
	var inner_right := center_pos - fwd * 3.0 + right * 3.0
	var inner_notch := center_pos - fwd * 1.0
	var inner_pts := PackedVector2Array([inner_tip, inner_right, inner_notch, inner_left])
	draw_colored_polygon(inner_pts, BRASS_ACCENT)


func _world_to_minimap(world_pos: Vector3, map_center: Vector2, map_radius: float) -> Vector2:
	var nx: float = clampf(world_pos.x / world_size_m.x, 0.0, 1.0)
	var nz: float = clampf(world_pos.z / world_size_m.y, 0.0, 1.0)
	var local_x: float = (nx - 0.5) * (map_radius * 2.0)
	var local_z: float = (nz - 0.5) * (map_radius * 2.0)
	return map_center + Vector2(local_x, local_z)
