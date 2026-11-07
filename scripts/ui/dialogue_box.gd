class_name DialogueBox
extends CanvasLayer
## Parchment dialogue panel at the bottom of the screen: speaker, text (typed out),
## and choice buttons. Freezes player input while open.
##   say(speaker, text, [["Continue", callable], ...])

var main: Node
var _root: Control
var _speaker: Label
var _text: Label
var _choices: HBoxContainer
var _open := false
var _reveal := 1.0


func setup(p_main: Node) -> void:
	main = p_main
	layer = 17
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.prepare(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var anchor := CenterContainer.new()
	anchor.anchor_top = 1.0
	anchor.anchor_bottom = 1.0
	anchor.anchor_right = 1.0
	anchor.offset_top = -300
	anchor.offset_bottom = -110
	_root.add_child(anchor)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Parchment"
	panel.custom_minimum_size = Vector2(720, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	anchor.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_speaker = Label.new()
	_speaker.theme_type_variation = &"InkLabel"
	_speaker.add_theme_font_override("font", UiTheme.font(800))
	_speaker.add_theme_font_size_override("font_size", 21)
	_speaker.add_theme_color_override("font_color", Color8(140, 70, 40))
	v.add_child(_speaker)
	_text = Label.new()
	_text.theme_type_variation = &"InkLabel"
	_text.add_theme_font_size_override("font_size", 18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.custom_minimum_size = Vector2(680, 0)
	v.add_child(_text)
	_choices = HBoxContainer.new()
	_choices.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_choices)


func is_open() -> bool:
	return _open


func say(speaker: String, text: String, choices: Array = []) -> void:
	_speaker.text = speaker
	_text.text = text
	_text.visible_ratio = 0.0
	_reveal = 0.0
	for c in _choices.get_children():
		c.queue_free()
	if choices.is_empty():
		choices = [["Continue", close]]
	var first: Button = null
	for ch: Array in choices:
		var b := Button.new()
		b.text = ch[0]
		var cb: Callable = ch[1]
		b.pressed.connect(func() -> void: cb.call())
		_choices.add_child(b)
		if first == null:
			first = b
	_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if main.player != null:
		main.player.input_enabled = false
	if first != null:
		first.call_deferred("grab_focus")


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if main.player != null:
		main.player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _open and _reveal < 1.0:
		_reveal = minf(1.0, _reveal + delta * 90.0 / maxf(20.0, _text.text.length()))
		_text.visible_ratio = _reveal


func _unhandled_input(e: InputEvent) -> void:
	if not _open:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu_toggle"):
		close()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("interact") and _reveal < 1.0:
		_reveal = 1.0
		_text.visible_ratio = 1.0
		get_viewport().set_input_as_handled()
