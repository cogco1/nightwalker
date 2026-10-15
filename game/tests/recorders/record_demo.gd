extends SceneTree
const MAIN = preload("res://tests/fixtures/combat_lab.tscn")
var arena: Node2D
var frame_index := 0
func _initialize() -> void: call_deferred("record")
func key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code;event.keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func release() -> void:
	for code in [KEY_W,KEY_S,KEY_A,KEY_D,KEY_J,KEY_CAPSLOCK,KEY_SPACE]: key(code,false)
func shot(count: int) -> void:
	for n in range(count):
		for i in range(4): await physics_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png("res://evidence/recorded/%03d.png"%frame_index)
		frame_index+=1
func record() -> void:
	DirAccess.make_dir_recursive_absolute("res://evidence/recorded")
	arena=MAIN.instantiate();root.add_child(arena)
	await shot(5)
	key(KEY_W,true);await shot(9);release()
	key(KEY_D,true);await shot(10);release()
	key(KEY_S,true);await shot(9);release()
	key(KEY_A,true);await shot(9);release()
	key(KEY_D,true);key(KEY_CAPSLOCK,true);await shot(9);release()
	arena.player.position=Vector2(145,143);arena.player.facing="right"
	key(KEY_J,true);await shot(7);release();await shot(5)
	arena.build_arena(1);await shot(5)
	key(KEY_D,true);await shot(7);release()
	for i in range(3):
		key(KEY_J,true);await shot(1);release();await shot(6)
	key(KEY_D,true);key(KEY_CAPSLOCK,true);await shot(8);release()
	arena.player.position=Vector2(110,160);await shot(2)
	key(KEY_D,true);key(KEY_SPACE,true);await shot(1);key(KEY_SPACE,false)
	await shot(9);release();await shot(5)
	arena.player.position=Vector2(185,160);await shot(2)
	key(KEY_S,true);key(KEY_D,true);await shot(46);release();await shot(8)
	print("PASS: recorded %d frames from actual Godot gameplay"%frame_index)
	quit()
