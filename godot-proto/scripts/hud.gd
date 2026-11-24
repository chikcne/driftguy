class_name GameHud
extends CanvasLayer

# Complete Driftguy HUD & screens for iOS + Desktop:
# - Top XP bar, Level, Timer, Wrecked kills, Pause & Gyro buttons
# - Bottom gauges (Speed, Hull, Smoke, Nitrous bar + tank pips) & Loadout badges
# - Off-screen War Party / War Rig threat markers (horizon-lock aware!)
# - Damage red flash & Nitrous cyan rush radial vignettes
# - Fixed-to-glass iOS touch controls (Auto Gas, Brake/Rev, Nitro, Drift)
# - Title, Level-Up (3 upgrade cards), Pause, and Game Over screens
# - Collapsible Gyro Tuning drawer + optional Artificial Horizon bar

signal start_pressed
signal retry_pressed
signal pause_pressed
signal resume_pressed
signal mute_pressed
signal recenter_pressed
signal upgrade_picked(upgrade: Upgrades.UpgradeDef)

const THREAT_SIDE_MARGIN := 78.0
const THREAT_VERTICAL_MARGIN := 105.0
const THREAT_TAG_OFFSET := 54.0
const GROUND_FORESHORTENING := 0.8

const LOCK_MODES := [1.0, 0.5, 0.0]
const LOCK_LABELS := ["LOCK 100%", "HALF 50%", "OFF 0%"]
const TILT_ANGLES := [25.0, 38.0, 50.0, 65.0]
const FUSION_VALUES := [0.015, 0.035, 0.08, 0.0]
const FUSION_LABELS := ["SNAPPY", "BALANCED", "FIRM", "PURE GYRO"]

var auto_throttle := true
var zoom_compensation := true
var show_horizon := false
var touch_brake := false
var touch_handbrake := false
var touch_nitro_queued := false

var _stabilizer: GyroStabilizer
var _root: Control

# Overlays
var _hit_rect: ColorRect
var _hit_mat: ShaderMaterial
var _hit_flash := 0.0
var _rush_rect: ColorRect
var _rush_mat: ShaderMaterial
var _rush_kick := 0.0

# Gameplay HUD container
var _hud_layer: Control
var _xp_fill: ColorRect
var _level_label: Label
var _timer_label: Label
var _kills_label: Label
var _speed_label: Label
var _hull_fill: ColorRect
var _hull_label: Label
var _smoke_fill: ColorRect
var _nitro_fill: ColorRect
var _nitro_tanks_box: HBoxContainer
var _nitro_pips: Array[ColorRect] = []
var _nitro_btn: Button
var _auto_gas_btn: Button
var _mute_btn: Button
var _loadout_grid: GridContainer
var _threats_layer: Control
var _threat_markers: Array[ThreatMarker] = []

# Horizon bar (optional verification tool)
var _horizon_anchor: Control
var _horizon_pivot: Control
var _horizon_angle_label: Label

# Gyro tuning drawer
var _tuning_panel: PanelContainer
var _telemetry_label: Label
var _lock_btn: Button
var _tilt_btn: Button
var _fusion_btn: Button
var _zoom_btn: Button
var _horizon_btn: Button
var _invert_btn: Button
var _lock_idx := 0
var _tilt_idx := 1
var _fusion_idx := 1

# Screens
var _title_screen: Control
var _title_btn: Button
var _levelup_screen: Control
var _cards_row: HBoxContainer
var _pause_screen: Control
var _pause_mute_btn: Button
var _gameover_screen: Control
var _gameover_survived: Label
var _gameover_kills: Label
var _gameover_level: Label
var _retry_btn: Button

var _choices: Array[Upgrades.UpgradeDef] = []
var _card_buttons: Array[Button] = []
var _selected_card := 0
var _pulse_clock := 0.0


class ThreatArrow:
	extends Control
	var arrow_color: Color = Palette.SCRAP
	var is_boss: bool = false

	func _draw() -> void:
		var w := 28.0 if is_boss else 21.0
		var h := 32.0 if is_boss else 24.0
		var pts := PackedVector2Array([
			Vector2(-w * 0.5, -h * 0.5),
			Vector2(w * 0.5, 0.0),
			Vector2(-w * 0.5, h * 0.5),
			Vector2(-w * 0.16, 0.0),
		])
		draw_colored_polygon(pts, arrow_color)
		var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(outline, Palette.INK, 2.5, true)


class ThreatMarker:
	extends RefCounted
	var root: Control
	var arrow: ThreatArrow
	var tag: PanelContainer
	var name_label: Label
	var detail_label: Label
	var tag_style: StyleBoxFlat
	var shown_kind: String = ""


func setup(stabilizer: GyroStabilizer) -> void:
	_stabilizer = stabilizer
	layer = 10

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_vignettes()
	_build_playing_hud()
	_build_title_screen()
	_build_levelup_screen()
	_build_pause_screen()
	_build_gameover_screen()


func _process(delta: float) -> void:
	_pulse_clock += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 2.8)
		_hit_mat.set_shader_parameter("intensity", _hit_flash)
		_hit_rect.visible = _hit_flash > 0.005
	if _rush_kick > 0.0:
		_rush_kick = maxf(0.0, _rush_kick - delta * 2.5)
		_rush_mat.set_shader_parameter("flash", _rush_kick)

	# Subtle button pulse on Title & Game Over prompts
	var pulse := 1.0 + 0.025 * sin(_pulse_clock * 4.0)
	if _title_screen.visible and _title_btn != null:
		_title_btn.pivot_offset = _title_btn.size * 0.5
		_title_btn.scale = Vector2(pulse, pulse)
	if _gameover_screen.visible and _retry_btn != null:
		_retry_btn.pivot_offset = _retry_btn.size * 0.5
		_retry_btn.scale = Vector2(pulse, pulse)


