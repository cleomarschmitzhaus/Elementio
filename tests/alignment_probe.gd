extends Node2D
# Sonda temporaria: mede o mapeamento mundo->tela usado pelo TERRENO (shader)
# e o usado pelas UNIDADES (canvas transform), para provar alinhamento.

@onready var main: Node2D = $Main

var shots: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(600.0, 0.0),
	Vector2(900.0, 400.0),
	Vector2(-700.0, 300.0),
	Vector2(1500.0, -1200.0),
]

func _dump(tag: String) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_2d()
	print("--- %s ---" % tag)
	print("  janela=%s  visible_rect=%s pos=%s" % [str(get_window().size), str(vp.get_visible_rect().size), str(vp.get_visible_rect().position)])
	print("  cam.global_position=%s zoom=%s" % [str(cam.global_position), str(cam.zoom)])
	print("  canvas_transform=%s" % str(vp.get_canvas_transform()))
	var pr: Control = main.get_node_or_null("Planet/PlanetSurface")
	if pr:
		print("  PlanetSurface.size=%s pos=%s global=%s scale=%s" % [str(pr.size), str(pr.position), str(pr.global_position), str(pr.scale)])
		var m := pr.material as ShaderMaterial
		if m:
			print("  shader rect_size=%s world_size=%s camera_offset=%s" % [str(m.get_shader_parameter("rect_size")), str(m.get_shader_parameter("world_size")), str(m.get_shader_parameter("camera_offset"))])
	# mapeamento das UNIDADES (mundo->tela) via canvas transform
	var xsform := vp.get_canvas_transform()
	for wsp in [Vector2(0,0), Vector2(500,0), Vector2(0,500), Vector2(675,25)]:
		print("    mundo %s -> tela(unidade) %s" % [str(wsp), str(xsform * wsp)])


func _ready() -> void:
	for _i in 3:
		await get_tree().process_frame

	var ui = main.get_node_or_null("UI")
	if ui:
		ui.visible = false

	var cam: Camera2D = get_viewport().get_camera_2d()
	cam.set_process(false)
	cam.set_process_input(false)
	cam.zoom = Vector2.ONE
	cam.position = Vector2.ZERO

	_dump("inicio")

	# 1) prints normais (terreno real)
	for i in shots.size():
		cam.position = shots[i]
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://docs/diagnostico/align_%d.png" % i)
		var f := FileAccess.open("res://docs/diagnostico/align_%d.txt" % i, FileAccess.WRITE)
		if f:
			f.store_string("%f %f\n" % [cam.position.x, cam.position.y])
			f.close()
		print("ALIGN shot %d cam=%s" % [i, str(cam.position)])

	# 2) shots com shader de depuracao (mapeamento do terreno)
	#    Troca-se APENAS o shader do mesmo material, para que o Planet._process
	#    continue atualizando camera_offset normalmente (igual em producao).
	var pr: Control = main.get_node_or_null("Planet/PlanetSurface")
	if pr:
		var old := pr.material as ShaderMaterial
		var dbg: Shader = load("res://tests/debug_world.gdshader") as Shader
		var use_dbg := false
		if old and dbg:
			old.shader = dbg
			use_dbg = true
		for _w in 3:
			await get_tree().process_frame
		for i in [0, 1]:
			cam.position = shots[i]
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img2: Image = get_viewport().get_texture().get_image()
			img2.save_png("res://docs/diagnostico/dbg_%d.png" % i)
			var f2 := FileAccess.open("res://docs/diagnostico/dbg_%d.txt" % i, FileAccess.WRITE)
			if f2:
				f2.store_string("%f %f\n" % [cam.position.x, cam.position.y])
				f2.close()
			print("DBG shot %d cam=%s shader_dbg=%s" % [i, str(cam.position), str(use_dbg)])
		_dump("depois do debug")

	print("PROBE_DONE")
	get_tree().quit()
