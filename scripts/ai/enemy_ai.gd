extends Node
## IA simples do jogador inimigo.
##
## Comportamento:
## - Treina operarias ate WORKER_TARGET e combatentes ate ARMY_TARGET.
## - Coloca operarias ociosas nas fontes com vaga (espalhando entre elas).
## - Defende a base quando unidades do jogador se aproximam.
## - Quando o exercito esta grande o suficiente, ataca a construcao do
##   jogador mais proxima. Vence quem destruir todas as construcoes inimigas.

const DECISION_INTERVAL: float = 1.0
const WORKER_TARGET: int = 3
const ARMY_TARGET: int = 6
const MAX_QUEUE: int = 2
const DEFENSE_RADIUS: float = 420.0
const ATTACK_INTERVAL: float = 5.0
const FOUNTAIN_SLOTS: int = 4
const STATE_IDLE: int = 0
const STATE_ATTACKING: int = 4

var decision_timer: float = 0.0
var attack_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_ai")

func _process(delta: float) -> void:
	if GameManager.match_over:
		return
	decision_timer -= delta
	if decision_timer > 0.0:
		return
	decision_timer = DECISION_INTERVAL
	_think()

func _think() -> void:
	var nest := _find_enemy_nest()
	if nest == null:
		return
	_assign_workers()
	_produce(nest)
	_command_army(nest)

func _find_enemy_nest() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_queued_for_deletion() or not (b is Node2D):
			continue
		if b.get("is_ghost") == true:
			continue
		if "team" in b and int(b.get("team")) == Faction.ENEMY:
			return b as Node2D
	return null

func _enemy_units() -> Array:
	var result: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if "team" in u and int(u.get("team")) == Faction.ENEMY:
			result.append(u)
	return result

func _assign_workers() -> void:
	for w in _enemy_units():
		if not bool(w.get("is_worker")):
			continue
		if int(w.get("current_state")) != STATE_IDLE:
			continue
		var fountain := _best_fountain(w)
		if fountain != null:
			w.call("harvest_resource", fountain)

## Escolhe a fonte com mais vagas e, em empate, a mais proxima da operaria.
## Isso distribui os operarios entre as fontes em vez de lotar uma so.
func _best_fountain(worker: Node) -> Node2D:
	var best: Node2D = null
	var best_slots: int = 0
	var best_dist := INF
	var wsize := _world_size()
	for r in get_tree().get_nodes_in_group("elementio_sources"):
		if not is_instance_valid(r) or r.is_queued_for_deletion() or not (r is Node2D):
			continue
		if r.get("is_depleted") == true:
			continue
		if int(r.get("remaining_elementio")) <= 0:
			continue
		var slots := FOUNTAIN_SLOTS - int(r.call("get_allocated_workers"))
		if slots <= 0:
			continue
		var d := PlanetTerrain.toroidal_delta(
			(worker as Node2D).global_position, (r as Node2D).global_position, wsize).length()
		if slots > best_slots or (slots == best_slots and d < best_dist):
			best_slots = slots
			best_dist = d
			best = r as Node2D
	return best

func _produce(nest: Node2D) -> void:
	var prod_queue: Array = nest.get("production_queue")
	var queue_len: int = prod_queue.size()
	if bool(nest.get("is_producing")):
		queue_len += 1
	if queue_len >= MAX_QUEUE:
		return

	var workers := 0
	var army := 0
	for u in _enemy_units():
		if bool(u.get("is_worker")):
			workers += 1
		else:
			army += 1

	if workers < WORKER_TARGET:
		if GameManager.can_afford(GameManager.skito_cost, Faction.ENEMY):
			GameManager.spend(GameManager.skito_cost, Faction.ENEMY)
			nest.call("spawn_unit", "skito")
		return

	if army >= ARMY_TARGET:
		return
	# Mistura o exercito: Spider (corpo a corpo), Mantis (pesado) e Scorpion
	# (a distancia, com veneno). Se o recurso nao der para o tipo sorteado,
	# cai para Spider.
	var unit_name := "spider"
	match army % 3:
		1:
			unit_name = "mantis"
		2:
			unit_name = "scorpion"
	var cost := _unit_cost(unit_name)
	if not GameManager.can_afford(cost, Faction.ENEMY) and unit_name != "spider":
		unit_name = "spider"
		cost = _unit_cost(unit_name)
	if GameManager.can_afford(cost, Faction.ENEMY):
		GameManager.spend(cost, Faction.ENEMY)
		nest.call("spawn_unit", unit_name)

func _unit_cost(unit_name: String) -> int:
	match unit_name:
		"mantis":
			return GameManager.mantis_cost
		"scorpion":
			return GameManager.scorpion_cost
		_:
			return GameManager.spider_cost

func _command_army(nest: Node2D) -> void:
	attack_timer -= DECISION_INTERVAL
	if attack_timer > 0.0:
		return
	attack_timer = ATTACK_INTERVAL

	var combat: Array = []
	for u in _enemy_units():
		if not bool(u.get("is_worker")):
			combat.append(u)
	if combat.is_empty():
		return

	var intruder := _nearest_player_unit(nest.global_position, DEFENSE_RADIUS)
	var target: Node2D = intruder
	if target == null:
		target = _nearest_player_building(nest.global_position)
	if target == null:
		return
	# Sem ameaca imediata, o exercito so ataca quando tiver forca.
	if intruder == null and combat.size() < 3:
		return

	for u in combat:
		if int(u.get("current_state")) == STATE_ATTACKING:
			continue
		u.call("attack", target)

func _nearest_player_unit(pos: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist := radius
	var wsize := _world_size()
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.is_queued_for_deletion() or not (u is Node2D):
			continue
		if not ("team" in u) or int(u.get("team")) != Faction.PLAYER:
			continue
		if u.get("is_ghost") == true:
			continue
		var d := PlanetTerrain.toroidal_delta(
			pos, (u as Node2D).global_position, wsize).length()
		if d <= best_dist:
			best_dist = d
			best = u as Node2D
	return best

func _nearest_player_building(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var wsize := _world_size()
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_queued_for_deletion() or not (b is Node2D):
			continue
		if b.get("is_ghost") == true:
			continue
		if not ("team" in b) or int(b.get("team")) != Faction.PLAYER:
			continue
		var d := PlanetTerrain.toroidal_delta(
			pos, (b as Node2D).global_position, wsize).length()
		if d < best_dist:
			best_dist = d
			best = b as Node2D
	return best

func _world_size() -> Vector2:
	var planet = get_tree().get_first_node_in_group("planet")
	if planet and "world_size" in planet:
		var ws: Vector2 = planet.get("world_size")
		return ws
	return Vector2(8000.0, 4000.0)
