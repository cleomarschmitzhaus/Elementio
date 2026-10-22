extends Node2D
# Sonda temporaria: salva o quadro renderizado do jogo (com HUD) para conferencia.

@onready var main: Node2D = $Main

func _ready() -> void:
	for _i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var p := "res://docs/diagnostico/03_depois_correcao_base.png"
	img.save_png(p)
	print("SHOT_OK %dx%d -> %s" % [img.get_width(), img.get_height(), p])
	get_tree().quit()