func consume_touch_nitro() -> bool:
	if touch_nitro_queued:
		touch_nitro_queued = false
		return true
	return false


func show_phase(phase: String) -> void:
	_title_screen.visible = phase == "title"
	_hud_layer.visible = phase != "title"
	_levelup_screen.visible = phase == "levelup"
	_pause_screen.visible = phase == "paused"
	_gameover_screen.visible = phase == "gameover"
	if phase != "playing":
		touch_brake = false
		touch_handbrake = false
		touch_nitro_queued = false
	if phase == "dying" or phase == "gameover":
		set_threats([], 0.0)


func show_game_over_stats(seconds: float, kills: int, level: int) -> void:
	_gameover_survived.text = _format_time(seconds)
	_gameover_kills.text = str(kills)
	_gameover_level.text = str(level)


func set_frame(
	hp: float,
	max_hp: float,
	xp_fraction: float,
	level: int,
	seconds: float,
	kills: int,
	kmh: float,
	smoke: float,
	fps: float,
) -> void:
	_timer_label.text = _format_time(seconds)
	_kills_label.text = str(kills)
	_level_label.text = str(level)
	_speed_label.text = str(int(round(kmh)))
	_hull_label.text = "HULL %d / %d" % [maxi(0, int(ceil(hp))), int(round(max_hp))]
	_hull_fill.anchor_right = clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	_smoke_fill.anchor_right = clampf(smoke, 0.0, 1.0)
	_xp_fill.anchor_right = clampf(xp_fraction, 0.0, 1.0)

	if _horizon_anchor.visible:
		_horizon_pivot.rotation = -_stabilizer.display_roll
		var roll_deg := rad_to_deg(_stabilizer.fused_roll - _stabilizer.zero_offset)
		_horizon_angle_label.text = "%+.1f°" % roll_deg

	if _tuning_panel.visible:
		var roll_deg := rad_to_deg(_stabilizer.fused_roll - _stabilizer.zero_offset)
		_telemetry_label.text = (
			"%d FPS · %s\n"
			+ "Gyro Z: %+.2f rad/s\n"
			+ "Fused: %+.1f° | Steer: %+.2f"
		) % [
			int(round(fps)),
			"IMU" if _stabilizer.has_hardware_imu else "DESKTOP",
			_stabilizer.raw_gyro.z,
			roll_deg,
			_stabilizer.steer_output,
		]


func set_nitro(tanks: int, max_tanks: int, fill: float, burning: bool) -> void:
	if _nitro_pips.size() != max_tanks:
		for child in _nitro_tanks_box.get_children():
			child.queue_free()
		_nitro_pips.clear()
		for _i in max_tanks:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10.0, 14.0)
			pip.color = Color(0.168, 0.114, 0.102, 0.85)
			_nitro_tanks_box.add_child(pip)
			_nitro_pips.append(pip)
	for i in _nitro_pips.size():
		_nitro_pips[i].color = Palette.NITRO_CYAN if i < tanks else Color(0.168, 0.114, 0.102, 0.85)

	_nitro_fill.anchor_right = clampf(fill, 0.0, 1.0)
	_nitro_fill.color = Color("#e0f7ff") if burning else Palette.NITRO_CYAN

	if burning:
		_nitro_btn.text = "NITRO\nBURN!"
		_nitro_btn.modulate = Color(1.15, 1.25, 1.35, 1.0)
	elif tanks > 0:
		_nitro_btn.text = "NITRO\n[%d]" % tanks
		_nitro_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		_nitro_btn.text = "NITRO\n0"
		_nitro_btn.modulate = Color(0.7, 0.7, 0.75, 0.65)


func set_rush(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	_rush_mat.set_shader_parameter("intensity", clamped)
	_rush_rect.visible = clamped > 0.005 or _rush_kick > 0.005
	if clamped > 0.3:
		_speed_label.add_theme_color_override("font_color", Color("#c9efff"))
	else:
		_speed_label.add_theme_color_override("font_color", Palette.PAPER)


func kick_rush() -> void:
	_rush_kick = 1.0
	_rush_rect.visible = true
	_rush_mat.set_shader_parameter("flash", 1.0)


func flash_damage() -> void:
	_hit_flash = 1.0
	_hit_rect.visible = true
	_hit_mat.set_shader_parameter("intensity", 1.0)


func set_muted(is_muted: bool) -> void:
	var txt := "MUTED" if is_muted else "SFX ON"
	_mute_btn.text = txt
	_pause_mute_btn.text = "Audio: " + ("MUTED" if is_muted else "ON")


func set_loadout(levels: Dictionary) -> void:
	for child in _loadout_grid.get_children():
		child.queue_free()
	for u in Upgrades.all_upgrades():
		var lv: int = levels[u.id]
		if lv <= 0:
			continue
		var accent: Color = Upgrades.CATEGORY_COLORS[u.category]
		var panel := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.168, 0.114, 0.102, 0.78)
		st.border_width_left = 3
		st.border_color = accent
		st.corner_radius_top_left = 3
		st.corner_radius_top_right = 3
		st.corner_radius_bottom_left = 3
		st.corner_radius_bottom_right = 3
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = 3
		st.content_margin_bottom = 3
		panel.add_theme_stylebox_override("panel", st)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)

		var nm := Label.new()
		nm.text = u.name.to_upper()
		nm.add_theme_font_size_override("font_size", 11)
		nm.add_theme_color_override("font_color", Palette.PAPER)
		row.add_child(nm)

		var pips := Label.new()
		pips.text = "●".repeat(lv) + "○".repeat(maxi(0, u.max_level - lv))
		pips.add_theme_font_size_override("font_size", 11)
		pips.add_theme_color_override("font_color", accent)
		row.add_child(pips)

		_loadout_grid.add_child(panel)


