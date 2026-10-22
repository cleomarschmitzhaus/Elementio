extends Node2D
# Sonda temporaria: enquadra as fontes de Elementium para conferir o sprite.
# Prefixo dos arquivos via variavel de ambiente SHOT_PREFIX.

@onready var main: Node2D = $Main
var prefix: String = "fonte"

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var p := "res://docs/diagnostico/%s_%s.png" % [prefix, tag]
	var err := img.save_png(p)
	print("SHOT_OK %dx%d -> %s (err=%d)" % [img.get_width(), img.get_height(), p, err])

func _ready() -> void:
	prefix = OS.get_environment("SHOT_PREFIX")
	if prefix == "":
		prefix = "fonte"
	for _i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout

	# congela a camera (o rts_camera.gd fica lerpando o zoom e andando com o mouse)
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam:
		cam.set_process(false)
		cam.set_process_input(false)

	var alvos := [
		[Vector2(577.0, 254.0), 3.0, "zoom3"],
		[Vector2(583.0, -207.0), 1.5, "zoom15"],
		[Vector2(675.0, 25.0), 1.0, "zoom1"],
	]
	for a in alvos:
		if cam:
			cam.position = a[0]
			cam.zoom = Vector2(a[1], a[1])
			cam.force_update_scroll()
		await get_tree().create_timer(0.7).timeout
		await _shot(a[2])

	get_tree().quit()
