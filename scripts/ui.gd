extends CanvasLayer

const SETTINGS_MENU_SCENE := preload("res://scenes/settings_menu.tscn")

@onready var build_grid: GridContainer = $Control/BottomBar/Panel/Margin/HBox/MainContent/BuildGrid
@onready var action_grid: GridContainer = $Control/BottomBar/Panel/Margin/HBox/MainContent/ActionGrid
@onready var spells_grid: GridContainer = $Control/BottomBar/Panel/Margin/HBox/MainContent/SpellsGrid

@onready var tab_build_btn: Button = $Control/BottomBar/Panel/Margin/HBox/CategoryTabs/TabBuild
@onready var tab_action_btn: Button = $Control/BottomBar/Panel/Margin/HBox/CategoryTabs/TabAction
@onready var tab_spells_btn: Button = $Control/BottomBar/Panel/Margin/HBox/CategoryTabs/TabSpells

@onready var elemeth_label: Label = $Control/TopBar/Panel/Margin/HBox/ElemethLabel
@onready var mana_bar: ProgressBar = $Control/TopBar/Panel/Margin/HBox/ManaBar
@onready var stats_label: Label = $Control/TopBar/Panel/Margin/HBox/StatsLabel
# Indicadores de unidades idle por tipo
var idle_skito_btn: Button = null
var idle_spider_btn: Button = null
var idle_mantis_btn: Button = null
var idle_scorpion_btn: Button = null
@onready var formation_btn: Button = $Control/TopBar/Panel/Margin/HBox/FormationBtn
@onready var options_btn: Button = $Control/TopBar/Panel/Margin/HBox/OptionsBtn
@onready var view_toggle_btn: Button = $Control/TopBar/Panel/Margin/HBox/ViewToggleBtn

@onready var selection_header: Label = $Control/BottomBar/Panel/Margin/HBox/SelectionPanel/SelectionHeader
@onready var selection_stats: Label = $Control/BottomBar/Panel/Margin/HBox/SelectionPanel/SelectionStats
@onready var units_hbox: HBoxContainer = $Control/BottomBar/Panel/Margin/HBox/SelectionPanel/SelectionScroll/UnitsHBox

var selected_building = null
var selected_resource = null
var is_building_mode = false
var building_ghost = null
var building_scene = preload("res://scenes/buildings/artropes/hollow_nest.tscn")

var is_world_view: bool = false
var saved_camera_zoom: float = 1.0

# Tela de fim de partida (construida em codigo para nao alterar o .tscn)
var match_overlay: Control = null
var match_title: Label = null
var match_subtitle: Label = null

# Menu de opcoes/pausa (criado depois do overlay de fim de partida para ficar acima dele)
var settings_menu: Control = null

func _ready() -> void:
	# A interface continua respondendo enquanto o jogo esta pausado no menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui")
	_on_tab_build_pressed()
	update_formation_label("box")
	_setup_idle_indicators()
	_build_match_overlay()
	_setup_settings_menu()

func _setup_idle_indicators() -> void:
	var hbox: HBoxContainer = $Control/TopBar/Panel/Margin/HBox
	idle_skito_btn = _create_idle_button("Skito: 0", "Skito")
	hbox.add_child(idle_skito_btn)
	idle_spider_btn = _create_idle_button("Spider: 0", "Spider")
	hbox.add_child(idle_spider_btn)
	idle_mantis_btn = _create_idle_button("Mantis: 0", "Mantis")
	hbox.add_child(idle_mantis_btn)
	idle_scorpion_btn = _create_idle_button("Escorpião: 0", "Scorpion")
	idle_scorpion_btn.custom_minimum_size = Vector2(76, 30)
	idle_scorpion_btn.add_theme_font_size_override("font_size", 10)
	hbox.add_child(idle_scorpion_btn)

func _create_idle_button(label_text: String, unit_type: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(64, 30)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _select_idle_units(unit_type))
	return btn

func _count_idle(unit_type: String) -> int:
	var count = 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if "team" in u and int(u.get("team")) != Faction.PLAYER:
			continue
		if "is_controllable" in u and not bool(u.get("is_controllable")):
			continue
		if u.get("unit_type") == unit_type and int(u.get("current_state")) == 0:
			count += 1
	return count