func set_threats(threats: Array, display_roll: float) -> void:
	var vp_size := _root.get_viewport_rect().size
	if vp_size.x < 10.0 or vp_size.y < 10.0:
		return
	var half_w := vp_size.x * 0.5
	var half_h := vp_size.y * 0.5
	var reach_x := maxf(1.0, half_w - THREAT_SIDE_MARGIN)
	var reach_y := maxf(1.0, half_h - THREAT_VERTICAL_MARGIN)
	var cr := cos(-display_roll)
	var sr := sin(-display_roll)

	for i in threats.size():
		var threat: EnemySystem.Threat = threats[i]
		while _threat_markers.size() <= i:
			_threat_markers.append(_add_threat_marker())
		var m := _threat_markers[i]
		var incoming := threat.countdown > 0.0
		var raw_x := sin(threat.bearing)
		var raw_y := -cos(threat.bearing) * GROUND_FORESHORTENING
		# Rotate screen direction to stay aligned with counter-rotated horizon camera
		var rx := raw_x * cr - raw_y * sr
		var ry := raw_x * sr + raw_y * cr
		var length := sqrt(rx * rx + ry * ry)
		if length < 0.001:
			length = 1.0
		var dir_x := rx / length
		var dir_y := ry / length
		var reach := minf(reach_x / maxf(absf(dir_x), 0.0001), reach_y / maxf(absf(dir_y), 0.0001))

		m.root.visible = true
		m.root.position = Vector2(half_w + dir_x * reach, half_h + dir_y * reach)
		m.arrow.rotation = atan2(dir_y, dir_x)
		m.tag.position = Vector2(-dir_x * THREAT_TAG_OFFSET, -dir_y * THREAT_TAG_OFFSET) - m.tag.size * 0.5
		if incoming:
			m.arrow.modulate.a = 1.0 if fmod(_pulse_clock, 0.45) < 0.225 else 0.45
		else:
			m.arrow.modulate.a = 1.0

		if threat.kind != m.shown_kind:
			m.shown_kind = threat.kind
			var is_boss := threat.kind == "boss"
			var col := Palette.CAR_STRIPE if is_boss else Palette.SCRAP
			m.arrow.is_boss = is_boss
			m.arrow.arrow_color = col
			m.arrow.queue_redraw()
			m.name_label.text = "WAR RIG" if is_boss else "WAR PARTY"
			m.name_label.add_theme_color_override("font_color", col)
			m.tag_style.border_color = col

		m.detail_label.text = ("%.1f s" % threat.countdown) if incoming else ("%d m" % int(round(threat.distance)))

	for i in range(threats.size(), _threat_markers.size()):
		_threat_markers[i].root.visible = false


func open_level_up(choices: Array[Upgrades.UpgradeDef], levels: Dictionary) -> void:
	_choices = choices
	_selected_card = mini(1, choices.size() - 1)
	_card_buttons.clear()
	for child in _cards_row.get_children():
		child.queue_free()

	for i in choices.size():
		var u := choices[i]
		var next_lv: int = levels[u.id] + 1
		var accent: Color = Upgrades.CATEGORY_COLORS[u.category]
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(240.0, 236.0)

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 8)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vbox)

		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_bottom", 14)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.remove_child(vbox)
		card.add_child(margin)
		margin.add_child(vbox)

		var glyph_lbl := Label.new()
		glyph_lbl.text = u.glyph
		glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_lbl.add_theme_font_size_override("font_size", 42)
		glyph_lbl.add_theme_color_override("font_color", accent)
		vbox.add_child(glyph_lbl)

		var cat_lbl := Label.new()
		cat_lbl.text = Upgrades.CATEGORY_LABELS[u.category]
		cat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cat_lbl.add_theme_font_size_override("font_size", 11)
		cat_lbl.add_theme_color_override("font_color", accent)
		vbox.add_child(cat_lbl)

		var name_lbl := Label.new()
		name_lbl.text = u.name.to_upper()
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Palette.PAPER)
		vbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = u.describe(next_lv)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.9))
		vbox.add_child(desc_lbl)

		var tier_lbl := Label.new()
		if u.max_level < 999:
			tier_lbl.text = "NEW" if next_lv == 1 else "TIER %d OF %d" % [next_lv, u.max_level]
		else:
			tier_lbl.text = "INSTANT"
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.72))
		vbox.add_child(tier_lbl)

		var idx := i
		card.mouse_entered.connect(func() -> void: _select_card(idx))
		card.pressed.connect(func() -> void: upgrade_picked.emit(_choices[idx]))
		_cards_row.add_child(card)
		_card_buttons.append(card)

	_select_card(_selected_card)


