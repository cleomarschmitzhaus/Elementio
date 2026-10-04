extends ColorRect

# Tamanho do mundo virtual para o minimapa
var map_size: Vector2 = Vector2(2000, 2000)

func _process(_delta):
	# Pede para redesenhar todos os frames
	queue_redraw()

func _draw():
	# Fator de conversão do mundo (map_size) para a tela do minimapa (size)
	var scale_x = size.x / map_size.x
	var scale_y = size.y / map_size.y
	
	# Função auxiliar para converter posição
	var world_to_minimap = func(pos: Vector2) -> Vector2:
		# Assumimos que o mundo 2D tem 0,0 no centro. 
		# Adicionamos map_size/2 para o centro do mundo virar o centro do minimapa.
		var offset_pos = pos + (map_size / 2.0)
		return Vector2(offset_pos.x * scale_x, offset_pos.y * scale_y)
		
	# Desenha construções (Azul)
	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		var minimap_pos = world_to_minimap.call(b.global_position)
		draw_rect(Rect2(minimap_pos - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.5, 1.0))

	# Desenha unidades (Laranja/Skito)
	var units = get_tree().get_nodes_in_group("units")
	for u in units:
		var minimap_pos = world_to_minimap.call(u.global_position)
		draw_rect(Rect2(minimap_pos - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.5, 0.2))
		
	# Desenha a visão da câmera (Retângulo Branco)
	var cam = get_viewport().get_camera_2d()
	if cam:
		# Tamanho da tela dividido pelo zoom
		var screen_size = get_viewport().get_visible_rect().size / cam.zoom
		# Posição top-left da câmera
		var cam_top_left = cam.global_position - (screen_size / 2.0)
		
		var mm_cam_pos = world_to_minimap.call(cam_top_left)
		var mm_cam_size = Vector2(screen_size.x * scale_x, screen_size.y * scale_y)
		
		draw_rect(Rect2(mm_cam_pos, mm_cam_size), Color.WHITE, false, 1.0)
