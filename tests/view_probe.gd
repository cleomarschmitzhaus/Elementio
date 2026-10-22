extends Node
## Probe: valida as duas vistas (planeta + superficie estilo Populous 3).
## Roda a cena globe_main, tira screenshot de cada vista e sai.
## godot --path <proj> res://tests/view_probe.gd  (via tscn abaixo)

var _sky_check_ok: bool = false

func _ready() -> void:
	var globe = load("res://scenes/globe_main.tscn").instantiate()
	globe.boot_to_surface = false   # o probe controla a vista manualmente
	add_child(globe)
	await _frames(90)
	await _shot("docs/diagnostico/view_planet.png")
	# Zoom MAXIMO da vista planetaria: o globo deve cobrir a tela inteira (sem
	# espaco ao redor). Mede a fracao de pixels de "espaco" na borda da imagem.
	globe.planet_dist = globe.PLANET_DIST_MIN
	globe.sphere.rotation = Vector3.ZERO
	await _frames(60)
	var max_img: Image = await _shot("docs/diagnostico/view_planet_max.png")
	print("SPACE_BORDA zoom_max=%.4f (0 = globo cobre toda a tela)" % _space_fraction(max_img))
	globe.planet_dist = globe.PLANET_DIST
	await _frames(30)
	globe.set_surface_view(true)
	await _frames(150)  # deixa a transicao terminar e camera pousar
	await _shot("docs/diagnostico/view_surface.png")
	_surface_magnification(globe)
	# SKYBOX no Foco Local: mede a fracao do quadro que e' CEU (raios da camera
	# que NAO batem na esfera). Com FOV 28 e pitch 65 o horizonte entra no topo.
	print("SURF_CEU coluna_central=%.3f  area_total=%.3f (0=sem ceu, 1=so' ceu)"
		% [_sky_fraction(globe), _sky_area_fraction(globe)])
	# Cenario com o sol e a lua DENTRO da faixa de ceu visivel, para o screenshot
	# mostrar os dois astros (a pino eles ficariam fora do quadro).
	var astros: Array = _sun_near_horizon(globe)
	await _frames(2)
	var sky_img: Image = await _shot("docs/diagnostico/view_sky.png")
	globe.set_process(true)
	_sky_pixel_check(sky_img, astros)
	# NORTE FIXO: o eixo "direita" da tela deve ficar no eixo leste-oeste do
	# mundo (a camera nao rola/nao gira ao andar) e o "cima" aponta ao norte.
	var xb: Vector3 = globe.camera.global_transform.basis.x
	var yb: Vector3 = globe.camera.global_transform.basis.y
	print("SURF_NORTE_FIXO direita_tela.dot(leste_oeste)=%.4f cima_tela.dot(norte)=%.4f"
		% [xb.dot(globe.surface_right()), yb.dot(globe.surface_north())])
	# superficie em outro ponto (caminha com WASD simulado nao da; move angulos)
	globe.focus_at_lat_lon(0.5, 2.0)
	await _frames(60)
	await _shot("docs/diagnostico/view_surface2.png")
	# vista do polo: testa se a emenda norte-sul fecha sem corte (planeta-toro)
	globe.set_surface_view(false)
	globe.sphere.rotation = Vector3(PI * 0.5, 0, 0)
	await _frames(60)
	await _shot("docs/diagnostico/view_pole.png")
	# COMPARACAO de FOV no Foco Local: com FOV 28 (default) o ceu fica ~44% da
	# area com o terreno ainda no centro; com FOV 40 o planeta vira uma "bola"
	# (~66% de ceu).
	globe.sphere.rotation = Vector3.ZERO
	globe.set_surface_view(true)
	globe.surf_fov = 40.0
	await _frames(120)
	_sun_near_horizon(globe)
	await _frames(2)
	await _shot("docs/diagnostico/view_surface_fov40.png")
	globe.set_process(true)
	print("SURF_CEU fov40 coluna_central=%.3f  area_total=%.3f"
		% [_sky_fraction(globe), _sky_area_fraction(globe)])
	print("FPS %.0f | Mem %.0f MB" % [Engine.get_frames_per_second(), OS.get_static_memory_usage() / 1048576.0])
	print("PROBE_DONE sky_check_ok=%d" % int(_sky_check_ok))
	get_tree().quit(0 if _sky_check_ok else 1)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://" + path)
	print("SHOT %s err=%d" % [path, err])
	return img

