extends StaticBody2D

const _PlanetTerrain = preload("res://scripts/planet_terrain.gd")

var is_selected: bool = false
# Marcador usado pela pre-visualizacao de construcao do HUD. Fantasmas nao
# contam para vitoria nem sao alvos da IA.
var is_ghost: bool = false
# Classificacao da entidade (player, enemy ou neutral)
@export var team: int = Faction.PLAYER
@onready var selection_ring = $SelectionRing
@onready var spawn_point = $SpawnPoint
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

var anim_timer: float = 0.0
var _sphere_mat: ShaderMaterial = null

# Vida da construcao
@export var max_health: int = 500
var current_health: int = 500

# Barra de vida
var health_bar_container: Node2D = null
var health_bar_fill: ColorRect = null

# Fila de producao
var is_producing: bool = false
var current_production: String = ""
var production_timer: float = 0.0
var production_time_total: float = 0.0
var production_queue: Array[String] = []

const PRODUCTION_TIMES: Dictionary = {
	"skito": 2.5,
	"spider": 3.0,
	"mantis": 3.5,
	"scorpion": 3.2,
}

# Barra de producao (HUD)
var prod_bar_bg: ColorRect = null
var prod_bar_fill: ColorRect = null

# Rally point
var rally_point: Vector2 = Vector2.ZERO
var has_rally_point: bool = false
var rally_flag: Node2D = null
var placing_rally: bool = false

const ANIM_SPEED: float = 2.0

func _ready() -> void:
	selection_ring.visible = false
	add_to_group("buildings")
	current_health = max_health
	_sphere_mat = ShaderMaterial.new()
	_sphere_mat.shader = load("res://shaders/entity_sphere.gdshader")
	if sprite:
		sprite.material = _sphere_mat
		if team == Faction.ENEMY:
			sprite.modulate = Color(1.0, 0.55, 0.55, 1.0)
	_setup_health_bar()
	_setup_production_queue()

func _process(delta: float) -> void:
	anim_timer += delta * ANIM_SPEED
	_update_sphere_shading()
	_update_health_bar()
	_process_production(delta)
	_update_production_queue()

	if sprite:
		if is_producing or production_queue.size() > 0:
			sprite.frame = 2 if int(anim_timer * 1.0) % 2 == 0 else 3
		else:
			sprite.frame = 0 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 1

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

func _setup_health_bar() -> void:
	var container = Node2D.new()
	container.name = "HealthBar"
	container.position = Vector2(0, -46)
	add_child(container)
	health_bar_container = container

	var bg = ColorRect.new()
	bg.size = Vector2(44, 4)
	bg.position = Vector2(-22, 0)
	bg.color = Color(0.12, 0.12, 0.12, 0.85)
	container.add_child(bg)

	health_bar_fill = ColorRect.new()
	health_bar_fill.size = Vector2(44, 4)
	health_bar_fill.position = Vector2(-22, 0)
	health_bar_fill.color = Color(0.2, 0.9, 0.3, 1.0)
	container.add_child(health_bar_fill)

func _update_health_bar() -> void:
	if health_bar_fill == null:
		return
	var ratio = 0.0
	if max_health > 0:
		ratio = clamp(float(current_health) / float(max_health), 0.0, 1.0)
	health_bar_fill.size.x = 44.0 * ratio
	if team == Faction.ENEMY:
		health_bar_fill.color = Color(0.95, 0.3, 0.25, 1.0).lerp(
			Color(0.55, 0.05, 0.05, 1.0), 1.0 - ratio)
	elif ratio > 0.5:
		health_bar_fill.color = Color(0.2, 0.9, 0.3, 1.0).lerp(Color(0.95, 0.9, 0.2, 1.0), (1.0 - ratio) * 2.0)
	else:
		health_bar_fill.color = Color(0.95, 0.9, 0.2, 1.0).lerp(Color(0.95, 0.2, 0.2, 1.0), (0.5 - ratio) * 2.0)

