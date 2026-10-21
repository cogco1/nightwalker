extends RefCounted
## Shared melee pacing for current and future enemies. A full readable windup and recovery surround one hit.
const WINDUP_SECONDS := 0.55
const ACTIVE_SECONDS := 0.10
const RECOVERY_SECONDS := 0.55
const MIN_COOLDOWN_SECONDS := 0.80

static func can_begin(hero: Node, windup := WINDUP_SECONDS) -> bool:
	if not is_instance_valid(hero):
		return false
	if hero.has_method("is_frozen") and hero.is_frozen():
		return false
	return hero.can_receive_melee_windup(windup) if hero.has_method("can_receive_melee_windup") else true
