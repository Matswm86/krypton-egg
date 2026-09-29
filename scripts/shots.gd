extends Node
## Test driver, active only when the game is launched with `-- --shots <dir>`.
## Walks every screen, plays a few seconds of a level with the racket kept
## under the ball, and saves PNG screenshots.

var main: Node
var out_dir := ""
var autoplay := false


func start(owner_main: Node, dir: String) -> void:
	main = owner_main
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _physics_process(_delta: float) -> void:
	if autoplay and main.screen == main.Screen.GAME and not main.balls.is_empty():
		var target: float = main.balls[0]["p"].x
		main._move_rack(clampf(target - main.rack_x, -6.0, 6.0), 0.0)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _run() -> void:
	main._play_cutscenes([main.CUT_LOGO], main.Screen.PRESENTS)
	await _wait(200)
	await _snap("01_c2v_logo")
	main._play_cutscenes([main.CUT_INTRO], main.Screen.PRESENTS)
	await _wait(120)
	await _snap("02_intro")
	main.go(main.Screen.PRESENTS)
	await _wait(5)
	await _snap("03_presents")
	main.go(main.Screen.TITLE)
	await _wait(400)
	await _snap("04_title")
	main.go(main.Screen.MENU)
	await _wait(20)
	await _snap("05_menu")
	main.go(main.Screen.INFO)
	await _wait(5)
	await _snap("06_info")
	main.info_page = 2
	await _wait(5)
	await _snap("07_info_spells")
	main.level = 0
	main.score = 0
	main.lives = 3
	main.screen = main.Screen.GAME
	main._begin_level()
	await _wait(10)
	await _snap("08_level1")
	autoplay = true
	main._action()
	await _wait(600)
	await _snap("09_level1_play")
	main.drops.append({"p": Vector2(120, 100), "s": main.Sp.GLUE, "t": 0.0})
	main.drops.append({"p": Vector2(200, 110), "s": main.Sp.LASER, "t": 0.0})
	main.monster_timer = 0.0
	await _wait(90)
	await _snap("10_spells_monsters")
	main._apply_spell(main.Sp.MULTI)
	main._apply_spell(main.Sp.GROW)
	await _wait(120)
	await _snap("11_multiball")
	for lv in [9, 34, 57, 99]:
		main.level = lv
		main._begin_level()
		await _wait(5)
		await _snap("12_level%d" % (lv + 1))
	main._pause()
	await _wait(5)
	await _snap("13_pause")
	main.phase = main.Phase.PLAY
	autoplay = false
	main.go(main.Screen.SCORES)
	await _wait(5)
	await _snap("14_scores")
	main.score = 999999
	main.go(main.Screen.NAME_ENTRY)
	await _wait(5)
	await _snap("15_name_entry")
	main._play_cutscenes([main.CUT_WORLD], main.Screen.MENU)
	await _wait(300)
	await _snap("16_world_cutscene")
	get_tree().quit()
