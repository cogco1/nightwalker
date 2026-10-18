extends "res://tests/test_chapter_flow.gd"
## The complete paid withdrawal, using the shipped F / E input and the real home colliders. This deliberately
## stops when the first night is ready: combat lessons and day 2's complete script remain in chapter_flow.


func wallet_contract() -> void:
	story = STORY_STATE.ensure(self)
	story.start_chapter()
	var changes: Array[int] = []
	var changed := func(amount: int) -> void: changes.append(amount)
	story.balance_changed.connect(changed)
	check(story.balance == 0, "the wallet starts empty")
	for invalid: Variant in [0, -1, 0.5, "50"]:
		check(not story.award_once("invalid", invalid) and story.balance == 0, "an invalid reward cannot mint money: " + str(invalid))
		check(not story.spend(invalid) and story.balance == 0, "an invalid debit cannot change money: " + str(invalid))
	check(changes.is_empty(), "rejected wallet mutations emit no balance changes")
	check(story.award_once("fixture", 50) and story.balance == 50, "a positive integer reward reaches the account")
	check(changes == [50], "a real reward emits the resulting account balance once")
	check(not story.award_once("fixture", 50) and story.balance == 50, "a repeated reward cannot pay twice")
	check(not story.spend(51) and story.balance == 50, "an unaffordable debit cannot make the balance negative")
	check(story.purchase("throwing_spike", 40) == "purchased" and story.balance == 10 and story.has_item("throwing_spike"),
		"a successful purchase debits its price and grants its item together")
	check(story.purchase("throwing_spike", 40) == "owned" and story.balance == 10,
		"an owned item is rejected without another charge")
	check(story.purchase("ration", 12) == "insufficient" and story.balance == 10 and not story.has_item("ration"),
		"an unaffordable item changes neither balance nor inventory")
	check(changes == [50, 10], "only the reward and successful purchase notify the visible account")
	story.set_step("d2_wake")
	check(story.balance == 10, "changing the story day preserves earned money")
	story.start_chapter()
	check(story.balance == 0 and story.items.is_empty() and not story.has_flag("reward:fixture"),
		"restarting the chapter clears money, purchases and reward receipts")
	story.balance_changed.disconnect(changed)


func no_freeze(label: String) -> void:
	var session: Node = current_scene.get_node("GameSession")
	check(not paused and not session.has_modal() and not player().is_frozen(), label + " leaves no pause, modal or player freeze")


func open_shop_with_keys() -> void:
	await tap(KEY_E)
	check(current_scene.chapter.menu.active and current_scene.chapter.menu_page == "root", "E reopens the computer terminal")
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(current_scene.chapter.menu.active and current_scene.chapter.menu_page == "shop", "arrow and Enter keys open the shop")


