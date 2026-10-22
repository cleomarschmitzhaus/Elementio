extends Node2D

var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO
var selected_units: Array = []
var selected_building = null
var selected_resource = null

# Grupos de controle clássicos RTS (Ctrl + 1-9)
var control_groups: Dictionary = {}

# Tipo de formação: "line", "box", "circle", "wedge"
var current_formation: String = "box"

func _ready() -> void:
	add_to_group("selection_manager")
	z_index = 100

func _input(event: InputEvent) -> void:
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.is_building_mode: return

	# Tecla F11 para alternar tela cheia
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		
		# Atalhos de Formação (F)
		if event.keycode == KEY_F:
			cycle_formation()
			get_viewport().set_input_as_handled()
			return

		# Grupos de Controle RTS (1 a 9)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var group_num = event.keycode - KEY_0
			if Input.is_key_pressed(KEY_CTRL):
				assign_control_group(group_num)
			else:
				select_control_group(group_num)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_screen = event.position
		var viewport_size = get_viewport().get_visible_rect().size
		
		# Ignora clique se estiver na barra de controle do topo ou inferior
		if mouse_screen.y < 46.0 or mouse_screen.y > viewport_size.y - 145.0:
			if is_dragging:
				is_dragging = false
				queue_redraw()
			return

		if event.is_pressed():
			is_dragging = true
			drag_start = get_global_mouse_position()
			drag_end = drag_start
			queue_redraw()
		else:
			if is_dragging:
				is_dragging = false
				drag_end = get_global_mouse_position()
				select_units_in_box(Input.is_key_pressed(KEY_SHIFT))
				queue_redraw()
			
	if event is InputEventMouseMotion and is_dragging:
		drag_end = get_global_mouse_position()
		queue_redraw()
		
	# Botão Direito do Mouse: Mover, Coletar Recurso, Atacar ou definir Rally Point
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# Modo rally point: se o predio selecionado esta em modo de posicionamento
		if selected_building and is_instance_valid(selected_building) and selected_building.get("placing_rally"):
			selected_building.set_rally_point(get_global_mouse_position())
			selected_building.placing_rally = false
			get_viewport().set_input_as_handled()
			return
		if selected_units.size() > 0:
			var target_pos = get_global_mouse_position()
			var target_res = _get_resource_under_mouse(target_pos)
			if target_res:
				for u in selected_units:
					if is_instance_valid(u) and u.has_method("harvest_resource"):
						u.harvest_resource(target_res)
			else:
				var attacker_team := Faction.PLAYER
				if "team" in selected_units[0]:
					attacker_team = int(selected_units[0].get("team"))
				var target_enemy = _get_hostile_under_mouse(target_pos, attacker_team)
				if target_enemy:
					for u in selected_units:
						if is_instance_valid(u) and u.has_method("attack"):
							u.attack(target_enemy)
				else:
					move_selected_units_in_formation(target_pos)
			get_viewport().set_input_as_handled()

func _get_resource_under_mouse(pos: Vector2) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_point(query)
	for r in result:
		var col = r.collider
		if col.is_in_group("resources") or col.is_in_group("elementio_sources"):
			# Fonte esgotada nao pode ser coletada: o clique vira movimento
			if "is_depleted" in col and bool(col.get("is_depleted")):
				continue
			if "remaining_elementio" in col and int(col.get("remaining_elementio")) <= 0:
				continue
			return col
	return null

## Procura uma entidade hostil a `attacker_team` sob o mouse. Inclui unidades
## e construcoes, para que o jogador possa ordenar a destruicao do ninho inimigo.
func _get_hostile_under_mouse(pos: Vector2, attacker_team: int) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_point(query)
	for r in result:
		var col = r.collider
		if col == null or not is_instance_valid(col):
			continue
		if not ("team" in col):
			continue
		if not Faction.is_hostile(attacker_team, int(col.get("team"))):
			continue
		if col.is_in_group("units") or col.is_in_group("buildings") or col.is_in_group("enemies"):
			return col
	return null

func _toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _draw() -> void:
	if is_dragging:
		var min_x = min(drag_start.x, drag_end.x)
		var min_y = min(drag_start.y, drag_end.y)
		var max_x = max(drag_start.x, drag_end.x)
		var max_y = max(drag_start.y, drag_end.y)
		var rect = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		
		if rect.size.length() > 5.0:
			draw_rect(rect, Color(0.2, 0.85, 0.35, 0.25), true)
			draw_rect(rect, Color(0.35, 1.0, 0.45, 0.95), false, 2.0)

