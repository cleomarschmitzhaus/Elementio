extends Node3D
## Cena principal 3D estilo Populous 3.
## - Vista planeta: camera longe; WASD gira o planeta SOMENTE no eixo vertical
##   (o norte fica sempre para cima; o globo nunca inclina para os lados)
##   (textura = mundo 2D do SubViewport, entidades acompanham pois sao parte
##   da textura).
## - Vista superficie ( outra solucao do Populous 3 ): camera ISOMETRICA de
##   cima (inclinada ~65 graus) sobre o ponto focado. WASD e setas movem o foco
##   sobre a esfera com NORTE FIXO: a imagem nunca gira (W/↑ sobe, S/↓ desce,
##   A/← e D/→ andam para os lados e nao ha mais teclas de giro). A roda do
##   mouse ajusta o zoom (distancia). Cliques usam raio-na-esfera ->
##   coordenada do mundo 2D.
## - Boot: comeca na vista planetaria e entra no Foco Local apos 2 s.
## - Skybox procedural (shaders/sky.gdshader): universo na vista planeta (estrelas)
##   e ceu azul com nuvens, sol e lua ORBITANDO no Foco Local.

@onready var subviewport: SubViewport = $SubViewport
@onready var sphere: MeshInstance3D = $Sphere
@onready var camera: Camera3D = $Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var flat_camera: Camera2D = subviewport.get_node_or_null("WorldFlat/Camera2D")
@onready var selection_manager = get_tree().get_first_node_in_group("selection_manager")

const WORLD_SIZE := Vector2(8000.0, 4000.0)
const PLANET_DIST := 2.2      # globo maior/mais perto na vista planetaria
const PLANET_ROT_SPEED := 1.2
const SURF_MOVE_SPEED := 0.8    # radianos de arco por segundo sobre a esfera
# Limite de latitude do foco: o POLO e' o ponto singular da bussola (a direcao
# "norte" deixa de existir exatamente em +-90 graus). Com o norte FIXO o foco
# para um pouco antes, em +-88 graus = 1.53588974175501 rad, sem girar e sem NaN.
const SURF_LAT_MAX := 1.53588974175501
# Foco Local: vista ISOMETRICA de cima (como o Populous 3 de perto). A camera
# fica ACIMA do ponto focado, inclinada, olhando para a superficie. A distancia
# controla o zoom e o FOV estreito tira a distorcao de perspectiva (aparencia
# isometrica).
const SURF_DIST_MIN := 1.1
const SURF_DIST_MAX := 4.5
const PLANET_DIST_MIN := 1.10  # zoom maximo: globo preenche a tela, sem espaco ao redor
const PLANET_DIST_MAX := 5.0
const SURF_ISO_PITCH := 1.134  # ~65 graus de inclinacao (aparece de cima)
# FOV do Foco Local. 16 = terreno preenche tudo (o ceu fica FORA do quadro);
# 22 = terreno preenche a tela, ceu ~21% da area; 28 = ceu ~44% (bem visivel no
# topo e nos lados, terreno ainda no centro); 40 = o planeta vira uma bola com
# ~66% de ceu. Areas medidas pelo probe (rays que nao batem na esfera). Vira
# `var` para o probe comparar valores.
var surf_fov: float = 28.0

# ---------------------------------------------------------------------------
# Skybox / ciclo dia-noite (sol e lua orbitando)
# ---------------------------------------------------------------------------
const BOOT_DELAY := 2.0        # vista planeta -> Foco Local (segundos)
const SUN_ORBIT_PERIOD := 150.0 # uma volta completa do sol (segundos)
const MOON_ORBIT_PERIOD := 230.0 # periodo DIFERENTE: a lua cruza o sol no ceu
const SUN_ORBIT_TILT := 0.42    # inclinacao do plano orbital (~24 graus)

var boot_to_surface: bool = true   # testes/probes desligam este boot automatico
var boot_delay: float = BOOT_DELAY
var sky_material: ShaderMaterial = null
var _sky_time: float = 0.0
var _sun_angle: float = 0.0
var _moon_angle: float = 2.4

