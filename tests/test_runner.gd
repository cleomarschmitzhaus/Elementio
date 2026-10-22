extends Node
## Testes automatizados headless do Elementio.
## Executar: godot --headless --path <projeto> res://tests/test_runner.tscn
## Sai com codigo 0 se tudo passou, 1 se houve falha. Relatorio em
## docs/diagnostico/test_report.txt.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _report_lines: Array[String] = []

func _ready() -> void:
	print("=== ELEMENTIO TEST SUITE ===")
	await _test_terrain()
	await _test_fountain()
	await _test_unit_harvest_cycle()
	await _test_fountain_worker_queue()
	await _test_nest_rally()
	await _test_draw_layers()
	await _test_unit_stats_and_projectile()
	await _test_settings_menu()
	await _test_camera_wrap()
	await _test_toroidal_planet()
	await _test_selection_manager()
	await _test_game_manager()
	await _test_enemy_player()
	await _test_globe_screen_to_world()
	await _test_scenes_load()
	await _test_globe_scene_integrity()
	await _test_sky_and_boot()
	await _test_error_report()
	await _finish()

func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		_report_lines.append("PASS  %s" % name)
		print("  PASS  %s" % name)
	else:
		_failed += 1
		_failures.append(name)
		_report_lines.append("FAIL  %s" % name)
		print("  FAIL  %s" % name)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

