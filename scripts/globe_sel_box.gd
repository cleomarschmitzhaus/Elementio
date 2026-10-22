extends Control
## Overlay de caixa de selecao (retangulo arrastado) para a vista 3D (globe_main).
## Desenhado em screen-space; globe_main controla drag_start/drag_end/active.

var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO
var active: bool = false

func _draw() -> void:
	if not active:
		return
	var min_x := minf(drag_start.x, drag_end.x)
	var min_y := minf(drag_start.y, drag_end.y)
	var max_x := maxf(drag_start.x, drag_end.x)
	var max_y := maxf(drag_start.y, drag_end.y)
	var rect := Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	if rect.size.length() > 5.0:
		draw_rect(rect, Color(0.2, 0.85, 0.35, 0.25), true)
		draw_rect(rect, Color(0.35, 1.0, 0.45, 0.95), false, 2.0)