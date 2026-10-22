extends Node
# Converte um arquivo de imagem (jfif/jpg/png) para PNG em docs/diagnostico.
# Uso: defina SRC e DST via env ou edite abaixo.

func _ready() -> void:
	var src := "C:/Users/roger/Downloads/Gemini_Generated_Image_3i1rlr3i1rlr3i1r.jfif"
	var dst := "res://docs/diagnostico/sheet_fountain.png"
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		print("OPEN FAILED")
		get_tree().quit()
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes)
	print("LOAD_JPG err=%d size=%dx%d" % [err, img.get_width(), img.get_height()])
	if err == OK:
		err = img.save_png(dst)
		print("SAVE err=%d -> %s" % [err, dst])
	get_tree().quit()