func move_selection(direction: int) -> void:
	if _choices.is_empty():
		return
	_select_card((_selected_card + direction + _choices.size()) % _choices.size())


func confirm_selection() -> void:
	if _selected_card >= 0 and _selected_card < _choices.size():
		upgrade_picked.emit(_choices[_selected_card])


func _select_card(index: int) -> void:
	_selected_card = index
	for i in _card_buttons.size():
		var card := _card_buttons[i]
		var accent: Color = Upgrades.CATEGORY_COLORS[_choices[i].category]
		var selected := i == index
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.22, 0.145, 0.125, 0.96) if selected else Color(0.168, 0.114, 0.102, 0.9)
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_left = 8
		st.corner_radius_bottom_right = 8
		st.border_width_top = 4
		st.border_width_left = 3 if selected else 1
		st.border_width_right = 3 if selected else 1
		st.border_width_bottom = 3 if selected else 1
		st.border_color = accent if selected else Color(accent.r, accent.g, accent.b, 0.4)
		card.add_theme_stylebox_override("normal", st)
		card.add_theme_stylebox_override("hover", st)
		card.add_theme_stylebox_override("pressed", st)


func _build_vignettes() -> void:
	var vig_shader: Shader = load("res://shaders/vignette.gdshader")

	_hit_mat = ShaderMaterial.new()
	_hit_mat.shader = vig_shader
	_hit_mat.set_shader_parameter("tint", Color(0.886, 0.271, 0.184, 0.78))
	_hit_mat.set_shader_parameter("inner_radius", 0.45)
	_hit_mat.set_shader_parameter("outer_radius", 1.1)
	_hit_mat.set_shader_parameter("intensity", 0.0)
	_hit_mat.set_shader_parameter("flash", 0.0)

	_hit_rect = ColorRect.new()
	_hit_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_rect.material = _hit_mat
	_hit_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_rect.visible = false
	_root.add_child(_hit_rect)

	_rush_mat = ShaderMaterial.new()
	_rush_mat.shader = vig_shader
	_rush_mat.set_shader_parameter("tint", Color(0.47, 0.84, 1.0, 0.34))
	_rush_mat.set_shader_parameter("inner_radius", 0.58)
	_rush_mat.set_shader_parameter("outer_radius", 1.15)
	_rush_mat.set_shader_parameter("intensity", 0.0)
	_rush_mat.set_shader_parameter("flash", 0.0)

	_rush_rect = ColorRect.new()
	_rush_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rush_rect.material = _rush_mat
	_rush_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rush_rect.visible = false
	_root.add_child(_rush_rect)


