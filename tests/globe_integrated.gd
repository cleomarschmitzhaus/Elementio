extends Node3D

@onready var subviewport: SubViewport = $SubViewport
@onready var sphere: MeshInstance3D = $Sphere
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	var wf = subviewport.get_node_or_null("WorldFlat")
	print("WorldFlat: ", wf)
	if wf:
		# debug: add a red rect to verify SubViewport renders
		var dbg = ColorRect.new()
		dbg.color = Color(1, 0, 0, 1)
		dbg.size = Vector2(200, 200)
		dbg.position = Vector2(400, 150)
		wf.add_child(dbg)
		var cam = wf.get_node_or_null("Camera2D")
		print("Camera2D: ", cam)
		if cam:
			cam.position = Vector2(0, 0)
			cam.zoom = Vector2(0.512, 0.512)
			cam.force_update_scroll()
			cam.set_process(false)
			cam.set_process_input(false)
		var planet = wf.get_node_or_null("Planet")
		print("Planet: ", planet)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = subviewport.get_texture()
	mat.roughness = 0.8
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sphere.material_override = mat
	camera.look_at(Vector3.ZERO)

func _process(delta: float) -> void:
	# Norte sempre para cima: o globo gira SOMENTE no eixo vertical.
	var yaw := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) \
			or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		yaw -= 1.2 * delta
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) \
			or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		yaw += 1.2 * delta
	sphere.rotation.y = wrapf(sphere.rotation.y + yaw, -PI, PI)

	if not has_meta("shot"):
		set_meta("shot", true)
		await get_tree().create_timer(2.0).timeout
		var vp_img: Image = subviewport.get_texture().get_image()
		vp_img.convert(Image.FORMAT_RGBA8)
		var nonzero := 0
		var nonalpha := 0
		for y in range(0, vp_img.get_height(), 4):
			for x in range(0, vp_img.get_width(), 4):
				var c := vp_img.get_pixel(x, y)
				if c.r > 0.01 or c.g > 0.01 or c.b > 0.01:
					nonzero += 1
				if c.a > 0.01:
					nonalpha += 1
		print("VP texture %dx%d nonzero_rgb=%d nonzero_alpha=%d" % [vp_img.get_width(), vp_img.get_height(), nonzero, nonalpha])
		vp_img.save_png("res://docs/diagnostico/globe_vp_texture.png")
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var path := "res://docs/diagnostico/globe_integrated_test.png"
		var err := img.save_png(path)
		print("GLOBE_INTEGRATED shot %dx%d -> %s (err=%d)" % [img.get_width(), img.get_height(), path, err])
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()