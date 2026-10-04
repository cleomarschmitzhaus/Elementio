extends Camera2D

@export var move_speed: float = 800.0
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var edge_margin: float = 20.0

var target_zoom: float = 1.0

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_zoom(delta)

func _handle_movement(delta: float) -> void:
	var move_vector = Vector2.ZERO
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Keyboard movement
	if Input.is_action_pressed("ui_right"):
		move_vector.x += 1
	if Input.is_action_pressed("ui_left"):
		move_vector.x -= 1
	if Input.is_action_pressed("ui_down"):
		move_vector.y += 1
	if Input.is_action_pressed("ui_up"):
		move_vector.y -= 1
		
	# Screen edge mouse movement
	if mouse_pos.x < edge_margin:
		move_vector.x -= 1
	elif mouse_pos.x > viewport_size.x - edge_margin:
		move_vector.x += 1
		
	if mouse_pos.y < edge_margin:
		move_vector.y -= 1
	elif mouse_pos.y > viewport_size.y - edge_margin:
		move_vector.y += 1

	position += move_vector.normalized() * move_speed * delta * (1.0 / zoom.x)

func _handle_zoom(delta: float) -> void:
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), zoom_speed * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clamp(target_zoom + 0.1, min_zoom, max_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clamp(target_zoom - 0.1, min_zoom, max_zoom)
