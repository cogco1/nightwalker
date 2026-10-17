extends RefCounted
## The hero's hit points for a chapter night (the sandbox and the day jobs have none). Damage eats the temporary
## overheal first ("临时过量生命", the vodka of milestone 3: grant_overheal(roundi(max_hp * 0.3)) before the
## night), then hp. At 0 the hero is down and the night restarts the floor (night_fight.gd), which refills.

signal changed
signal died

var max_hp := 100
var hp := 100
## Temporary excess hit points on top of hp; never refilled, cleared by a restart.
var overheal := 0
var dead := false


func _init(maximum := 100) -> void:
	max_hp = maxi(1, maximum)
	hp = max_hp


## Takes amount off overheal, then hp; returns what was actually taken. Hitting 0 emits died once.
func damage(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var from_overheal := mini(overheal, amount)
	overheal -= from_overheal
	var from_hp := mini(hp, amount - from_overheal)
	hp -= from_hp
	changed.emit()
	if hp <= 0:
		dead = true
		died.emit()
	return from_overheal + from_hp


func grant_overheal(amount: int) -> void:
	if amount <= 0 or dead:
		return
	overheal += amount
	changed.emit()


## Back to full hp with no overheal (a restart after going down).
func refill() -> void:
	hp = max_hp
	overheal = 0
	dead = false
	changed.emit()


func ratio() -> float:
	return float(hp) / float(max_hp)
