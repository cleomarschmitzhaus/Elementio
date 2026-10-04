extends CharacterBody2D

@export var speed: float = 150.0
var target_position: Vector2
var is_selected: bool = false
var is_moving: bool = false

@onready var selection_ring = $SelectionRing

func _ready() -> void:
	target_position = global_position
	selection_ring.visible = false

func _physics_process(_delta: float) -> void:
	if is_moving:
		var direction = global_position.direction_to(target_position)
		var distance = global_position.distance_to(target_position)
		
		if distance > 5.0:
			velocity = direction * speed
			move_and_slide()
		else:
			is_moving = false
			velocity = Vector2.ZERO

func select() -> void:
	is_selected = true
	selection_ring.visible = true

func deselect() -> void:
	is_selected = false
	selection_ring.visible = false

func set_target(pos: Vector2) -> void:
	target_position = pos
	is_moving = true
