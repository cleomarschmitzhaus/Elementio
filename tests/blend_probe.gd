extends Node
## Probe A/B da MISTURA ENTRE MATERIAIS do terreno.
##
## Renderiza a MESMA vista de superficie duas vezes: com a mistura ligada
## (camadas com smoothstep + serpenteio, o padrao do jogo) e com o corte seco
## (faixa de mistura praticamente nula, sem serpenteio — como era antes, com um
## "if" por material). Depois mede o que mudou.
##
## Quem vem da mistura sao exatamente as BORDAS de material: se a transicao
## fosse um degrau, as duas imagens seriam identicas. A fracao de pixels
## diferentes e' a prova numerica de que a borda deixou de ser um corte.
##
##   godot --path <proj> res://tests/blend_probe.tscn
##
## Saida: docs/diagnostico/view_blend_on.png / view_blend_off.png +
##        linhas BLEND_AB no console.

const OUT_ON := "docs/diagnostico/view_blend_on.png"
const OUT_OFF := "docs/diagnostico/view_blend_off.png"
# Ponto de COSTA no mundo (elevacao ~0.3815: agua, areia e terra no quadro).
const FOCUS := Vector2(2799.0, 846.0)

func _ready() -> void:
	var globe = load("res://scenes/globe_main.tscn").instantiate()
	add_child(globe)
	await _frames(60)
	globe.set_surface_view(true)
	globe._focus_world_at(FOCUS)
	await _frames(180)  # transicao + camera pousada

	var planet = get_tree().get_first_node_in_group("planet")
	if planet == null or planet.mat == null:
		print("BLEND_AB sem planeta/material")
		get_tree().quit(1)
		return
	var mat: ShaderMaterial = planet.mat

	# --- LIGADO: padrao do jogo (faixa larga + serpenteio) ---
	mat.set_shader_parameter("blend_width", planet.blend_width)
	mat.set_shader_parameter("edge_strength", planet.edge_strength)
	await _frames(12)
	var img_on: Image = await _shot(OUT_ON)

	# --- DESLIGADO: corte seco (faixa minima, sem serpenteio) ---
	mat.set_shader_parameter("blend_width", 0.0006)
	mat.set_shader_parameter("edge_strength", 0.0)
	await _frames(12)
	var img_off: Image = await _shot(OUT_OFF)

	mat.set_shader_parameter("blend_width", planet.blend_width)
	mat.set_shader_parameter("edge_strength", planet.edge_strength)

	_compare(img_on, img_off)
	print("PROBE_DONE")
	get_tree().quit(0)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://" + path)
	print("SHOT %s err=%d" % [path, err])
	return img

# Compara as duas imagens na area central (onde fica o terreno) e devolve a
# fracao de pixels que a mistura mudou + o retangulo onde isso aconteceu.
func _compare(a: Image, b: Image) -> void:
	var w := a.get_width()
	var h := a.get_height()
	var x0 := int(w * 0.15)
	var y0 := int(h * 0.15)
	var x1 := int(w * 0.85)
	var y1 := int(h * 0.85)
	var total := 0
	var changed := 0
	var acc := 0.0
	var bx0 := w
	var by0 := h
	var bx1 := -1
	var by1 := -1
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length()
			total += 1
			acc += d
			if d > 0.06:
				changed += 1
				bx0 = mini(bx0, x)
				by0 = mini(by0, y)
				bx1 = maxi(bx1, x)
				by1 = maxi(by1, y)
	var frac := 100.0 * float(changed) / float(maxi(total, 1))
	print("BLEND_AB pixels=%d  alterados(>0.06)=%d (%.2f%%)  diff_media=%.4f"
		% [total, changed, frac, acc / float(maxi(total, 1))])
	print("BLEND_AB bbox alterado: (%d,%d)-(%d,%d) em %dx%d"
		% [bx0, by0, bx1, by1, w, h])
