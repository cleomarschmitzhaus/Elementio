extends Node3D

func _ready() -> void:
	# Aguarda render e tira screenshot para validar o 3D
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := "res://docs/diagnostico/globe_3d_test.png"
	var err := img.save_png(path)
	print("GLOBE3D shot %dx%d -> %s (err=%d)" % [img.get_width(), img.get_height(), path, err])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()