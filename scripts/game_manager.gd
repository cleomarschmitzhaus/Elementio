extends Node

var elemeth: int = 500

# Custos
var skito_cost: int = 50
var spider_cost: int = 100
var mantis_cost: int = 150
var hollow_nest_cost: int = 200

func can_afford(cost: int) -> bool:
	return elemeth >= cost

func spend(cost: int) -> void:
	elemeth -= cost

func add_elemeth(amount: int) -> void:
	elemeth += amount
