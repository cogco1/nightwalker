extends "res://tests/test_charged_draw.gd"
## Exercise the real input and hit-stop paths after removing the screen split and sword qi.

func no_extra_layers() -> bool:
	return arena.session.get_node_or_null("ImpactBurst")==null and arena.player.fx.get_node_or_null("ChargedDraw")==null \
		and root.find_children("*Split*", "", true, false).is_empty() and root.find_children("*SwordQi*", "", true, false).is_empty()

func run_tests() -> void:
	CONTROLS.install(false)
	arena=MAIN.instantiate();root.add_child(arena)
	await setup_draw(1)
	check(no_extra_layers(),"Fresh game contains no screen-split or sword-qi nodes")
	await tap(KEY_F10)
	check(no_extra_layers(),"F10 cannot restore the removed prototype")
	check(await coil_full(),"Real held input still reaches full charge")
	var enemy:=target_at(arena.player.position+Vector2(74,0),40)
	mouse(false)
	var saw_stop:=false
	for index in range(180):
		await tick()
		if paused:saw_stop=true
		check(no_extra_layers(),"Charge/release/contact frame has no removed overlay: "+str(index))
		if not arena.player.is_attacking and not arena.player.is_charging and not paused:break
	check(enemy.hp==34 and saw_stop,"Charged damage and original heavy hit feedback still work")
	await tap(KEY_F10)
	check(no_extra_layers(),"F10 after contact cannot create a split or flying blade")
	var report:Dictionary={"suite":"effect_removal","status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}
	print(JSON.stringify(report))
	arena.queue_free();await tick(6);quit(0 if failures.is_empty() else 1)
