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
	
	# Keyboard movement (setas + WASD)
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_vector.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_vector.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_vector.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_vector.y -= 1
		
	# Screen edge mouse movement (pode ser desligada nas opcoes)
	if SettingsManager.edge_scroll:
		if mouse_pos.x < edge_margin:
			move_vector.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin:
			move_vector.x += 1

		if mouse_pos.y < edge_margin:
			move_vector.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin:
			move_vector.y += 1

	var scroll_speed := SettingsManager.scroll_speed
	var new_pos = position + move_vector.normalized() * scroll_speed * delta * (1.0 / zoom.x)

	# Mundo toroidal (Populous 3): a camera "da a volta" ao cruzar a borda do
	# mundo, aparecendo do lado oposto. Todos os objetos sao transladados junto
	# para manter a coerencia visual (sem saltos). O tamanho vem do terreno,
	# para X e Y darem a volta no lugar certo (se o terreno nao estiver
	# disponivel, usa 8000x4000 -> meia largura 4000, meia altura 2000).
	var half := Vector2(4000.0, 2000.0)
	var planet = get_tree().get_first_node_in_group("planet")
	if planet and "world_size" in planet:
		var ws: Vector2 = planet.world_size
		half = ws * 0.5
	var wrap := Vector2.ZERO
	if new_pos.x > half.x:
		wrap.x = -2.0 * half.x
	elif new_pos.x < -half.x:
		wrap.x = 2.0 * half.x
	if new_pos.y > half.y:
		wrap.y = -2.0 * half.y
	elif new_pos.y < -half.y:
		wrap.y = 2.0 * half.y
	if wrap != Vector2.ZERO:
		new_pos += wrap
		_shift_world_entities(wrap)

	position = new_pos

## Translada as entidades junto com a camera no wrap toroidal.
## Deduplica por instancia: uma entidade pode estar em mais de um grupo
## (ex.: a fonte esta em "resources" e "elementio_sources") e so pode
## ser transladada 1 vez, senao se descola das unidades.
func _shift_world_entities(wrap: Vector2) -> void:
	var wrapped_nodes: Dictionary = {}
	for g in ["units", "buildings", "resources", "elementio_sources", "projectiles"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				wrapped_nodes[n.get_instance_id()] = n
	for id in wrapped_nodes:
		var n = wrapped_nodes[id]
		if is_instance_valid(n):
			n.global_position += wrap

func _handle_zoom(delta: float) -> void:
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), zoom_speed * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clamp(target_zoom + 0.1, min_zoom, max_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clamp(target_zoom - 0.1, min_zoom, max_zoom)
