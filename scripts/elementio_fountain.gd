extends StaticBody2D

const _PlanetTerrain = preload("res://scripts/planet_terrain.gd")

@export var remaining_elementio: int = 20000
# Classificacao da entidade: fonte natural e neutra
@export var team: int = Faction.NEUTRAL
var max_elementio: int = 20000
var is_depleted: bool = false
@onready var selection_ring = $SelectionRing if has_node("SelectionRing") else null
@onready var sprite = $Sprite2D if has_node("Sprite2D") else null
var _sphere_mat: ShaderMaterial = null
# Barra de recurso (6 divisoes) sobre a fonte
var res_bar_container: Node2D = null
var res_bar_fill: ColorRect = null
# Animacao da spritesheet (8 frames)
var anim_timer: float = 0.0
const FRAME_INTERVAL: float = 0.5  # 2x mais rapido (original 1.0)

var is_selected: bool = false

# Ocupacao: apenas 1 operario extrai por vez; ate 4 podem ficar alocados (fila)
const MAX_WORKERS: int = 4
const WAIT_OFFSETS := [Vector2(64, 0), Vector2(-64, 0), Vector2(0, 44), Vector2(0, -44)]
var worker_queue: Array = []
var active_worker: Node = null
var worker_label: Label = null

func _ready() -> void:
	add_to_group("resources")
	add_to_group("elementio_sources")
	if selection_ring:
		selection_ring.visible = false
	max_elementio = remaining_elementio
	_sphere_mat = ShaderMaterial.new()
	_sphere_mat.shader = load("res://shaders/entity_sphere.gdshader")
	if sprite:
		sprite.material = _sphere_mat
	_setup_res_bar()

func _process(_delta: float) -> void:
	if not is_depleted:
		anim_timer += _delta
		if sprite and sprite.hframes > 0 and sprite.vframes > 0:
			var total = sprite.hframes * sprite.vframes
			sprite.frame = int(anim_timer / FRAME_INTERVAL) % total
	else:
		if sprite:
			sprite.frame = 0
	_update_sphere_shading()
	_update_res_bar()
	_maintain_workers()

func _update_sphere_shading() -> void:
	if _sphere_mat == null:
		return
	var u = _PlanetTerrain.get_sphere_uniforms()
	_sphere_mat.set_shader_parameter("camera_offset", u["camera_offset"])
	_sphere_mat.set_shader_parameter("rect_size", u["rect_size"])
	_sphere_mat.set_shader_parameter("planet_radius", u["planet_radius"])
	_sphere_mat.set_shader_parameter("planet_radius_world", u["planet_radius_world"])
	_sphere_mat.set_shader_parameter("atmosphere_color", u["atmosphere_color"])
	_sphere_mat.set_shader_parameter("entity_world_pos", global_position)

func _setup_res_bar() -> void:
	var container = Node2D.new()
	container.name = "ResBar"
	container.position = Vector2(0, -34)
	add_child(container)
	res_bar_container = container

	var bg = ColorRect.new()
	bg.size = Vector2(44, 4)
	bg.position = Vector2(-22, 0)
	bg.color = Color(0.12, 0.12, 0.12, 0.85)
	container.add_child(bg)

	res_bar_fill = ColorRect.new()
	res_bar_fill.size = Vector2(44, 4)
	res_bar_fill.position = Vector2(-22, 0)
	res_bar_fill.color = Color(0.2, 0.85, 1.0, 1.0)
	container.add_child(res_bar_fill)

	for i in range(1, 6):
		var tick = ColorRect.new()
		tick.size = Vector2(1, 4)
		tick.position = Vector2(-22 + i * (44.0 / 6.0), 0)
		tick.color = Color(0, 0, 0, 0.75)
		container.add_child(tick)

	worker_label = Label.new()
	worker_label.name = "WorkerCount"
	worker_label.position = Vector2(-22, -18)
	worker_label.size = Vector2(44, 16)
	worker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	worker_label.add_theme_font_size_override("font_size", 12)
	worker_label.add_theme_color_override("font_color", Faction.NEUTRAL_RING)
	worker_label.text = "0/%d" % MAX_WORKERS
	container.add_child(worker_label)

func _update_res_bar() -> void:
	if res_bar_fill == null:
		return
	var ratio = 0.0
	if max_elementio > 0:
		ratio = clamp(float(remaining_elementio) / float(max_elementio), 0.0, 1.0)
	res_bar_fill.size.x = 44.0 * ratio

