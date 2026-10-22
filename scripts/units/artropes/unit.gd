extends CharacterBody2D

const _PlanetTerrain = preload("res://scripts/planet_terrain.gd")

@export var unit_type: String = "Skito"
@export var speed: float = 140.0
@export var max_health: int = 100
var current_health: int = 100
# Equipe: 0 = jogador, 1+ = inimigo/outro jogador
@export var team: int = Faction.PLAYER
# Unidades do jogador sao controlaveis
var is_controllable: bool = true
# Unidades operarias (Skito) coletam recursos; as demais (Spider, Mantis) atacam.
@export var is_worker: bool = false
# Combate
@export var attack_damage: int = 10
@export var attack_range: float = 24.0
@export var attack_cooldown: float = 0.8
var attack_timer: float = 0.0
var target_enemy: Node2D = null
const AUTO_ATTACK_RADIUS: float = 170.0
var acquire_timer: float = 0.0

var target_position: Vector2
var path: Array[Vector2] = []
var path_index: int = 0

var is_selected: bool = false
var is_moving: bool = false

# Sistema de Coleta e Estados
enum UnitState { IDLE, MOVING, HARVESTING, RETURNING_TO_BASE, ATTACKING }
var current_state: UnitState = UnitState.IDLE

var target_resource = null
var target_nest = null
var carried_elementio: int = 0
var max_carry_capacity: int = 200
var harvest_timer: float = 0.0
var harvest_interval: float = 1.0

# Animação de Spritesheet (frames 0-1 = Walk/Fly; frames 2-3 = Harvest/Attack)
var anim_timer: float = 0.0

# Raio máximo do mapa toroidal (metade de world_size do terreno).
# Precisa ser IGUAL ao do terreno, senão a unidade "pula" ao cruzar a emenda.
var sphere_map_radius: float = 4000.0

@onready var selection_ring = $SelectionRing
@onready var sprite = $Sprite2D
var _sphere_mat: ShaderMaterial = null
@onready var resource_indicator = $ResourceIndicator if has_node("ResourceIndicator") else null
# Barra de carga (6 divisoes) sobre a unidade
var carry_bar_container: Node2D = null
var carry_bar_fill: ColorRect = null
var is_unloading: bool = false
var unload_timer: float = 0.0
# Reference to the planet terrain node for walkability checks
var planet
# Units that can fly over water (e.g., Skito). Set true in the inspector for flying units.
@export var can_fly_over_water: bool = false

func _ready() -> void:
	target_position = global_position
	current_health = max_health
	is_controllable = (team == Faction.PLAYER)
	selection_ring.visible = false
	if resource_indicator:
		resource_indicator.visible = false
	add_to_group("units")
	add_to_group("artropes")
	_sphere_mat = ShaderMaterial.new()
	_sphere_mat.shader = load("res://shaders/entity_sphere.gdshader")
	if sprite:
		sprite.material = _sphere_mat
		# Unidades inimigas recebem um tom avermelhado para identificacao
		if team == Faction.ENEMY:
			sprite.modulate = Color(1.0, 0.55, 0.55, 1.0)
	_setup_carry_bar()

func _process(_delta: float) -> void:
	_update_sphere_shading()
	_update_carry_bar()

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

func _physics_process(delta: float) -> void:
	anim_timer += delta

	# Unidades de combate adquirem automaticamente hostis proximos. Isso vale
	# para os dois lados (jogador e IA) e tambem para construcoes inimigas.
	if not is_worker and current_state != UnitState.ATTACKING \
			and current_state != UnitState.HARVESTING \
			and current_state != UnitState.RETURNING_TO_BASE:
		acquire_timer -= delta
		if acquire_timer <= 0.0:
			acquire_timer = 0.5
			var hostile := _find_nearest_hostile(AUTO_ATTACK_RADIUS)
			if hostile != null:
				attack(hostile)

	# Mosquito sobrevoa a fonte (sem colisao) durante coleta/retorno
	if current_state == UnitState.HARVESTING or current_state == UnitState.RETURNING_TO_BASE:
		collision_mask = 0
	else:
		collision_mask = 1

	match current_state:
		UnitState.HARVESTING:
			_process_harvesting(delta)
		UnitState.RETURNING_TO_BASE:
			_process_returning(delta)
		UnitState.ATTACKING:
			_process_attacking(delta)
		_:
			_process_movement(delta)

	_update_animation_frame()
	# Wrap agora e' tratado pela camera (mundo toroidal): nao re-enrolar aqui,
	# senao desfaz a translacao da camera e causa saltos.
	# _constrain_to_sphere_surface()

