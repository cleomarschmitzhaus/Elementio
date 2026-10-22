extends RefCounted
class_name Faction

## Classificacao de entidades do mundo.
## PLAYER  = entidades do jogador (controlaveis)
## ENEMY   = entidades hostis (nao controlaveis)
## NEUTRAL = entidades naturais/neutras (nao controlaveis, nao hostis)
enum { PLAYER, ENEMY, NEUTRAL }

const PLAYER_RING := Color(0.2, 0.95, 0.35, 0.95)
const ENEMY_RING := Color(1.0, 0.3, 0.3, 0.95)
const NEUTRAL_RING := Color(0.82, 0.84, 0.88, 0.95)

const FILL_ALPHA := 0.10

## Cor do indicador de selecao para a classificacao informada.
static func selection_color(faction: int) -> Color:
	match faction:
		ENEMY:
			return ENEMY_RING
		NEUTRAL:
			return NEUTRAL_RING
		_:
			return PLAYER_RING

## Preenchimento do indicador de selecao (mesma cor, 10% de opacidade).
static func selection_fill(faction: int) -> Color:
	var c := selection_color(faction)
	c.a = FILL_ALPHA
	return c

## Nome legivel da classificacao.
static func faction_name(faction: int) -> String:
	match faction:
		ENEMY:
			return "Inimigo"
		NEUTRAL:
			return "Neutro"
		_:
			return "Jogador"

## Duas entidades so sao hostis se forem de classificacoes diferentes
## e nenhuma delas for neutra.
static func is_hostile(a: int, b: int) -> bool:
	if a == NEUTRAL or b == NEUTRAL:
		return false
	return a != b
