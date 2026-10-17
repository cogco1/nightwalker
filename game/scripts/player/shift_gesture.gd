extends RefCounted
## One modifier gesture, timed by the player's combat clock so a hit-stop cannot turn a tap into a hold.
const HOLD_SECONDS := 0.18
var held := false
var pressed_at := 0.0
var consumed := false


func press(now: float) -> void:
	if held:
		return
	held = true
	pressed_at = now
	consumed = false


func release(now: float) -> bool:
	var tapped := held and not consumed and now - pressed_at < HOLD_SECONDS
	clear()
	return tapped


func running(now: float) -> bool:
	return held and now - pressed_at >= HOLD_SECONDS


func consume() -> void:
	consumed = true


func clear() -> void:
	held = false
	consumed = false