func _build_playing_hud() -> void:
	_hud_layer = Control.new()
	_hud_layer.name = "PlayingHud"
	_hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud_layer)

	# Threat arrows layer behind HUD controls
	_threats_layer = Control.new()
	_threats_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_threats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_threats_layer)

	# Top XP bar
	var xp_bg := ColorRect.new()
	xp_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	xp_bg.offset_bottom = 9.0
	xp_bg.color = Color(0.168, 0.114, 0.102, 0.5)
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(xp_bg)

	_xp_fill = ColorRect.new()
	_xp_fill.anchor_left = 0.0
	_xp_fill.anchor_top = 0.0
	_xp_fill.anchor_bottom = 1.0
	_xp_fill.anchor_right = 0.0
	_xp_fill.color = Palette.SCRAP
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bg.add_child(_xp_fill)

	# Top-left: Level + quick Pause & Mute
	var top_left := HBoxContainer.new()
	top_left.position = Vector2(44.0, 18.0)
	top_left.add_theme_constant_override("separation", 14)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(top_left)

	var lv_col := VBoxContainer.new()
	lv_col.add_theme_constant_override("separation", 0)
	lv_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_child(lv_col)
	lv_col.add_child(_make_caption("LEVEL"))
	_level_label = _make_big_stat("1", 32)
	lv_col.add_child(_level_label)

	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	util_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	util_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_left.add_child(util_row)

	var pause_btn := _make_pill_button("II", Palette.INK, Palette.PAPER)
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	util_row.add_child(pause_btn)

	_mute_btn = _make_pill_button("SFX ON", Palette.INK, Palette.PAPER)
	_mute_btn.pressed.connect(func() -> void: mute_pressed.emit())
	util_row.add_child(_mute_btn)

	# Top-center: Timer + optional Horizon Bar
	var top_center := VBoxContainer.new()
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.offset_left = -90.0
	top_center.offset_right = 90.0
	top_center.offset_top = 16.0
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(top_center)

	_timer_label = _make_big_stat("00:00", 38)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(_timer_label)

	_horizon_anchor = Control.new()
	_horizon_anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_horizon_anchor.offset_top = 78.0
	_horizon_anchor.visible = show_horizon
	_horizon_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_horizon_anchor)

	_horizon_pivot = Control.new()
	_horizon_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_horizon_anchor.add_child(_horizon_pivot)

	var hline := ColorRect.new()
	hline.color = Color(0.984, 0.945, 0.875, 0.8)
	hline.position = Vector2(-60.0, -1.5)
	hline.size = Vector2(120.0, 3.0)
	hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_horizon_pivot.add_child(hline)

	var htick := ColorRect.new()
	htick.color = Palette.CAR_STRIPE
	htick.position = Vector2(-2.0, -8.0)
	htick.size = Vector2(4.0, 16.0)
	htick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_horizon_pivot.add_child(htick)

	_horizon_angle_label = Label.new()
	_horizon_angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_horizon_angle_label.position = Vector2(-50.0, 10.0)
	_horizon_angle_label.size = Vector2(100.0, 20.0)
	_horizon_angle_label.add_theme_font_size_override("font_size", 12)
	_horizon_angle_label.add_theme_color_override("font_color", Palette.PAPER)
	_horizon_anchor.add_child(_horizon_angle_label)

	# Top-right: Wrecked count + Gyro Tuning drawer
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -290.0
	top_right.offset_right = -44.0
	top_right.offset_top = 18.0
	top_right.offset_bottom = 390.0
	top_right.add_theme_constant_override("separation", 6)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(top_right)

	var tr_bar := HBoxContainer.new()
	tr_bar.alignment = BoxContainer.ALIGNMENT_END
	tr_bar.add_theme_constant_override("separation", 12)
	tr_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(tr_bar)

	var gyro_btn := _make_pill_button("GYRO", Palette.INK, Palette.SCRAP)
	gyro_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr_bar.add_child(gyro_btn)

	var kills_col := VBoxContainer.new()
	kills_col.add_theme_constant_override("separation", 0)
	kills_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_bar.add_child(kills_col)
	var k_cap := _make_caption("WRECKED")
	k_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_col.add_child(k_cap)
	_kills_label = _make_big_stat("0", 32)
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_col.add_child(_kills_label)

	_build_gyro_drawer(top_right, gyro_btn)

	# Bottom-left: Brake/Rev touch pad + Gauges cleanly beside it (thumb-friendly!)
	var bl_row := HBoxContainer.new()
	bl_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl_row.offset_left = 44.0
	bl_row.offset_bottom = -24.0
	bl_row.offset_top = -185.0
	bl_row.offset_right = 460.0
	bl_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	bl_row.add_theme_constant_override("separation", 16)
	bl_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(bl_row)

	var left_pad_col := VBoxContainer.new()
	left_pad_col.alignment = BoxContainer.ALIGNMENT_END
	left_pad_col.add_theme_constant_override("separation", 8)
	left_pad_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_row.add_child(left_pad_col)

	_auto_gas_btn = _make_pill_button("AUTO GAS: ON", Palette.INK, Palette.REPAIR)
	_auto_gas_btn.pressed.connect(_toggle_auto_gas)
	left_pad_col.add_child(_auto_gas_btn)

	var brake_btn := _make_thumb_button("BRAKE\nREV", Color(0.168, 0.114, 0.102, 0.72), Palette.PAPER)
	brake_btn.button_down.connect(func() -> void: touch_brake = true)
	brake_btn.button_up.connect(func() -> void: touch_brake = false)
	left_pad_col.add_child(brake_btn)

	# Gauges column (Speed, Hull, Smoke, Nitrous)
	var gauges := VBoxContainer.new()
	gauges.custom_minimum_size = Vector2(240.0, 0.0)
	gauges.alignment = BoxContainer.ALIGNMENT_END
	gauges.add_theme_constant_override("separation", 6)
	gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_row.add_child(gauges)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauges.add_child(speed_row)

	_speed_label = _make_big_stat("0", 42)
	speed_row.add_child(_speed_label)
	var kmh_lbl := _make_caption("KM/H")
	kmh_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	speed_row.add_child(kmh_lbl)

	# Hull bar
	var hull_bar := _make_bar(20.0, Palette.CAR_STRIPE)
	_hull_fill = hull_bar["fill"]
	_hull_label = hull_bar["label"]
	_hull_label.text = "HULL 100 / 100"
	gauges.add_child(hull_bar["root"])

	# Smoke bar
	var smoke_bar := _make_bar(12.0, Palette.PAPER)
	_smoke_fill = smoke_bar["fill"]
	var sm_lbl: Label = smoke_bar["label"]
	sm_lbl.text = "SMOKE"
	sm_lbl.add_theme_font_size_override("font_size", 9)
	sm_lbl.add_theme_color_override("font_color", Color(0.45, 0.38, 0.35))
	gauges.add_child(smoke_bar["root"])

	# Nitrous bar + tank pips
	var nitro_row := HBoxContainer.new()
	nitro_row.add_theme_constant_override("separation", 6)
	nitro_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauges.add_child(nitro_row)

	var nitro_bar := _make_bar(14.0, Palette.NITRO_CYAN)
	var nb_root: Control = nitro_bar["root"]
	nb_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nitro_fill = nitro_bar["fill"]
	var nb_lbl: Label = nitro_bar["label"]
	nb_lbl.text = "NITROUS"
	nb_lbl.add_theme_font_size_override("font_size", 9)
	nitro_row.add_child(nb_root)

	_nitro_tanks_box = HBoxContainer.new()
	_nitro_tanks_box.add_theme_constant_override("separation", 4)
	_nitro_tanks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nitro_row.add_child(_nitro_tanks_box)

	# Bottom-right: Loadout badges above Nitro + Drift thumb pads
	var br_col := VBoxContainer.new()
	br_col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br_col.offset_right = -44.0
	br_col.offset_bottom = -24.0
	br_col.offset_left = -380.0
	br_col.offset_top = -340.0
	br_col.alignment = BoxContainer.ALIGNMENT_END
	br_col.add_theme_constant_override("separation", 10)
	br_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(br_col)

	var loadout_wrap := HBoxContainer.new()
	loadout_wrap.alignment = BoxContainer.ALIGNMENT_END
	loadout_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br_col.add_child(loadout_wrap)

	_loadout_grid = GridContainer.new()
	_loadout_grid.columns = 2
	_loadout_grid.add_theme_constant_override("h_separation", 8)
	_loadout_grid.add_theme_constant_override("v_separation", 5)
	_loadout_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loadout_wrap.add_child(_loadout_grid)

	var right_pads := HBoxContainer.new()
	right_pads.alignment = BoxContainer.ALIGNMENT_END
	right_pads.add_theme_constant_override("separation", 12)
	right_pads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br_col.add_child(right_pads)

	_nitro_btn = _make_thumb_button("NITRO\n[1]", Color(0.12, 0.35, 0.52, 0.8), Color("#d6f3ff"))
	_nitro_btn.button_down.connect(func() -> void: touch_nitro_queued = true)
	right_pads.add_child(_nitro_btn)

	var drift_btn := _make_thumb_button("DRIFT", Color(0.76, 0.23, 0.16, 0.82), Palette.PAPER)
	drift_btn.button_down.connect(func() -> void: touch_handbrake = true)
	drift_btn.button_up.connect(func() -> void: touch_handbrake = false)
	right_pads.add_child(drift_btn)