func _setup_production_queue() -> void:
	# Container colado acima da barra de vida (sem gap)
	var container = Node2D.new()
	container.name = "ProductionQueue"
	container.position = Vector2(0, -50)
	add_child(container)

	# Fundo da barra de producao
	prod_bar_bg = ColorRect.new()
	prod_bar_bg.size = Vector2(44, 4)
	prod_bar_bg.position = Vector2(-22, 0)
	prod_bar_bg.color = Color(0.12, 0.12, 0.12, 0.85)
	container.add_child(prod_bar_bg)

	# Preenchimento da barra de producao
	prod_bar_fill = ColorRect.new()
	prod_bar_fill.size = Vector2(0, 4)
	prod_bar_fill.position = Vector2(-22, 0)
	prod_bar_fill.color = Color(0.95, 0.75, 0.2, 1.0)
	container.add_child(prod_bar_fill)

	# (label de texto flutuante removido a pedido do usuario)

func _process_production(delta: float) -> void:
	if not is_producing:
		return
	production_timer -= delta
	if production_timer <= 0.0:
		_spawn_unit_now(current_production)
		_start_next_production()

func _start_next_production() -> void:
	if production_queue.size() == 0:
		is_producing = false
		current_production = ""
		production_timer = 0.0
		production_time_total = 0.0
		return
	current_production = production_queue[0]
	production_queue.remove_at(0)
	production_time_total = PRODUCTION_TIMES.get(current_production, 2.5)
	production_timer = production_time_total
	is_producing = true

func _spawn_unit_now(unit_name: String) -> void:
	var unit_scene = load("res://scenes/units/artropes/" + unit_name + ".tscn")
	var unit = unit_scene.instantiate()
	# Herda a faccao do ninho antes de entrar na arvore, para que _ready()
	# aplique a cor e a controlabilidade corretas.
	unit.team = team
	unit.is_controllable = (team == Faction.PLAYER)
	var spawn_pos = spawn_point.global_position
	var planet = get_tree().get_first_node_in_group("planet")
	if planet and planet.has_method("is_walkable_land"):
		if not planet.is_walkable_land(spawn_pos):
			var unit_can_fly = unit.get("can_fly_over_water") if "can_fly_over_water" in unit else false
			var is_water_tile = planet.is_water(spawn_pos)
			if not (unit_can_fly and is_water_tile):
				var found = false
				for i in range(16):
					var angle = float(i) * (TAU / 16.0)
					var radius = 40.0 + float(i) * 8.0
					var candidate = global_position + Vector2(cos(angle), sin(angle)) * radius
					if planet.is_walkable_land(candidate):
						spawn_pos = candidate
						found = true
						break
				if not found:
					spawn_pos = global_position
	unit.global_position = spawn_pos
	get_parent().add_child(unit)
	# Move para o rally point se definido; se o rally estiver sobre uma fonte,
	# o operario recebe automaticamente o ciclo de coleta.
	if has_rally_point:
		var rally_pos := get_rally_position()
		var resource_at_rally = _get_resource_at(rally_pos) if bool(unit.get("is_worker")) else null
		if resource_at_rally and unit.has_method("harvest_resource"):
			unit.harvest_resource(resource_at_rally)
			if unit.get("target_resource") == null and unit.has_method("set_target"):
				unit.set_target(rally_pos, true)
		elif unit.has_method("set_target"):
			unit.set_target(rally_pos, true)

func _get_resource_at(pos: Vector2) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_point(query)
	for r in result:
		var col = r.collider
		if col.is_in_group("resources") or col.is_in_group("elementio_sources"):
			return col
	return null

func spawn_unit(unit_name: String) -> void:
	production_queue.append(unit_name)
	if not is_producing and production_queue.size() > 0:
		_start_next_production()