func _select_idle_units(unit_type: String) -> void:
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if not sm:
		return
	# Deseleciona tudo
	for u in sm.selected_units:
		if is_instance_valid(u):
			u.deselect()
	sm.selected_units.clear()
	if is_instance_valid(sm.selected_building):
		sm.selected_building.deselect()
		sm.selected_building = null
	# Seleciona unidades idle do tipo
	var count = 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if "team" in u and int(u.get("team")) != Faction.PLAYER:
			continue
		if "is_controllable" in u and not bool(u.get("is_controllable")):
			continue
		if u.get("unit_type") == unit_type and int(u.get("current_state")) == 0:
			u.select()
			if not sm.selected_units.has(u):
				sm.selected_units.append(u)
			count += 1
	if sm.has_method("_notify_ui_selection"):
		sm._notify_ui_selection()

func _process(_delta: float) -> void:
	elemeth_label.text = "⚡ Elemeth: %d" % GameManager.elemeth
	var mana_percent = clamp((float(GameManager.elemeth) / 500.0) * 100.0, 0.0, 100.0)
	mana_bar.value = mana_percent

	var player_buildings := 0
	var enemy_count := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b.get("is_ghost") == true:
			continue
		if "team" in b:
			var bteam := int(b.get("team"))
			if bteam == Faction.PLAYER:
				player_buildings += 1
			elif bteam == Faction.ENEMY:
				enemy_count += 1
	var player_units := 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if "team" in u and int(u.get("team")) == Faction.ENEMY:
			enemy_count += 1
		elif not ("is_controllable" in u) or bool(u.get("is_controllable")):
			player_units += 1
	stats_label.text = "Ninhos: %d | Unid: %d | Inim: %d" % [
		player_buildings, player_units, enemy_count]

	if idle_skito_btn:
		idle_skito_btn.text = "Skito: %d" % _count_idle("Skito")
	if idle_spider_btn:
		idle_spider_btn.text = "Spider: %d" % _count_idle("Spider")
	if idle_mantis_btn:
		idle_mantis_btn.text = "Mantis: %d" % _count_idle("Mantis")
	if idle_scorpion_btn:
		idle_scorpion_btn.text = "Escorpião: %d" % _count_idle("Scorpion")


	# HUD: info do que esta selecionado, atualizando sempre (inclui elementio carregado)
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if sm != null:
		_prune_selected_units(sm)
	var has_units = sm != null and sm.selected_units.size() > 0
	if has_units:
		var total_carried = 0
		for u in sm.selected_units:
			if is_instance_valid(u) and "carried_elementio" in u:
				total_carried += u.carried_elementio
		selection_header.text = "🎯 Selecionadas: %d  |  ⚡ Carregado: %d" % [sm.selected_units.size(), total_carried]
		_update_selection_stats(sm.selected_units)
	elif selected_resource and is_instance_valid(selected_resource) and selected_resource.has_method("get_resource_info"):
		selection_header.text = selected_resource.get_resource_info()
		selection_stats.text = ""
	elif selected_building and is_instance_valid(selected_building) and selected_building.has_method("get_building_info"):
		selection_header.text = selected_building.get_building_info()
		selection_stats.text = ""
	else:
		selection_header.text = "🎯 Selecionadas: 0"
		selection_stats.text = ""

func _prune_selected_units(sm: Node) -> void:
	var selected_units: Array = sm.get("selected_units")
	var removed := false
	for i in range(selected_units.size() - 1, -1, -1):
		var u = selected_units[i]
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			selected_units.remove_at(i)
			removed = true
	if removed:
		sm.set("selected_units", selected_units)
		update_selected_units_display(selected_units)

func _update_selection_stats(units: Array) -> void:
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.has_method("get_unit_info"):
			selection_stats.text = u.get_unit_info()
			return
	selection_stats.text = ""

func update_formation_label(form_name: String) -> void:
	var label_pt = "Bloco"
	match form_name:
		"line": label_pt = "Linha"
		"circle": label_pt = "Círculo"
		"wedge": label_pt = "Cunha (V)"
		_: label_pt = "Bloco"
	formation_btn.text = "🛡 Formação: %s (F)" % label_pt