func _build_gyro_drawer(holder: VBoxContainer, toggle_btn: Button) -> void:
	_tuning_panel = PanelContainer.new()
	_tuning_panel.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.168, 0.114, 0.102, 0.88)
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_left = 8
	st.corner_radius_bottom_right = 8
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	_tuning_panel.add_theme_stylebox_override("panel", st)
	holder.add_child(_tuning_panel)

	toggle_btn.pressed.connect(func() -> void: _tuning_panel.visible = not _tuning_panel.visible)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	_tuning_panel.add_child(list)

	_lock_btn = _make_pill_button("Screen Lock: " + LOCK_LABELS[_lock_idx], Color("#3c2823"), Palette.SCRAP)
	_lock_btn.pressed.connect(_cycle_lock)
	list.add_child(_lock_btn)

	_tilt_btn = _make_pill_button("Max Tilt: %d°" % int(TILT_ANGLES[_tilt_idx]), Color("#3c2823"), Palette.PAPER)
	_tilt_btn.pressed.connect(_cycle_tilt)
	list.add_child(_tilt_btn)

	_fusion_btn = _make_pill_button("Fusion: " + FUSION_LABELS[_fusion_idx], Color("#3c2823"), Palette.PAPER)
	_fusion_btn.pressed.connect(_cycle_fusion)
	list.add_child(_fusion_btn)

	_zoom_btn = _make_pill_button("Tilt Zoom Comp: ON", Color("#3c2823"), Palette.PAPER)
	_zoom_btn.pressed.connect(_toggle_zoom)
	list.add_child(_zoom_btn)

	_horizon_btn = _make_pill_button("Horizon Bar: OFF", Color("#3c2823"), Palette.PAPER)
	_horizon_btn.pressed.connect(_toggle_horizon)
	list.add_child(_horizon_btn)

	_invert_btn = _make_pill_button("Invert Roll: OFF", Color("#3c2823"), Palette.PAPER)
	_invert_btn.pressed.connect(_toggle_invert)
	list.add_child(_invert_btn)

	var zero_btn := _make_pill_button("ZERO TILT NOW", Color("#593728"), Palette.SCRAP)
	zero_btn.pressed.connect(func() -> void: recenter_pressed.emit())
	list.add_child(zero_btn)

	_telemetry_label = Label.new()
	_telemetry_label.add_theme_font_size_override("font_size", 11)
	_telemetry_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.85))
	list.add_child(_telemetry_label)


func _build_title_screen() -> void:
	_title_screen = _make_screen_backdrop()
	_root.add_child(_title_screen)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -360.0
	center.offset_right = 360.0
	center.offset_top = -230.0
	center.offset_bottom = 230.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	_title_screen.add_child(center)

	var eyebrow := Label.new()
	eyebrow.text = "A WASTELAND DRIFT SURVIVAL"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Palette.CAR_STRIPE_ALT)
	center.add_child(eyebrow)

	var title := Label.new()
	title.text = "DRIFTGUY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", Palette.PAPER)
	title.add_theme_color_override("font_shadow_color", Palette.CAR_STRIPE)
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	center.add_child(title)

	var tagline := Label.new()
	tagline.text = "Your smoke is your weapon. Slide wide, choke the raiders, grab their scrap.\nHurting them fills your nitrous."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 15)
	tagline.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.92))
	center.add_child(tagline)

	var controls_row := HBoxContainer.new()
	controls_row.alignment = BoxContainer.ALIGNMENT_CENTER
	controls_row.add_theme_constant_override("separation", 20)
	center.add_child(controls_row)

	controls_row.add_child(_make_control_card("IPHONE · GYRO & TOUCH", [
		["TILT PHONE", "Steer (horizon stays level)"],
		["AUTO GAS", "Hands-free throttle"],
		["BRAKE / REV", "Left thumb"],
		["DRIFT · NITRO", "Right thumb"],
	]))
	controls_row.add_child(_make_control_card("KEYBOARD · CONTROLLER", [
		["W / S · RT / LT", "Throttle / Brake"],
		["A D · STICK", "Steer"],
		["SPACE · B/X", "Handbrake"],
		["E · A / ESC · M", "Nitrous · Pause · Mute"],
	]))

	var btn_wrap := HBoxContainer.new()
	btn_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(btn_wrap)

	_title_btn = _make_cta_button("TAP OR PRESS ENTER TO DRIVE")
	_title_btn.pressed.connect(func() -> void: start_pressed.emit())
	btn_wrap.add_child(_title_btn)