var surface_view: bool = false
var blend: float = 0.0          # 0 = planeta, 1 = superficie (transicao suave)

# estado da camera de superficie. Guardamos apenas o PONTO 3D focado na esfera:
# a orientacao (norte/leste) e' DERIVADA do ponto (surface_north/surface_right),
# entao a imagem nunca acumula rotacao/deriva ao andar (norte sempre para cima).
# O lat/lon "puro" quebrava em +-90 graus; aqui o foco para em +-88 graus antes
# do polo, que e' o ponto singular da bussola.
var surf_point: Vector3 = Vector3(0.0, 0.0, 1.0)
var surf_dist: float = 2.2     # distancia da camera acima do foco (zoom)

var planet_dist: float = PLANET_DIST

# Caixa de selecao arrastada (screen-space), usada na vista 3D (foco/planeta).
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO
var _sel_box: Control = null

func _ready() -> void:
	add_to_group("globe_controller")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = subviewport.get_texture()
	mat.roughness = 0.8
	# Filtro linear (com mipmap) em vez de NEAREST: a textura do planeta e'
	# ampliada na Vista de Foco Local, e NEAREST deixava os sprites/blocos
	# "quadriculados". Linear suaviza a ampliacao e o mipmap evita o serrilhado
	# quando o globo e' reduzido na Vista Planetaria.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sphere.material_override = mat
	if flat_camera:
		# Mantem exatamente uma "volta" do mundo (WORLD_SIZE) no SubViewport,
		# qualquer que seja a resolucao: zoom = textura / mundo (= texels por
		# pixel de mundo). Assim mudar o tamanho em globe_main.tscn nao quebra
		# o enquadramento.
		flat_camera.position = Vector2(0, 0)
		flat_camera.zoom = Vector2(subviewport.size) / WORLD_SIZE
		flat_camera.set_process(false)
		flat_camera.set_process_input(false)
	# Cliques precisam ser convertidos via raio-3D; o gestor 2D receberia
	# coordenadas erradas (viewport raiz != subviewport), entao ficamos com
	# o input dele desativado e tratamos selecao/comandos aqui.
	if selection_manager:
		selection_manager.set_process_input(false)
	# Overlay de caixa de selecao (arrastar) em screen-space, por cima de tudo.
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var box := Control.new()
	box.set_script(load("res://scripts/globe_sel_box.gd"))
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	canvas.add_child(box)
	_sel_box = box
	# comecar a superficie focada no ninho inicial (2740, 169)
	_focus_world_at(Vector2(2740, 169))
	camera.fov = 60.0
	_setup_sky()
	# Comeca com o sol ALTO sobre o ponto inicial: o boot cai no Foco Local e o
	# ceu aparece iluminado (sem isto o sorteio do angulo podia pegar "noite").
	_sun_angle = _best_sun_angle(surf_point)
	_update_sky(0.0)
	# Boot: comeca na VISTA PLANETARIA e entra no Foco Local depois de 2 s.
	if boot_to_surface:
		_boot_sequence()

# ---------------------------------------------------------------------------
# Skybox / ciclo orbital do sol e da lua
# ---------------------------------------------------------------------------
# Cria o ceu procedural (shader `sky.gdshader`) e o liga no WorldEnvironment.
# Se o ambiente nao existir, um e' criado. O fundo passa a ser a SKY (antes era
# uma cor escura fixa) — o visual de "universo" tambem vem do shader.
func _setup_sky() -> void:
	var env := world_environment.environment
	if env == null:
		env = Environment.new()
		world_environment.environment = env
	var sky := Sky.new()
	# Radiance minima: o ceu NAO alimenta ambiente/reflexos (o ambiente usa COR),
	# entao o cubemap de radiancia fica no MENOR tamanho possivel (quase gratis).
	# INCREMENTAL (e nao REALTIME, que forca radiance 256): o fundo continua
	# sendo desenhado pelo shader a cada quadro, com sol/lua/nuvens animados,
	# mas o cubemap de radiancia atualiza devagarzinho no tamanho minimo.
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky

# Angulo do sol que deixa o sol o mais ALTO possivel sobre `p` (usado no boot).
func _best_sun_angle(p: Vector3) -> float:
	var best := 0.0
	var best_dot := -2.0
	var n := 96
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var d := _orbit_dir(a).dot(p)
		if d > best_dot:
			best_dot = d
			best = a
	# um pouco antes do zênite: o sol aparece (nao no ponto cego de cima)
	return wrapf(best - 0.55, 0.0, TAU)

# Direcao de um astro no seu plano orbital inclinado (grande circulo).
func _orbit_dir(angle: float) -> Vector3:
	var axis := Vector3(sin(SUN_ORBIT_TILT), cos(SUN_ORBIT_TILT), 0.0).normalized()
	return Vector3(1.0, 0.0, 0.0).rotated(axis, angle).normalized()

# Avanca o relogio do ceu e reenvia os uniformes. `delta` = 0 apenas posiciona.
func _update_sky(delta: float) -> void:
	_sky_time += delta
	_sun_angle = wrapf(_sun_angle + TAU * delta / SUN_ORBIT_PERIOD, 0.0, TAU)
	_moon_angle = wrapf(_moon_angle + TAU * delta / MOON_ORBIT_PERIOD, 0.0, TAU)
	var sd := _orbit_dir(_sun_angle)
	var md := _orbit_dir(_moon_angle)
	if sky_material:
		sky_material.set_shader_parameter("view_blend", blend)
		sky_material.set_shader_parameter("sky_up", surf_point)
		sky_material.set_shader_parameter("sky_north", surface_north())
		sky_material.set_shader_parameter("sky_right", surface_right())
		sky_material.set_shader_parameter("sun_dir", sd)
		sky_material.set_shader_parameter("moon_dir", md)
		sky_material.set_shader_parameter("sky_time", _sky_time)
	# A luz direcional segue o sol: a luz bate de onde o sol aparece no ceu.
	if directional_light:
		var up_ref: Vector3 = Vector3.UP if absf(sd.y) < 0.98 else Vector3.FORWARD
		var light_xf := Transform3D().looking_at(-sd, up_ref)
		light_xf.origin = sd * 20.0
		directional_light.global_transform = light_xf

# Boot: inicia na vista planetaria e entra no Foco Local depois de `boot_delay`.
func _boot_sequence() -> void:
	if boot_delay > 0.0:
		await get_tree().create_timer(boot_delay).timeout
	set_surface_view(true)
	_notify_ui_view_changed()

# ---------------------------------------------------------------------------
# API da vista (usada pelo botao da UI e pela tecla V)
# ---------------------------------------------------------------------------
func set_surface_view(on: bool) -> void:
	surface_view = on

func toggle_view() -> void:
	surface_view = not surface_view

func is_surface_view() -> bool:
	return surface_view

func _focus_world_at(world_pos: Vector2) -> void:
	# mapeia coordenada do mundo 2D -> (lon, lat) na esfera (mesma formula
	# inversa do _screen_to_world)
	var u := -world_pos.x / WORLD_SIZE.x + 0.5
	var v := world_pos.y / WORLD_SIZE.y + 0.5
	focus_at_lat_lon(v * PI - PI * 0.5, u * TAU - PI)

# Posiciona o foco num ponto (lat, lon) da esfera. A orientacao da camera e'
# sempre NORTE FIXO (nao existe mais "heading"). Usado no boot, nos testes e no
# probe. A latitude e' presa em +-88 graus (limite da bussola).
func focus_at_lat_lon(lat: float, lon: float) -> void:
	var lat_c := clampf(lat, -SURF_LAT_MAX, SURF_LAT_MAX)
	var cl := cos(lat_c)
	surf_point = Vector3(cl * cos(lon), sin(lat_c), cl * sin(lon)).normalized()

# Direcao "norte" da vista local: projecao do +Y do MUNDO no plano tangente do
# ponto focado. Depende SO' do ponto -> andar nao gira a camera (sem deriva).
func surface_north() -> Vector3:
	var n := Vector3.UP - surf_point * surf_point.dot(Vector3.UP)
	if n.length_squared() < 1e-10:
		return Vector3.FORWARD  # inalcancavel: o foco para em +-88 graus
	return n.normalized()