func _on_formation_btn_pressed() -> void:
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if sm and sm.has_method("cycle_formation"):
		sm.cycle_formation()

func _on_options_btn_pressed() -> void:
	if settings_menu == null:
		return
	if settings_menu.visible:
		settings_menu.call("close")
	else:
		if is_building_mode:
			_cancel_building()
		settings_menu.call("open")

func _setup_settings_menu() -> void:
	if settings_menu != null:
		return
	var parent := $Control as Control
	if parent == null:
		return
	settings_menu = SETTINGS_MENU_SCENE.instantiate() as Control
	if settings_menu == null:
		return
	parent.add_child(settings_menu)
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# Agrupamento das unidades selecionadas no HUD (RTS clássico como StarCraft / Age of Empires)
func update_selected_units_display(units: Array) -> void:
	# Limpa ícones anteriores
	for child in units_hbox.get_children():
		child.queue_free()

	var valid_units = []
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion():
			valid_units.append(u)

	selection_header.text = "🎯 Selecionadas: %d" % valid_units.size()
	if valid_units.size() == 0:
		selection_stats.text = ""
		return

	# Agrupa por tipo de unidade para contar (ex: 5 Skitos, 2 Spiders)
	var type_counts = {}
	for u in valid_units:
		var utype = u.get("unit_type") if "unit_type" in u else u.name
		if not type_counts.has(utype):
			type_counts[utype] = {"count": 0, "sample": u}
		type_counts[utype]["count"] += 1

	for utype in type_counts.keys():
		var info = type_counts[utype]
		var sample = info["sample"]
		var label_text: String = str(utype)
		if sample.has_method("get_display_name"):
			label_text = sample.get_display_name()
		var card = Button.new()
		card.custom_minimum_size = Vector2(75, 75)
		card.text = "%s\nx%d" % [label_text, info["count"]]
		card.alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Ao clicar no card de um grupo, seleciona apenas aquele tipo
		card.pressed.connect(func(): _filter_selection_by_type(utype))
		units_hbox.add_child(card)
	_update_selection_stats(valid_units)

func _filter_selection_by_type(target_type: String) -> void:
	var sm = get_tree().get_first_node_in_group("selection_manager")
	if sm:
		var new_selection = []
		for u in sm.selected_units:
			if is_instance_valid(u):
				var utype = u.get("unit_type") if "unit_type" in u else u.name
				if utype == target_type:
					new_selection.append(u)
				else:
					u.deselect()
		sm.selected_units = new_selection
		sm._notify_ui_selection()

func show_building_menu(building: Node) -> void:
	if building == null or not is_instance_valid(building):
		return
	if "team" in building and int(building.get("team")) != Faction.PLAYER:
		return
	selected_building = building
	if building.has_method("get_building_info"):
		selection_header.text = building.get_building_info()
	selection_stats.text = ""
	_on_tab_action_pressed()

func hide_building_menu() -> void:
	selected_building = null
	selection_header.text = "🎯 Selecionadas: 0"
	selection_stats.text = ""
	_on_tab_build_pressed()

func show_resource_menu(resource: Node) -> void:
	selected_resource = resource
	# mantem a aba atual, mas exibe info no header
	if selected_resource and is_instance_valid(selected_resource) and selected_resource.has_method("get_resource_info"):
		selection_header.text = selected_resource.get_resource_info()
	selection_stats.text = ""

func hide_resource_menu() -> void:
	selected_resource = null
	selection_header.text = "🎯 Selecionadas: 0"
	selection_stats.text = ""
func _reset_tab_styles() -> void:
	tab_build_btn.modulate = Color(0.8, 0.8, 0.8)
	tab_action_btn.modulate = Color(0.8, 0.8, 0.8)
	tab_spells_btn.modulate = Color(0.8, 0.8, 0.8)

func _on_tab_build_pressed() -> void:
	_reset_tab_styles()
	tab_build_btn.modulate = Color(1.2, 1.1, 0.8)
	build_grid.visible = true
	action_grid.visible = false
	spells_grid.visible = false

