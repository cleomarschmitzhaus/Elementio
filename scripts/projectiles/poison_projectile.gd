extends Node2D
## Jato de veneno do Scorpion.
##
## Persegue o alvo pelo caminho mais curto do mundo toroidal. Ao encostar,
## aplica dano direto e, se o alvo for uma unidade, deixa um veneno que causa
## dano ao longo do tempo.

const _PlanetTerrain = preload("res://scripts/planet_terrain.gd")

@export var speed: float = 520.0
@export var damage: int = 8
@export var poison_dps: float = 3.0
@export var poison_duration: float = 4.0
@export var lifetime: float = 2.5
@export var hit_radius: float = 18.0

var target: Node2D = null

func _ready() -> void:
	add_to_group("projectiles")
	z_index = 20
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return
	var wsize := _world_size()
	var to_target := _PlanetTerrain.toroidal_delta(global_position, target.global_position, wsize)
	var dist := to_target.length()
	var radius := hit_radius
	if target.is_in_group("buildings"):
		radius = 34.0
	elif target.is_in_group("units"):
		radius = 16.0
	if dist <= radius:
		_hit()
		return
	if dist <= 0.001:
		return
	var dir := to_target / dist
	rotation = dir.angle()
	global_position += dir * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _hit() -> void:
	if is_instance_valid(target):
		if target.has_method("take_damage"):
			target.take_damage(damage)
		if is_instance_valid(target) and not target.is_queued_for_deletion() \
				and poison_dps > 0.0 and poison_duration > 0.0 \
				and target.has_method("apply_poison"):
			target.apply_poison(poison_dps, poison_duration)
	queue_free()

func _world_size() -> Vector2:
	var planet_node = get_tree().get_first_node_in_group("planet")
	if planet_node and "world_size" in planet_node:
		var ws: Vector2 = planet_node.get("world_size")
		return ws
	return Vector2(8000.0, 4000.0)

func _draw() -> void:
	# Rastro largo e translucido + nucleo brilhante: leitura de "jato" mesmo
	# com o sprite pequeno no zoom normal do RTS.
	draw_line(Vector2(-24, 0), Vector2.ZERO, Color(0.15, 0.75, 0.1, 0.28), 10.0, true)
	draw_line(Vector2(-20, 0), Vector2.ZERO, Color(0.35, 1.0, 0.2, 0.8), 6.0, true)
	draw_circle(Vector2.ZERO, 5.0, Color(0.55, 1.0, 0.25, 0.95))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 0.65, 1.0))