const ANIM_SPEED: float = 2.0  # 2x mais rapido

func _update_animation_frame() -> void:
	if not sprite: return
	
	if current_state == UnitState.ATTACKING:
		# Frames 2 e 3: Golpe de Ataque
		sprite.frame = 2 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 3
	elif current_state == UnitState.HARVESTING:
		# Animacao de coleta SO quando sobre a fonte (hover); senao, voo
		var hovering = is_instance_valid(target_resource) and global_position.distance_to(target_resource.global_position) <= 8.0
		if hovering:
			sprite.frame = 2 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 3
		elif is_moving or velocity.length() > 5.0:
			sprite.frame = 0 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 1
		else:
			sprite.frame = 0 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 1
	elif is_moving or velocity.length() > 5.0:
		# Frames 0 e 1: Movimento / Voo / Caminhada (mais rápido em marcha)
		sprite.frame = 0 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 1
	else:
		# Parado (Idle): batimento lento de asas ou postura estática
		sprite.frame = 0 if int(anim_timer * ANIM_SPEED) % 2 == 0 else 1

func _process_movement(_delta: float) -> void:
	if is_moving:
		var wsize := _planet_world_size()
		var current_target = target_position
		if path.size() > 0 and path_index < path.size():
			current_target = path[path_index]
			if _PlanetTerrain.toroidal_delta(global_position, current_target, wsize).length() < 10.0:
				path_index += 1
				if path_index >= path.size():
					current_target = target_position
				else:
					current_target = path[path_index]

		# Mundo toroidal (Populous 3): mira pelo caminho MAIS CURTO, atravessando
		# a emenda quando for preciso, em vez de dar a volta inteira no mapa.
		var to_target := _PlanetTerrain.toroidal_delta(global_position, current_target, wsize)
		var direction := to_target.normalized()
		var distance := _PlanetTerrain.toroidal_delta(global_position, target_position, wsize).length()
		
		if distance > 6.0:
			var desired_velocity = direction * speed
			var separation = _calculate_separation()
			desired_velocity += separation * (speed * 0.5)
			
			velocity = desired_velocity.limit_length(speed)
			move_and_slide()
			
			# Orientação para o movimento (flip horizontal se mover para a esquerda)
			if velocity.x < -2.0:
				sprite.flip_h = true
			elif velocity.x > 2.0:
				sprite.flip_h = false
		else:
			is_moving = false
			velocity = Vector2.ZERO
			path.clear()
			path_index = 0

