extends CanvasLayer

@onready var action_panel = $Control/ActionPanel
@onready var build_panel = $Control/BuildPanel

var selected_building = null
var is_building_mode = false
var building_ghost = null
var building_scene = preload("res://scenes/buildings/artropes/hollow_nest.tscn")

func _ready() -> void:
	add_to_group("ui")
	action_panel.visible = false

func show_building_menu(building: Node) -> void:
	selected_building = building
	action_panel.visible = true

func hide_building_menu() -> void:
	selected_building = null
	action_panel.visible = false

func _on_train_skito_pressed() -> void:
	if selected_building and selected_building.has_method("spawn_skito"):
		selected_building.spawn_skito()

func _on_build_nest_pressed() -> void:
	is_building_mode = true
	building_ghost = building_scene.instantiate()
	building_ghost.get_node("CollisionShape2D").disabled = true
	building_ghost.modulate = Color(1, 1, 1, 0.5) # Deixa transparente
	get_parent().add_child(building_ghost)

func _input(event: InputEvent) -> void:
	if is_building_mode and building_ghost:
		# Pega a posição do mouse no mundo 2D
		building_ghost.global_position = building_ghost.get_global_mouse_position()
		
		if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			# Placed!
			building_ghost.modulate = Color(1, 1, 1, 1)
			building_ghost.get_node("CollisionShape2D").disabled = false
			building_ghost = null
			is_building_mode = false
			get_viewport().set_input_as_handled()
