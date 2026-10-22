extends Node2D
# Sonda temporaria: salva quadros do terreno. Prefixo via variavel de ambiente SHOT_PREFIX.

@onready var main: Node2D = $Main
var prefix: String = "shot"

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var p := "res://docs/diagnostico/%s_%s.png" % [prefix, tag]
	img.save_png(p)
	print("SHOT_OK %dx%d -> %s" % [img.get_width(), img.get_height(), p])

func _ready() -> void:
	prefix = OS.get_environment("SHOT_PREFIX")
	if prefix == "":
		prefix = "shot"
	for _i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await _shot("zoom1")

	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam:
		cam.zoom = Vector2(2.5, 2.5)
	await get_tree().create_timer(0.6).timeout
	await _shot("zoom25")

	if cam:
		cam.zoom = Vector2(0.5, 0.5)
	await get_tree().create_timer(0.6).timeout
	await _shot("zoom05")

	get_tree().quit()