# Direcao "direita da tela" (eixo leste/oeste): perpendicular ao norte, no
# plano tangente. Tambem depende SO' do ponto focado.
func surface_right() -> Vector3:
	return surface_north().cross(surf_point).normalized()

# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	blend = move_toward(blend, 1.0 if surface_view else 0.0, delta * 2.5)

	if surface_view:
		_process_surface_movement(delta)
	else:
		_process_planet_rotation(delta)

	_keep_entities_on_torus()
	_update_sky(delta)
	_update_camera_transform(delta)

# Mundo toroidal (Populous 3): quem cruza uma borda do mapa reaparece na borda
# oposta, tanto em X quanto em Y. O SubViewport mostra exatamente uma "volta"
# do mundo (WORLD_SIZE) e a esfera faz o wrap nos dois eixos; sem isto a unidade
# sairia da textura e sumiria do planeta.
func _keep_entities_on_torus() -> void:
	var half := WORLD_SIZE * 0.5
	for g in ["units", "buildings", "resources"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			var nn := n as Node2D
			if nn == null:
				continue
			var p := nn.global_position
			var w := Vector2(
				fposmod(p.x + half.x, WORLD_SIZE.x) - half.x,
				fposmod(p.y + half.y, WORLD_SIZE.y) - half.y)
			if not w.is_equal_approx(p):
				nn.global_position = w

func _process_planet_rotation(delta: float) -> void:
	# O globo gira SOMENTE no eixo vertical: o norte fica sempre para cima e o
	# planeta nunca inclina para os lados (a orientacao N/S/L/O nao muda).
	var yaw := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) \
			or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		yaw -= PLANET_ROT_SPEED * delta
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) \
			or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		yaw += PLANET_ROT_SPEED * delta
	sphere.rotation.y = wrapf(sphere.rotation.y + yaw, -PI, PI)

func _process_surface_movement(delta: float) -> void:
	# Sem giro de camera: a orientacao e' sempre norte fixo (WASD e setas so'
	# movem o foco; antes as setas/QE giravam o "heading").
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	_move_surface(move, delta)

# Movimento puro (sem input, por isso testavel): anda `move` (x = direita da
# TELA, y = frente/norte) sobre a esfera, em coordenadas do MUNDO: leste/oeste
# segue o PARALELO (latitude fixa) e norte/sul segue o MERIDIANO. Assim um
# circuito fechado fecha exato e a orientacao (norte fixo) nunca deriva. O foco
# para em +-88 graus; no polo a bussola e' singular, por isso nunca chegamos la'.
func _move_surface(move: Vector2, delta: float) -> void:
	if move == Vector2.ZERO:
		return
	var p := surf_point
	var lat := asin(clampf(p.y, -1.0, 1.0))
	var lon := atan2(p.z, p.x)
	var arc := SURF_MOVE_SPEED * delta
	lat = clampf(lat + move.y * arc, -SURF_LAT_MAX, SURF_LAT_MAX)
	var cl := cos(lat)
	# `move.x` positivo = DIREITA DA TELA. Como a vista local olha a esfera de
	# FORA, a imagem e' ESPELHADA: a direita da tela e' o OESTE do mundo
	# (longitude diminui). Sem este sinal, A/D andam ao contrario na tela.
	lon = wrapf(lon - move.x * arc / maxf(cl, 1e-4), -PI, PI)
	surf_point = Vector3(cl * cos(lon), sin(lat), cl * sin(lon))

