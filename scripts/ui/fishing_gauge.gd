class_name FishingGauge
extends Control
## Drawn angling gauge that sits above the hotbar while a line is out.
##   CASTING      - power meter that fills as the cast is held
##   NIBBLING     - "get ready" pulse
##   HOOK_WINDOW  - strike timer that drains from full
##   REELING      - tension dial with slack / safe / snap zones, plus a line
##                  track showing the fish being drawn in toward the rod
## Reads a FishingController each frame; owns no game state.

const W := 360.0
const TRACK_H := 14.0

const COL_TRACK := Color(0.10, 0.07, 0.05, 0.70)
const COL_EDGE := Color(0.96, 0.88, 0.70, 0.55)
const COL_SLACK := Color8(110, 170, 220)
const COL_SAFE := Color8(120, 200, 150)
const COL_SNAP := Color8(222, 92, 78)
const COL_TEXT := UiTheme.CREAM
const COL_DIM := UiTheme.CREAM_DIM

## Tension within this margin of a limit counts as "in the warning zone".
const SNAP_WARN := 0.07
const SLACK_WARN := 0.05

var state: int = -1
var cast_power := 0.0
var tension := 0.0
var progress := 0.0          ## 0 = fish at the lure, 1 = fish at the rod
var distance_m := 0.0
var hook_left := 0.0         ## 0..1 of the strike window remaining
var snap_risk := 0.0         ## 0..1 of the snap timer used up
var slip_risk := 0.0         ## 0..1 of the slack timer used up
var thrashing := false
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	visible = false


## Pulls the latest numbers from the controller. Returns true if the gauge should show.
func sync(fc: FishingController, p_cast_power: float, delta: float) -> bool:
	_t += delta
	if fc == null:
		state = -1
	else:
		state = fc.current_state
		cast_power = p_cast_power
		tension = fc.line_tension
		progress = fc.reel_progress
		distance_m = fc.line_distance
		hook_left = clampf(fc.hook_window_timer / FishingController.HOOK_WINDOW_BASE, 0.0, 1.0)
		snap_risk = clampf(fc.high_tension_timer / 0.75, 0.0, 1.0)
		slip_risk = clampf(fc.slack_timer / 1.2, 0.0, 1.0)
		thrashing = fc.fish_stamina_left > 0.0
	var h := 0.0
	match state:
		FishingController.State.CASTING, FishingController.State.NIBBLING, FishingController.State.HOOK_WINDOW:
			h = 44.0
		FishingController.State.REELING:
			h = 78.0
	custom_minimum_size = Vector2(W, h)
	visible = h > 0.0
	if visible:
		queue_redraw()
	return visible


## Short word for the tension the player is holding — shown under the dial.
static func tension_word(t: float) -> String:
	if t >= FishingController.HIGH_TENSION_LIMIT - SNAP_WARN:
		return "Ease off!"
	if t <= FishingController.SLACK_LIMIT + SLACK_WARN:
		return "Slack - reel!"
	return "Steady"


static func tension_color(t: float) -> Color:
	if t >= FishingController.HIGH_TENSION_LIMIT - SNAP_WARN:
		return COL_SNAP
	if t <= FishingController.SLACK_LIMIT + SLACK_WARN:
		return COL_SLACK
	return COL_SAFE


func _draw() -> void:
	var font := UiTheme.font(700)
	match state:
		FishingController.State.CASTING:
			_caption(font, Vector2(0, 14), "CAST", "%d m" % roundi(6.0 + clampf(cast_power, 0.1, 1.0) * 14.0))
			var r := Rect2(0, 22, W, TRACK_H)
			_track(r)
			var fill := Rect2(r.position, Vector2(r.size.x * cast_power, r.size.y))
			draw_rect(fill, UiTheme.BRASS.lerp(Color.WHITE, 0.25 * cast_power))
			for i in range(1, 4):   # quarter ticks
				var x := r.size.x * i / 4.0
				draw_line(Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3), COL_EDGE, 1.0)
			_frame(r)
		FishingController.State.NIBBLING:
			var a := 0.55 + 0.45 * sin(_t * 14.0)
			_centered(font, Vector2(W * 0.5, 28), "Something's nibbling...", 18, Color(COL_TEXT, a))
		FishingController.State.HOOK_WINDOW:
			_centered(font, Vector2(W * 0.5, 16), "BITE!  STRIKE NOW", 18, UiTheme.BRASS)
			var r := Rect2(W * 0.15, 26, W * 0.7, 10)
			_track(r)
			var c := COL_SAFE.lerp(COL_SNAP, 1.0 - hook_left)
			draw_rect(Rect2(r.position, Vector2(r.size.x * hook_left, r.size.y)), c)
			_frame(r)
		FishingController.State.REELING:
			_draw_reeling(font)