func _on_tab_action_pressed() -> void:
	_reset_tab_styles()
	tab_action_btn.modulate = Color(1.2, 1.1, 0.8)
	build_grid.visible = false
	action_grid.visible = true
	spells_grid.visible = false

func _on_tab_spells_pressed() -> void:
	_reset_tab_styles()
	tab_spells_btn.modulate = Color(1.2, 1.1, 0.8)
	build_grid.visible = false
	action_grid.visible = false
	spells_grid.visible = true

func _get_player_nest() -> Node:
	if selected_building and is_instance_valid(selected_building):
		if "team" in selected_building and int(selected_building.get("team")) == Faction.PLAYER:
			return selected_building
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.get("is_ghost") == true:
			continue
		if "team" in b and int(b.get("team")) == Faction.PLAYER:
			return b
	return null

func _on_train_skito_pressed() -> void:
	var target = _get_player_nest()
	if target and target.has_method("spawn_unit"):
		if GameManager.can_afford(GameManager.skito_cost):
			GameManager.spend(GameManager.skito_cost)
			target.spawn_unit("skito")
		else:
			_flash_cost_warning()

func _on_train_spider_pressed() -> void:
	var target = _get_player_nest()
	if target and target.has_method("spawn_unit"):
		if GameManager.can_afford(GameManager.spider_cost):
			GameManager.spend(GameManager.spider_cost)
			target.spawn_unit("spider")
		else:
			_flash_cost_warning()

func _on_train_mantis_pressed() -> void:
	var target = _get_player_nest()
	if target and target.has_method("spawn_unit"):
		if GameManager.can_afford(GameManager.mantis_cost):
			GameManager.spend(GameManager.mantis_cost)
			target.spawn_unit("mantis")
		else:
			_flash_cost_warning()

func _on_train_scorpion_pressed() -> void:
	var target = _get_player_nest()
	if target and target.has_method("spawn_unit"):
		if GameManager.can_afford(GameManager.scorpion_cost):
			GameManager.spend(GameManager.scorpion_cost)
			target.spawn_unit("scorpion")
		else:
			_flash_cost_warning()

func _on_rally_pressed() -> void:
	var target = _get_player_nest()
	if target and target.has_method("set_rally_point"):
		target.placing_rally = true
		selection_header.text = "Clique com botao direito no terreno para definir o Rally Point"

func _on_spell_swarm_pressed() -> void:
	if GameManager.can_afford(80):
		GameManager.spend(80)
		var units = get_tree().get_nodes_in_group("units")
		for u in units:
			if "speed" in u:
				u.speed *= 1.3
		print("Magia: Enxame ativada!")

func _on_spell_terraforming_pressed() -> void:
	print("Magia: Aplanar Terreno ativada (estilo Populous 3)")

func _flash_cost_warning() -> void:
	elemeth_label.modulate = Color(1.5, 0.2, 0.2)
	var tween = create_tween()
	tween.tween_property(elemeth_label, "modulate", Color(1, 1, 1), 0.4)

func _on_build_nest_pressed() -> void:
	if is_building_mode: return
	
	if not GameManager.can_afford(GameManager.hollow_nest_cost):
		_flash_cost_warning()
		return
		
	is_building_mode = true
	building_ghost = building_scene.instantiate()
	building_ghost.is_ghost = true
	if building_ghost.has_node("CollisionShape2D"):
		building_ghost.get_node("CollisionShape2D").disabled = true
	building_ghost.modulate = Color(1, 1, 0.4, 0.6)
	
	var main_scene = get_tree().get_first_node_in_group("main")
	if not main_scene:
		main_scene = get_parent()
	main_scene.add_child(building_ghost)