func _update_camera_transform(delta: float) -> void:
	# pose desejada de cada modo; interpola por `blend`
	var p := surf_point
	var north := surface_north()
	var surf_pos: Vector3 = p * (1.0 + surf_dist * sin(SURF_ISO_PITCH)) \
		- north * (surf_dist * cos(SURF_ISO_PITCH))
	# olha para o proprio ponto focado -> o terreno aparece visto de cima
	var surf_target: Vector3 = p

	var pos: Vector3 = Vector3(0, 0, planet_dist).lerp(surf_pos, blend)
	var target: Vector3 = Vector3.ZERO.lerp(surf_target, blend)
	var up: Vector3 = _blend_up(p, blend)

	var zb := (pos - target).normalized()
	# "Direita da tela" (leste). Em vista planeta (blend=0) usamos o leste
	# global (Vector3.RIGHT); no Foco Local (blend=1) usamos o leste tangente
	# (surface_right). up.cross(zb) apontava para oeste no Foco Local, o que
	# invertia o eixo Y da tela ("cima" virava sul). surface_right() aponta
	# para leste em ambos os casos, mantendo o norte sempre para cima.
	var xb_planet := Vector3.RIGHT
	var xb_surface := surface_right()
	if xb_surface.length_squared() < 0.0001:
		xb_surface = Vector3.RIGHT
	var xb := xb_planet.lerp(xb_surface, blend).normalized()
	if xb.length_squared() < 0.0001:
		xb = Vector3.RIGHT
	xb = xb.normalized()
	var yb := zb.cross(xb)
	var desired := Transform3D(Basis(xb, yb, zb).orthonormalized(), pos)
	camera.global_transform = camera.global_transform.interpolate_with(
		desired, 1.0 - exp(-10.0 * delta))
	camera.fov = lerpf(60.0, surf_fov, blend)

# Mistura o "up" da camera entre a vista planeta (UP) e a superficie (radial p)
# por ROTACAO, e nao por slerp: Vector3.UP.slerp(p) degenera quando p ~ -UP
# (polo sul), o que travava/embaralhava a camera por la.
func _blend_up(p: Vector3, blend: float) -> Vector3:
	if blend <= 0.0001:
		return Vector3.UP
	var axis := Vector3.UP.cross(p)
	if axis.length_squared() < 1e-10:
		return Vector3.UP if p.y >= 0.0 else Vector3.DOWN
	return Vector3.UP.rotated(axis.normalized(), Vector3.UP.angle_to(p) * blend)

