extends StaticBody2D

var is_selected: bool = false
@onready var selection_ring = $SelectionRing
@onready var spawn_point = $SpawnPoint

# Usaremos grupos ou sinais globais para a UI saber o que mostrar
func _ready() -> void:
	selection_ring.visible = false
	add_to_group("buildings")

func select() -> void:
	is_selected = true
	selection_ring.visible = true
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		ui.show_building_menu(self)

func deselect() -> void:
	is_selected = false
	selection_ring.visible = false
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		ui.hide_building_menu()

func spawn_unit(unit_name: String) -> void:
	var unit_scene = load("res://scenes/units/artropes/" + unit_name + ".tscn")
	var unit = unit_scene.instantiate()
	unit.global_position = spawn_point.global_position
	get_parent().add_child(unit)