func _process_harvesting(delta: float) -> void:
	if not is_instance_valid(target_resource) or not _resource_has_elementio(target_resource):
		# Fonte esgotada/removida: libera a vaga e encerra a coleta
		_release_fountain_slot()
		target_resource = null
		if carried_elementio > 0:
			_find_nearest_nest()
			if target_nest:
				current_state = UnitState.RETURNING_TO_BASE
				set_target(target_nest.global_position)
				return
		current_state = UnitState.IDLE
		return

	# Fonte com fila: se ainda nao e o operario ativo, aguarda fora do circulo
	if target_resource.has_method("is_active_worker") and not target_resource.is_active_worker(self):
		var wait_pos: Vector2 = target_resource.get_wait_position(self)
		var wait_dist := _PlanetTerrain.toroidal_delta(global_position, wait_pos, _planet_world_size()).length()
		if wait_dist > 6.0:
			# Reposiciona se o alvo mudou (a fila andou) e volta a se mover
			if not is_moving or _PlanetTerrain.toroidal_delta(target_position, wait_pos, _planet_world_size()).length() > 6.0:
				set_target(wait_pos)
			_process_movement(delta)
		else:
			velocity = Vector2.ZERO
			is_moving = false
		return
		
	var fountain_pos: Vector2 = target_resource.global_position
	var dist := _PlanetTerrain.toroidal_delta(global_position, fountain_pos, _planet_world_size()).length()
	if dist > 8.0:
		# Promovida: retoma o movimento ate a fonte automaticamente
		if not is_moving or _PlanetTerrain.toroidal_delta(target_position, fountain_pos, _planet_world_size()).length() > 6.0:
			set_target(fountain_pos)
		_process_movement(delta)
	else:
		# Sobrevoa a fonte: trava sobre ela
		global_position = target_resource.global_position
		velocity = Vector2.ZERO
		is_moving = false
		harvest_timer += delta
		if harvest_timer >= harvest_interval:
			harvest_timer = 0.0
			var gathered = target_resource.harvest(20)
			carried_elementio += gathered
			if carried_elementio > max_carry_capacity:
				carried_elementio = max_carry_capacity
			if resource_indicator:
				resource_indicator.visible = (carried_elementio > 0)
			
			# Fonte esgotada ou sem ganho: encerra a coleta
			var depleted = (not is_instance_valid(target_resource)) or (target_resource.has_method("is_depleted") and target_resource.is_depleted) or gathered <= 0
			if carried_elementio >= max_carry_capacity:
				_rotate_fountain_slot()
				_find_nearest_nest()
				if target_nest:
					current_state = UnitState.RETURNING_TO_BASE
					set_target(target_nest.global_position)
			elif depleted:
				_release_fountain_slot()
				target_resource = null
				if carried_elementio > 0:
					_find_nearest_nest()
					if target_nest:
						current_state = UnitState.RETURNING_TO_BASE
						set_target(target_nest.global_position)
						return
				current_state = UnitState.IDLE

func _process_returning(delta: float) -> void:
	if not is_instance_valid(target_nest):
		_find_nearest_nest()
		if not target_nest:
			current_state = UnitState.IDLE
			return
			
	var dist := _PlanetTerrain.toroidal_delta(global_position, target_nest.global_position, _planet_world_size()).length()
	if dist > 36.0:
		is_unloading = false
		target_position = target_nest.global_position
		_process_movement(delta)
	else:
		is_moving = false
		velocity = Vector2.ZERO
		if not is_unloading:
			is_unloading = true
			unload_timer = 0.0
		unload_timer += delta
		if unload_timer >= 0.4:
			unload_timer = 0.0
			var chunk = min(40, carried_elementio)
			if chunk > 0:
				GameManager.add_elemeth(chunk, team)
				carried_elementio -= chunk
				_update_carry_bar()
			if carried_elementio <= 0:
				carried_elementio = 0
				is_unloading = false
				if resource_indicator:
					resource_indicator.visible = false
				# Permanece na fila durante o ciclo; volta quando for a vez
				var still_harvestable = _resource_has_elementio(target_resource)
				var still_allocated = still_harvestable and target_resource.has_method("is_worker_allocated") and bool(target_resource.call("is_worker_allocated", self))
				if still_allocated:
					current_state = UnitState.HARVESTING
					if bool(target_resource.call("is_active_worker", self)):
						set_target(target_resource.global_position)
					else:
						var wait_pos: Vector2 = target_resource.call("get_wait_position", self)
						set_target(wait_pos)
				elif still_harvestable:
					harvest_resource(target_resource as Node2D)
				else:
					target_resource = null
					current_state = UnitState.IDLE
func _process_attacking(delta: float) -> void:
	if not is_instance_valid(target_enemy):
		current_state = UnitState.IDLE
		target_enemy = null
		return
	var wsize := _planet_world_size()
	var dist := _PlanetTerrain.toroidal_delta(global_position, target_enemy.global_position, wsize).length()
	if dist > attack_range:
		# Move em direcao ao inimigo
		target_position = target_enemy.global_position
		_process_movement(delta)
	else:
		# No alcance: ataca
		is_moving = false
		velocity = Vector2.ZERO
		attack_timer += delta
		if attack_timer >= attack_cooldown:
			attack_timer = 0.0
			if target_enemy.has_method("take_damage"):
				target_enemy.take_damage(attack_damage)
				if not is_instance_valid(target_enemy) or (target_enemy.has_method("get_health_ratio") and target_enemy.get_health_ratio() <= 0.0):
					current_state = UnitState.IDLE
					target_enemy = null

