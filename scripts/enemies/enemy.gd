extends CharacterBody2D

@export var max_health: int = 50
var current_health: int = 50
@export var move_speed: float = 60.0
# Classificacao: 0 = jogador, 1 = inimigo, 2 = neutro
@export var team: int = Faction.ENEMY
# Inimigos nao sao controlaveis
var is_controllable: bool = false

var is_selected: bool = false

@onready var selection_ring = $SelectionRing if has_node("SelectionRing") else null
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

var health_bar_container: Node2D = null
var health_bar_fill: ColorRect = null

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("units")  # para ser detectado por _select_at (mas nao controlavel)
	current_health = max_health
	if selection_ring:
		selection_ring.visible = false
	if sprite:
		var sphere_mat := ShaderMaterial.new()
		sphere_mat.shader = load("res://shaders/entity_sphere.gdshader")
		sprite.material = sphere_mat
	_setup_health_bar()

func _setup_health_bar() -> void:
	var container = Node2D.new()
	container.name = "HealthBar"
	container.position = Vector2(0, -20)
	add_child(container)
	health_bar_container = container

	var bg = ColorRect.new()
	bg.size = Vector2(32, 3)
	bg.position = Vector2(-16, 0)
	bg.color = Color(0.12, 0.12, 0.12, 0.85)
	container.add_child(bg)

	health_bar_fill = ColorRect.new()
	health_bar_fill.size = Vector2(32, 3)
	health_bar_fill.position = Vector2(-16, 0)
	health_bar_fill.color = Color(0.9, 0.2, 0.2, 1.0)
	container.add_child(health_bar_fill)

func _process(_delta: float) -> void:
	_update_health_bar()

func _update_health_bar() -> void:
	if health_bar_fill == null:
		return
	var ratio = 0.0
	if max_health > 0:
		ratio = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	health_bar_fill.size.x = 32.0 * ratio

func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		current_health = 0
		queue_free()

func get_health_ratio() -> float:
	if max_health <= 0:
		return 0.0
	return clampf(float(current_health) / float(max_health), 0.0, 1.0)

func get_unit_info() -> String:
	return "Inimigo  |  Vida: %d/%d" % [current_health, max_health]

func select() -> void:
	is_selected = true
	queue_redraw()

func deselect() -> void:
	is_selected = false
	queue_redraw()

func _draw() -> void:
	# Inimigo: elipse vermelha (visao topdown) com centro 10% opaco
	if is_selected:
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 14.0, Faction.selection_fill(team))
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, Faction.selection_color(team), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)