# ---------------------------------------------------------------------------
# Input: teclas globais, roda do mouse, cliques convertidos raio->mundo
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_V:
			toggle_view()
			_notify_ui_view_changed()
		elif event.keycode == KEY_F11:
			_toggle_fullscreen()
		elif event.keycode == KEY_F:
			if selection_manager and selection_manager.has_method("cycle_formation"):
				selection_manager.cycle_formation()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if surface_view:
				surf_dist = clampf(surf_dist - 0.2, SURF_DIST_MIN, SURF_DIST_MAX)
			else:
				planet_dist = clampf(planet_dist - 0.25, PLANET_DIST_MIN, PLANET_DIST_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if surface_view:
				surf_dist = clampf(surf_dist + 0.2, SURF_DIST_MIN, SURF_DIST_MAX)
			else:
				planet_dist = clampf(planet_dist + 0.25, PLANET_DIST_MIN, PLANET_DIST_MAX)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start = event.position
				_drag_end = event.position
				if _sel_box:
					_sel_box.drag_start = _drag_start
					_sel_box.drag_end = _drag_end
					_sel_box.active = true
					_sel_box.visible = true
					_sel_box.queue_redraw()
			else:
				_dragging = false
				if _sel_box:
					_sel_box.active = false
					_sel_box.visible = false
					_sel_box.queue_redraw()
				var drag_vec := _drag_end - _drag_start
				if drag_vec.length() < 4.0:
					# clique simples -> selecao pontual em screen-space (tolerancia 80 px)
					_select_at_screen(event.position, Input.is_key_pressed(KEY_SHIFT))
				else:
					# arrasto -> seleciona tudo dentro da caixa (em screen-space)
					_drag_select_screen(_drag_start, _drag_end, Input.is_key_pressed(KEY_SHIFT))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var world_pos2: Variant = _screen_to_world(event.position)
			if world_pos2 != null:
				_command_at(world_pos2)
	elif event is InputEventMouseMotion and _dragging:
		_drag_end = event.position
		if _sel_box:
			_sel_box.drag_end = _drag_end
			_sel_box.queue_redraw()

func _notify_ui_view_changed() -> void:
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and "view_toggle_btn" in ui and ui.view_toggle_btn:
		ui.view_toggle_btn.text = "🌍 Vista Planetária" if surface_view else "🔍 Foco Local"

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------------------------------------------------------------------
# Conversao tela -> mundo 2D (raio contra a esfera; funciona nas 2 vistas)
# ---------------------------------------------------------------------------
func _screen_to_world(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var b := from.dot(dir)
	var c := from.dot(from) - 1.0   # esfera raio 1 na origem
	var disc := b * b - c
	if disc < 0.0:
		return null
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	if t < 0.0:
		return null
	var hit := from + dir * t
	# desfaz a rotacao da esfera -> ponto no espaco-textura
	var local: Vector3 = sphere.global_transform.basis.inverse() * hit
	var theta := atan2(local.z, local.x)
	var phi := asin(clampf(local.y, -1.0, 1.0))
	var u := (theta + PI) / TAU
	var v := (phi + PI * 0.5) / PI
	return Vector2(-(u - 0.5) * WORLD_SIZE.x, (v - 0.5) * WORLD_SIZE.y)

# ---------------------------------------------------------------------------
# Selecao e comandos (substituem o gestor 2D com coordenadas convertidas)
# ---------------------------------------------------------------------------
func _select_at(world_pos: Vector2, additive: bool = false) -> void:
	var sm = get_tree().get_first_node_in_group("selection_manager")
	var best: Node = null
	var best_dist := 32.0
	for g in ["units", "buildings", "resources"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			var nn := n as Node2D
			var d := nn.global_position.distance_to(world_pos)
			if d < best_dist:
				best_dist = d
				best = n
	if sm:
		if not additive:
			for u in sm.selected_units:
				if is_instance_valid(u):
					u.deselect()
			sm.selected_units.clear()
			if is_instance_valid(sm.selected_building):
				sm.selected_building.deselect()
				sm.selected_building = null
			if is_instance_valid(sm.selected_resource):
				sm.selected_resource.deselect()
				sm.selected_resource = null
	if best != null and best.has_method("select"):
		best.select()
		if sm:
			if best.is_in_group("units"):
				if not sm.selected_units.has(best):
					sm.selected_units.append(best)
			elif best.is_in_group("buildings"):
				sm.selected_building = best
			elif best.is_in_group("resources"):
				sm.selected_resource = best
			if sm.has_method("_notify_ui_selection"):
				sm._notify_ui_selection()

func _world_to_screen(world_pos: Vector2) -> Vector2:
	# Converte uma coordenada do mundo 2D (centrada) para screen-space,
	# projetando o ponto correspondente na esfera. Retorna (-1,-1) se estiver
	# atras da camera (fora de tela).
	var u := -world_pos.x / WORLD_SIZE.x + 0.5
	var v := world_pos.y / WORLD_SIZE.y + 0.5
	var theta := u * TAU - PI
	var phi := v * PI - (PI * 0.5)
	var pt := Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
	var world3: Vector3 = sphere.global_transform * pt
	if camera.is_position_behind(world3):
		return Vector2(-1.0, -1.0)
	return camera.unproject_position(world3)

func _is_front(world_pos: Vector2) -> bool:
	# Uma entidade so' pode ser selecionada se estiver no lado da frente do
	# planeta (hemisferio voltado para a camera), nao ocluida pela esfera.
	var u := -world_pos.x / WORLD_SIZE.x + 0.5
	var v := world_pos.y / WORLD_SIZE.y + 0.5
	var theta := u * TAU - PI
	var phi := v * PI - (PI * 0.5)
	var pt := Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
	var world3: Vector3 = sphere.global_transform * pt
	var cam_pos: Vector3 = camera.global_position
	# frente: ponto na mesma hemisfera que a camera (nao ocluido pela esfera).
	if world3.dot(cam_pos) < -0.05:
		return false
	# e na frente da camera (nao atras do near plane)
	if camera.is_position_behind(world3):
		return false
	return true

# (debug helpers removed)

func _select_at_screen(screen_pos: Vector2, additive: bool) -> void:
	# Selecao pontual: converte o clique para coordenada de mundo (raio na
	# esfera) e seleciona a entidade mais proxima dentro de 500 unidades.
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if not additive:
		if sm:
			for u in sm.selected_units:
				if is_instance_valid(u):
					u.deselect()
			sm.selected_units.clear()
			if is_instance_valid(sm.selected_building):
				sm.selected_building.deselect()
				sm.selected_building = null
			if is_instance_valid(sm.selected_resource):
				sm.selected_resource.deselect()
				sm.selected_resource = null
	var best: Node = null
	var best_dist := 500.0
	var units_count: int = get_tree().get_nodes_in_group("units").size()
	var bld_count: int = get_tree().get_nodes_in_group("buildings").size()
	var res_count: int = get_tree().get_nodes_in_group("resources").size()
	var world_pos: Variant = _screen_to_world(screen_pos)
	if world_pos != null:
		var wp: Vector2 = world_pos
		for g in ["units", "buildings", "resources"]:
			for n in get_tree().get_nodes_in_group(g):
				if not is_instance_valid(n):
					continue
				var wpos: Vector2 = (n as Node2D).global_position
				if not _is_front(wpos):
					continue  # so' o lado da frente do planeta e' selecionavel
				var d := wpos.distance_to(wp)
				if d < best_dist:
					best_dist = d
					best = n
	if best != null and best.has_method("select"):
		best.select()
		if sm:
			if best.is_in_group("units"):
				if not sm.selected_units.has(best):
					sm.selected_units.append(best)
			elif best.is_in_group("buildings"):
				sm.selected_building = best
			elif best.is_in_group("resources"):
				sm.selected_resource = best
		pass
	else:
		pass
	if sm and sm.has_method("_notify_ui_selection"):
		sm._notify_ui_selection()

func _drag_select_screen(start: Vector2, end: Vector2, additive: bool) -> void:
	# Selecao por arrasto em screen-space: seleciona tudo cuja projecao na tela
	# cai dentro do retangulo arrastado.
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if not additive:
		if sm:
			for u in sm.selected_units:
				if is_instance_valid(u):
					u.deselect()
			sm.selected_units.clear()
			if is_instance_valid(sm.selected_building):
				sm.selected_building.deselect()
				sm.selected_building = null
			if is_instance_valid(sm.selected_resource):
				sm.selected_resource.deselect()
				sm.selected_resource = null
	var min_x := minf(start.x, end.x)
	var min_y := minf(start.y, end.y)
	var max_x := maxf(start.x, end.x)
	var max_y := maxf(start.y, end.y)
	var rect := Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	# margem de 8 px para absorver a imprecisao da projecao esfera<->tela
	var rect_grown := rect.grow(8.0)
	for g in ["units", "buildings", "resources"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			var wpos: Vector2 = (n as Node2D).global_position
			if not _is_front(wpos):
				continue  # so' o lado da frente do planeta e' selecionavel
			var sp := _world_to_screen(wpos)
			if sp.x < 0.0 and sp.y < 0.0:
				continue
			if rect_grown.has_point(sp):
				if n.has_method("select"):
					n.select()
				if sm:
					if n.is_in_group("units"):
						if not sm.selected_units.has(n):
							sm.selected_units.append(n)
					elif n.is_in_group("buildings"):
						sm.selected_building = n
					elif n.is_in_group("resources"):
						sm.selected_resource = n
	if sm and sm.has_method("_notify_ui_selection"):
		sm._notify_ui_selection()

func _command_at(world_pos: Vector2) -> void:
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if sm == null or sm.selected_units.is_empty():
		return
	# clique sobre fonte -> coletar
	var res = null
	for r in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(r) and (r as Node2D).global_position.distance_to(world_pos) < 32.0:
			res = r
			break
	if res != null:
		for u in sm.selected_units:
			if is_instance_valid(u) and u.has_method("harvest_resource"):
				u.harvest_resource(res)
	elif sm.has_method("move_selected_units_in_formation"):
		sm.move_selected_units_in_formation(world_pos)
	if sm.has_method("_notify_ui_selection"):
		sm._notify_ui_selection()