func paid_home() -> void:
	if not await arrive(HOME, "The paid withdrawal"):
		return
	var home := current_scene
	var hud: Node = home.chapter.hud
	check(story.step == "d1_return" and story.balance == 50, "the actual hospital exit pays exactly 50 only after arrival in 601")
	check(hud.balance_panel.visible and hud.balance_label.text == "账户 ￥50", "the safehouse displays the real 50 yuan account")
	check(hud.balance_change_label.visible and hud.balance_change_label.text.contains("+50"), "the first arrival visibly announces the payment")
	check(story.has_flag("reward:coburn_contract"), "the contract keeps a single-use reward receipt")
	check(not story.award_once("coburn_contract", 50) and story.balance == 50, "a duplicate settlement signal cannot pay twice")
	story.set_step("d1_return")
	story.set_step("d1_return")
	await frames(2)
	check(story.balance == 50, "repeating the return step cannot pay twice")
	# A replay/re-entry fixture: the main journey above walked and used the real exit. Rebuild the hospital,
	# then leave through that same E input again; the receipt must survive both scene reconstructions.
	routes.travel("d1_hospital")
	if not await arrive(HOSPITAL, "A hospital revisit"):
		return
	check(story.balance == 50, "a scene transition keeps the paid balance")
	story.set_step("d1_target_down")
	current_scene.floor_id = 2
	current_scene.activate_view(0, "", Vector2(590, 175))
	await frames(6)
	await tap(KEY_E)
	if not await arrive(HOME, "The repeated withdrawal"):
		return
	home = current_scene
	hud = home.chapter.hud
	check(story.balance == 50 and story.step == "d1_return", "a second real E withdrawal never pays another 50")
	check(not hud.balance_change_label.visible, "returning again does not announce a new payment")
	if not await walk_home("bed"):
		return
	await tap(KEY_E)
	check(home.dialogue.active and story.step == "d1_return", "the bed waits for the settlement and resupply")
	await read_all(home.dialogue)
	no_freeze("closing the premature bed reading")
	if not await walk_home("computer"):
		return
	await tap(KEY_E)
	var menu: Panel = home.chapter.menu
	check(menu.active and menu.badges[0] and menu.corner.text.contains("￥50"), "the terminal shows the unread settlement and 50 yuan")
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(not menu.active and home.dialogue.active and story.step == "d1_return", "shopping waits until the settlement is read")
	await tap(KEY_ESCAPE)
	check(story.balance == 50 and story.items.is_empty(), "an early shopping attempt grants nothing and charges nothing")
	await tap(KEY_E)
	await tap(KEY_ENTER)
	check(home.dialogue.active and story.step == "d1_return", "Enter opens the settlement without completing it")
	var settlement: Array = home.dialogue.pages.duplicate()
	check(not settlement.is_empty() and not settlement.has("我让你去处理那个混账科伯恩！！！"), "the return message does not bring day 2's accusation forward")
	await tap(KEY_ESCAPE)
	check(story.step == "d1_return" and story.balance == 50, "Esc midway through the message keeps it unread without paying again")
	no_freeze("closing an unfinished settlement")
	await tap(KEY_ESCAPE)
	check(paused and home.get_node("GameSession").settings_open, "settings still open after an unfinished reading")
	await tap(KEY_ESCAPE)
	no_freeze("closing settings")
	await tap(KEY_E)
	check(menu.active and menu.badges[0], "the interrupted settlement keeps its unread marker")
	await tap(KEY_ENTER)
	await read_all(home.dialogue)
	check(story.step == "d1_resupply" and menu.active and home.chapter.menu_page == "shop", "finishing every page automatically opens mainline resupply")
	check(menu.notes[0].contains("￥40") and menu.corner.text.contains("￥50"), "the shop shows a real price alongside available money")
	await tap(KEY_ESCAPE)
	check(menu.active and home.chapter.menu_page == "root", "Esc from resupply returns to the terminal")
	await tap(KEY_ESCAPE)
	no_freeze("closing the terminal")
	check(story.step == "d1_resupply", "closing the shop does not skip its objective")
	await open_shop_with_keys()
	await tap(KEY_ENTER)
	check(story.balance == 10 and story.has_item("throwing_spike") and story.step == "d1_shopped", "the first equipment purchase spends 40 and enables rest")
	check(home.dialogue.active and not menu.active, "the paid order returns from the menu to its confirmation")
	await read_all(home.dialogue)
	check(hud.balance_label.text == "账户 ￥10" and hud.goal_label.text.contains("床"), "the account reads 10 and the next goal is the bed")
	no_freeze("completing an order")
	await open_shop_with_keys()
	check(menu.corner.text.contains("￥10") and menu.notes[0].contains("已"), "the reopened shop shows the remaining balance and owned equipment")
	await tap(KEY_ENTER)
	check(home.dialogue.active and story.balance == 10 and story.step == "d1_shopped", "buying the same equipment is rejected without debit or phase change")
	await read_all(home.dialogue)
	no_freeze("closing the owned-item refusal")
	await open_shop_with_keys()
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(home.dialogue.active and story.balance == 10 and not story.has_item("ration") and story.step == "d1_shopped",
		"a 12 yuan ration is refused when only 10 remain, without granting it or changing the phase")
	await read_all(home.dialogue)
	no_freeze("closing the insufficient-funds refusal")
	if not await walk_home("bed"):
		return
	await tap(KEY_E)
	check(home.chapter.busy and home.player.is_frozen(), "the real bed starts the transition into the mainline night")
	if not await arrive(HOSPITAL, "Resting to the first night"):
		return
	var hospital := current_scene
	check(story.step == "d1_night" and story.clock_text() == "22:00" and story.is_night(), "rest advances the script to the 22:00 first night")
	check(hospital.view_mode == 1 and hospital.chapter.fight != null and hospital.chapter.fight.enemies.size() == 11,
		"the mainline chooses side view and instantiates its actual night enemies")
	check(story.balance == 10 and hospital.chapter.chapter_hud.balance_label.text.contains("￥10"), "the night hospital retains and displays the remaining account")
	await tap(KEY_TAB)
	check(hospital.view_mode == 1, "the story selects the projection and Tab cannot switch it")
	check(not paused and not hospital.chapter.busy and not hospital.player.is_frozen(), "the first night is playable without a leftover transition freeze")
	observations["route_result"] = {"reward": 50, "purchase": 40, "balance": story.balance,
		"step": story.step, "time": story.clock_text(), "view": hospital.view_mode, "enemies": hospital.chapter.fight.enemies.size()}
	# This fixture exercises persistence through the following day without replaying combat's unrelated bot.
	routes.travel("d2_wake")
	if not await arrive(HOME, "The next-day persistence fixture"):
		return
	await play_sequence(current_scene.chapter, current_scene.dialogue)
	check(story.day == 2 and story.balance == 10 and current_scene.chapter.hud.balance_label.text.contains("￥10"), "day 2 keeps the account across its wake-up sequence")
	check(story.chapter["messages"]["d2_wake"]["lines"][0] == "我让你去处理那个混账科伯恩！！！", "Joren's scripted accusation remains assigned to the next morning")
	story.start_chapter()
	check(story.balance == 0 and not story.has_item("throwing_spike") and not story.has_flag("reward:coburn_contract"), "starting over cannot inherit money, equipment or the old receipt")


func run() -> void:
	routes = root.get_node("SceneRoutes")
	wallet_contract()
	await day_one_home()
	await hospital_day()
	await paid_home()
	observations["walk_seconds"] = snappedf(_walk_frames / 60.0, 0.1)
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	hold(0)
	print(JSON.stringify({"suite": "coburn_reward_flow", "checks": checks, "failures": failures,
		"observations": observations, "status": "passed" if failures.is_empty() else "failed"}))
	quit(0 if failures.is_empty() else 1)