func _on_view_toggle_pressed() -> void:
	# Cena 3D (globo): alterna entre vista planeta e vista superficie
	var globe = get_tree().get_first_node_in_group("globe_controller")
	if globe and globe.has_method("toggle_view"):
		globe.toggle_view()
		is_world_view = globe.is_surface_view()
		view_toggle_btn.text = "🌍 Planeta" if is_world_view else "🔍 Foco Local"
		return
	# Cena 2D (main.tscn): ajusta zoom da camera
	var cam = get_viewport().get_camera_2d()
	if cam:
		is_world_view = !is_world_view
		if is_world_view:
			saved_camera_zoom = cam.zoom.x
			if "target_zoom" in cam:
				cam.target_zoom = 0.5
			else:
				cam.zoom = Vector2(0.5, 0.5)
			view_toggle_btn.text = "🔍 Foco Local"
		else:
			if "target_zoom" in cam:
				cam.target_zoom = saved_camera_zoom
			else:
				cam.zoom = Vector2(saved_camera_zoom, saved_camera_zoom)
			view_toggle_btn.text = "🌍 Planeta"

func _input(event: InputEvent) -> void:
	# Esc: fecha o menu, cancela a construcao ou abre as opcoes (pausa a partida).
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		if settings_menu != null:
			if settings_menu.visible:
				settings_menu.call("close")
			elif is_building_mode:
				_cancel_building()
			else:
				settings_menu.call("open")
		get_viewport().set_input_as_handled()
		return

	if is_building_mode and building_ghost:
		var mouse_pos = building_ghost.get_global_mouse_position()
		building_ghost.global_position = mouse_pos
		
		# Validação de terreno: Só pode construir sobre terra firme (não sobre água nem penhascos)
		var planet = get_tree().get_first_node_in_group("planet")
		var can_place_here = true
		if planet and planet.has_method("is_walkable_land"):
			can_place_here = planet.is_walkable_land(mouse_pos)
			
		if can_place_here:
			building_ghost.modulate = Color(0.4, 1.0, 0.4, 0.7)
		else:
			building_ghost.modulate = Color(1.0, 0.3, 0.3, 0.7)
		
		if event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT:
				if can_place_here and GameManager.can_afford(GameManager.hollow_nest_cost):
					GameManager.spend(GameManager.hollow_nest_cost)
					building_ghost.is_ghost = false
					building_ghost.modulate = Color(1, 1, 1, 1)
					if building_ghost.has_node("CollisionShape2D"):
						building_ghost.get_node("CollisionShape2D").disabled = false
					building_ghost = null
					is_building_mode = false
					get_viewport().set_input_as_handled()
				else:
					if not can_place_here:
						print("Construção inválida: deve ser colocada sobre a terra!")
					else:
						_cancel_building()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_building()

func _cancel_building() -> void:
	if building_ghost:
		building_ghost.queue_free()
		building_ghost = null
	is_building_mode = false

# ---------------------------------------------------------------------------
# Fim de partida: vitoria, derrota ou empate
# ---------------------------------------------------------------------------
func _build_match_overlay() -> void:
	var parent := $Control as Control
	if parent == null:
		return
	match_overlay = Control.new()
	match_overlay.name = "MatchOverlay"
	match_overlay.visible = false
	match_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	match_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(match_overlay)
	match_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	match_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	match_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	match_title = Label.new()
	match_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_title.add_theme_font_size_override("font_size", 64)
	box.add_child(match_title)

	match_subtitle = Label.new()
	match_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_subtitle.add_theme_font_size_override("font_size", 22)
	match_subtitle.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	box.add_child(match_subtitle)

	var restart := Button.new()
	restart.text = "Jogar novamente"
	restart.custom_minimum_size = Vector2(280, 54)
	restart.add_theme_font_size_override("font_size", 20)
	restart.pressed.connect(_on_restart_match_pressed)
	box.add_child(restart)

func show_match_result(winner: int) -> void:
	if match_overlay == null:
		_build_match_overlay()
	if match_overlay == null:
		return
	match_overlay.visible = true
	match_overlay.move_to_front()
	if winner == Faction.PLAYER:
		match_title.text = "VITÓRIA"
		match_title.add_theme_color_override("font_color", Color(0.3, 0.95, 0.45))
		match_subtitle.text = "Todas as construções inimigas foram destruídas."
	elif winner == Faction.ENEMY:
		match_title.text = "DERROTA"
		match_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		match_subtitle.text = "Todas as suas construções foram destruídas."
	else:
		match_title.text = "EMPATE"
		match_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		match_subtitle.text = "As últimas construções caíram ao mesmo tempo."

func _on_restart_match_pressed() -> void:
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")
