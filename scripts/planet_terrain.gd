class_name PlanetTerrain
extends Node2D

@export var world_size: Vector2 = Vector2(8000.0, 4000.0)

# Tiles do terreno (um por material), gerados proceduralmente no estilo
# Factorio: nitidos, sem emenda e com contraste local forte.
@export var tex_water_path: String = "res://assets/sprites/terrain_water.png"
@export var tex_sand_path: String = "res://assets/sprites/terrain_sand.png"
@export var tex_dirt_path: String = "res://assets/sprites/terrain_dirt.png"
@export var tex_grass_path: String = "res://assets/sprites/terrain_grass.png"
@export var tex_rock_path: String = "res://assets/sprites/terrain_rock.png"

# Um tile de textura a cada N pixels de mundo. Com o mundo 8000x4000 isso da'
# 40x20 tiles: como o tamanho do tile nao mudou, o planeta ganhou 4x mais
# blocos de terreno (aspecto mais fino/detalhado).
@export var tile_world_size: float = 200.0

# Mistura entre materiais (transicoes suaves no shader). Espelham os defaults de
# populous_planet.gdshader e ficam exportados para ajustar a "dissolucao" entre
# agua/areia/terra/grama/pedra sem precisar editar o shader.
@export var blend_width: float = 0.03     # largura da faixa de mistura
@export var edge_cells: float = 36.0      # celulas do serpenteio ao longo do mundo
@export var edge_strength: float = 0.018  # amplitude do serpenteio da borda

@onready var planet_rect: ColorRect = $PlanetSurface
var mat: ShaderMaterial

# Limiares de elevacao. DEVEM ser identicos aos do shader
# res://shaders/populous_planet.gdshader (water_level / sand_level / cliff_level)
const WATER_THRESHOLD: float = 0.38
const SAND_THRESHOLD: float = 0.42
const CLIFF_THRESHOLD: float = 0.68

func _ready() -> void:
	add_to_group("planet")
	# Roda DEPOIS da camera (prioridade menor) para que global_position e
	# camera_offset usem a posicao atual da camera, eliminando a defasagem
	# de 1 frame entre o terreno e as unidades ao mover a camera.
	process_priority = -1
	mat = planet_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("world_size", world_size)
		var rect = planet_rect.get_rect().size
		if rect.x <= 0.0 or rect.y <= 0.0:
			rect = Vector2(10400.0, 10400.0)
		mat.set_shader_parameter("rect_size", rect)
		mat.set_shader_parameter("tile_scale", 1.0 / max(tile_world_size, 1.0))
		mat.set_shader_parameter("blend_width", blend_width)
		mat.set_shader_parameter("edge_cells", edge_cells)
		mat.set_shader_parameter("edge_strength", edge_strength)
		mat.set_shader_parameter("planet_radius_world", 960.0)
		_set_texture("tex_water", tex_water_path)
		_set_texture("tex_sand", tex_sand_path)
		_set_texture("tex_dirt", tex_dirt_path)
		_set_texture("tex_grass", tex_grass_path)
		_set_texture("tex_rock", tex_rock_path)

func _set_texture(param: String, path: String) -> void:
	var tex = load(path)
	if tex:
		mat.set_shader_parameter(param, tex)
	else:
		push_warning("Textura de terreno nao encontrada: %s" % path)

func _process(_delta: float) -> void:
	var cam = get_viewport().get_camera_2d()
	if cam:
		global_position = cam.global_position
		if mat:
			mat.set_shader_parameter("camera_offset", cam.global_position)

# ---------------------------------------------------------------------------
# Elevacao do terreno. Esta e a FONTE UNICA da verdade: e a mesma formula
# usada no shader, entao a colisao/logica de "andar e construir" bate
# exatamente com o que o jogador ve na tela.
# ---------------------------------------------------------------------------
func _hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453123, 1.0)

# Hash PERIODICO: o reticulado e' dobrado modulo `period`. Sem isto o ruido nao
# fechava na emenda do toro (x=0 / y=0) e surgia uma LINHA RETA de material no
# meio do planeta: a elevacao saltava ~0.15 de um pixel para o outro.
func _hash_periodic(p: Vector2, period: Vector2) -> float:
	return _hash(Vector2(fposmod(p.x, period.x), fposmod(p.y, period.y)))

