extends Node2D

var is_dragging = false
var drag_start = Vector2.ZERO
var drag_end = Vector2.ZERO
var selected_units = []
var selected_building = null

func _ready():
	add_to_group("selection_manager")

func _unhandled_input(event):
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.is_building_mode: return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_dragging = true
			drag_start = get_global_mouse_position()
			drag_end = drag_start
		else:
			is_dragging = false
			select_units_in_box()
			queue_redraw()
			
	if event is InputEventMouseMotion and is_dragging:
		drag_end = get_global_mouse_position()
		queue_redraw()
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		if selected_units.size() > 0:
			move_selected_units(get_global_mouse_position())
			get_viewport().set_input_as_handled()

func _draw():
	if is_dragging:
		var rect = Rect2(drag_start, drag_end - drag_start)
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.3), true) # Preenchimento verde translúcido
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.8), false, 2.0) # Borda

func select_units_in_box():
	# Deseleciona todos primeiro
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	
	if is_instance_valid(selected_building):
		selected_building.deselect()
		selected_building = null
	
	var rect = Rect2(drag_start, drag_end - drag_start).abs()
	
	# Se for só um clique (caixa muito pequena), detecta o que foi clicado
	if rect.size.length() < 10:
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsPointQueryParameters2D.new()
		query.position = get_global_mouse_position()
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result = space_state.intersect_point(query)
		
		if result:
			var clicked = result[0].collider
			if clicked.is_in_group("units"):
				clicked.select()
				selected_units.append(clicked)
			elif clicked.is_in_group("buildings"):
				clicked.select()
				selected_building = clicked
		return
		
	# Se for uma caixa de seleção arrastada, seleciona várias unidades
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if rect.has_point(unit.global_position):
			unit.select()
			selected_units.append(unit)

func move_selected_units(target: Vector2):
	var count = selected_units.size()
	if count == 0: return
	
	# Calcula formação simples (círculo) para eles não se amontoarem
	var radius = 20.0 * sqrt(count)
	var angle_step = TAU / count if count > 1 else 0
	
	for i in range(count):
		var unit = selected_units[i]
		if is_instance_valid(unit):
			var pos = target
			if count > 1:
				var angle = i * angle_step
				pos += Vector2(cos(angle), sin(angle)) * (radius * 0.5 * randf_range(0.8, 1.2))
			unit.set_target(pos)