func _draw_reeling(font: Font) -> void:
	# --- line track: rod on the left, fish swimming in from the right
	_caption(font, Vector2(0, 14), "LINE", "%.1f m" % distance_m)
	var lr := Rect2(0, 22, W, 10)
	_track(lr)
	var fx := lerpf(lr.end.x - 6.0, lr.position.x + 6.0, progress)
	# Line still out: from the rod (left edge) to the fish. Shrinks as you reel.
	draw_line(Vector2(lr.position.x, lr.get_center().y), Vector2(fx, lr.get_center().y), Color(UiTheme.TEAL, 0.8), 2.0)
	_frame(lr)
	draw_rect(Rect2(lr.position.x - 3, lr.position.y - 3, 4, lr.size.y + 6), UiTheme.BRASS)   # rod tip
	var wiggle := sin(_t * 30.0) * 2.5 if thrashing else 0.0
	_fish_marker(Vector2(fx, lr.get_center().y + wiggle), thrashing)

	# --- tension dial with zones
	var tr := Rect2(0, 44, W, TRACK_H)
	_track(tr)
	var slack_x := tr.size.x * (FishingController.SLACK_LIMIT + SLACK_WARN)
	var snap_x := tr.size.x * (FishingController.HIGH_TENSION_LIMIT - SNAP_WARN)
	draw_rect(Rect2(tr.position, Vector2(slack_x, tr.size.y)), Color(COL_SLACK, 0.45))
	draw_rect(Rect2(tr.position + Vector2(slack_x, 0), Vector2(snap_x - slack_x, tr.size.y)), Color(COL_SAFE, 0.30))
	draw_rect(Rect2(tr.position + Vector2(snap_x, 0), Vector2(tr.size.x - snap_x, tr.size.y)), Color(COL_SNAP, 0.50))
	# Danger timers fill their zone so the player sees how close a snap / slip is.
	if snap_risk > 0.0:
		draw_rect(Rect2(tr.position + Vector2(snap_x, 0), Vector2((tr.size.x - snap_x) * snap_risk, tr.size.y)), COL_SNAP)
	if slip_risk > 0.0:
		draw_rect(Rect2(tr.position, Vector2(slack_x * slip_risk, tr.size.y)), COL_SLACK)
	_frame(tr)
	# Needle
	var nx := tr.position.x + tr.size.x * clampf(tension, 0.0, 1.0)
	var nc := tension_color(tension)
	draw_line(Vector2(nx, tr.position.y - 4), Vector2(nx, tr.end.y + 4), Color(0.1, 0.07, 0.05, 0.9), 5.0)
	draw_line(Vector2(nx, tr.position.y - 4), Vector2(nx, tr.end.y + 4), nc.lerp(Color.WHITE, 0.35), 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(nx - 5, tr.position.y - 9), Vector2(nx + 5, tr.position.y - 9), Vector2(nx, tr.position.y - 3)]), nc)
	# Readout under the dial
	var word := tension_word(tension)
	var flash := 1.0
	if word != "Steady":
		flash = 0.6 + 0.4 * sin(_t * 16.0)
	draw_string(font, Vector2(0, 76), "TENSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
	_centered(font, Vector2(W * 0.5, 76), word, 15, Color(nc.lerp(Color.WHITE, 0.2), flash))
	if thrashing:
		draw_string(font, Vector2(0, 76), "fighting", HORIZONTAL_ALIGNMENT_RIGHT, W, 13, COL_DIM)


# ------------------------------------------------------------- drawing bits

func _track(r: Rect2) -> void:
	draw_rect(r.grow(2.0), Color(0.1, 0.07, 0.05, 0.85))
	draw_rect(r, COL_TRACK)


func _frame(r: Rect2) -> void:
	draw_rect(r.grow(1.0), COL_EDGE, false, 1.0)


func _caption(font: Font, pos: Vector2, left: String, right: String) -> void:
	draw_string(font, pos, left, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
	draw_string(font, Vector2(0, pos.y), right, HORIZONTAL_ALIGNMENT_RIGHT, W, 14, COL_TEXT)


func _centered(font: Font, pos: Vector2, text: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := Vector2(pos.x - w * 0.5, pos.y)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0.1, 0.07, 0.05, col.a * 0.9))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Small side-on fish silhouette (head pointing at the rod, i.e. left).
func _fish_marker(c: Vector2, fighting: bool) -> void:
	var col := UiTheme.BRASS if not fighting else Color8(250, 170, 110)
	var outline := Color(0.1, 0.07, 0.05, 0.95)
	var body := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		body.append(c + Vector2(cos(a) * 9.0, sin(a) * 5.0))
	var tail := PackedVector2Array([c + Vector2(7, 0), c + Vector2(15, -6), c + Vector2(15, 6)])
	for poly in [tail, body]:
		var grown := Geometry2D.offset_polygon(poly, 1.5)
		if not grown.is_empty():
			draw_colored_polygon(grown[0], outline)
	draw_colored_polygon(tail, col)
	draw_colored_polygon(body, col)
	draw_circle(c + Vector2(-5, -1), 1.3, outline)
