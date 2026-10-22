extends SceneTree
# Conversor utilitario: carrega imagem (jpg/png/webp/bmp/tga) e salva como PNG.
func _init() -> void:
	var src := OS.get_environment("IMG_IN")
	var dst := OS.get_environment("IMG_OUT")
	var img := Image.load_from_file(src)
	if img == null:
		print("ERRO: nao conseguiu carregar ", src)
		quit(1)
		return
	var err := img.save_png(dst)
	print("CONVERTIDO %dx%d formato=%s err=%d -> %s" % [img.get_width(), img.get_height(), img.get_format(), err, dst])
	quit(0)
