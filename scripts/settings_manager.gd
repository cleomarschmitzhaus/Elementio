extends Node
## Configuracoes persistentes do jogo (estilo RTS classico).
##
## O menu de opcoes le e escreve estas variaveis; o restante do jogo consulta
## os valores em tempo real (velocidade da camera, barras de vida, etc.).

const CONFIG_PATH := "user://elementio_settings.cfg"

const DEFAULT_MASTER_VOLUME := 0.85
const DEFAULT_MUSIC_VOLUME := 0.65
const DEFAULT_SFX_VOLUME := 0.85
const DEFAULT_GAME_SPEED := 1.0
const DEFAULT_SCROLL_SPEED := 800.0

var master_volume: float = DEFAULT_MASTER_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME
var game_speed: float = DEFAULT_GAME_SPEED
var scroll_speed: float = DEFAULT_SCROLL_SPEED
var edge_scroll: bool = true
var show_health_bars: bool = false
var fullscreen: bool = true

func _ready() -> void:
	load_settings()
	apply_all()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	game_speed = clampf(float(cfg.get_value("game", "speed", game_speed)), 0.25, 3.0)
	scroll_speed = clampf(float(cfg.get_value("game", "scroll_speed", scroll_speed)), 200.0, 2000.0)
	edge_scroll = bool(cfg.get_value("game", "edge_scroll", edge_scroll))
	show_health_bars = bool(cfg.get_value("game", "show_health_bars", show_health_bars))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("game", "speed", game_speed)
	cfg.set_value("game", "scroll_speed", scroll_speed)
	cfg.set_value("game", "edge_scroll", edge_scroll)
	cfg.set_value("game", "show_health_bars", show_health_bars)
	cfg.set_value("video", "fullscreen", fullscreen)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("Nao foi possivel salvar as configuracoes em %s" % CONFIG_PATH)

func reset_defaults() -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	game_speed = DEFAULT_GAME_SPEED
	scroll_speed = DEFAULT_SCROLL_SPEED
	edge_scroll = true
	show_health_bars = false
	fullscreen = true
	apply_all()

func apply_all() -> void:
	Engine.time_scale = clampf(game_speed, 0.25, 3.0)
	_apply_audio()
	_apply_fullscreen()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func set_game_speed(value: float) -> void:
	game_speed = clampf(value, 0.25, 3.0)
	Engine.time_scale = game_speed

func set_scroll_speed(value: float) -> void:
	scroll_speed = clampf(value, 200.0, 2000.0)

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()

func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)
	save_settings()

func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)

func _set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		if bus_name == "Master":
			idx = 0
		else:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var clamped := clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(clamped, 0.001)))

func _apply_fullscreen() -> void:
	# No headless (testes/CI) nao existe janela para alternar.
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
