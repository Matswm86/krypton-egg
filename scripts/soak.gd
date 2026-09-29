extends Node
## Soak test, active only with `-- --soak <first level> <levels>`: plays levels
## with an autopilot racket at 10x speed and prints progress per level.

var main: Node
var first := 0
var count := 3
var level_t := 0.0
var last_remaining := -1
var stall := 0.0


func start(owner_main: Node, a: int, n: int) -> void:
	main = owner_main
	first = a
	count = n
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 60
	main.level = first
	main.lives = 99
	main.screen = main.Screen.GAME
	main._begin_level()


func _physics_process(delta: float) -> void:
	if main.screen != main.Screen.GAME:
		print("SOAK left game screen at level ", main.level + 1)
		get_tree().quit()
		return
	level_t += delta
	if not main.balls.is_empty():
		var lowest: Dictionary = main.balls[0]
		for b in main.balls:
			if b["p"].y > lowest["p"].y and b["v"].y > 0:
				lowest = b
		main._move_rack(clampf(lowest["p"].x - main.rack_x + randf_range(-6, 6), -30.0, 30.0), 0.0)
	if main.phase == main.Phase.READY and main.phase_t > 0.5:
		main._action()
	for b in main.balls:
		if b["stuck"] and main.phase == main.Phase.PLAY:
			main._action()
			break
	if main.remaining != last_remaining:
		last_remaining = main.remaining
		stall = 0.0
	else:
		stall += delta
	if main.level >= first + count or stall > 180.0:
		print(
			(
				"SOAK end level=%d remaining=%d lives=%d score=%d stall=%.0f"
				% [main.level + 1, main.remaining, main.lives, main.score, stall]
			)
		)
		get_tree().quit()
	if int(level_t) % 30 == 0 and int(level_t - delta) % 30 != 0:
		print(
			(
				"t=%4.0f level=%d remaining=%d lives=%d balls=%d ball=%s"
				% [
					level_t,
					main.level + 1,
					main.remaining,
					main.lives,
					main.balls.size(),
					str(main.balls[0] if main.balls.size() else "-")
				]
			)
		)
