extends Node
## ErrorReport — relatorio de execucao + autodebug (autoload).
## - Checagens de integridade: nós críticos, materiais, shaders, SubViewport,
##   referencias mortas na selecao, unidades travadas, FPS.
## - Autodebug: corrige automaticamente os problemas detectados (reaplica
##   materiais, poda referencias invalidas, reativa SubViewport, etc).
## - Log persistente em user://logs/ e relatorio final em
##   docs/diagnostico/runtime_report.txt.
## - Overlay F3 (FPS / memoria / estado / ultimo problema).

const CHECK_INTERVAL := 5.0
const LOG_DIR := "user://logs"
const REPORT_PATH := "res://docs/diagnostico/runtime_report.txt"
const MAX_ENTRIES := 500

var _entries: Array = []          # {t, level, context, msg}
var _checks_run: int = 0
var _fixes_applied: int = 0
var _since_check: float = 0.0
var _last_fps_warn: float = -999.0
var _entity_shader: Shader = null

var _overlay_layer: CanvasLayer = null
var _overlay_label: Label = null
var _overlay_visible: bool = false

func _ready() -> void:
	process_priority = 100  # roda depois da maioria dos scripts
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	log_event("INFO", "boot", "ErrorReport ativo | Godot %s | %s | cena raiz: %s" % [
		Engine.get_version_info().string, OS.get_name(),
		get_tree().current_scene.name if get_tree().current_scene else "?"])
	_setup_overlay()
	# primeira checagem depois que a cena termina de carregar
	await get_tree().create_timer(1.0).timeout
	run_checks("startup")

func _process(delta: float) -> void:
	_since_check += delta
	if _since_check >= CHECK_INTERVAL:
		_since_check = 0.0
		run_checks("periodic")
	if _overlay_visible and _overlay_label:
		_update_overlay_text()

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------
func log_event(level: String, context: String, msg: String) -> void:
	var entry := {
		"t": Time.get_time_string_from_system(),
		"level": level,
		"context": context,
		"msg": msg,
	}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	var line := "[%s] %s/%s: %s" % [entry["t"], level, context, msg]
	print("[ERR-REPORT] " + line)
	var log_path := LOG_DIR + "/runtime.log"
	var mode: int = FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE
	var f := FileAccess.open(log_path, mode)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func report_error(context: String, msg: String) -> void:
	log_event("ERROR", context, msg)

func report_warning(context: String, msg: String) -> void:
	log_event("WARN", context, msg)

func get_stats() -> Dictionary:
	return {
		"checks": _checks_run,
		"fixes": _fixes_applied,
		"entries": _entries.size(),
	}

# ---------------------------------------------------------------------------
# Checagens de integridade + autodebug
# ---------------------------------------------------------------------------
func run_checks(phase: String) -> Array:
	_checks_run += 1
	var problems: Array = []
	_check_planet(problems)
	_check_subviewports(problems)
	_check_selection_refs(problems)
	_check_units(problems)
	_check_game_manager(problems)
	_check_fps(problems)
	for p in problems:
		var level := "WARN" if p.get("fixed", false) else "ERROR"
		var msg: String = p["msg"]
		if p.get("fixed", false):
			msg += " [autodebug: %s]" % p.get("fix", "corrigido")
			_fixes_applied += 1
		log_event(level, phase, msg)
	return problems

func _check_planet(problems: Array) -> void:
	var planet = get_tree().get_first_node_in_group("planet")
	if planet == null:
		problems.append({"msg": "Planeta (grupo 'planet') nao encontrado", "fixed": false})
		return
	var ps = planet.get_node_or_null("PlanetSurface")
	if ps == null:
		problems.append({"msg": "PlanetSurface ausente", "fixed": false})
		return
	if ps.material == null or not (ps.material is ShaderMaterial) or (ps.material as ShaderMaterial).shader == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/populous_planet.gdshader")
		ps.material = mat
		problems.append({
			"msg": "Material do terreno ausente/invalido",
			"fixed": true,
			"fix": "ShaderMaterial recreado a partir de populous_planet.gdshader",
		})

func _check_subviewports(problems: Array) -> void:
	for vp in get_tree().root.find_children("*", "SubViewport", true, false):
		if vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			problems.append({
				"msg": "SubViewport '%s' estava com render desativado (tela preta)" % vp.name,
				"fixed": true,
				"fix": "render_target_update_mode = UPDATE_ALWAYS",
			})

func _check_selection_refs(problems: Array) -> void:
	for sm in get_tree().get_nodes_in_group("selection_manager"):
		if not is_instance_valid(sm):
			continue
		var before: int = sm.selected_units.size()
		var alive: Array = []
		for u in sm.selected_units:
			if is_instance_valid(u):
				alive.append(u)
		if alive.size() != before:
			sm.selected_units = alive
			problems.append({
				"msg": "Selecao continha %d unidade(s) liberada(s)/invalida(s)" % (before - alive.size()),
				"fixed": true,
				"fix": "referencias mortas removidas do array de selecao",
			})
		if sm.selected_building != null and not is_instance_valid(sm.selected_building):
			sm.selected_building = null
			problems.append({
				"msg": "selected_building apontava para objeto liberado",
				"fixed": true,
				"fix": "selected_building = null",
			})
		if sm.selected_resource != null and not is_instance_valid(sm.selected_resource):
			sm.selected_resource = null
			problems.append({
				"msg": "selected_resource apontava para objeto liberado",
				"fixed": true,
				"fix": "selected_resource = null",
			})
		if sm.control_groups is Dictionary:
			for gk in sm.control_groups.keys():
				var garr: Array = []
				for u in sm.control_groups[gk]:
					if is_instance_valid(u):
						garr.append(u)
				sm.control_groups[gk] = garr