func _build_levelup_screen() -> void:
	_levelup_screen = _make_screen_backdrop()
	_levelup_screen.visible = false
	_root.add_child(_levelup_screen)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -420.0
	center.offset_right = 420.0
	center.offset_top = -210.0
	center.offset_bottom = 210.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	_levelup_screen.add_child(center)

	var eyebrow := Label.new()
	eyebrow.text = "SCRAP WELDED"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Palette.CAR_STRIPE_ALT)
	center.add_child(eyebrow)

	var h2 := Label.new()
	h2.text = "CHOOSE AN UPGRADE"
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h2.add_theme_font_size_override("font_size", 42)
	h2.add_theme_color_override("font_color", Palette.PAPER)
	center.add_child(h2)

	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", 18)
	center.add_child(_cards_row)

	var hint := Label.new()
	hint.text = "TAP A CARD · OR ← → + ENTER / A TO BOLT IT ON"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.78))
	center.add_child(hint)


func _build_pause_screen() -> void:
	_pause_screen = _make_screen_backdrop()
	_pause_screen.visible = false
	_root.add_child(_pause_screen)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -220.0
	center.offset_right = 220.0
	center.offset_top = -170.0
	center.offset_bottom = 170.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 12)
	_pause_screen.add_child(center)

	var h2 := Label.new()
	h2.text = "PAUSED"
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h2.add_theme_font_size_override("font_size", 48)
	h2.add_theme_color_override("font_color", Palette.PAPER)
	center.add_child(h2)

	var resume_btn := _make_cta_button("RESUME")
	resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	center.add_child(resume_btn)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)

	_pause_mute_btn = _make_pill_button("Audio: ON", Color("#3c2823"), Palette.PAPER)
	_pause_mute_btn.pressed.connect(func() -> void: mute_pressed.emit())
	row.add_child(_pause_mute_btn)

	var zero_btn := _make_pill_button("Zero Tilt", Color("#3c2823"), Palette.SCRAP)
	zero_btn.pressed.connect(func() -> void: recenter_pressed.emit())
	row.add_child(zero_btn)

	var restart_btn := _make_pill_button("Restart Run", Color("#5a241d"), Palette.PAPER)
	restart_btn.pressed.connect(func() -> void: retry_pressed.emit())
	row.add_child(restart_btn)

	var hint := Label.new()
	hint.text = "ESC OR START TO RESUME · USE TOP-RIGHT GYRO FOR TUNING"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.72))
	center.add_child(hint)


func _build_gameover_screen() -> void:
	_gameover_screen = _make_screen_backdrop()
	_gameover_screen.visible = false
	_root.add_child(_gameover_screen)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -300.0
	center.offset_right = 300.0
	center.offset_top = -190.0
	center.offset_bottom = 190.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	_gameover_screen.add_child(center)

	var eyebrow := Label.new()
	eyebrow.text = "THE WASTELAND TAKES ITS DUE"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Palette.CAR_STRIPE_ALT)
	center.add_child(eyebrow)

	var h2 := Label.new()
	h2.text = "WRECKED"
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h2.add_theme_font_size_override("font_size", 58)
	h2.add_theme_color_override("font_color", Palette.PAPER)
	h2.add_theme_color_override("font_shadow_color", Palette.CAR_STRIPE)
	h2.add_theme_constant_override("shadow_offset_x", 3)
	h2.add_theme_constant_override("shadow_offset_y", 3)
	center.add_child(h2)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 42)
	center.add_child(stats_row)

	var c1 := _make_result_cell("SURVIVED")
	_gameover_survived = c1["val"]
	stats_row.add_child(c1["root"])

	var c2 := _make_result_cell("WRECKED")
	_gameover_kills = c2["val"]
	stats_row.add_child(c2["root"])

	var c3 := _make_result_cell("LEVEL")
	_gameover_level = c3["val"]
	stats_row.add_child(c3["root"])

	var btn_wrap := HBoxContainer.new()
	btn_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(btn_wrap)

	_retry_btn = _make_cta_button("ROLL OUT AGAIN")
	_retry_btn.pressed.connect(func() -> void: retry_pressed.emit())
	btn_wrap.add_child(_retry_btn)


func _add_threat_marker() -> ThreatMarker:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	_threats_layer.add_child(root)

	var arrow := ThreatArrow.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(arrow)

	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.168, 0.114, 0.102, 0.82)
	st.border_width_bottom = 3
	st.border_color = Palette.SCRAP
	st.corner_radius_top_left = 3
	st.corner_radius_top_right = 3
	st.corner_radius_bottom_left = 3
	st.corner_radius_bottom_right = 3
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", st)
	root.add_child(tag)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(col)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Palette.SCRAP)
	col.add_child(name_lbl)

	var det_lbl := Label.new()
	det_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	det_lbl.add_theme_font_size_override("font_size", 14)
	det_lbl.add_theme_color_override("font_color", Palette.PAPER)
	col.add_child(det_lbl)

	var m := ThreatMarker.new()
	m.root = root
	m.arrow = arrow
	m.tag = tag
	m.name_label = name_lbl
	m.detail_label = det_lbl
	m.tag_style = st
	return m