func _noise(p: Vector2, period: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := Vector2(p.x - i.x, p.y - i.y)
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a := _hash_periodic(i, period)
	var b := _hash_periodic(i + Vector2(1.0, 0.0), period)
	var c := _hash_periodic(i + Vector2(0.0, 1.0), period)
	var d := _hash_periodic(i + Vector2(1.0, 1.0), period)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

# fbm periodico: a cada oitava a frequencia dobra e o periodo dobra junto; o
# deslocamento por oitava e' um inteiro, entao nao quebra a periodicidade.
func _fbm(p: Vector2, period: Vector2) -> float:
	var v := 0.0
	var a := 0.5
	var q := p
	var per := period
	for i in range(4):
		v += a * _noise(q + Vector2(float(i) * 3.0 + 1.0, float(i) * 5.0 + 2.0), per)
		q = q * 2.0
		per = per * 2.0
		a *= 0.5
	return v

# Elevacao fisica real em qualquer posicao global (x, y)
func get_elevation_at(world_pos: Vector2) -> float:
	var half_w := world_size.x / 2.0
	var half_h := world_size.y / 2.0

	# Coordenadas normalizadas periodicas [0.0, 1.0].
	# IMPORTANTE: deve ser IDENTICO ao shader (fract(world_px / world_size)).
	# Antes usava fposmod(world + half_w), o que deslocava a logica em meio
	# mundo (1000 px) em relacao ao que o jogador ve na tela.
	var norm_x := fposmod(world_pos.x, world_size.x) / world_size.x
	var norm_y := fposmod(world_pos.y, world_size.y) / world_size.y
	var norm := Vector2(norm_x, norm_y)

	var p := norm * TAU
	var e := sin(p.x) * cos(p.y) * 0.35 \
		+ _fbm(norm * 12.0, Vector2(12.0, 12.0)) * 0.45 \
		+ _fbm(norm * 24.0, Vector2(24.0, 24.0)) * 0.20
	return clampf(e, 0.0, 1.0)

# Verifica se a posicao e terra firme caminhavel e edificavel (nao e oceano nem penhasco intransponivel)
func is_walkable_land(world_pos: Vector2) -> bool:
	var elev := get_elevation_at(world_pos)
	return elev >= WATER_THRESHOLD and elev < CLIFF_THRESHOLD

func is_water(world_pos: Vector2) -> bool:
	return get_elevation_at(world_pos) < WATER_THRESHOLD

func wrap_world_position(pos: Vector2) -> Vector2:
	# Planeta-toro: cada eixo "da a volta" de forma independente.
	var half := world_size * 0.5
	return Vector2(
		fposmod(pos.x + half.x, world_size.x) - half.x,
		fposmod(pos.y + half.y, world_size.y) - half.y)

# Menor deslocamento vetorial de `from` ate `to` num mundo toroidal (o planeta
# e' topologicamente um toro, como no Populous 3). Atravessa as emendas pelo
# caminho mais curto em X e em Y, entao perseguir um alvo do outro lado do
# mapa nao faz a unidade dar a volta inteira.
static func toroidal_delta(from: Vector2, to: Vector2, size: Vector2) -> Vector2:
	var d := to - from
	d.x = fposmod(d.x + size.x * 0.5, size.x) - size.x * 0.5
	d.y = fposmod(d.y + size.y * 0.5, size.y) - size.y * 0.5
	return d

# Parametros da iluminacao esferica (iguais aos do shader do terreno), lidos do
# material do planeta para que unidades/construcoes usem EXATAMENTE a mesma
# luz e nao parecam flutuar fora do chao.
static func get_sphere_uniforms() -> Dictionary:
	var d := {
		"camera_offset": Vector2.ZERO,
		"rect_size": Vector2(10400.0, 10400.0),
		"planet_radius": 0.48,
		"planet_radius_world": 960.0,
		"atmosphere_color": Color(0.2, 0.55, 0.85, 0.4),
	}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return d
	var planet := tree.get_first_node_in_group("planet")
	if planet == null:
		return d
	var ps := planet.get_node_or_null("PlanetSurface")
	if ps == null or ps.material == null:
		return d
	var m := ps.material as ShaderMaterial
	if m == null:
		return d
	var v = m.get_shader_parameter("camera_offset")
	if v != null:
		d["camera_offset"] = v
	v = m.get_shader_parameter("rect_size")
	if v != null:
		d["rect_size"] = v
	v = m.get_shader_parameter("planet_radius")
	if v != null:
		d["planet_radius"] = v
	v = m.get_shader_parameter("planet_radius_world")
	if v != null:
		d["planet_radius_world"] = v
	v = m.get_shader_parameter("atmosphere_color")
	if v != null:
		d["atmosphere_color"] = v
	return d
