extends Node
## Regras de fim de partida: vence quem destruir primeiro todas as construcoes
## da faccao adversaria. Fontes sao neutras e nao entram na contagem.

const CHECK_INTERVAL: float = 0.5
const NO_WINNER: int = -1
const DRAW: int = -2

var check_timer: float = 0.0

func _ready() -> void:
	add_to_group("match_manager")
	GameManager.reset_match()

func _process(delta: float) -> void:
	if GameManager.match_over:
		return
	check_timer -= delta
	if check_timer > 0.0:
		return
	check_timer = CHECK_INTERVAL
	_check_victory()

func _check_victory() -> void:
	var player_buildings := count_buildings(Faction.PLAYER)
	var enemy_buildings := count_buildings(Faction.ENEMY)
	var winner := winner_for_counts(player_buildings, enemy_buildings)
	if winner == NO_WINNER:
		return
	GameManager.finish_match(winner)
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("show_match_result"):
		ui.show_match_result(winner)
	# A tela de resultado tem process_mode ALWAYS e continua clicavel.
	get_tree().paused = true

func count_buildings(team: int) -> int:
	var count := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b.get("is_ghost") == true:
			continue
		if "team" in b and int(b.get("team")) == team:
			count += 1
	return count

## Retorna Faction.PLAYER/Faction.ENEMY, NO_WINNER (jogo continua) ou DRAW.
static func winner_for_counts(player_buildings: int, enemy_buildings: int) -> int:
	if player_buildings == 0 and enemy_buildings == 0:
		return DRAW
	if enemy_buildings == 0:
		return Faction.PLAYER
	if player_buildings == 0:
		return Faction.ENEMY
	return NO_WINNER