func _check_units(problems: Array) -> void:
	if _entity_shader == null:
		_entity_shader = load("res://shaders/entity_sphere.gdshader")
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		# sprite sem material => entidade "sem sombra/luz" (bug ja visto)
		var spr = u.get_node_or_null("Sprite2D")
		if spr and spr.material == null and _entity_shader != null:
			var m := ShaderMaterial.new()
			m.shader = _entity_shader
			spr.material = m
			problems.append({
				"msg": "Unidade '%s' sem material no sprite" % u.name,
				"fixed": true,
				"fix": "entity_sphere.gdshader reaplicado",
			})
		# watchdog de unidade travada (is_moving sem velocidade por muito tempo)
		if "is_moving" in u and u.is_moving:
			var id := u.get_instance_id()
			var p: Vector2 = u.global_position
			if not _unit_watch.has(id):
				_unit_watch[id] = {"pos": p, "t": 0.0}
			else:
				var w = _unit_watch[id]
				if w["pos"].distance_to(p) < 0.5:
					w["t"] += CHECK_INTERVAL
					if w["t"] >= 10.0:
						u.is_moving = false
						if "velocity" in u:
							u.velocity = Vector2.ZERO
						if "current_state" in u and u.current_state == u.UnitState.MOVING:
							u.current_state = u.UnitState.IDLE
						problems.append({
							"msg": "Unidade '%s' travada ha %.0fs (is_moving sem deslocamento)" % [u.name, w["t"]],
							"fixed": true,
							"fix": "estado resetado para IDLE",
						})
						_unit_watch.erase(id)
				else:
					_unit_watch[id] = {"pos": p, "t": 0.0}

var _unit_watch: Dictionary = {}

func _check_game_manager(problems: Array) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.elemeth < 0:
		gm.elemeth = 0
		problems.append({
			"msg": "GameManager.elemeth negativo (%d)" % gm.elemeth,
			"fixed": true,
			"fix": "clamp para 0",
		})

func _check_fps(problems: Array) -> void:
	# Em modo headless nao existe render real: o FPS medido e' artificial (1) e
	# geraria um falso positivo em toda execucao de teste. So' avaliamos FPS
	# quando ha um display de verdade.
	if DisplayServer.get_name() == "headless":
		return
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	if fps > 0.0 and fps < 25.0 and Time.get_ticks_msec() / 1000.0 - _last_fps_warn > 60.0:
		_last_fps_warn = Time.get_ticks_msec() / 1000.0
		problems.append({
			"msg": "FPS baixo detectado (%.0f)" % fps,
			"fixed": false,
		})

# ---------------------------------------------------------------------------
# Relatorio final (ao fechar)
# ---------------------------------------------------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_write_report()

func _write_report() -> void:
	# copia um resumo para dentro do projeto (facil de encontrar)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# Relatorio de execucao — Elementio")
	f.store_line("Gerado: %s" % Time.get_datetime_string_from_system())
	f.store_line("Godot: %s | SO: %s" % [Engine.get_version_info().string, OS.get_name()])
	f.store_line("Checagens: %d | Autofixes aplicados: %d | Eventos: %d" % [
		_checks_run, _fixes_applied, _entries.size()])
	f.store_line("")
	var errors := 0
	var warns := 0
	for e in _entries:
		if e["level"] == "ERROR":
			errors += 1
		elif e["level"] == "WARN":
			warns += 1
	f.store_line("RESUMO: %d erro(s), %d aviso(s)" % [errors, warns])
	f.store_line("")
	f.store_line("## Ultimos eventos")
	var start: int = max(0, _entries.size() - 100)
	for i in range(start, _entries.size()):
		var e = _entries[i]
		f.store_line("- [%s] %s/%s: %s" % [e["t"], e["level"], e["context"], e["msg"]])
	f.close()

# ---------------------------------------------------------------------------
# Overlay de debug (F3)
# ---------------------------------------------------------------------------
func _setup_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 999
	add_child(_overlay_layer)
	var panel := PanelContainer.new()
	panel.self_modulate = Color(1, 1, 1, 0.85)
	panel.position = Vector2(8, 52)
	_overlay_layer.add_child(panel)
	_overlay_label = Label.new()
	_overlay_label.add_theme_font_size_override("font_size", 13)
	_overlay_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	panel.add_child(_overlay_label)
	_overlay_layer.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_F3:
		_overlay_visible = not _overlay_visible
		if _overlay_layer:
			_overlay_layer.visible = _overlay_visible
		if _overlay_visible:
			_update_overlay_text()

func _update_overlay_text() -> void:
	var mem_mb := OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var last: String = "-"
	if _entries.size() > 0:
		last = str(_entries[_entries.size() - 1]["msg"])
	_overlay_label.text = "F3: AUTODEBUG ATIVO\nFPS: %.0f | Mem: %.1f MB\nChecagens: %d | Autofixes: %d | Eventos: %d\nUltimo: %s" % [
		Performance.get_monitor(Performance.TIME_FPS), mem_mb,
		_checks_run, _fixes_applied, _entries.size(), last]