# Fracao de pixels de "espaco" (fundo escuro) amostrados na BORDA da imagem.
# Na vista planetaria com zoom maximo o globo deve preencher tudo -> ~0.
func _space_fraction(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var space := 0
	var total := 0
	for i in range(240):
		var t := float(i) / 240.0
		var xs := clampi(int(t * float(w - 1)), 1, w - 2)
		var ys := clampi(int(t * float(h - 1)), 1, h - 2)
		var pts: Array[Vector2i] = [
			Vector2i(xs, 1), Vector2i(xs, h - 2),
			Vector2i(1, ys), Vector2i(w - 2, ys),
		]
		for p in pts:
			total += 1
			if img.get_pixelv(p).get_luminance() < 0.10:
				space += 1
	return float(space) / float(maxi(total, 1))

# Diagnostico: quantos pixels de mundo cabem na tela (magnificacao da vista
# local). Quanto maior, mais a textura e' ampliada (sprites ficam menos nitidos
# se o SubViewport nao tiver texels suficientes).
func _surface_magnification(globe) -> void:
	var vr := get_viewport().get_visible_rect().size
	# Amostra perto do centro: com o FOV do Foco Local (28) o globo ja' nao cobre
	# as bordas da tela (ha' ceu em cima/lados), entao 0,25/0,75 cairia fora.
	var wl: Variant = globe._screen_to_world(Vector2(vr.x * 0.30, vr.y * 0.5))
	var wr: Variant = globe._screen_to_world(Vector2(vr.x * 0.70, vr.y * 0.5))
	if wl == null or wr == null:
		print("SURF_SPAN indisponivel")
		return
	var d: Vector2 = (wr as Vector2) - (wl as Vector2)
	# menor caminho no toro (world_size) para nao medir atravessando a emenda
	var ws: Vector2 = globe.WORLD_SIZE
	d.x = fposmod(d.x + ws.x * 0.5, ws.x) - ws.x * 0.5
	d.y = fposmod(d.y + ws.y * 0.5, ws.y) - ws.y * 0.5
	var span: float = maxf(d.length(), 0.001)
	var screen_px: float = vr.x * 0.5
	var texels: float = float(Vector2(globe.get_node("SubViewport").size).x) / ws.x
	print("SURF_SPAN tela=%.0fpx  mundo=%.1fpx  magnificacao=%.2fx  texels_por_pixel_mundo=%.2f"
		% [screen_px, span, screen_px / span, texels])

# Coloca o sol e a lua DENTRO da faixa de ceu vista no Foco Local. Como a camera
# olha o planeta de cima, essa faixa fica logo acima do horizonte da esfera — o
# sol a pino (ou mesmo no horizonte) cai FORA do quadro. Para o screenshot,
# achamos a faixa medindo onde a esfera termina em duas colunas e posicionamos os
# dois astros ali (com `set_process(false)` para o `_process` nao reescrever).
# Devolve as DUAS posicoes de tela (para o check de pixel).
func _sun_near_horizon(globe) -> Array:
	globe.set_process(false)
	var sun_pt := _sky_band_mid(globe, 0.34)
	var moon_pt := _sky_band_mid(globe, 0.68)
	globe.sky_material.set_shader_parameter("sun_dir",
		globe.camera.project_ray_normal(sun_pt).normalized())
	globe.sky_material.set_shader_parameter("moon_dir",
		globe.camera.project_ray_normal(moon_pt).normalized())
	return [sun_pt, moon_pt]

# Verificacao AUTOMATICA do ceu por pixel: o disco do sol tem que ser bem mais
# claro que o ceu ao lado (o nucleo satura em branco), o disco da lua frio/
# brilhante, e um ponto neutro tem que ser azul (bem mais azul que vermelho).
# Sem isso, "tem ceu" seria so' opiniao.
func _sky_pixel_check(img: Image, astros: Array) -> void:
	var sun := _sample(img, astros[0])
	var moon := _sample(img, astros[1])
	var sky_far := _sample(img, astros[0] + Vector2(140.0, 0.0))
	var vr: Vector2 = get_viewport().get_visible_rect().size
	var sky := _sample(img, Vector2(vr.x * 0.82, vr.y * 0.10))
	var sun_ok := sun.get_luminance() > 0.85 and sun.get_luminance() > sky_far.get_luminance() + 0.25
	var moon_ok := moon.b > 0.70 and moon.b >= moon.r and moon.g > 0.70
	var sky_ok := sky.b > sky.r + 0.10 and sky.b > 0.45
	print("SKY_PIXEL img=%dx%d fmt=%d sol=(%d,%d,%d) lua=(%d,%d,%d) ceu=(%d,%d,%d) sol_ok=%d lua_ok=%d ceu_ok=%d"
		% [img.get_width(), img.get_height(), img.get_format(),
			int(sun.r * 255.0), int(sun.g * 255.0), int(sun.b * 255.0),
			int(moon.r * 255.0), int(moon.g * 255.0), int(moon.b * 255.0),
			int(sky.r * 255.0), int(sky.g * 255.0), int(sky.b * 255.0),
			int(sun_ok), int(moon_ok), int(sky_ok)])
	_sky_check_ok = sun_ok and moon_ok and sky_ok

# Amostra um ponto em coordenadas de TELA (logicas) na imagem do viewport. A
# imagem pode vir maior que o viewport (escala de DPI) e em HDR/linear — o PNG
# salvo e' 8-bit sRGB, entao convertemos para comparar com o que o usuario ve.
func _sample(img: Image, pt: Vector2) -> Color:
	var vr: Vector2 = get_viewport().get_visible_rect().size
	var x := clampi(int(pt.x / vr.x * float(img.get_width())), 0, img.get_width() - 1)
	var y := clampi(int(pt.y / vr.y * float(img.get_height())), 0, img.get_height() - 1)
	var c := img.get_pixel(x, y)
	if img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBF]:
		c = Color(_to_srgb(c.r), _to_srgb(c.g), _to_srgb(c.b), 1.0)
	return c