func _cycle_lock() -> void:
	_lock_idx = (_lock_idx + 1) % LOCK_MODES.size()
	_stabilizer.counter_rotate_scale = LOCK_MODES[_lock_idx]
	_lock_btn.text = "Screen Lock: " + LOCK_LABELS[_lock_idx]


func _cycle_tilt() -> void:
	_tilt_idx = (_tilt_idx + 1) % TILT_ANGLES.size()
	_stabilizer.max_steer_deg = TILT_ANGLES[_tilt_idx]
	_tilt_btn.text = "Max Tilt: %d°" % int(TILT_ANGLES[_tilt_idx])


func _cycle_fusion() -> void:
	_fusion_idx = (_fusion_idx + 1) % FUSION_VALUES.size()
	_stabilizer.gravity_correction = FUSION_VALUES[_fusion_idx]
	_fusion_btn.text = "Fusion: " + FUSION_LABELS[_fusion_idx]


func _toggle_zoom() -> void:
	zoom_compensation = not zoom_compensation
	_zoom_btn.text = "Tilt Zoom Comp: " + ("ON" if zoom_compensation else "OFF")


func _toggle_horizon() -> void:
	show_horizon = not show_horizon
	_horizon_anchor.visible = show_horizon
	_horizon_btn.text = "Horizon Bar: " + ("ON" if show_horizon else "OFF")


func _toggle_invert() -> void:
	_stabilizer.invert_gyro = not _stabilizer.invert_gyro
	_invert_btn.text = "Invert Roll: " + ("ON" if _stabilizer.invert_gyro else "OFF")


func _toggle_auto_gas() -> void:
	auto_throttle = not auto_throttle
	_auto_gas_btn.text = "AUTO GAS: " + ("ON" if auto_throttle else "OFF")
	_auto_gas_btn.add_theme_color_override("font_color", Palette.REPAIR if auto_throttle else Palette.CAR_STRIPE_ALT)


static func _format_time(seconds: float) -> String:
	var whole := int(floor(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


static func _make_screen_backdrop() -> Control:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.168, 0.114, 0.102, 0.78)
	return bg


static func _make_caption(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.84))
	l.add_theme_color_override("font_shadow_color", Color(0.17, 0.11, 0.1, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func _make_big_stat(txt: String, sz: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Palette.PAPER)
	l.add_theme_color_override("font_shadow_color", Color(0.17, 0.11, 0.1, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func _make_bar(height: float, fill_col: Color) -> Dictionary:
	var root := ColorRect.new()
	root.custom_minimum_size = Vector2(0.0, height)
	root.color = Color(0.168, 0.114, 0.102, 0.74)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill := ColorRect.new()
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = 1.0
	fill.color = fill_col
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)

	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = 8.0
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Palette.PAPER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)

	return { "root": root, "fill": fill, "label": lbl }


static func _make_control_card(heading: String, rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290.0, 0.0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.168, 0.114, 0.102, 0.82)
	st.border_width_top = 3
	st.border_color = Palette.SCRAP
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", Palette.SCRAP)
	vbox.add_child(h)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for pair in rows:
		var k := Label.new()
		k.text = pair[0]
		k.add_theme_font_size_override("font_size", 11)
		k.add_theme_color_override("font_color", Palette.PAPER)
		grid.add_child(k)

		var v := Label.new()
		v.text = pair[1]
		v.add_theme_font_size_override("font_size", 11)
		v.add_theme_color_override("font_color", Color(0.98, 0.94, 0.87, 0.8))
		grid.add_child(v)

	return panel


static func _make_result_cell(caption: String) -> Dictionary:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)

	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Palette.CAR_STRIPE_ALT)
	col.add_child(cap)

	var val := Label.new()
	val.text = "0"
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 38)
	val.add_theme_color_override("font_color", Palette.PAPER)
	col.add_child(val)
	return { "root": col, "val": val }


static func _make_cta_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Palette.INK)
	btn.add_theme_color_override("font_hover_color", Palette.INK)
	btn.add_theme_color_override("font_pressed_color", Palette.INK)
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SCRAP
	st.corner_radius_top_left = 5
	st.corner_radius_top_right = 5
	st.corner_radius_bottom_left = 5
	st.corner_radius_bottom_right = 5
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 13
	st.content_margin_bottom = 13
	btn.add_theme_stylebox_override("normal", st)
	var hov: StyleBoxFlat = st.duplicate()
	hov.bg_color = Palette.PAPER
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	return btn


static func _make_pill_button(label: String, bg: Color, fg: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.bg_color.a = 0.84
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)
	var pressed: StyleBoxFlat = style.duplicate()
	pressed.bg_color = bg.lightened(0.18)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", pressed)
	return btn


static func _make_thumb_button(label: String, bg: Color, fg: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.keep_pressed_outside = true
	btn.custom_minimum_size = Vector2(106.0, 96.0)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(fg.r, fg.g, fg.b, 0.35)
	btn.add_theme_stylebox_override("normal", style)
	var pressed: StyleBoxFlat = style.duplicate()
	pressed.bg_color = bg.lightened(0.22)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", style)
	return btn