func get_production_progress() -> float:
	if not is_producing or production_time_total <= 0.0:
		return 0.0
	return clampf(1.0 - (production_timer / production_time_total), 0.0, 1.0)

func get_production_queue_text() -> String:
	var parts: Array[String] = []
	if is_producing and current_production != "":
		var pct = int(get_production_progress() * 100.0)
		parts.append("%s %d%%" % [current_production.capitalize(), pct])
	for q in production_queue:
		parts.append(q.capitalize())
	if parts.size() == 0:
		return "Fila: vazia"
	return "Fila: " + ", ".join(parts)

func _update_production_queue() -> void:
	if prod_bar_fill == null or prod_bar_bg == null:
		return
	if is_producing:
		var pct = get_production_progress()
		prod_bar_fill.size.x = 44.0 * pct
		prod_bar_fill.visible = true
		prod_bar_bg.visible = true
	else:
		prod_bar_fill.size.x = 0.0
		prod_bar_fill.visible = false
		prod_bar_bg.visible = false

func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		current_health = 0
		queue_free()

func get_building_info() -> String:
	var pct = 0.0
	if max_health > 0:
		pct = float(current_health) / float(max_health) * 100.0
	return "Ninho Oco [%s]  |  Vida: %d/%d (%.0f%%)" % [
		Faction.faction_name(team), current_health, max_health, pct]

func set_rally_point(pos: Vector2) -> void:
	# Se o rally for definido sobre uma construcao, centraliza na construcao
	var building = _get_building_at(pos)
	if building != null:
		rally_point = building.global_position
	else:
		rally_point = pos
	has_rally_point = true
	# Remove flag anterior
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.queue_free()
	rally_flag = null
	# Cria nova flag visual
	var flag = Node2D.new()
	var pole = ColorRect.new()
	pole.size = Vector2(2, 16)
	pole.position = Vector2(-1, -16)
	pole.color = Color(0.8, 0.8, 0.8, 1)
	flag.add_child(pole)
	var banner = ColorRect.new()
	banner.size = Vector2(10, 6)
	banner.position = Vector2(1, -16)
	banner.color = Color(1.0, 0.3, 0.3, 1)
	flag.add_child(banner)
	# Filha do predio: acompanha o wrap toroidal junto com a construcao
	add_child(flag)
	flag.position = to_local(rally_point)
	rally_flag = flag
	# A bandeira so aparece com a construcao selecionada
	rally_flag.visible = is_selected

func _get_building_at(pos: Vector2) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_point(query)
	for r in result:
		var col = r.collider
		if col.is_in_group("buildings"):
			return col
	# Tolerancia para cliques na borda visual do sprite (alem do collider)
	var nearest = null
	var best := 44.0
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and is_instance_valid(b):
			var d: float = pos.distance_to((b as Node2D).global_position)
			if d <= best:
				best = d
				nearest = b
	return nearest

func get_rally_position() -> Vector2:
	if rally_flag and is_instance_valid(rally_flag):
		return rally_flag.global_position
	return rally_point

func clear_rally_point() -> void:
	has_rally_point = false
	rally_point = Vector2.ZERO
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.queue_free()
	rally_flag = null

func select() -> void:
	is_selected = true
	if selection_ring:
		selection_ring.visible = false
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.visible = true
	queue_redraw()
	# Construcoes inimigas podem ser inspecionadas visualmente, mas nao
	# abrem o menu de producao do jogador.
	if team != Faction.PLAYER:
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		ui.show_building_menu(self)

func deselect() -> void:
	is_selected = false
	if selection_ring:
		selection_ring.visible = false
	if rally_flag and is_instance_valid(rally_flag):
		rally_flag.visible = false
	queue_redraw()
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		ui.hide_building_menu()

func _draw() -> void:
	# Indicador de selecao: elipse na cor da classificacao (topdown, centro 10%)
	if is_selected:
		draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 34.0, Faction.selection_fill(team))
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Faction.selection_color(team), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)