func _to_srgb(v: float) -> float:
	var cv: float = clampf(v, 0.0, 1.0)
	return cv * 12.92 if cv <= 0.0031308 else 1.055 * pow(cv, 1.0 / 2.4) - 0.055

# Meio da faixa de ceu na coluna `x_frac`: o meio entre o topo do quadro e o
# primeiro pixel (de cima para baixo) que bate na esfera.
func _sky_band_mid(globe, x_frac: float) -> Vector2:
	var vr: Vector2 = get_viewport().get_visible_rect().size
	var x: float = vr.x * x_frac
	var n := 300
	for i in range(n):
		var y: float = (float(i) + 0.5) / float(n) * vr.y
		var pt := Vector2(x, y)
		var from: Vector3 = globe.camera.project_ray_origin(pt)
		var dir: Vector3 = globe.camera.project_ray_normal(pt)
		var b: float = from.dot(dir)
		var c: float = from.dot(from) - 1.0
		if b * b - c >= 0.0:
			return Vector2(x, y * 0.5)
	return Vector2(x, vr.y * 0.05)

# Fracao do quadro que e' CEU: amostra a coluna central de cima para baixo e
# conta os raios da camera que NAO intersectam a esfera (ceu/horizonte).
func _sky_fraction(globe) -> float:
	var vr: Vector2 = get_viewport().get_visible_rect().size
	var sky := 0
	var n := 200
	for i in range(n):
		var y: float = (float(i) + 0.5) / float(n) * vr.y
		var pt := Vector2(vr.x * 0.5, y)
		var from: Vector3 = globe.camera.project_ray_origin(pt)
		var dir: Vector3 = globe.camera.project_ray_normal(pt)
		var b: float = from.dot(dir)
		var c: float = from.dot(from) - 1.0
		if b * b - c < 0.0:
			sky += 1
	return float(sky) / float(n)

# Fracao da AREA do quadro que e' ceu (grade de raios em toda a tela).
func _sky_area_fraction(globe) -> float:
	var vr: Vector2 = get_viewport().get_visible_rect().size
	var sky := 0
	var total := 0
	for iy in range(48):
		for ix in range(64):
			var pt := Vector2((float(ix) + 0.5) / 64.0 * vr.x, (float(iy) + 0.5) / 48.0 * vr.y)
			var from: Vector3 = globe.camera.project_ray_origin(pt)
			var dir: Vector3 = globe.camera.project_ray_normal(pt)
			var b: float = from.dot(dir)
			var c: float = from.dot(from) - 1.0
			total += 1
			if b * b - c < 0.0:
				sky += 1
	return float(sky) / float(total)