func attack(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	# So pode atacar entidades hostis (classificacao diferente e nao neutra)
	if "team" in enemy and not Faction.is_hostile(team, enemy.team):
		return
	_release_fountain_slot()
	target_resource = null
	target_enemy = enemy
	current_state = UnitState.ATTACKING
	set_target(enemy.global_position)

func _find_nearest_nest() -> void:
	var nests = get_tree().get_nodes_in_group("buildings")
	var closest_dist = INF
	target_nest = null
	var wsize := _planet_world_size()
	for n in nests:
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n.get("is_ghost") == true:
			continue
		# So entrega recursos em construcoes da propria faccao.
		if "team" in n and int(n.get("team")) != team:
			continue
		var d := _PlanetTerrain.toroidal_delta(global_position, n.global_position, wsize).length()
		if d < closest_dist:
			closest_dist = d
			target_nest = n

## Procura a entidade hostil mais proxima dentro do raio (unidades, inimigos
## avulsos ou construcoes). Neutros nunca sao alvos.
func _find_nearest_hostile(radius: float) -> Node2D:
	var best = null
	var best_dist := radius
	var wsize := _planet_world_size()
	for group_name in ["units", "buildings", "enemies"]:
		for e in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(e) or e == self or e.is_queued_for_deletion():
				continue
			if not (e is Node2D):
				continue
			if not ("team" in e) or not Faction.is_hostile(team, int(e.get("team"))):
				continue
			if e.get("is_ghost") == true:
				continue
			var d := _PlanetTerrain.toroidal_delta(
				global_position, (e as Node2D).global_position, wsize).length()
			if d < best_dist:
				best_dist = d
				best = e
	return best

func harvest_resource(resource_node: Node2D) -> void:
	if not is_worker:
		return  # apenas operarias coletam recursos
	if not _resource_has_elementio(resource_node):
		return  # fonte esgotada ou invalida nao pode ser coletada
	# Troca de fonte: libera a vaga anterior
	if is_instance_valid(target_resource) and target_resource != resource_node:
		_release_fountain_slot()
	target_resource = resource_node
	target_enemy = null
	current_state = UnitState.HARVESTING
	# Fonte com ocupacao: entra na fila (maximo de 4 operarios alocados)
	if resource_node.has_method("request_worker"):
		if not bool(resource_node.call("request_worker", self)):
			target_resource = null
			if carried_elementio > 0:
				_find_nearest_nest()
				if target_nest:
					current_state = UnitState.RETURNING_TO_BASE
					set_target(target_nest.global_position)
					return
			current_state = UnitState.IDLE
			return
	var dest: Vector2 = resource_node.global_position
	if resource_node.has_method("is_active_worker") and not bool(resource_node.call("is_active_worker", self)):
		var wait_pos: Vector2 = resource_node.call("get_wait_position", self)
		dest = wait_pos
	set_target(dest)

## Libera a vaga na fonte (outra ordem, fonte esgotada).
func _release_fountain_slot() -> void:
	if not is_instance_valid(target_resource):
		return
	if target_resource.has_method("release_worker"):
		target_resource.release_worker(self)

## Sai da fonte para descarregar: continua alocada, mas vai ao fim da fila.
func _rotate_fountain_slot() -> void:
	if not is_instance_valid(target_resource):
		return
	if target_resource.has_method("rotate_worker"):
		target_resource.rotate_worker(self)

## Retorna true se a fonte ainda tem recurso para coletar.
func _resource_has_elementio(resource_node: Node) -> bool:
	if resource_node == null or not is_instance_valid(resource_node):
		return false
	if "is_depleted" in resource_node and bool(resource_node.get("is_depleted")):
		return false
	if "remaining_elementio" in resource_node and int(resource_node.get("remaining_elementio")) <= 0:
		return false
	return true

func _constrain_to_sphere_surface() -> void:
	# Usa o mesmo tamanho de mundo do terreno para a emenda (wrap) coincidir
	var planet_node = get_tree().get_first_node_in_group("planet")
	if planet_node and "world_size" in planet_node:
		sphere_map_radius = planet_node.world_size.x / 2.0
	var half_w = sphere_map_radius
	var half_h = planet_node.world_size.y / 2.0 if (planet_node and "world_size" in planet_node) else sphere_map_radius
	if global_position.x > half_w:
		global_position.x = -half_w + (global_position.x - half_w)
	elif global_position.x < -half_w:
		global_position.x = half_w - (-half_w - global_position.x)
	if global_position.y > half_h:
		global_position.y = -half_h + (global_position.y - half_h)
	elif global_position.y < -half_h:
		global_position.y = half_h - (-half_h - global_position.y)

func _calculate_separation() -> Vector2:
	var separation := Vector2.ZERO
	var neighbor_count := 0
	var units = get_tree().get_nodes_in_group("units")
	var wsize := _planet_world_size()
	for u in units:
		if u != self and is_instance_valid(u):
			var off := _PlanetTerrain.toroidal_delta(u.global_position, global_position, wsize)
			var dist := off.length()
			if dist > 0.1 and dist < 24.0:
				separation += off.normalized() / dist
				neighbor_count += 1
	if neighbor_count > 0:
		separation = (separation / neighbor_count).normalized()
	return separation

# Tamanho do mundo toroidal, lido do terreno (mesma fonte usada pelo shader).
func _planet_world_size() -> Vector2:
	var planet_node = get_tree().get_first_node_in_group("planet")
	if planet_node and "world_size" in planet_node:
		var ws: Vector2 = planet_node.world_size
		return ws
	return Vector2(8000.0, 4000.0)

func _setup_carry_bar() -> void:
	var container = Node2D.new()
	container.name = "CarryBar"
	container.position = Vector2(0, -18)
	add_child(container)
	carry_bar_container = container

	var bg = ColorRect.new()
	bg.size = Vector2(40, 4)
	bg.position = Vector2(-20, 0)
	bg.color = Color(0.12, 0.12, 0.12, 0.85)
	container.add_child(bg)

	carry_bar_fill = ColorRect.new()
	carry_bar_fill.size = Vector2(0, 4)
	carry_bar_fill.position = Vector2(-20, 0)
	carry_bar_fill.color = Color(0.2, 0.95, 0.35, 1.0)
	container.add_child(carry_bar_fill)

	for i in range(1, 6):
		var tick = ColorRect.new()
		tick.size = Vector2(1, 4)
		tick.position = Vector2(-20 + i * (40.0 / 6.0), 0)
		tick.color = Color(0, 0, 0, 0.75)
		container.add_child(tick)

	container.visible = false

func _update_carry_bar() -> void:
	if carry_bar_container == null:
		return
	# Barra visivel apenas ao coletar/recursos carregados
	if carried_elementio <= 0:
		carry_bar_container.visible = false
		return
	carry_bar_container.visible = true
	var ratio = clamp(float(carried_elementio) / float(max_carry_capacity), 0.0, 1.0)
	carry_bar_fill.size.x = 40.0 * ratio

func _draw() -> void:
	# Indicador de selecao: elipse na cor da classificacao (topdown, centro 10%)
	if is_selected:
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 14.0, Faction.selection_fill(team))
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, Faction.selection_color(team), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func select() -> void:
	is_selected = true
	if selection_ring:
		selection_ring.visible = false
	queue_redraw()

func deselect() -> void:
	is_selected = false
	if selection_ring:
		selection_ring.visible = false
	queue_redraw()

func set_target(pos: Vector2, interrupt_collection: bool = false) -> void:
	if interrupt_collection:
		# Para o ciclo de coleta (coleta/retorno) ao receber outro comando
		_release_fountain_slot()
		target_resource = null
		target_nest = null
		harvest_timer = 0.0
		is_unloading = false
		unload_timer = 0.0
		current_state = UnitState.MOVING
	target_position = pos
	path.clear()
	path_index = 0
	
	var map = get_world_2d().navigation_map
	if map.is_valid():
		var nav_path = NavigationServer2D.map_get_path(map, global_position, pos, true)
		if nav_path.size() > 1:
			path = nav_path
			path_index = 1
	is_moving = true