func select_units_in_box(is_shift_pressed: bool = false) -> void:
	if not is_shift_pressed:
		for unit in selected_units:
			if is_instance_valid(unit):
				unit.deselect()
		selected_units.clear()
		
		if is_instance_valid(selected_building):
			selected_building.deselect()
			selected_building = null
			
		if is_instance_valid(selected_resource):
			selected_resource.deselect()
			selected_resource = null
	
	var min_x = min(drag_start.x, drag_end.x)
	var min_y = min(drag_start.y, drag_end.y)
	var max_x = max(drag_start.x, drag_end.x)
	var max_y = max(drag_start.y, drag_end.y)
	var rect = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	
	if rect.size.length() < 8.0:
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsPointQueryParameters2D.new()
		query.position = drag_end
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result = space_state.intersect_point(query)
		
		if result:
			var clicked = result[0].collider
			if clicked.is_in_group("units"):
				clicked.select()
				# Apenas unidades controlaveis podem ser comandadas.
				# Inimigos podem ser selecionados para ver info, mas nao comandados.
				var controllable = true
				if "is_controllable" in clicked:
					controllable = clicked.is_controllable
				if controllable and not selected_units.has(clicked):
					selected_units.append(clicked)
			elif clicked.is_in_group("buildings"):
				clicked.select()
				# O menu de producao so pertence a construcoes do jogador.
				if "team" in clicked and int(clicked.get("team")) != Faction.PLAYER:
					selected_building = null
				else:
					selected_building = clicked
			elif clicked.is_in_group("resources"):
				clicked.select()
				selected_resource = clicked
		_notify_ui_selection()
		return
		
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if is_instance_valid(unit):
			# Caixa de selecao so pode comandar unidades do jogador.
			if "is_controllable" in unit and not bool(unit.get("is_controllable")):
				continue
			if "team" in unit and int(unit.get("team")) != Faction.PLAYER:
				continue
			if rect.has_point(unit.global_position) or rect.grow(16.0).has_point(unit.global_position):
				unit.select()
				if not selected_units.has(unit):
					selected_units.append(unit)
				
	_notify_ui_selection()

func assign_control_group(group_num: int) -> void:
	var valid_group = []
	for u in selected_units:
		if is_instance_valid(u):
			valid_group.append(u)
	control_groups[group_num] = valid_group

func select_control_group(group_num: int) -> void:
	if not control_groups.has(group_num): return
	
	for u in selected_units:
		if is_instance_valid(u):
			u.deselect()
	selected_units.clear()
	
	var valid_list = []
	for u in control_groups[group_num]:
		if is_instance_valid(u):
			u.select()
			selected_units.append(u)
			valid_list.append(u)
	control_groups[group_num] = valid_list
	_notify_ui_selection()

func cycle_formation() -> void:
	match current_formation:
		"box": current_formation = "line"
		"line": current_formation = "circle"
		"circle": current_formation = "wedge"
		"wedge": current_formation = "box"
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("update_formation_label"):
		ui.update_formation_label(current_formation)

func set_formation(form: String) -> void:
	current_formation = form

func _notify_ui_selection() -> void:
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("update_selected_units_display"):
		ui.update_selected_units_display(selected_units)

func move_selected_units_in_formation(target: Vector2) -> void:
	var count = selected_units.size()
	if count == 0: return
	
	var valid_units = []
	for u in selected_units:
		if is_instance_valid(u):
			valid_units.append(u)
	selected_units = valid_units
	count = selected_units.size()
	if count == 0: return

	if count == 1:
		selected_units[0].set_target(target, true)
		return

	var group_center = Vector2.ZERO
	for u in selected_units:
		group_center += u.global_position
	group_center /= count
	
	var forward = (target - group_center).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.DOWN
	var right = Vector2(-forward.y, forward.x)

	var spacing = 32.0
	var offsets: Array[Vector2] = []

	match current_formation:
		"line":
			var half = (count - 1) / 2.0
			for i in range(count):
				offsets.append(right * ((i - half) * spacing))
				
		"wedge":
			offsets.append(Vector2.ZERO)
			for i in range(1, count):
				var side = 1 if i % 2 == 1 else -1
				var rank = int(ceil(i / 2.0))
				var off = (-forward * rank * spacing * 0.8) + (right * side * rank * spacing * 0.8)
				offsets.append(off)
				
		"circle":
			var radius = max(28.0, count * 8.0)
			var angle_step = TAU / count
			for i in range(count):
				var angle = i * angle_step
				offsets.append(Vector2(cos(angle), sin(angle)) * radius)
				
		_:
			var cols = int(ceil(sqrt(count)))
			var rows = int(ceil(float(count) / float(cols)))
			var half_w = (cols - 1) * spacing * 0.5
			var half_h = (rows - 1) * spacing * 0.5
			for i in range(count):
				var col = i % cols
				var row = int(i / cols)
				var off = (right * (col * spacing - half_w)) + (-forward * (row * spacing - half_h))
				offsets.append(off)

	for i in range(count):
		selected_units[i].set_target(target + offsets[i], true)