func _update_worker_label() -> void:
	if worker_label == null:
		return
	worker_label.text = "%d/%d" % [worker_queue.size(), MAX_WORKERS]

func _maintain_workers() -> void:
	_cleanup_workers()
	_promote_worker()
	_update_worker_label()

func _cleanup_workers() -> void:
	var valid: Array = []
	for w in worker_queue:
		if w != null and is_instance_valid(w):
			valid.append(w)
	worker_queue = valid
	if active_worker != null and (not is_instance_valid(active_worker) or not worker_queue.has(active_worker)):
		active_worker = null

func _promote_worker() -> void:
	_cleanup_workers()
	if is_depleted or remaining_elementio <= 0:
		active_worker = null
		return
	if active_worker != null and is_instance_valid(active_worker) and worker_queue.has(active_worker):
		return
	active_worker = null
	if worker_queue.is_empty():
		return
	# Ordem de alocacao: o primeiro da fila ocupa a fonte, sem pular ninguem
	active_worker = worker_queue[0]

func _clear_workers() -> void:
	worker_queue.clear()
	active_worker = null
	_update_worker_label()

## Tenta alocar um operario. Retorna false se a fonte estiver cheia ou esgotada.
func request_worker(unit: Node) -> bool:
	_cleanup_workers()
	if is_depleted or remaining_elementio <= 0:
		return false
	if unit == null or not is_instance_valid(unit):
		return false
	if worker_queue.has(unit):
		return true
	if worker_queue.size() >= MAX_WORKERS:
		return false
	worker_queue.append(unit)
	_promote_worker()
	_update_worker_label()
	return true

## Remove o operario da alocacao (outra ordem, fonte esgotada, etc.).
func release_worker(unit: Node) -> void:
	if unit == null:
		return
	worker_queue.erase(unit)
	if active_worker == unit:
		active_worker = null
	_promote_worker()
	_update_worker_label()

## Operario sai da fonte para descarregar no ninho: permanece alocado,
## porem vai para o fim da fila.
func rotate_worker(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if active_worker == unit:
		active_worker = null
	var idx: int = worker_queue.find(unit)
	if idx >= 0:
		worker_queue.remove_at(idx)
		worker_queue.append(unit)
	_promote_worker()
	_update_worker_label()

func is_worker_allocated(unit: Node) -> bool:
	return unit != null and worker_queue.has(unit)

func is_active_worker(unit: Node) -> bool:
	return active_worker != null and is_instance_valid(active_worker) and active_worker == unit

## Posicao de espera na fila (fora do circulo da fonte).
func get_wait_position(unit: Node) -> Vector2:
	var idx: int = worker_queue.find(unit)
	if idx < 0:
		idx = 0
	return global_position + WAIT_OFFSETS[idx % WAIT_OFFSETS.size()]

func get_allocated_workers() -> int:
	return worker_queue.size()
func harvest(amount: int) -> int:
	if is_depleted:
		return 0
	var harvested = min(amount, remaining_elementio)
	remaining_elementio -= harvested
	if remaining_elementio <= 0:
		remaining_elementio = 0
		is_depleted = true
		_clear_workers()
		if sprite:
			sprite.frame = 0
	# barra atualiza em _process
	return harvested

func select() -> void:
	is_selected = true
	if selection_ring:
		selection_ring.visible = false
	queue_redraw()
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("show_resource_menu"):
		ui.show_resource_menu(self)

func deselect() -> void:
	is_selected = false
	if selection_ring:
		selection_ring.visible = false
	queue_redraw()
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("hide_resource_menu"):
		ui.hide_resource_menu()

func _draw() -> void:
	# Indicador de selecao: elipse neutra (topdown, centro 10%)
	if is_selected:
		draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 34.0, Faction.selection_fill(team))
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Faction.selection_color(team), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_resource_info() -> String:
	var workers := "  |  Operarios: %d/%d" % [get_allocated_workers(), MAX_WORKERS]
	if is_depleted:
		return "⚡ Fonte de Elementio (Neutra)  |  Vida: ∞  |  Recurso: 0/%d (Esgotada)%s" % [max_elementio, workers]
	var pct = 0.0
	if max_elementio > 0:
		pct = float(remaining_elementio) / float(max_elementio) * 100.0
	return "⚡ Fonte de Elementio (Neutra)  |  Vida: ∞  |  Recurso: %d/%d (%.0f%%)  |  Coleta: 20/s  |  Descarga: 40/ciclo%s" % [remaining_elementio, max_elementio, pct, workers]
