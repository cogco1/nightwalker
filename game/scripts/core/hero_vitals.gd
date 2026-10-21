extends RefCounted
## The hero's hit points in the combat scenes (whitebox and the sniper / drone / melee trials; the safehouse and the
## night street have none). At 0 the hero is down and the scene respawns the hero, which refills.

signal changed
signal died

var max_hp := 100
var hp := 100
var dead := false


func _init(maximum := 100) -> void:
	max_hp = maxi(1, maximum)
	hp = max_hp


## Takes amount off hp; returns what was actually taken. Hitting 0 emits died once.
func damage(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var from_hp := mini(hp, amount)
	hp -= from_hp
	changed.emit()
	if hp <= 0:
		dead = true
		died.emit()
	return from_hp


## Back to full hp (a restart after going down).
func refill() -> void:
	hp = max_hp
	dead = false
	changed.emit()


func ratio() -> float:
	return float(hp) / float(max_hp)
