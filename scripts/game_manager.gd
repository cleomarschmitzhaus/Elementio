extends Node

## Economia separada por faccao. O jogador e a IA inimiga nao compartilham
## o mesmo caixa: cada um coleta e gasta os seus proprios recursos.
var elemeth: int = 500
var elemeth_enemy: int = 600
var initial_player_elemeth: int = 500
var initial_enemy_elemeth: int = 600

# Custos
var skito_cost: int = 50
var spider_cost: int = 100
var mantis_cost: int = 150
var scorpion_cost: int = 120
var hollow_nest_cost: int = 200

# Resultado da partida
enum MatchState { PLAYING, VICTORY, DEFEAT, DRAW }
var match_state: int = MatchState.PLAYING
var match_over: bool = false
var winner_team: int = -1

func get_elemeth(team: int = Faction.PLAYER) -> int:
	if team == Faction.ENEMY:
		return elemeth_enemy
	return elemeth

func can_afford(cost: int, team: int = Faction.PLAYER) -> bool:
	return get_elemeth(team) >= cost

func spend(cost: int, team: int = Faction.PLAYER) -> void:
	if team == Faction.ENEMY:
		elemeth_enemy -= cost
	else:
		elemeth -= cost

func add_elemeth(amount: int, team: int = Faction.PLAYER) -> void:
	if team == Faction.ENEMY:
		elemeth_enemy += amount
	else:
		elemeth += amount

## Chamado ao iniciar/reiniciar uma partida.
func reset_match() -> void:
	elemeth = initial_player_elemeth
	elemeth_enemy = initial_enemy_elemeth
	match_state = MatchState.PLAYING
	match_over = false
	winner_team = -1

## Encerra a partida. winner = Faction.PLAYER, Faction.ENEMY ou -2 (empate).
func finish_match(winner: int) -> void:
	if match_over:
		return
	match_over = true
	winner_team = winner
	if winner == Faction.PLAYER:
		match_state = MatchState.VICTORY
	elif winner == Faction.ENEMY:
		match_state = MatchState.DEFEAT
	else:
		match_state = MatchState.DRAW
