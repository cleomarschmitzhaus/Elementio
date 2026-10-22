extends Node
## Probe do BOOT: roda a cena principal do jogo (com o boot automatico LIGADO),
## tira um print antes do atraso (vista planeta) e outro depois (Foco Local) e
## confere que a vista realmente trocou sozinha. Sai com codigo 1 se nao trocar.
## godot --path <proj> res://tests/boot_probe.tscn

func _ready() -> void:
	var globe = load("res://scenes/globe_main.tscn").instantiate()
	add_child(globe)  # boot_to_surface = true por padrao (como no jogo)
	await _frames(20)
	await _shot("docs/diagnostico/view_boot_planet.png")
	var before: bool = globe.is_surface_view()
	print("BOOT antes atraso: surface=%d (esperado 0/vista planeta)" % int(before))
	# Espera passar o atraso do boot (2 s) mais folga para a transicao.
	await get_tree().create_timer(globe.boot_delay + 1.5).timeout
	await _frames(20)
	await _shot("docs/diagnostico/view_boot_surface.png")
	var after: bool = globe.is_surface_view()
	print("BOOT depois atraso: surface=%d (esperado 1/Foco Local)" % int(after))
	var ok := (not before) and after
	print("PROBE_BOOT_DONE ok=%d" % int(ok))
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://" + path)
	print("SHOT %s err=%d" % [path, err])
