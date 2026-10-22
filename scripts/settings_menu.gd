class_name SettingsMenu
extends Control
## Menu de opcoes/pausa no estilo dos RTS classicos.
##
## Os controles sao criados em abas (Jogo, Audio, Video) e escrevem direto no
## SettingsManager. A partida fica pausada enquanto este menu estiver aberto.

signal closed

@onready var tabs: TabContainer = $Center/Panel/Margin/VBox/Tabs
@onready var version_label: Label = $Center/Panel/Margin/VBox/Version
@onready var status_label: Label = $Center/Panel/Margin/VBox/Status
@onready var close_btn: Button = $Center/Panel/Margin/VBox/Buttons/CloseBtn

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _checks: Dictionary = {}
var _was_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var version := str(ProjectSettings.get_setting("application/config/version", "0.01.000"))
	version_label.text = "Elementio v%s (alpha)" % version
	_style_panel()
	_build_tabs()
	visible = false

func _style_panel() -> void:
	var panel := $Center/Panel as PanelContainer
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.075, 0.055, 0.98)
	style.border_color = Color(0.62, 0.45, 0.22, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

func _build_tabs() -> void:
	tabs.add_theme_font_size_override("font_size", 14)

	var game := _create_tab("Jogo")
	_add_slider(game, "Velocidade do jogo", 0.5, 2.0, 0.1, "game_speed")
	_add_slider(game, "Velocidade de rolagem", 200.0, 2000.0, 50.0, "scroll_speed")
	_add_check(game, "Rolagem nas bordas da tela", "edge_scroll")
	_add_check(game, "Sempre mostrar barras de vida (unidades)", "show_health_bars")
	var hint := _make_hint("A velocidade do jogo afeta o ritmo de todas as unidades e da IA.")
	game.add_child(hint)

	var audio := _create_tab("Áudio")
	_add_slider(audio, "Volume geral", 0.0, 1.0, 0.05, "master_volume")
	_add_slider(audio, "Música", 0.0, 1.0, 0.05, "music_volume")
	_add_slider(audio, "Efeitos sonoros", 0.0, 1.0, 0.05, "sfx_volume")
	audio.add_child(_make_hint("Os volumes são aplicados em tempo real."))

	var video := _create_tab("Vídeo")
	_add_check(video, "Tela cheia", "fullscreen")
	video.add_child(_make_hint("Dica: F11 também alterna entre tela cheia e janela."))

func _create_tab(title_text: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title_text
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	tabs.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	return box

func _add_slider(parent: VBoxContainer, label_text: String, min_value: float,
		max_value: float, step_value: float, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(230, 26)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step_value
	slider.value = float(SettingsManager.get(key))
	slider.custom_minimum_size = Vector2(300, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72, 26)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = _value_text(key, slider.value)
	row.add_child(value_label)

	parent.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = value_label
	slider.value_changed.connect(func(value: float) -> void: _on_slider_changed(key, value))

func _add_check(parent: VBoxContainer, label_text: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = label_text
	check.button_pressed = bool(SettingsManager.get(key))
	check.add_theme_font_size_override("font_size", 14)
	check.toggled.connect(func(pressed: bool) -> void: _on_check_toggled(key, pressed))
	parent.add_child(check)
	_checks[key] = check

func _make_hint(text_value: String) -> Label:
	var hint := Label.new()
	hint.text = text_value
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6, 1.0))
	return hint

func _value_text(key: String, value: float) -> String:
	match key:
		"game_speed":
			return "%.1fx" % value
		"scroll_speed":
			return "%d px/s" % int(round(value))
		_:
			return "%d%%" % int(round(value * 100.0))

func _on_slider_changed(key: String, value: float) -> void:
	match key:
		"game_speed":
			SettingsManager.set_game_speed(value)
		"scroll_speed":
			SettingsManager.set_scroll_speed(value)
		"master_volume":
			SettingsManager.set_master_volume(value)
		"music_volume":
			SettingsManager.set_music_volume(value)
		"sfx_volume":
			SettingsManager.set_sfx_volume(value)
	if _value_labels.has(key):
		_value_labels[key].text = _value_text(key, value)
	status_label.text = "Alterações aplicadas. Clique em Aplicar para salvar."

func _on_check_toggled(key: String, pressed: bool) -> void:
	match key:
		"edge_scroll":
			SettingsManager.edge_scroll = pressed
		"show_health_bars":
			SettingsManager.show_health_bars = pressed
		"fullscreen":
			SettingsManager.set_fullscreen(pressed)
	status_label.text = "Alterações aplicadas. Clique em Aplicar para salvar."

func _sync_controls() -> void:
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(float(SettingsManager.get(key)))
		var value_label: Label = _value_labels[key]
		value_label.text = _value_text(key, slider.value)
	for key in _checks.keys():
		var check: CheckButton = _checks[key]
		check.set_pressed_no_signal(bool(SettingsManager.get(key)))

func open() -> void:
	if visible:
		return
	_sync_controls()
	_was_paused = get_tree().paused
	visible = true
	move_to_front()
	get_tree().paused = true
	status_label.text = "Partida pausada."
	close_btn.grab_focus()

func close() -> void:
	if not visible:
		return
	close_btn.release_focus()
	visible = false
	get_tree().paused = _was_paused
	SettingsManager.save_settings()
	status_label.text = ""
	closed.emit()

func _on_apply_pressed() -> void:
	SettingsManager.save_settings()
	status_label.text = "Configurações salvas."

func _on_defaults_pressed() -> void:
	SettingsManager.reset_defaults()
	SettingsManager.save_settings()
	_sync_controls()
	status_label.text = "Padrões restaurados. Configurações salvas."

func _on_close_pressed() -> void:
	close()