## Espera N ticks de física — em headless o loop de render roda muito rápido,
## então só contar process_frame não avança o tempo simulado suficiente.
func _pframes(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

# ---------------------------------------------------------------------------
# 1. Terreno: elevacao, wrap, caminhabilidade
# ---------------------------------------------------------------------------
func _test_terrain() -> void:
	print("[1] Terreno")
	var planet = get_tree().get_first_node_in_group("planet")
	_check(planet != null, "planeta existe (grupo 'planet')")
	if planet == null:
		return
	# elevacao limitada a [0,1]
	var ok_range := true
	for p in [Vector2.ZERO, Vector2(999, 499), Vector2(-999, -499), Vector2(500, -200)]:
		var e: float = planet.get_elevation_at(p)
		if e < 0.0 or e > 1.0:
			ok_range = false
	_check(ok_range, "get_elevation_at sempre em [0,1]")
	# consistencia de wrap: posicao e posicao+world_size tem a mesma elevacao
	var ws: Vector2 = planet.world_size
	var e1: float = planet.get_elevation_at(Vector2(100, 50))
	var e2: float = planet.get_elevation_at(Vector2(100, 50) + ws)
	_check(is_equal_approx(e1, e2), "elevacao periodica no wrap do mundo")
	# Transicoes naturais entre tiles: o material do planeta precisa expor os
	# parametros de mistura (camadas com smoothstep), em vez de escolher o
	# material com um "if" que desenhava uma linha de contorno nitida.
	var ps_node := planet.get_node_or_null("PlanetSurface")
	var pmat: ShaderMaterial = ps_node.material if ps_node else null
	_check(pmat != null and pmat.get_shader_parameter("blend_width") != null
			and float(pmat.get_shader_parameter("blend_width")) > 0.0,
		"shader do planeta expoe blend_width > 0 (mistura entre materiais)")
	_check(pmat != null and pmat.get_shader_parameter("edge_strength") != null
			and float(pmat.get_shader_parameter("edge_strength")) > 0.0,
		"shader do planeta expoe edge_strength > 0 (serpenteio da borda)")
	# agua vs terra coerente
	var walked_ok := true
	for p in [Vector2(675, 25), Vector2(428, -10), Vector2(583, -207)]:
		var is_w: bool = planet.is_water(p)
		var is_l: bool = planet.is_walkable_land(p)
		if is_w and is_l:
			walked_ok = false
	_check(walked_ok, "is_water e is_walkable_land nunca simultaneamente true")
	# Ao dobrar o mundo (4000x2000 -> 8000x4000) as posicoes foram dobradas
	# junto; como a elevacao e' normalizada, o relevo sob cada uma e' o mesmo.
	# Aqui so garantimos os invariantes: ninho em terra firme e relevo intacto.
	# (As fontes ficam em terra firme ou na praia — nao ha' recurso inalcancavel.)
	var key_positions := {
		"ninho": Vector2(2740, 169),
		"skito1": Vector2(2540, 300),
		"skito3": Vector2(2860, 300),
		"fonte1": Vector2(1832, 168),
		"fonte2": Vector2(2332, -828),
		"fonte3": Vector2(3713, 61),
		"fonte4": Vector2(3255, 745),
		"fonte5": Vector2(2225, 707),
	}
	_check(planet.is_walkable_land(key_positions["ninho"]), "ninho em terra firme (2740,169)")
	var fountains_on_land := true
	for fname in ["fonte1", "fonte2", "fonte3", "fonte4", "fonte5"]:
		if not planet.is_walkable_land(key_positions[fname]):
			fountains_on_land = false
	_check(fountains_on_land, "as 5 fontes estao em terra firme caminhavel (alcancaveis)")
	# Referencia: mesmo relevo num mundo de metade do tamanho com as posicoes
	# pela metade. Garante que um futuro ajuste de world_size sem reescalar as
	# posicoes nao passe silencioso.
	var ref = load("res://scripts/planet_terrain.gd").new()
	ref.world_size = planet.world_size * 0.5
	var relief_ok := true
	for kname in key_positions:
		var kp: Vector2 = key_positions[kname]
		if not is_equal_approx(planet.get_elevation_at(kp), ref.get_elevation_at(kp * 0.5)):
			relief_ok = false
	_check(relief_ok, "dobrar o mundo preservou o relevo (elevacao normalizada identica)")
	ref.free()
	# Largura da faixa de transicao entre materiais: no shader a faixa cobre
	# `blend_width` de elevacao, entao a largura espacial e' blend_width/|grad|.
	# O alvo, medido em FRACAO DE TILE (tile = 200 px), nao depende do tamanho do
	# mundo: pequena demais volta a parecer corte seco e grande demais "lava" os
	# materiais (dissolve o tile inteiro).
	var grads: Array[float] = []
	for i in range(160):
		for j in range(80):
			var wx: float = (float(i) + 0.37) / 160.0 * planet.world_size.x - planet.world_size.x * 0.5
			var wy: float = (float(j) + 0.61) / 80.0 * planet.world_size.y - planet.world_size.y * 0.5
			if absf(planet.get_elevation_at(Vector2(wx, wy)) - planet.WATER_THRESHOLD) < 0.004:
				var h := 3.0
				var gx: float = (planet.get_elevation_at(Vector2(wx + h, wy))
						- planet.get_elevation_at(Vector2(wx - h, wy))) / (2.0 * h)
				var gy: float = (planet.get_elevation_at(Vector2(wx, wy + h))
						- planet.get_elevation_at(Vector2(wx, wy - h))) / (2.0 * h)
				var g: float = sqrt(gx * gx + gy * gy)
				if g > 1e-9:
					grads.append(g)
	if grads.size() > 10:
		grads.sort()
		var g_med: float = grads[grads.size() / 2]
		var band_px: float = planet.blend_width / g_med
		var tile: float = planet.tile_world_size if "tile_world_size" in planet else 200.0
		var band_tiles: float = band_px / tile
		_check(band_tiles > 0.05 and band_tiles < 0.6,
			"faixa de transicao com %.0f px de mundo = %.2f de tile (p50 de %d amostras; alvo 0,05-0,60 tile)"
			% [band_px, band_tiles, grads.size()])
	else:
		_check(false, "amostras de costa suficientes para medir a faixa de transicao")
	await _frames(1)

# ---------------------------------------------------------------------------
# 2. Fonte de Elementio: coleta, esgotamento, vida infinita
# ---------------------------------------------------------------------------
func _test_fountain() -> void:
	print("[2] Fonte de Elementio")
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	get_tree().current_scene.add_child(fountain)
	await _frames(2)
	_check(fountain.is_in_group("resources"), "fonte no grupo 'resources'")
	_check(fountain.remaining_elementio == 20000, "fonte com 20000 de recurso")
	var got: int = fountain.harvest(20)
	_check(got == 20, "harvest(20) devolve 20")
	_check(fountain.remaining_elementio == 19980, "recurso decrementado corretamente")
	# esgota tudo
	fountain.remaining_elementio = 0
	fountain.is_depleted = true
	_check(fountain.harvest(20) == 0, "fonte esgotada devolve 0")
	_check(fountain.get_resource_info().contains("Esgotada"), "HUD indica Esgotada")
	# vida infinita: get_building_info nao existe em fonte, mas get_resource_info mostra ∞
	_check(fountain.get_resource_info().contains("∞"), "fonte mostra vida infinita")
	# Fonte esgotada nao pode mais ser coletada pelo operario
	var skito = load("res://scenes/units/artropes/skito.tscn").instantiate()
	get_tree().current_scene.add_child(skito)
	await _frames(2)
	skito.harvest_resource(fountain)
	_check(skito.current_state != skito.UnitState.HARVESTING,
		"operaria nao inicia coleta em fonte esgotada")
	_check(skito.target_resource == null,
		"operaria nao guarda fonte esgotada como alvo")
	skito.queue_free()
	await _frames(2)
	fountain.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 3. Ciclo completo do Skito: coleta 20/s -> 200 carregado -> volta -> 40/ciclo
# ---------------------------------------------------------------------------
func _test_unit_harvest_cycle() -> void:
	print("[3] Ciclo de coleta do Skito")
	var unit = load("res://scenes/units/artropes/skito.tscn").instantiate()
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	var nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	var root := get_tree().current_scene
	root.add_child(unit)
	root.add_child(fountain)
	root.add_child(nest)
	unit.global_position = fountain.global_position + Vector2(200, 0)
	fountain.global_position = Vector2(300, 300)
	nest.global_position = Vector2(320, 300)
	await _pframes(2)

	_check(unit.max_carry_capacity == 200, "capacidade de carga = 200")
	_check(unit.has_method("harvest_resource"), "unidade tem harvest_resource")

	unit.harvest_resource(fountain)
	_check(unit.current_state == unit.UnitState.HARVESTING, "estado HARVESTING ao ordenar coleta")

	# simula a coleta direto no limite (evita esperar tempo real)
	unit.global_position = fountain.global_position
	unit.harvest_timer = 999.0
	var before: int = fountain.remaining_elementio
	await _pframes(3)  # _process_harvesting roda e coleta 20
	_check(fountain.remaining_elementio == before - 20, "coletou 20 do ciclo")
	_check(unit.carried_elementio == 20, "carregado = 20 apos 1 ciclo")

	# enche a unidade
	unit.carried_elementio = 200
	unit.harvest_timer = 999.0
	await _pframes(3)
	_check(unit.current_state == unit.UnitState.RETURNING_TO_BASE,
		"com 200 carregado vai retornar a base")
	_check(unit.target_nest != null, "ninho alvo definido")

	# leva junto do ninho e simula descarga
	unit.global_position = nest.global_position
	unit.is_unloading = false
	unit.unload_timer = 0.0
	var gm_before: int = GameManager.elemeth
	await _pframes(30)  # ~0.5s de jogo: descarrega 40 (0.4s por ciclo)
	_check(GameManager.elemeth > gm_before, "descarregou elementio no GameManager")
	_check(unit.carried_elementio == 160, "apos 1 descarga: 200-40=160 carregado")

	# interrupcao por novo comando
	unit.set_target(Vector2(100, 100), true)
	_check(unit.current_state == unit.UnitState.MOVING, "novo comando interrompe o ciclo")
	_check(unit.target_resource == null, "interrupcao limpa target_resource")

	unit.queue_free()
	fountain.queue_free()
	nest.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 3b. Fonte: 1 operario por vez, fila de ate 4 alocados
# ---------------------------------------------------------------------------
func _test_fountain_worker_queue() -> void:
	print("[3b] Fila de operarios na fonte")
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	var root := get_tree().current_scene
	root.add_child(fountain)
	fountain.global_position = Vector2(500, 500)
	var units: Array = []
	for i in range(5):
		var u = load("res://scenes/units/artropes/skito.tscn").instantiate()
		root.add_child(u)
		u.global_position = fountain.global_position + Vector2(120.0 + i * 12.0, 0)
		units.append(u)
	await _pframes(2)
	for u in units:
		u.harvest_resource(fountain)
	await _pframes(2)
	_check(fountain.get_allocated_workers() == 4, "fonte aloca no maximo 4 operarios")
	_check(units[4].current_state == units[4].UnitState.IDLE, "5o operario fica de fora (fila cheia)")
	_check(fountain.get_resource_info().contains("Operarios: 4/4"), "HUD mostra operarios 4/4")
	var active_count := 0
	for u in units:
		if fountain.is_active_worker(u):
			active_count += 1
	_check(active_count == 1, "apenas 1 operario ocupa a fonte por vez")
	# Ciclo: ao sair para descarregar, permanece alocada e vai para o fim da fila
	var first_active = fountain.active_worker
	fountain.rotate_worker(first_active)
	await _pframes(2)
	_check(fountain.get_allocated_workers() == 4, "operario em descarga continua alocado")
	_check(fountain.worker_queue[fountain.get_allocated_workers() - 1] == first_active,
		"ao sair da fonte vai para o fim da fila")
	_check(fountain.active_worker != null and fountain.active_worker != first_active,
		"proximo da fila assume a fonte automaticamente")
	var new_active = fountain.active_worker
	_check(new_active.target_position.distance_to(fountain.global_position) < 8.0,
		"novo ativo entra na fonte automaticamente")
	_check(new_active.is_moving, "operario promovido retoma o movimento sozinho")
	_check(fountain.worker_queue[0] == new_active, "promocao respeita a ordem de alocacao")
	var wait_pos: Vector2 = fountain.get_wait_position(units[3])
	_check(wait_pos.distance_to(fountain.global_position) > 40.0,
		"operario da fila espera fora da fonte")
	# Outra acao remove a unidade da fila
	var interrupted = fountain.active_worker
	interrupted.set_target(Vector2(700, 700), true)
	await _pframes(1)
	_check(not fountain.is_worker_allocated(interrupted), "outra acao remove o operario da fila")
	_check(fountain.get_allocated_workers() == 3, "fila cai para 3 apos interrupcao")
	for u in units:
		u.queue_free()
	fountain.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 3c. Ninho: bandeira de rally visivel so com o predio selecionado
# ---------------------------------------------------------------------------
func _test_nest_rally() -> void:
	print("[3c] Rally point do ninho")
	var root := get_tree().current_scene
	var nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	root.add_child(nest)
	root.add_child(fountain)
	nest.global_position = Vector2(800, 800)
	fountain.global_position = Vector2(1000, 800)
	await _pframes(2)

	nest.select()
	nest.set_rally_point(fountain.global_position)
	await _pframes(1)
	_check(nest.rally_flag != null and nest.rally_flag.visible,
		"bandeira visivel com o predio selecionado")
	nest.deselect()
	await _pframes(1)
	_check(nest.rally_flag != null and not nest.rally_flag.visible,
		"bandeira oculta ao desselecionar")
	nest.select()
	await _pframes(1)
	_check(nest.rally_flag != null and nest.rally_flag.visible,
		"bandeira volta ao selecionar")

	# Bandeira centralizada quando o rally e definido sobre uma construcao
	var other = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	root.add_child(other)
	other.global_position = Vector2(1200, 800)
	await _pframes(2)
	nest.set_rally_point(other.global_position + Vector2(20, 0))
	await _pframes(1)
	_check(nest.rally_point == other.global_position,
		"rally sobre construcao centraliza no predio")
	_check(nest.rally_flag != null and nest.rally_flag.get_parent() == nest,
		"bandeira e filha do predio (acompanha o wrap)")
	_check(nest.get_rally_position() == other.global_position,
		"bandeira no centro da construcao alvo")
	# Simula o deslocamento do wrap: a bandeira acompanha o predio
	var before_flag: Vector2 = nest.rally_flag.global_position
	nest.global_position += Vector2(0, 400)
	await _pframes(1)
	_check(nest.rally_flag.global_position == before_flag + Vector2(0, 400),
		"bandeira acompanha o deslocamento do predio")
	nest.global_position = Vector2(800, 800)
	nest.set_rally_point(fountain.global_position)
	other.queue_free()
	await _pframes(1)

	# Operario spawnado com rally sobre a fonte entra no ciclo de coleta
	var before_ids: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		before_ids.append(u.get_instance_id())
	nest._spawn_unit_now("skito")
	await _pframes(3)
	var spawned = null
	for u in get_tree().get_nodes_in_group("units"):
		if not before_ids.has(u.get_instance_id()):
			spawned = u
	_check(spawned != null, "skito spawnado pelo ninho")
	if spawned:
		_check(spawned.target_resource == fountain, "rally sobre a fonte ordena coleta automaticamente")
		_check(spawned.current_state == spawned.UnitState.HARVESTING,
			"skito spawnado ja em HARVESTING")

	# Nao-operario nao recebe ordem de coleta
	var before_ids2: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		before_ids2.append(u.get_instance_id())
	nest._spawn_unit_now("spider")
	await _pframes(3)
	var spider = null
	for u in get_tree().get_nodes_in_group("units"):
		if not before_ids2.has(u.get_instance_id()):
			spider = u
	if spider:
		_check(spider.target_resource == null, "nao-operario no rally nao recebe coleta")
		spider.queue_free()
	if spawned:
		spawned.queue_free()
	nest.queue_free()
	fountain.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 3d. Camadas de exibicao: construcoes sempre atras das unidades
# ---------------------------------------------------------------------------
func _test_draw_layers() -> void:
	print("[3d] Camadas de exibicao")
	var nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	var skito = load("res://scenes/units/artropes/skito.tscn").instantiate()
	var spider = load("res://scenes/units/artropes/spider.tscn").instantiate()
	_check(nest.z_index < 0, "ninho abaixo da camada base (z=%d)" % nest.z_index)
	_check(fountain.z_index < 0,
		"fonte (construcao) abaixo da camada base (z=%d)" % fountain.z_index)
	_check(nest.z_index == fountain.z_index,
		"ninho e fonte na mesma camada de construcao")
	_check(skito.z_index > nest.z_index, "skito acima das construcoes")
	_check(spider.z_index > fountain.z_index, "spider acima das construcoes")
	_check(nest.z_index > -10, "construcoes acima do terreno (z=-10)")
	nest.free()
	fountain.free()
	skito.free()
	spider.free()

# ---------------------------------------------------------------------------
# 3e. Status de combate (vida/defesa/ataque) e projetil de veneno
# ---------------------------------------------------------------------------
func _test_unit_stats_and_projectile() -> void:
	print("[3e] Status de combate / projetil de veneno")
	var root := get_tree().current_scene

	# Spider: vida, defesa e mitigacao de dano
	var spider = load("res://scenes/units/artropes/spider.tscn").instantiate()
	spider.team = Faction.PLAYER
	spider.position = Vector2(1200, 1200)
	root.add_child(spider)
	spider.set_physics_process(false)
	await _frames(2)
	_check(spider.max_health == 120, "Spider tem 120 de vida")
	_check(is_equal_approx(spider.defense, 0.15), "Spider tem 15% de defesa")
	_check(spider.attack_damage == 12, "Spider tem 12 de ataque")
	var spider_info: String = spider.get_unit_info()
	_check(spider_info.contains("Defesa: 15%") and spider_info.contains("Ataque: 12"),
		"HUD da unidade mostra vida/defesa/ataque")
	var spider_sprite: Sprite2D = spider.get_node("Sprite2D")
	_check(is_equal_approx(spider_sprite.region_rect.position.y, 0.0),
		"Spider usa somente a linha de cima da folha (nao vira escorpiao)")
	var hp0: int = spider.current_health
	spider.take_damage(20)
	_check(spider.current_health == hp0 - 17, "dano 20 com 15% de defesa = 17")
	var health_bar: Node2D = spider.get_node_or_null("HealthBar")
	_check(health_bar != null and health_bar.visible,
		"barra de vida da unidade aparece apos sofrer dano")
	spider.take_damage(1000)
	_check(spider.current_health == 0 and spider.is_queued_for_deletion(),
		"unidade morre ao chegar a 0 de vida")
	await _frames(2)

	# Scorpion: unidade a distancia, recorte da linha de baixo da folha
	var scorpion = load("res://scenes/units/artropes/scorpion.tscn").instantiate()
	scorpion.team = Faction.PLAYER
	scorpion.position = Vector2(1600, 1200)
	root.add_child(scorpion)
	scorpion.set_physics_process(false)
	await _frames(2)
	_check(scorpion.is_ranged, "Scorpion e uma unidade de ataque a distancia")
	_check(scorpion.attack_range >= 150.0, "Scorpion ataca a distancia (alcance >= 150)")
	_check(scorpion.projectile_scene != null, "Scorpion tem cena de projetil")
	var scorpion_info: String = scorpion.get_unit_info()
	_check(scorpion_info.contains("Escorpião"), "HUD identifica o Escorpião")
	_check(scorpion_info.contains("Defesa: 10%"), "Escorpião mostra 10% de defesa")
	_check(scorpion_info.contains("veneno 3/s"), "HUD mostra o veneno do Escorpião")
	var scorpion_sprite: Sprite2D = scorpion.get_node("Sprite2D")
	_check(is_equal_approx(scorpion_sprite.region_rect.position.y, 512.0),
		"Scorpion usa a linha de baixo da folha (jato de veneno)")

	# Alvo inimigo para testar o projetil e o veneno ao longo do tempo
	var target = load("res://scenes/units/artropes/skito.tscn").instantiate()
	target.team = Faction.ENEMY
	target.position = Vector2(1700, 1200)
	root.add_child(target)
	target.set_physics_process(false)
	await _frames(1)
	var target_hp0: int = target.current_health
	scorpion.attack(target)
	scorpion.attack_timer = scorpion.attack_cooldown
	scorpion._process_attacking(0.01)
	var projectiles := get_tree().get_nodes_in_group("projectiles")
	_check(projectiles.size() > 0, "Scorpion dispara projetil de veneno")
	target.set_physics_process(true)
	await _pframes(20)
	_check(target.current_health < target_hp0, "projetil causa dano no alvo")
	_check(target.poison_time_left > 0.0, "projetil aplica veneno no alvo")
	var hp_after_hit: int = target.current_health
	await _pframes(75)
	_check(target.current_health < hp_after_hit, "veneno causa dano continuo")

	# HUD: o painel de selecao mostra os atributos da unidade
	var ui = load("res://scenes/ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(2)
	_check(ui.get_node_or_null("Control/BottomBar/Panel/Margin/HBox/SelectionPanel/SelectionStats") != null,
		"HUD tem campo de atributos da unidade")
	_check(ui.get_node_or_null("Control/BottomBar/Panel/Margin/HBox/MainContent/ActionGrid/TrainScorpionBtn") != null,
		"HUD tem botao de treinar Escorpião")
	_check(ui.idle_scorpion_btn != null, "HUD tem indicador de Escorpião ocioso")
	ui.update_selected_units_display([scorpion])
	_check(ui.selection_stats.text.contains("Escorpião") and ui.selection_stats.text.contains("Defesa: 10%"),
		"painel de selecao exibe os atributos do Escorpião")
	# O botao do HUD enfileira a producao no ninho do jogador e cobra o custo.
	var player_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	player_nest.team = Faction.PLAYER
	player_nest.position = Vector2(1200, 1000)
	root.add_child(player_nest)
	await _frames(1)
	if GameManager.elemeth < GameManager.scorpion_cost:
		GameManager.add_elemeth(GameManager.scorpion_cost - GameManager.elemeth)
	var gold_before: int = GameManager.elemeth
	ui.show_building_menu(player_nest)
	ui._on_train_scorpion_pressed()
	_check(player_nest.is_producing and player_nest.current_production == "scorpion",
		"botao do HUD enfileira a producao do Escorpião")
	_check(GameManager.elemeth == gold_before - GameManager.scorpion_cost,
		"treinar Escorpião cobra o custo correto")
	player_nest.queue_free()
	ui.queue_free()
	await _frames(2)

	# Custo e IA conhecem o novo tipo
	_check(GameManager.scorpion_cost > 0, "Escorpião tem custo de producao")
	var ai = load("res://scripts/ai/enemy_ai.gd").new()
	_check(ai._unit_cost("scorpion") == GameManager.scorpion_cost,
		"IA usa o custo correto do Escorpião")
	ai.free()

	scorpion.queue_free()
	target.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 3f. Menu de opcoes / pausa
# ---------------------------------------------------------------------------
func _test_settings_menu() -> void:
	print("[3f] Menu de opcoes / pausa")
	var settings_manager = get_tree().root.get_node_or_null("SettingsManager")
	_check(settings_manager != null, "autoload SettingsManager presente")
	if settings_manager == null:
		return

	var old_speed: float = SettingsManager.game_speed
	var old_scroll: float = SettingsManager.scroll_speed
	var old_time_scale: float = Engine.time_scale

	SettingsManager.set_game_speed(1.5)
	SettingsManager.set_scroll_speed(1200.0)
	_check(is_equal_approx(Engine.time_scale, 1.5), "opcao de velocidade do jogo aplica time_scale")
	_check(is_equal_approx(SettingsManager.scroll_speed, 1200.0),
		"opcao de velocidade de rolagem e aplicada")

	var root := get_tree().current_scene
	var ui = load("res://scenes/ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(2)
	_check(ui.get_node_or_null("Control/TopBar/Panel/Margin/HBox/OptionsBtn") != null,
		"HUD tem botao de opcoes")
	_check(ui.settings_menu != null, "menu de opcoes e instanciado no HUD")
	if ui.settings_menu != null:
		var menu = ui.settings_menu
		_check(menu.get_node_or_null("Center/Panel/Margin/VBox/Tabs") != null,
			"menu de opcoes tem abas")
		_check(menu.tabs.get_tab_count() == 3, "menu tem abas Jogo/Audio/Video")
		_check(menu._sliders.size() == 5, "menu tem os 5 sliders de configuracao")
		_check(menu._checks.size() == 3, "menu tem as 3 opcoes de alternancia")
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
		var parts := version.split(".")
		_check(parts.size() == 3 and parts[0] == "0" and parts[1].length() == 2
			and parts[2].length() == 3 and parts[1].is_valid_int() and parts[2].is_valid_int(),
			"versionamento segue o formato 0.xx.xxx")
		_check(menu.version_label.text.contains(version), "menu exibe a versao do jogo")

		# Esc abre, pausa e fecha o menu.
		var esc := InputEventKey.new()
		esc.pressed = true
		esc.keycode = KEY_ESCAPE
		ui._input(esc)
		_check(menu.visible and get_tree().paused, "Esc abre opcoes e pausa a partida")
		var speed_slider: HSlider = menu._sliders["game_speed"]
		speed_slider.value = 1.3
		_check(is_equal_approx(SettingsManager.game_speed, 1.3),
			"slider de velocidade altera a configuracao em tempo real")
		# Volta aos valores anteriores antes de fechar (close salva no disco).
		SettingsManager.set_game_speed(old_speed)
		SettingsManager.set_scroll_speed(old_scroll)
		ui._input(esc)
		_check(not menu.visible and not get_tree().paused, "Esc fecha opcoes e retoma a partida")

	ui.queue_free()
	await _frames(2)

	# Restaura os valores anteriores para nao alterar a preferencia do jogador.
	SettingsManager.set_game_speed(old_speed)
	SettingsManager.set_scroll_speed(old_scroll)
	Engine.time_scale = old_time_scale

# ---------------------------------------------------------------------------
# 4. Camera: wrap toroidal
# ---------------------------------------------------------------------------
func _test_camera_wrap() -> void:
	print("[4] Camera / wrap toroidal")
	var planet = get_tree().get_first_node_in_group("planet")
	if planet == null:
		_check(false, "planeta ausente no teste de wrap")
		return
	var ws: Vector2 = planet.world_size
	var wrapped: Vector2 = planet.wrap_world_position(Vector2(ws.x * 0.55, 0.0))
	_check(wrapped.x < 0, "x=55%% da largura da a volta (world %.0fx%.0f)" % [ws.x, ws.y])
	wrapped = planet.wrap_world_position(Vector2(0, ws.y * 0.6))
	_check(absf(wrapped.y) <= ws.y * 0.5 + 0.001, "y=60%% da altura da a volta no eixo Y")
	wrapped = planet.wrap_world_position(Vector2(-ws.x * 0.55, -ws.y * 0.6))
	_check(wrapped.x > 0 and wrapped.y > 0, "canto oposto wrap nos dois eixos")

	# Entidade em varios grupos nao pode ser transladada duas vezes no wrap
	var cam = Camera2D.new()
	cam.set_script(load("res://scripts/rts_camera.gd"))
	get_tree().current_scene.add_child(cam)
	var fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	get_tree().current_scene.add_child(fountain)
	fountain.global_position = Vector2(100, 100)
	var before: Vector2 = fountain.global_position
	cam._shift_world_entities(Vector2(0.0, ws.y))
	_check(is_equal_approx(fountain.global_position.y, before.y + ws.y),
		"wrap translada entidade de grupos duplicados uma unica vez")
	fountain.queue_free()
	cam.queue_free()
	await _frames(1)

# ---------------------------------------------------------------------------
# 4b. Planeta-toro (Populous 3): emenda sem corte nos DOIS eixos e caminho
#     mais curto atravessando as bordas.
# ---------------------------------------------------------------------------
func _test_toroidal_planet() -> void:
	print("[4b] Planeta-toro (wrap nos dois eixos)")
	var planet = get_tree().get_first_node_in_group("planet")
	if planet == null:
		_check(false, "planeta ausente no teste toroidal")
		return
	var ws: Vector2 = planet.world_size
	var eps := 0.5
	# A emenda REAL do fract(world_px / world_size) fica em x=0 e y=0, no MEIO
	# do mundo jogavel — nao nas bordas +-ws/2, onde o fract da' o mesmo valor
	# dos dois lados por construcao (teste fraco que nao pegava nada).
	# Comparar -eps com +eps e' o que pega ruido NAO-periodico, que desenhava
	# uma linha reta de material no meio do planeta.
	_check(absf(planet.get_elevation_at(Vector2(-eps, 300.0))
			- planet.get_elevation_at(Vector2(eps, 300.0))) < 0.002,
		"emenda X em x=0 sem degrau de elevacao (ruido periodico)")
	_check(absf(planet.get_elevation_at(Vector2(2700.0, -eps))
			- planet.get_elevation_at(Vector2(2700.0, eps))) < 0.002,
		"emenda Y em y=0 sem degrau de elevacao (ruido periodico)")
	# e continua valendo que dar uma volta inteira e' o mesmo ponto
	_check(is_equal_approx(planet.get_elevation_at(Vector2(1234.0, 567.0)),
			planet.get_elevation_at(Vector2(1234.0, 567.0) + ws)),
		"elevacao periodica: posicao + world_size == posicao (toro)")
	# toroidal_delta: pega o caminho MAIS CURTO, atravessando a emenda.
	var hx := ws.x * 0.5 - 10.0
	var dx := PlanetTerrain.toroidal_delta(Vector2(hx, 0.0), Vector2(-hx, 0.0), ws)
	_check(dx.x > 0.0 and absf(dx.x) < 30.0, "toroidal_delta X atravessa a emenda pelo caminho curto")
	var hy := ws.y * 0.5 - 10.0
	var dy := PlanetTerrain.toroidal_delta(Vector2(0.0, hy), Vector2(0.0, -hy), ws)
	_check(dy.y > 0.0 and absf(dy.y) < 30.0, "toroidal_delta Y atravessa a emenda pelo caminho curto")
	await _frames(1)

# ---------------------------------------------------------------------------
# 5. Selection manager: formacoes e selecao
# ---------------------------------------------------------------------------
func _test_selection_manager() -> void:
	print("[5] Selection manager")
	var sm = get_tree().get_first_node_in_group("selection_manager")
	_check(sm != null, "selection_manager existe")
	if sm == null:
		return
	var u1 = load("res://scenes/units/artropes/skito.tscn").instantiate()
	var u2 = load("res://scenes/units/artropes/skito.tscn").instantiate()
	get_tree().current_scene.add_child(u1)
	get_tree().current_scene.add_child(u2)
	await _frames(2)
	u1.global_position = Vector2.ZERO
	u2.global_position = Vector2(40, 0)
	sm.selected_units = [u1, u2]
	sm.current_formation = "line"
	sm.move_selected_units_in_formation(Vector2(500, 0))
	_check(u1.is_moving and u2.is_moving, "formacao linha move todas as unidades")
	_check(u1.target_position != u2.target_position, "offsets de formacao diferentes")
	# formacao invalida nao deve quebrar
	sm.current_formation = "invented"
	sm.move_selected_units_in_formation(Vector2(600, 0))
	_check(u1.is_moving, "formacao desconhecida cai no padrao (box)")
	u1.queue_free()
	u2.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 6. GameManager: economia
# ---------------------------------------------------------------------------
func _test_game_manager() -> void:
	print("[6] GameManager")
	var e0: int = GameManager.elemeth
	GameManager.add_elemeth(100)
	_check(GameManager.elemeth == e0 + 100, "add_elemeth soma")
	GameManager.spend(50)
	_check(GameManager.elemeth == e0 + 50, "spend subtrai")
	_check(GameManager.can_afford(1000) == (GameManager.elemeth >= 1000), "can_afford coerente")
	_check(GameManager.can_afford(-1) == true, "custo negativo sempre acessivel (sanidade)")
	await _frames(1)

# ---------------------------------------------------------------------------
# 6b. Jogador inimigo: economia separada, IA, alvos e vitoria
# ---------------------------------------------------------------------------
func _test_enemy_player() -> void:
	print("[6b] Jogador inimigo / IA / vitoria")
	var root := get_tree().current_scene

	# Economia separada por faccao
	var p0: int = GameManager.elemeth
	var e0: int = GameManager.elemeth_enemy
	GameManager.add_elemeth(30, Faction.ENEMY)
	_check(GameManager.elemeth == p0, "economia inimiga nao altera a do jogador")
	_check(GameManager.elemeth_enemy == e0 + 30, "add_elemeth soma no pool inimigo")
	GameManager.spend(10, Faction.ENEMY)
	_check(GameManager.elemeth_enemy == e0 + 20, "spend desconta do pool inimigo")

	# Ninho inimigo spawna unidade com a faccao correta
	var enemy_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	enemy_nest.team = Faction.ENEMY
	root.add_child(enemy_nest)
	enemy_nest.global_position = Vector2(2500, -1600)
	await _pframes(2)
	var before_ids: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		before_ids.append(u.get_instance_id())
	enemy_nest._spawn_unit_now("skito")
	await _pframes(2)
	var spawned = null
	for u in get_tree().get_nodes_in_group("units"):
		if not before_ids.has(u.get_instance_id()):
			spawned = u
	_check(spawned != null, "ninho inimigo spawna unidade")
	if spawned:
		_check(spawned.team == Faction.ENEMY, "unidade spawnada herda faccao inimiga")
		_check(not spawned.is_controllable, "unidade inimiga nao e controlavel")

		# Entrega no ninho da propria faccao, mesmo com um ninho do jogador por perto
		var player_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
		player_nest.team = Faction.PLAYER
		root.add_child(player_nest)
		player_nest.global_position = spawned.global_position + Vector2(-120, 0)
		await _pframes(2)
		spawned._find_nearest_nest()
		_check(spawned.target_nest == enemy_nest,
			"operaria inimiga entrega no ninho inimigo")

		# Descarga no pool inimigo, nunca no do jogador
		var pp: int = GameManager.elemeth
		var ee: int = GameManager.elemeth_enemy
		spawned.target_nest = enemy_nest
		spawned.carried_elementio = 40
		spawned.global_position = enemy_nest.global_position
		spawned.unload_timer = 0.0
		spawned.is_unloading = false
		spawned._process_returning(0.5)
		_check(GameManager.elemeth == pp, "descarga inimiga nao credita o jogador")
		_check(GameManager.elemeth_enemy == ee + 40, "descarga inimiga credita o pool inimigo")
		player_nest.queue_free()
		spawned.queue_free()
	await _frames(2)
	enemy_nest.queue_free()
	await _frames(2)

	# IA: aloca operaria ociosa e inicia producao
	GameManager.elemeth_enemy = 1000
	var ai_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	ai_nest.team = Faction.ENEMY
	root.add_child(ai_nest)
	ai_nest.global_position = Vector2(3000, 0)
	var ai_fountain = load("res://scenes/elementio_fountain.tscn").instantiate()
	root.add_child(ai_fountain)
	ai_fountain.global_position = Vector2(3100, 0)
	var ai_worker = load("res://scenes/units/artropes/skito.tscn").instantiate()
	ai_worker.team = Faction.ENEMY
	root.add_child(ai_worker)
	ai_worker.global_position = Vector2(3000, 40)
	await _pframes(2)
	var ai = load("res://scripts/ai/enemy_ai.gd").new()
	ai.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(ai)
	await _frames(1)
	var e1: int = GameManager.elemeth_enemy
	ai._think()
	_check(ai_worker.target_resource == ai_fountain,
		"IA coloca operaria ociosa na fonte")
	_check(GameManager.elemeth_enemy < e1, "IA gasta recursos para produzir")
	_check(bool(ai_nest.is_producing) or ai_nest.production_queue.size() > 0,
		"IA inicia producao")
	ai.queue_free()
	ai_worker.queue_free()
	ai_fountain.queue_free()
	ai_nest.queue_free()
	await _frames(2)

	# Regra de vitoria e contagem de construcoes
	var mm = load("res://scripts/match_manager.gd").new()
	mm.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(mm)
	await _frames(1)
	_check(mm.winner_for_counts(1, 0) == Faction.PLAYER,
		"jogador vence ao zerar as construcoes inimigas")
	_check(mm.winner_for_counts(0, 1) == Faction.ENEMY,
		"inimigo vence ao zerar as construcoes do jogador")
	_check(mm.winner_for_counts(1, 1) == -1,
		"partida continua com as duas bases vivas")
	_check(mm.winner_for_counts(0, 0) == -2,
		"empate quando as duas bases caem")

	var p_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	p_nest.team = Faction.PLAYER
	root.add_child(p_nest)
	p_nest.global_position = Vector2(-3000, 0)
	var e_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	e_nest.team = Faction.ENEMY
	root.add_child(e_nest)
	e_nest.global_position = Vector2(-2500, 0)
	await _pframes(2)
	_check(mm.count_buildings(Faction.PLAYER) == 1, "conta construcoes do jogador")
	_check(mm.count_buildings(Faction.ENEMY) == 1, "conta construcoes inimigas")
	p_nest.is_ghost = true
	_check(mm.count_buildings(Faction.PLAYER) == 0,
		"pre-visualizacao de construcao nao conta para vitoria")
	p_nest.queue_free()
	e_nest.queue_free()
	mm.queue_free()
	await _frames(2)

	# Jogador consegue mirar em construcao inimiga; fonte neutra nao e alvo
	var target_nest = load("res://scenes/buildings/artropes/hollow_nest.tscn").instantiate()
	target_nest.team = Faction.ENEMY
	root.add_child(target_nest)
	target_nest.global_position = Vector2(2000, 500)
	await _pframes(2)
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if sm:
		_check(sm._get_hostile_under_mouse(target_nest.global_position, Faction.PLAYER) == target_nest,
			"clique direito reconhece construcao inimiga como alvo")
		var neutral = load("res://scenes/elementio_fountain.tscn").instantiate()
		root.add_child(neutral)
		neutral.global_position = Vector2(2000, 700)
		await _pframes(2)
		_check(sm._get_hostile_under_mouse(neutral.global_position, Faction.PLAYER) == null,
			"fonte neutra nao e alvo de ataque")
		neutral.queue_free()

	# Unidade de combate adquire automaticamente uma construcao hostil proxima
	var spider = load("res://scenes/units/artropes/spider.tscn").instantiate()
	spider.team = Faction.PLAYER
	root.add_child(spider)
	spider.global_position = Vector2(2000, 540)
	await _pframes(4)
	_check(spider.target_enemy == target_nest,
		"unidade de combate adquire construcao hostil proxima")
	spider.queue_free()
	target_nest.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
# 7. Globo 3D: tela -> mundo via raio na esfera
# ---------------------------------------------------------------------------
func _test_globe_screen_to_world() -> void:
	print("[7] Globo: conversao tela->mundo")
	var globe_script = load("res://scripts/globe_main.gd")
	_check(globe_script != null, "script globe_main carrega")
	# teste unitario da matematica: monta um no minimo com camera e esfera
	var cam := Camera3D.new()
	var sph := MeshInstance3D.new()
	sph.mesh = SphereMesh.new()
	add_child(cam)
	add_child(sph)
	cam.position = Vector3(0, 0, 3)
	cam.look_at(Vector3.ZERO)
	await _frames(1)
	var g = globe_script.new()
	g.camera = cam
	g.sphere = sph
	# centro REAL da viewport (em headless o tamanho pode diferir de 1280x720)
	var vsize: Vector2 = cam.get_viewport().get_visible_rect().size
	var center_pt := vsize * 0.5
	# centro da tela: raio bate no polo frontal da esfera -> y~0 no mundo
	var center: Variant = g._screen_to_world(center_pt)
	_check(center != null, "centro da tela intersecta a esfera")
	if center != null:
		_check(absf(center.y) < 120.0, "centro da tela -> polo (y~0 no mundo)")
	# fora da esfera: canto da tela com camera longe => pode retornar null ou dentro
	var far: Variant = g._screen_to_world(Vector2(-5000, -5000))
	_check(far == null, "clique fora da esfera retorna null")
	# esfera rotacionada: o mundo acompanha (entidades na textura)
	sph.rotation = Vector3(0, PI * 0.5, 0)
	var rot_hit: Variant = g._screen_to_world(center_pt)
	_check(rot_hit != null, "esfera rotacionada ainda intersecta")
	if center != null and rot_hit != null:
		_check(absf(rot_hit.x - center.x) > 100.0, "rotacao da esfera desloca o ponto do mundo")
	g.free()
	cam.queue_free()
	sph.queue_free()
	await _frames(1)

# ---------------------------------------------------------------------------
# 8. Cenas principais carregam sem erro
# ---------------------------------------------------------------------------
func _test_scenes_load() -> void:
	print("[8] Carga de cenas")
	for path in ["res://scenes/world_flat.tscn", "res://scenes/elementio_fountain.tscn",
			"res://scenes/buildings/artropes/hollow_nest.tscn", "res://scenes/units/artropes/skito.tscn",
			"res://scenes/units/artropes/scorpion.tscn", "res://scenes/projectiles/poison_projectile.tscn"]:
		var ps: PackedScene = load(path)
		_check(ps != null, "cena carrega: %s" % path)
		if ps:
			var inst = ps.instantiate()
			_check(inst != null, "instancia criada: %s" % path)
			if inst:
				inst.free()
	# Arte dos elementos: os sprites estao no TAMANHO ORIGINAL. O efeito de
	# "elementos pequenos" no planeta vem da AREA maior (mundo 8000x4000), nao
	# de encolher a arte. O teste guarda as duas coisas.
	var size_cases := {
		"res://scenes/units/artropes/skito.tscn": 40.755,
		"res://scenes/units/artropes/mantis.tscn": 35.84,
		"res://scenes/units/artropes/spider.tscn": 35.84,
		"res://scenes/units/artropes/scorpion.tscn": 35.84,
		"res://scenes/buildings/artropes/hollow_nest.tscn": 75.24,
		"res://scenes/elementio_fountain.tscn": 59.76,
	}
	for epath in size_cases:
		var eps: PackedScene = load(epath)
		var e_inst = eps.instantiate()
		var spr: Sprite2D = e_inst.get_node("Sprite2D")
		var frame_px: float = float(spr.texture.get_width()) / float(maxi(spr.hframes, 1))
		var world_px: float = frame_px * spr.scale.x
		_check(is_equal_approx(world_px, float(size_cases[epath])),
			"%s com a arte no tamanho original (%.2f px de mundo)" % [epath.get_file(), world_px])
		e_inst.free()
	# Barras de status no tamanho ORIGINAL (a reducao 4x foi revertida junto com
	# a arte): 40x4 px na unidade carregada e 44x4 px no ninho e na fonte, com
	# separador de 1 px (5 separadores = 6 divisoes) e a barra acima do sprite.
	var bar_cases := [
		["res://scenes/units/artropes/skito.tscn", "_setup_carry_bar", "CarryBar", 40.0, -18.0, 5],
		["res://scenes/units/artropes/spider.tscn", "_setup_health_bar", "HealthBar", 38.0, -26.0, 0],
		["res://scenes/buildings/artropes/hollow_nest.tscn", "_setup_health_bar", "HealthBar", 44.0, -46.0, 0],
		["res://scenes/elementio_fountain.tscn", "_setup_res_bar", "ResBar", 44.0, -34.0, 5],
	]
	for bc in bar_cases:
		var b_inst = load(str(bc[0])).instantiate()
		b_inst.call(str(bc[1]))
		var bar: Node2D = b_inst.get_node_or_null(str(bc[2]))
		_check(bar != null, "%s: barra de status %s presente" % [str(bc[0]).get_file(), str(bc[2])])
		if bar != null:
			var bg_bar: ColorRect = bar.get_child(0)
			_check(is_equal_approx(bg_bar.size.x, float(bc[3])) and is_equal_approx(bg_bar.size.y, 4.0),
				"%s no tamanho original (%.0fx%.0f px)" % [str(bc[2]), bg_bar.size.x, bg_bar.size.y])
			_check(is_equal_approx(bar.position.y, float(bc[4])),
				"%s acima do sprite (y=%.0f)" % [str(bc[2]), bar.position.y])
			var ticks := 0
			for c in bar.get_children():
				if c is ColorRect and (c as ColorRect).size.x > 0.5 and (c as ColorRect).size.x <= 1.01:
					ticks += 1
			_check(ticks == int(bc[5]),
				"%s com %d separadores de 1 px" % [str(bc[2]), ticks])
		b_inst.free()
	# Area do planeta: o mundo dobrou em cada eixo (4000x2000 -> 8000x4000),
	# entao a area quadruplicou; cada elemento passou a ocupar ~4x menos da
	# superficie (mesma arte, planeta maior).
	var pnode_area = get_tree().get_first_node_in_group("planet")
	if pnode_area:
		var ws_area: Vector2 = pnode_area.world_size
		_check(is_equal_approx(ws_area.x * ws_area.y, 8000.0 * 4000.0),
			"area do planeta 4x maior (mundo %.0fx%.0f)" % [ws_area.x, ws_area.y])
	await _frames(1)

# ---------------------------------------------------------------------------
# 8b. Integridade da cena principal (regressao do crash de no duplicado)
# ---------------------------------------------------------------------------
func _test_globe_scene_integrity() -> void:
	print("[8b] Integridade da cena principal (globe_main)")
	var ps: PackedScene = load("res://scenes/globe_main.tscn")
	_check(ps != null, "globe_main.tscn carrega (sem erro de no duplicado)")
	if ps == null:
		return
	var globe = ps.instantiate()
	globe.boot_to_surface = false   # o boot automatico (2 s) e' testado em [8c]
	get_tree().current_scene.add_child(globe)
	await _frames(5)
	# nomes de filhos devem ser unicos (o crash era um 'UI' duplicado)
	var names := {}
	var dup := ""
	for c in globe.get_children():
		if names.has(c.name):
			dup = c.name
		names[c.name] = true
	_check(dup == "", "nenhum no filho duplicado na cena principal (duplicado: '%s')" % dup)
	# nos e servicos criticos presentes
	_check(globe.get_node_or_null("SubViewport") != null, "SubViewport presente")
	_check(globe.get_node_or_null("Sphere") != null, "Sphere presente")
	_check(globe.get_node_or_null("Camera3D") != null, "Camera3D presente")
	_check(globe.get_node_or_null("UI") != null, "UI presente")
	# Qualidade de render: SubViewport em alta resolucao (4 texels por pixel de
	# mundo) + filtro linear+mipmap na textura do planeta + mipmaps nos sprites.
	# Sem isto os sprites ficam "quadriculados"/serrilhados na vista de perto.
	var sv: SubViewport = globe.get_node("SubViewport")
	_check(sv.size == Vector2i(8192, 4096), "SubViewport em alta resolucao (8192x4096)")
	var fc: Camera2D = sv.get_node_or_null("WorldFlat/Camera2D")
	var pnode = get_tree().get_first_node_in_group("planet")
	var world_ws: Vector2 = pnode.world_size if pnode else Vector2(8000, 4000)
	_check(fc != null and (Vector2(sv.size) / fc.zoom).is_equal_approx(world_ws),
		"camera plana cobre exatamente uma volta do mundo (%.0fx%.0f)" % [world_ws.x, world_ws.y])
	var sph_mat = globe.get_node("Sphere").material_override
	_check(sph_mat != null and sph_mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"textura do planeta com filtro linear+mipmap (sem serrilhado)")
	_check(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) == 3,
		"sprites 2D usam filtro linear+mipmap (evita aliasing ao reduzir)")
	var sheet: Texture2D = load("res://assets/sprites/skito_sheet.png")
	_check(sheet != null and sheet.get_image().has_mipmaps(), "spritesheet tem mipmaps gerados")
	# Globo maior na vista planetaria: ocupa boa parte da altura da tela.
	var globe_frac := 2.0 * asin(1.0 / globe.planet_dist) / deg_to_rad(60.0)
	_check(globe_frac >= 0.8, "globo enche >=80%% da altura na vista planetaria (%.0f%%)" % (globe_frac * 100.0))
	# o controlador do globo esta no grupo e alterna vistas
	_check(globe.is_in_group("globe_controller"), "globe no grupo globe_controller")
	_check(globe.is_surface_view() == false, "inicia em vista planeta")
	globe.toggle_view()
	_check(globe.is_surface_view() == true, "toggle_view muda para superficie")
	globe.toggle_view()
	_check(globe.is_surface_view() == false, "toggle_view volta para planeta")
	# conversao tela->mundo pela camera real da cena
	var center: Variant = globe._screen_to_world(
		globe.get_viewport().get_visible_rect().size * 0.5)
	_check(center != null, "clique no centro da cena real acerta o mundo")
	# wrap toroidal de entidades: unidade que cruza a borda reaparece do lado oposto
	var probe = load("res://scenes/units/artropes/skito.tscn").instantiate()
	get_tree().current_scene.add_child(probe)
	await _frames(2)
	var out_x: float = world_ws.x * 0.5 + 200.0
	probe.global_position = Vector2(out_x, 0.0)
	globe._keep_entities_on_torus()
	_check(probe.global_position.x < 0.0, "globo faz a unidade dar a volta no mapa (x=%.0f -> oposto)" % out_x)
	probe.queue_free()

	# FOCO LOCAL com NORTE FIXO: a orientacao da camera depende SO' do ponto
	# focado (norte = +Y do MUNDO projetado no plano tangente), entao a imagem
	# NUNCA gira/deriva ao andar com WASD (antes a direcao era transportada em
	# paralelo e a vista rodava conforme o caminho).
	globe.set_surface_view(true)
	globe.blend = 1.0
	globe.focus_at_lat_lon(0.0, 0.0)   # equador: o norte deve ser exatamente +Y
	_check(globe.surface_north().dot(Vector3.UP) > 0.999,
		"norte da vista local e' o +Y do mundo (equador)")
	_check(absf(globe.surface_right().dot(Vector3.UP)) < 0.001,
		"leste/oeste perpendicular ao norte (camera sem rolagem)")
	# movimentos puros: leste/oeste anda sobre o PARALELO (latitude fixa) e
	# norte/sul sobre o MERIDIANO; a ida e volta fecha exata (sem deriva).
	globe.focus_at_lat_lon(0.4, 0.9)
	var pa: Vector3 = globe.surf_point
	for i in range(20):
		globe._move_surface(Vector2(0.0, 1.0), 0.02)
	for i in range(20):
		globe._move_surface(Vector2(0.0, -1.0), 0.02)
	var d_ns: float = globe.surf_point.distance_to(pa)
	_check(d_ns < 1e-5, "ida e volta norte-sul volta ao mesmo ponto (desvio %.6f)" % d_ns)
	for i in range(20):
		globe._move_surface(Vector2(1.0, 0.0), 0.02)
	var lat_e: float = asin(clampf(globe.surf_point.y, -1.0, 1.0))
	for i in range(20):
		globe._move_surface(Vector2(-1.0, 0.0), 0.02)
	var d_lo: float = globe.surf_point.distance_to(pa)
	_check(d_lo < 1e-5, "ida e volta leste-oeste volta ao mesmo ponto (desvio %.6f)" % d_lo)
	_check(absf(lat_e - 0.4) < 1e-4, "leste/oeste mantem a latitude (anda sobre o paralelo)")
	# CAMERA NUNCA GIRA: depois de uma caminhada em "L" (norte + leste) o eixo
	# direito da tela continua no eixo leste-oeste do MUNDO. No modo antigo
	# (direcao transportada em paralelo) este caminho girava a vista ~6 graus.
	globe.focus_at_lat_lon(0.4, 0.9)
	for i in range(20):
		globe._move_surface(Vector2(0.0, 1.0), 0.02)
	for i in range(20):
		globe._move_surface(Vector2(1.0, 0.0), 0.02)
	for i in range(60):
		globe._update_camera_transform(0.05)
	var xb: Vector3 = globe.camera.global_transform.basis.x
	_check(absf(xb.dot(globe.surface_right())) > 0.999,
		"andar em L nao gira a camera (direito da tela no eixo leste-oeste)")
	# A/D NA TELA: `move.x` positivo tem de andar para a DIREITA da tela. A vista
	# local olha a esfera de FORA, entao a imagem e' espelhada: a direita da tela
	# e' o OESTE do mundo (era este o caso que invertia A/D).
	globe.focus_at_lat_lon(0.25, 0.6)
	for i in range(40):
		globe._update_camera_transform(0.05)
	var right_screen: Vector3 = globe.camera.global_transform.basis.x
	var before_d: Vector3 = globe.surf_point
	globe._move_surface(Vector2(1.0, 0.0), 0.05)
	var step_d: Vector3 = (globe.surf_point - before_d).normalized()
	_check(step_d.dot(right_screen) > 0.9,
		"D anda para a direita da tela (dot=%.3f)" % step_d.dot(right_screen))
	var before_a: Vector3 = globe.surf_point
	globe._move_surface(Vector2(-1.0, 0.0), 0.05)
	var step_a: Vector3 = (globe.surf_point - before_a).normalized()
	_check(step_a.dot(right_screen) < -0.9,
		"A anda para a esquerda da tela (dot=%.3f)" % step_a.dot(right_screen))
	# o foco para em +-88 graus: o polo e' o ponto singular da bussola
	globe.focus_at_lat_lon(deg_to_rad(85.0), 0.7)
	for i in range(400):
		globe._move_surface(Vector2(0.0, 1.0), 0.05)
	var lat_n: float = rad_to_deg(asin(clampf(globe.surf_point.y, -1.0, 1.0)))
	_check(lat_n <= 88.001 and lat_n > 87.0,
		"foco para em +88 graus ao ir para o norte (lat=%.2f)" % lat_n)
	for i in range(400):
		globe._move_surface(Vector2(0.0, -1.0), 0.05)
	var lat_s: float = rad_to_deg(asin(clampf(globe.surf_point.y, -1.0, 1.0)))
	_check(lat_s >= -88.001 and lat_s < -87.0,
		"foco para em -88 graus ao ir para o sul (lat=%.2f)" % lat_s)
	_check(absf(globe.surf_point.length() - 1.0) < 0.001, "ponto focado permanece na esfera")
	# no limite do polo a camera nao pode gerar NaN (era o slerp degenerado)
	for i in range(30):
		globe.blend = 1.0
		globe._update_camera_transform(0.05)
	var ct: Transform3D = globe.camera.global_transform
	_check(ct.origin.is_finite() and ct.basis.x.is_finite()
			and ct.basis.y.is_finite() and ct.basis.z.is_finite(),
		"camera estavel no limite do polo (sem NaN)")
	globe.blend = 0.0
	globe.set_surface_view(false)
	globe._focus_world_at(Vector2(2740, 169))

	globe.queue_free()
	await _frames(5)

# ---------------------------------------------------------------------------
# 8c. Skybox procedural (universo + ceu com sol/lua orbitando) e boot em 2 s
# ---------------------------------------------------------------------------
func _test_sky_and_boot() -> void:
	print("[8c] Skybox procedural + boot na vista planetaria")
	var ps: PackedScene = load("res://scenes/globe_main.tscn")
	var globe = ps.instantiate()
	globe.boot_to_surface = false
	get_tree().current_scene.add_child(globe)
	await _frames(3)
	var env: Environment = globe.world_environment.environment
	_check(env != null and env.background_mode == Environment.BG_SKY,
		"fundo e' SKY (skybox), nao mais uma cor fixa")
	_check(env != null and env.sky != null, "WorldEnvironment tem um Sky")
	if env == null or env.sky == null:
		globe.queue_free()
		return
	# Custo baixo: radiance minima (nao alimenta GI) e atualizacao incremental.
	_check(env.sky.radiance_size == Sky.RADIANCE_SIZE_32,
		"skybox barato: radiance cubemap no minimo (32)")
	_check(env.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL,
		"skybox barato: radiance incremental (nao REALTIME, que forca 256)")
	var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	_check(sm != null and sm.shader != null, "skybox usa ShaderMaterial (procedural)")
	for pname in ["view_blend", "sun_dir", "moon_dir", "sky_up", "sky_time"]:
		_check(sm != null and sm.get_shader_parameter(pname) != null,
			"skybox expoe o parametro '%s'" % pname)
	# O shader tem as DUAS vistas (ceu azul com nuvens/sol/lua no Foco Local +
	# universo com estrelas no planeta), misturadas por `view_blend`.
	var src: String = FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_check(src.contains("local_sky(") and src.contains("space_sky("),
		"shader do ceu tem as duas vistas (local_sky + space_sky)")
	_check(src.contains("cloud_field(") and src.contains("star_field("),
		"shader do ceu tem nuvens (Foco Local) e estrelas (universo)")
	_check(src.contains("view_blend"),
		"shader do ceu mistura as vistas pelo uniform view_blend")
	# FOV do Foco Local: 28 (ceu ~44% da area; o antigo 40 deixava 66%).
	_check(is_equal_approx(globe.surf_fov, 28.0),
		"FOV do Foco Local = 28 (ceu ~44% da area)")
	globe.set_surface_view(true)
	globe.blend = 1.0
	globe._update_camera_transform(0.016)
	_check(is_equal_approx(globe.camera.fov, globe.surf_fov),
		"camera no Foco Local usa o FOV do ceu (%.0f)" % globe.camera.fov)
	globe.set_surface_view(false)
	globe.blend = 0.0
	globe._update_camera_transform(0.016)
	# Sol e lua orbitam em periodos DIFERENTES: o sol (150 s) anda mais rapido.
	var before_sun: Vector3 = sm.get_shader_parameter("sun_dir")
	var before_moon: Vector3 = sm.get_shader_parameter("moon_dir")
	globe._update_sky(10.0)
	var after_sun: Vector3 = sm.get_shader_parameter("sun_dir")
	var after_moon: Vector3 = sm.get_shader_parameter("moon_dir")
	var sun_move: float = before_sun.angle_to(after_sun)
	var moon_move: float = before_moon.angle_to(after_moon)
	_check(sun_move > 0.01, "sol orbita (moveu %.3f rad em 10 s)" % sun_move)
	_check(moon_move > 0.01, "lua orbita (moveu %.3f rad em 10 s)" % moon_move)
	_check(sun_move > moon_move * 1.2,
		"periodos diferentes: sol (%.0fs) anda mais que a lua (%.0fs)"
		% [globe.SUN_ORBIT_PERIOD, globe.MOON_ORBIT_PERIOD])
	# A luz direcional acompanha o sol (luz vem de onde o sol esta').
	var sun_now: Vector3 = (sm.get_shader_parameter("sun_dir") as Vector3).normalized()
	var lz: Vector3 = globe.directional_light.global_transform.basis.z.normalized()
	_check(lz.dot(sun_now) > 0.99,
		"DirectionalLight3D aponta para o sol (dot=%.3f)" % lz.dot(sun_now))
	# `view_blend` acompanha a vista: 1 no Foco Local, 0 na vista planeta.
	globe.set_surface_view(true)
	globe.blend = 1.0
	globe._update_sky(0.0)
	_check(absf(float(sm.get_shader_parameter("view_blend")) - 1.0) < 0.001,
		"view_blend = 1 no Foco Local (ceu azul)")
	globe.set_surface_view(false)
	globe.blend = 0.0
	globe._update_sky(0.0)
	_check(absf(float(sm.get_shader_parameter("view_blend")) - 0.0) < 0.001,
		"view_blend = 0 na vista planeta (universo)")
	globe.queue_free()
	await _frames(3)

	# Boot: comeca na vista PLANETARIA e entra no Foco Local no atraso configurado.
	var boot = ps.instantiate()
	boot.boot_delay = 0.05
	get_tree().current_scene.add_child(boot)
	await _frames(2)
	_check(boot.is_surface_view() == false, "boot comeca na vista planetaria")
	await get_tree().create_timer(0.35).timeout
	_check(boot.is_surface_view() == true, "boot entra no Foco Local apos o atraso")
	_check(is_equal_approx(boot.boot_delay, 0.05), "atraso do boot configuravel (0.05 s no teste)")
	boot.queue_free()
	await _frames(3)

# ---------------------------------------------------------------------------
# 9. Autodebug / relatorio de execucao ativos
# ---------------------------------------------------------------------------
func _test_error_report() -> void:
	print("[9] Autodebug / relatorio")
	var er = get_tree().root.get_node_or_null("ErrorReport")
	_check(er != null, "autoload ErrorReport presente")
	if er != null:
		_check(er.has_method("run_checks"), "ErrorReport tem run_checks")
		var problems: Array = er.run_checks("test")
		_check(problems is Array, "run_checks devolve lista de problemas")
		_check(er.has_method("log_event"), "ErrorReport tem log_event")
		er.log_event("INFO", "test", "mensagem de teste do autodebug")
		var stats: Dictionary = er.get_stats()
		_check(stats.has("checks") and stats["checks"] > 0, "estatisticas do ErrorReport funcionam")
	await _frames(1)

# ---------------------------------------------------------------------------
func _finish() -> void:
	print("\n=== RESULTADO: %d PASS, %d FAIL ===" % [_passed, _failed])
	for f in _failures:
		print("  FALHOU: %s" % f)
	# relatorio em disco
	DirAccess.make_dir_recursive_absolute("res://docs/diagnostico")
	var report := FileAccess.open("res://docs/diagnostico/test_report.txt", FileAccess.WRITE)
	if report:
		report.store_line("Relatorio de testes — %s" % Time.get_datetime_string_from_system())
		report.store_line("Resultado: %d PASS / %d FAIL" % [_passed, _failed])
		report.store_line("")
		for line in _report_lines:
			report.store_line(line)
		report.close()
	get_tree().quit(1 if _failed > 0 else 0)
