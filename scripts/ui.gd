extends CanvasLayer

@onready var build_grid = $Control/SidePanel/VBox/BuildGrid
@onready var action_grid = $Control/SidePanel/VBox/ActionGrid
@onready var stats_label = $Control/SidePanel/VBox/StatsLabel
@onready var elemeth_label = $Control/SidePanel/VBox/ElemethLabel

var selected_building = null
var is_building_mode = false
var building_ghost = null
var building_scene = preload("res://scenes/buildings/artropes/hollow_nest.tscn")

func _ready() -> void:
	add_to_group("ui")
	_on_tab_build_pressed()

func _process(_delta: float) -> void:
	# Atualiza recurso
	elemeth_label.text = "Elemeth: %d" % GameManager.elemeth
	
	# Atualiza o contador de unidades
	var skitos = get_tree().get_nodes_in_group("units").size()
	var ninhos = get_tree().get_nodes_in_group("buildings").size()
	stats_label.text = "Skitos: %d | Ninhos: %d" % [skitos, ninhos]

func show_building_menu(building: Node) -> void:
	selected_building = building
	_on_tab_action_pressed()

func hide_building_menu() -> void:
	selected_building = null
	_on_tab_build_pressed()

func _on_tab_build_pressed() -> void:
	build_grid.visible = true
	action_grid.visible = false

func _on_tab_action_pressed() -> void:
	build_grid.visible = false
	action_grid.visible = true

func _on_train_skito_pressed() -> void:
	if selected_building and selected_building.has_method("spawn_skito"):
		if GameManager.can_afford(GameManager.skito_cost):
			GameManager.spend(GameManager.skito_cost)
			selected_building.spawn_skito()
		else:
			print("Elemeth insuficiente para Skito!")

func _on_build_nest_pressed() -> void:
	if is_building_mode: return
	
	if not GameManager.can_afford(GameManager.hollow_nest_cost):
		print("Elemeth insuficiente para Hollow Nest!")
		return
		
	is_building_mode = true
	building_ghost = building_scene.instantiate()
	building_ghost.get_node("CollisionShape2D").disabled = true
	building_ghost.modulate = Color(1, 1, 1, 0.5)
	
	# Usando group main para instanciar no mundo e não na UI
	var main_scene = get_tree().get_first_node_in_group("main")
	if not main_scene:
		main_scene = get_parent()
	main_scene.add_child(building_ghost)

func _input(event: InputEvent) -> void:
	if is_building_mode and building_ghost:
		building_ghost.global_position = building_ghost.get_global_mouse_position()
		
		if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			if GameManager.can_afford(GameManager.hollow_nest_cost):
				GameManager.spend(GameManager.hollow_nest_cost)
				# Placed!
				building_ghost.modulate = Color(1, 1, 1, 1)
				building_ghost.get_node("CollisionShape2D").disabled = false
				building_ghost = null
				is_building_mode = false
				get_viewport().set_input_as_handled()
			else:
				# Cancel build
				building_ghost.queue_free()
				building_ghost = null
				is_building_mode = false
