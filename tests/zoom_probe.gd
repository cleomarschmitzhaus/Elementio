extends Node2D
# Sonda temporaria: captura a "Vista Planetaria" (zoom 0.5) com a camera
# deslocada para o lado, para expor a segunda superficie do shader.

@onready var main: Node2D = $Main

func _ready() -> void:
	for _i in 10:
		await get_tree().process_frame

	var cam: Camera2D = get_viewport().get_camera_2d()
	cam.set_process(false)
	cam.set_process_input(false)
	cam.zoom = Vector2(0.5, 0.5)
	cam.position = Vector2(1400.0, -900.0)
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://docs/diagnostico/04_vista_planetaria_zoom.png")
	print("ZOOMSHOT_OK %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
