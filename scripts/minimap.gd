extends ColorRect

# Tamanho do mundo virtual para o minimapa
var map_size: Vector2 = Vector2(2000, 2000)
var is_dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var planet = get_tree().get_first_node_in_group("planet")
	if planet and "world_size" in planet:
		var ws: Vector2 = planet.get("world_size")
		if ws.x > 0.0 and ws.y > 0.0:
			map_size = ws

func _process(_delta: float) -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.is_pressed()
			if is_dragging:
				_move_camera_to_minimap(event.position)
	elif event is InputEventMouseMotion and is_dragging:
		_move_camera_to_minimap(event.position)

func _move_camera_to_minimap(pos: Vector2) -> void:
	var cam = get_viewport().get_camera_2d()
	if cam:
		var norm_x = clamp(pos.x / size.x, 0.0, 1.0)
		var norm_y = clamp(pos.y / size.y, 0.0, 1.0)
		var target_world_x = (norm_x * map_size.x) - (map_size.x / 2.0)
		var target_world_y = (norm_y * map_size.y) - (map_size.y / 2.0)
		cam.global_position = Vector2(target_world_x, target_world_y)

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 4.0
	
	draw_circle(center, radius + 3.0, Color(0.4, 0.28, 0.15, 0.9))
	draw_circle(center, radius, Color(0.08, 0.12, 0.09, 0.95))
	
	draw_arc(center, radius * 0.7, 0, TAU, 32, Color(0.2, 0.35, 0.25, 0.3), 1.0)
	draw_arc(center, radius * 0.4, 0, TAU, 32, Color(0.2, 0.35, 0.25, 0.2), 1.0)
	draw_line(Vector2(center.x, center.y - radius), Vector2(center.x, center.y + radius), Color(0.2, 0.35, 0.25, 0.25), 1.0)
	draw_line(Vector2(center.x - radius, center.y), Vector2(center.x + radius, center.y), Color(0.2, 0.35, 0.25, 0.25), 1.0)
	
	var scale_x = size.x / map_size.x
	var scale_y = size.y / map_size.y
	
	# Normaliza para o intervalo [0,1): o mundo toroidal desloca as entidades
	# junto com a camera, entao posicoes podem sair de [-half, +half].
	var world_to_minimap = func(pos: Vector2) -> Vector2:
		var norm := Vector2(
			fposmod(pos.x + map_size.x * 0.5, map_size.x) / map_size.x,
			fposmod(pos.y + map_size.y * 0.5, map_size.y) / map_size.y)
		return Vector2(norm.x * size.x, norm.y * size.y)
		
	# Desenha fontes de Elementio (Cristais Ciano brilhantes)
	var resources = get_tree().get_nodes_in_group("elementio_sources")
	for r in resources:
		if is_instance_valid(r):
			var mm_pos = world_to_minimap.call(r.global_position)
			if (mm_pos - center).length() <= radius:
				draw_circle(mm_pos, 3.5, Color(0.0, 0.9, 1.0, 1.0))

	# Desenha construções com a cor da facção (verde jogador, vermelho inimigo)
	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if is_instance_valid(b):
			var mm_pos = world_to_minimap.call(b.global_position)
			if (mm_pos - center).length() <= radius:
				var bteam := Faction.PLAYER
				if "team" in b:
					bteam = int(b.get("team"))
				var bcol := Faction.selection_color(bteam)
				draw_rect(Rect2(mm_pos - Vector2(3, 3), Vector2(6, 6)), bcol)
				draw_rect(Rect2(mm_pos - Vector2(2, 2), Vector2(4, 4)), Color(0.12, 0.14, 0.16, 1.0))

	# Desenha unidades com a cor da facção
	var units = get_tree().get_nodes_in_group("units")
	for u in units:
		if is_instance_valid(u):
			var mm_pos = world_to_minimap.call(u.global_position)
			if (mm_pos - center).length() <= radius:
				var uteam := Faction.PLAYER
				if "team" in u:
					uteam = int(u.get("team"))
				draw_circle(mm_pos, 2.0, Faction.selection_color(uteam))
		
	# Retângulo de visão da câmera (FOV)
	var cam = get_viewport().get_camera_2d()
	if cam:
		var screen_size = get_viewport().get_visible_rect().size / cam.zoom
		var cam_top_left = cam.global_position - (screen_size / 2.0)
		var mm_cam_pos = world_to_minimap.call(cam_top_left)
		var mm_cam_size = Vector2(screen_size.x * scale_x, screen_size.y * scale_y)
		draw_rect(Rect2(mm_cam_pos, mm_cam_size), Color(1.0, 1.0, 1.0, 0.8), false, 1.5)
