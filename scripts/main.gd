extends Node2D
## Krypton Egg (C2V, 1996 Windows CD release) remade for Android in Godot.
##
## Every picture, sprite, sample, cutscene and all 100 levels come from the
## original KE.RSC, baked by tools/carve_cd.py + tools/bake_assets.py. The
## game runs on the original 320x200 screen with the original coordinates:
## an 18x16 grid of 16x8 brick cells starting at (16, 24), wooden walls at
## x < 16 and x >= 304, a monster door in the top bar at x = 144.

const Atlas = preload("res://scripts/atlas_data.gd")
const FliPlayer = preload("res://scripts/fli_player.gd")
const FLI_SHADER = preload("res://scripts/fli_palette.gdshader")

const W := 320.0
const H := 200.0
const FIELD_L := 16.0
const FIELD_R := 304.0
const FIELD_T := 24.0
const COLS := 18
const ROWS := 16
const CELL_W := 16.0
const CELL_H := 8.0
const RACK_Y := 182.0
const FLY_TOP := 120.0
const LEVEL_SIZE := 586
const LEVEL_COUNT := 100
const START_LIVES := 3
const MAX_BALLS := 8
const BASE_SPEED := 120.0
const TOUCH_GAIN := 1.25
const TAP_MAX_MOVE := 6.0
const SAVE_PATH := "user://krypton_egg.cfg"
const MAX_SCORES := 5
const DOOR_X := 144.0
const GLUE_HOLD := 3.0
# Metal bricks give way after this many hits so no stage can lock up.
const METAL_HITS := 6

enum Screen { CUTSCENE, PRESENTS, TITLE, MENU, WORLDS, INFO, SCORES, GAME, NAME_ENTRY }
enum Phase { READY, PLAY, DYING, CLEARED, OVER, PAUSED }
enum Sp {
	GROW,
	SHRINK,
	GLUE,
	MULTI,
	BIG,
	FIRE,
	LASER,
	CANNON,
	SLOW,
	FAST,
	FROZEN,
	SHIELD,
	DYNAMITE,
	FLY,
	MYSTERY,
	LIFE,
	REVERSE,
	SMALL
}

# Falling icon frame range per spell, from the original KE_SPELL bank.
const SPELL_ICONS := [
	[62, 66],
	[71, 75],
	[38, 39],
	[53, 53],
	[70, 70],
	[33, 33],
	[54, 55],
	[32, 32],
	[68, 68],
	[69, 69],
	[50, 52],
	[34, 34],
	[81, 83],
	[57, 61],
	[36, 36],
	[35, 35],
	[49, 49],
	[44, 44],
]
const SPELL_NAMES := [
	"LONGER RACKET",
	"SHORTER RACKET",
	"GLUE",
	"MULTIPLE BALL",
	"BIGGER BALL",
	"FIRE BALL",
	"LASER",
	"CANNON",
	"SLOW BALL",
	"FAST BALL",
	"FROZEN TRAY",
	"SHIELD",
	"DYNAMITE",
	"FLY",
	"MYSTERY",
	"EXTRA RACKET",
	"REVERSED",
	"SMALL BALL",
]
const BAD_SPELLS := [Sp.SHRINK, Sp.FAST, Sp.FROZEN, Sp.REVERSE, Sp.SMALL]
const SPELL_TIME := 15.0
# Monster types 1..7 from the level header -> KE_NMY animation frames. Type 7 is
# the picus vulgarus, the only monster that kills an unshielded racket.
const MONSTER_FRAMES := {
	1: [5, 7], 2: [8, 10], 3: [11, 13], 4: [14, 16], 5: [17, 22], 6: [23, 30], 7: [2, 4]
}
const PICUS := 7
const EXPLOSION := [34, 45]
const DOOR_FRAMES := [52, 63]
# Background tiles from KE_FILL; tile 7 is the teal bevel of the Windows screenshots.
const FLOOR_TILES := [
	7, 6, 8, 10, 22, 25, 28, 21, 13, 23, 38, 9, 11, 15, 24, 27, 37, 41, 44, 45, 46
]
# Cutscenes (index into assets/fli) and the CD music that plays with each.
const CUT_LOGO := [6, "present3"]
const CUT_INTRO := [0, "kepres"]
const CUT_START := [1, "kelvlin"]
const CUT_WORLD := [2, "kelvlout"]
const CUT_END := [5, "kemstouw"]

# Menu hit rectangles on the menu picture.
const BTN_PLAY := Rect2(92, 66, 128, 25)
const BTN_SCORES := Rect2(92, 106, 128, 25)
const BTN_INFO := Rect2(92, 146, 128, 25)

var tex := {}
var sfx_cache := {}
var sfx_players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var levels := PackedByteArray()
var screen := Screen.CUTSCENE
var t := 0.0

# Cutscene state.
var fli: FliPlayer
var fli_sprite: Sprite2D
var cut_queue: Array = []
var cut_after := Screen.TITLE

# Game state.
var phase := Phase.READY
var phase_t := 0.0
var level := 0
var score := 0
var lives := START_LIVES
var bricks := PackedInt32Array()
var spells := PackedInt32Array()
var stone_hits := PackedInt32Array()
var remaining := 0
var level_speed := 1.0
var balls: Array = []
var rack_x := 160.0
var rack_y := RACK_Y
var rack_len := 5
var rack_vel := 0.0
var effects := {}
var shields := 0
var drops: Array = []
var shots: Array = []
var monsters: Array = []
var blasts: Array = []
var monster_types: Array = []
var monster_timer := 0.0
var door_t := -1.0
var shot_cool := 0.0
var speed_ramp := 1.0
var banner := ""
var banner_t := 0.0

# Input.
var touch_down := false
var touch_moved := 0.0
var touch_start := Vector2.ZERO
var keys_x := 0.0

# Persistence.
var high_scores: Array = []
var best_world := 0
var name_edit: LineEdit
var name_layer: CanvasLayer
var info_page := 0


func _ready() -> void:
	randomize()
	for key in Atlas.BANKS:
		tex[key] = load("res://assets/gfx/%s.png" % key)
	for pic in ["title", "menu", "score", "presents", "monst"]:
		tex["pic_" + pic] = load("res://assets/gfx/pic_%s.png" % pic)
	levels = FileAccess.get_file_as_bytes("res://assets/levels/ke.lvl.bin")
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	fli_sprite = Sprite2D.new()
	fli_sprite.centered = false
	var mat := ShaderMaterial.new()
	mat.shader = FLI_SHADER
	fli_sprite.material = mat
	fli_sprite.visible = false
	add_child(fli_sprite)
	_build_name_entry()
	_load_save()
	get_tree().set_auto_accept_quit(false)
	var args := OS.get_cmdline_user_args()
	var soak_at := args.find("--soak")
	if soak_at >= 0 and soak_at + 2 < args.size():
		var soak: Node = load("res://scripts/soak.gd").new()
		add_child(soak)
		soak.start(self, int(args[soak_at + 1]), int(args[soak_at + 2]))
		return
	var shots_at := args.find("--shots")
	if shots_at >= 0 and shots_at + 1 < args.size():
		var driver: Node = load("res://scripts/shots.gd").new()
		add_child(driver)
		driver.start(self, args[shots_at + 1])
		return
	_play_cutscenes([CUT_LOGO], Screen.PRESENTS)


# ---------------------------------------------------------------- audio


func _stream(name: String) -> AudioStreamWAV:
	if not sfx_cache.has(name):
		sfx_cache[name] = load("res://assets/sfx/%s.wav" % name)
	return sfx_cache[name]


func sfx(name: String) -> void:
	var s := _stream(name)
	if s == null:
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = s
			p.play()
			return
	sfx_players[0].stream = s
	sfx_players[0].play()


func play_music(name: String, loop: bool) -> void:
	var s: AudioStreamWAV = _stream(name).duplicate()
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	else:
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	music.stream = s
	music.play()


func stop_music() -> void:
	music.stop()


# ---------------------------------------------------------------- screens


func go(to: int) -> void:
	screen = to
	t = 0.0
	fli_sprite.visible = false
	name_layer.visible = false
	match to:
		Screen.PRESENTS:
			sfx("present3")
		Screen.TITLE:
			play_music("ke_tit", false)
		Screen.MENU:
			play_music("ke_menu", true)
		Screen.WORLDS:
			pass
		Screen.INFO:
			info_page = 0
			play_music("ke_infos", true)
		Screen.SCORES:
			play_music("ke_score", true)
		Screen.NAME_ENTRY:
			play_music("ke_score", true)
			name_layer.visible = true
			name_edit.text = ""
			name_edit.grab_focus()
			DisplayServer.virtual_keyboard_show("")
	queue_redraw()


func _play_cutscenes(list: Array, after: int) -> void:
	cut_queue = list.duplicate()
	cut_after = after
	_next_cutscene()


func _next_cutscene() -> void:
	if cut_queue.is_empty():
		stop_music()
		fli_sprite.visible = false
		if cut_after == Screen.GAME:
			screen = Screen.GAME
			_begin_level()
		else:
			go(cut_after)
		return
	name_layer.visible = false
	var cut: Array = cut_queue.pop_front()
	fli = FliPlayer.new()
	if not fli.open("res://assets/fli/%02d.fli.bin" % cut[0]):
		_next_cutscene()
		return
	screen = Screen.CUTSCENE
	t = 0.0
	fli_sprite.texture = fli.index_tex
	(fli_sprite.material as ShaderMaterial).set_shader_parameter("palette", fli.pal_tex)
	fli_sprite.visible = true
	play_music(cut[1], false)


func _skip() -> void:
	if screen == Screen.CUTSCENE:
		_next_cutscene()


# ---------------------------------------------------------------- persistence


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_scores = cfg.get_value("scores", "table", [])
		best_world = int(cfg.get_value("progress", "best_world", 0))
	if high_scores.is_empty():
		for i in MAX_SCORES:
			high_scores.append(["C2V", 5000 - i * 1000, 1])


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "table", high_scores)
	cfg.set_value("progress", "best_world", best_world)
	cfg.save(SAVE_PATH)


func _qualifies() -> bool:
	return score > int(high_scores[high_scores.size() - 1][1])


func _build_name_entry() -> void:
	name_layer = CanvasLayer.new()
	add_child(name_layer)
	name_edit = LineEdit.new()
	name_edit.max_length = 8
	name_edit.placeholder_text = "YOUR NAME"
	name_edit.position = Vector2(100, 150)
	name_edit.size = Vector2(120, 16)
	name_edit.add_theme_font_size_override("font_size", 10)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text_submitted.connect(_submit_name)
	name_layer.add_child(name_edit)
	name_layer.visible = false


func _submit_name(text: String) -> void:
	var nm := text.strip_edges().to_upper()
	if nm == "":
		nm = "PLAYER"
	high_scores.append([nm, score, level + 1])
	high_scores.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	high_scores.resize(MAX_SCORES)
	_save()
	DisplayServer.virtual_keyboard_hide()
	go(Screen.SCORES)


# ---------------------------------------------------------------- level setup


func _start_game(world: int) -> void:
	level = world * 10
	score = 0
	lives = START_LIVES
	_play_cutscenes([CUT_START], Screen.GAME)


func _cell(lv: int, i: int) -> Vector2i:
	var b := lv * LEVEL_SIZE + 10 + 2 * i
	return Vector2i(levels[b], levels[b + 1])


func _begin_level() -> void:
	bricks.resize(COLS * ROWS)
	spells.resize(COLS * ROWS)
	stone_hits.resize(COLS * ROWS)
	remaining = 0
	for i in COLS * ROWS:
		var c := _cell(level, i)
		bricks[i] = c.y if (c.x or c.y) else -1
		spells[i] = c.x >> 2
		stone_hits[i] = METAL_HITS if bricks[i] >= 0 and _kind(bricks[i]) == "metal" else 2
		if bricks[i] >= 0 and _destructible(bricks[i]):
			remaining += 1
	var base := level * LEVEL_SIZE
	var sp := levels[base] | (levels[base + 1] << 8)
	if sp < 150:
		sp = 400
	level_speed = clampf(500.0 / sp, 1.0, 1.6)
	monster_types = []
	for k in 8:
		var m := levels[base + 2 + k]
		if m > 0:
			monster_types.append(m)
	monster_timer = 6.0
	monsters.clear()
	drops.clear()
	shots.clear()
	blasts.clear()
	banner = "LEVEL %d" % (level + 1)
	banner_t = 2.5
	sfx("ke_lvl")
	_new_racket()


func _new_racket() -> void:
	rack_x = 160.0
	rack_y = RACK_Y
	rack_len = 5
	effects.clear()
	speed_ramp = 1.0
	balls = [_ball(Vector2(rack_x, rack_y - 6), Vector2.ZERO, true)]
	phase = Phase.READY
	phase_t = 0.0
	sfx("kerakbir")


func _ball(p: Vector2, v: Vector2, stuck: bool) -> Dictionary:
	return {"p": p, "v": v, "stuck": stuck, "off": 0.0, "held": 0.0}


# ---------------------------------------------------------------- bricks


## Brick classes by KE_BRICK sprite index. "armor" bricks carry 1-3 blue plus
## marks and lose one per hit; "framed" bricks lose the frame on the first hit
## and show the matching plain brick; the grey and greek-key frames are metal,
## which does not count toward clearing the stage.
func _kind(b: int) -> String:
	if b >= 48 and b < 96:
		return "armor"
	if b >= 176 and b < 191:
		return "metal"
	if (b >= 144 and b < 224 and b != 175 and b != 191) or (b >= 240 and b < 244):
		return "framed"
	if b >= 224 and b < 240:
		return "stone"
	if b >= 244 and b < 249:
		return "bomb"
	return "normal"


func _destructible(b: int) -> bool:
	return _kind(b) != "metal"


func _cell_rect(i: int) -> Rect2:
	return Rect2(FIELD_L + (i % COLS) * CELL_W, FIELD_T + (i / COLS) * CELL_H, CELL_W, CELL_H)


func _hit_brick(i: int, fire: bool) -> void:
	var b := bricks[i]
	if b < 0:
		return
	match _kind(b):
		"metal":
			stone_hits[i] -= 1
			if stone_hits[i] <= 0:
				bricks[i] = -1
				score += 50
				sfx("kebrea0%d" % (randi() % 6 + 1))
			else:
				sfx("kemeta0%d" % (randi() % 4 + 1))
		"armor":
			if fire:
				_destroy(i)
			else:
				bricks[i] = b - 16 if b >= 64 else b - 48
				score += 5
				sfx("kemeta0%d" % (randi() % 4 + 1))
		"framed":
			if fire:
				_destroy(i)
			else:
				bricks[i] = _unframed(b)
				score += 5
				sfx("kemeta0%d" % (randi() % 4 + 1))
		"stone":
			stone_hits[i] -= 1
			if stone_hits[i] <= 0 or fire:
				_destroy(i)
			else:
				bricks[i] = 231
				sfx("kemeta0%d" % (randi() % 4 + 1))
		"bomb":
			_destroy(i)
			_explode_around(i)
		_:
			_destroy(i)


func _unframed(b: int) -> int:
	if b >= 240:
		return [5, 13, 15, 8][b - 240]
	if b >= 208:
		return b - 112
	if b >= 192:
		return b - 192
	if b >= 160:
		return b - 64
	return b - 144


func _destroy(i: int) -> void:
	var b := bricks[i]
	if b < 0:
		return
	bricks[i] = -1
	remaining -= 1
	score += 10 + level
	sfx("kebrea0%d" % (randi() % 6 + 1))
	var sp := spells[i]
	var drop := -1
	if sp == 8:
		if randf() < 0.12:
			drop = randi() % SPELL_ICONS.size()
	elif sp > 0:
		drop = (sp - 1) % SPELL_ICONS.size()
	if drop >= 0:
		drops.append({"p": _cell_rect(i).get_center(), "s": drop, "t": 0.0})


func _explode_around(i: int) -> void:
	var cx := i % COLS
	var cy := i / COLS
	blasts.append(
		{
			"p": _cell_rect(i).get_center(),
			"t": 0.0,
			"bank": "nmy",
			"a": EXPLOSION[0],
			"b": EXPLOSION[1]
		}
	)
	sfx("kespldyn")
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= COLS or y < 0 or y >= ROWS:
				continue
			var j := y * COLS + x
			if bricks[j] >= 0 and _destructible(bricks[j]):
				if _kind(bricks[j]) == "bomb":
					bricks[j] = 0
					_destroy(j)
					_explode_around(j)
				else:
					_destroy(j)


func _bricks_hit(r: Rect2) -> Array:
	var out := []
	var x0 := int(floor((r.position.x - FIELD_L) / CELL_W))
	var x1 := int(floor((r.end.x - FIELD_L) / CELL_W))
	var y0 := int(floor((r.position.y - FIELD_T) / CELL_H))
	var y1 := int(floor((r.end.y - FIELD_T) / CELL_H))
	for y in range(maxi(y0, 0), mini(y1, ROWS - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, COLS - 1) + 1):
			if bricks[y * COLS + x] >= 0:
				out.append(y * COLS + x)
	return out


# ---------------------------------------------------------------- racket


func _rack_sprite() -> int:
	return 6 + rack_len


func _rack_w() -> float:
	return float(Atlas.BANKS["rack"][_rack_sprite()][2])


func _ball_r(_b: Dictionary) -> float:
	if effects.has(Sp.BIG):
		return 5.0
	if effects.has(Sp.SMALL):
		return 2.5
	return 3.5


func _ball_speed() -> float:
	var s := BASE_SPEED * level_speed * speed_ramp
	if effects.has(Sp.SLOW):
		s *= 0.7
	if effects.has(Sp.FAST):
		s *= 1.3
	return s


func _launch(b: Dictionary) -> void:
	b["stuck"] = false
	var ang := deg_to_rad(randf_range(-25.0, 25.0) + clampf(b["off"] * 2.0, -30.0, 30.0))
	b["v"] = Vector2(sin(ang), -cos(ang)) * _ball_speed()
	sfx("kebncrak")


func _action() -> void:
	if screen != Screen.GAME:
		return
	if phase == Phase.PAUSED:
		phase = Phase.PLAY
		stop_music()
		return
	if phase == Phase.READY or phase == Phase.PLAY:
		var any_stuck := false
		for b in balls:
			if b["stuck"]:
				_launch(b)
				any_stuck = true
		if any_stuck:
			phase = Phase.PLAY
			return
		if shot_cool <= 0.0 and (effects.has(Sp.LASER) or effects.has(Sp.CANNON)):
			var hw := _rack_w() * 0.5 - 3.0
			if effects.has(Sp.CANNON):
				shots.append({"p": Vector2(rack_x, rack_y - 8), "big": true})
				sfx("kefirdbl")
			else:
				shots.append({"p": Vector2(rack_x - hw, rack_y - 6), "big": false})
				shots.append({"p": Vector2(rack_x + hw, rack_y - 6), "big": false})
				sfx("kefirsgl")
			shot_cool = 0.3


func _move_rack(dx: float, dy: float) -> void:
	if effects.has(Sp.FROZEN):
		return
	if effects.has(Sp.REVERSE):
		dx = -dx
	var hw := _rack_w() * 0.5
	var old := rack_x
	rack_x = clampf(rack_x + dx, FIELD_L + hw, FIELD_R - hw)
	rack_vel = (rack_x - old) * 60.0
	if effects.has(Sp.FLY):
		rack_y = clampf(rack_y + dy, FLY_TOP, RACK_Y)


# ---------------------------------------------------------------- spells


func _apply_spell(s: int) -> void:
	if s == Sp.MYSTERY:
		s = randi() % SPELL_ICONS.size()
		if s == Sp.MYSTERY:
			s = Sp.LIFE
	sfx("kesplbad" if s in BAD_SPELLS else "kesplgod")
	score += 50
	match s:
		Sp.GROW:
			rack_len = mini(rack_len + 2, 14)
			sfx("kesplplu")
		Sp.SHRINK:
			rack_len = maxi(rack_len - 2, 0)
			sfx("kesplmin")
		Sp.GLUE:
			effects[Sp.GLUE] = SPELL_TIME
			sfx("kesplglu")
		Sp.MULTI:
			var extra := []
			for b in balls:
				if b["stuck"]:
					continue
				for k in [-1, 1]:
					if balls.size() + extra.size() >= MAX_BALLS:
						break
					extra.append(
						_ball(b["p"], (b["v"] as Vector2).rotated(deg_to_rad(25.0 * k)), false)
					)
			balls.append_array(extra)
			sfx("kesplcre")
		Sp.BIG:
			effects.erase(Sp.SMALL)
			effects[Sp.BIG] = SPELL_TIME
		Sp.SMALL:
			effects.erase(Sp.BIG)
			effects[Sp.SMALL] = SPELL_TIME
		Sp.FIRE:
			effects[Sp.FIRE] = SPELL_TIME * 0.6
		Sp.LASER:
			effects.erase(Sp.CANNON)
			effects[Sp.LASER] = SPELL_TIME
		Sp.CANNON:
			effects.erase(Sp.LASER)
			effects[Sp.CANNON] = SPELL_TIME
		Sp.SLOW:
			effects.erase(Sp.FAST)
			effects[Sp.SLOW] = SPELL_TIME
		Sp.FAST:
			effects.erase(Sp.SLOW)
			effects[Sp.FAST] = SPELL_TIME * 0.6
		Sp.FROZEN:
			effects[Sp.FROZEN] = 3.0
			sfx("kespljao")
		Sp.SHIELD:
			shields += 1
		Sp.DYNAMITE:
			var picks := []
			for i in bricks.size():
				if bricks[i] >= 0 and _destructible(bricks[i]):
					picks.append(i)
			picks.shuffle()
			for k in mini(3, picks.size()):
				if bricks[picks[k]] >= 0:
					_destroy(picks[k])
					_explode_around(picks[k])
		Sp.FLY:
			effects[Sp.FLY] = SPELL_TIME
			sfx("kesplfly")
		Sp.LIFE:
			lives = mini(lives + 1, 99)
		Sp.REVERSE:
			effects[Sp.REVERSE] = 8.0
	_rescale_balls()


func _rescale_balls() -> void:
	var s := _ball_speed()
	for b in balls:
		if not b["stuck"]:
			b["v"] = (b["v"] as Vector2).normalized() * s


# ---------------------------------------------------------------- game tick


func _physics_process(delta: float) -> void:
	t += delta
	match screen:
		Screen.CUTSCENE:
			if fli and not fli.advance(delta):
				_next_cutscene()
		Screen.PRESENTS:
			if t > 3.5:
				_play_cutscenes([CUT_INTRO], Screen.TITLE)
		Screen.GAME:
			_game_tick(delta)
	queue_redraw()


func _game_tick(dt: float) -> void:
	phase_t += dt
	if banner_t > 0.0:
		banner_t -= dt
	if keys_x != 0.0:
		_move_rack(keys_x * 180.0 * dt, 0.0)
	match phase:
		Phase.PAUSED, Phase.OVER:
			return
		Phase.DYING:
			_tick_blasts(dt)
			if phase_t > 1.6:
				if lives <= 0:
					_game_over()
				else:
					_new_racket()
			return
		Phase.CLEARED:
			_tick_blasts(dt)
			if phase_t > 2.0:
				_level_done()
			return
	for k in effects.keys():
		effects[k] -= dt
		if effects[k] <= 0.0:
			effects.erase(k)
			if k in [Sp.SLOW, Sp.FAST]:
				_rescale_balls()
	shot_cool -= dt
	if phase == Phase.PLAY:
		speed_ramp = minf(speed_ramp + dt * 0.004, 1.35)
	_tick_balls(dt)
	_tick_drops(dt)
	_tick_shots(dt)
	_tick_monsters(dt)
	_tick_blasts(dt)
	rack_vel *= 0.8
	if remaining <= 0:
		phase = Phase.CLEARED
		phase_t = 0.0
		banner = "WELL DONE"
		banner_t = 2.0
		score += 1000
		sfx("kesplgod")
	elif balls.is_empty():
		_lose_racket()


func _tick_balls(dt: float) -> void:
	var speed := _ball_speed()
	var fire := effects.has(Sp.FIRE)
	var lost := []
	for b in balls:
		if b["stuck"]:
			b["p"] = Vector2(rack_x + b["off"], rack_y - 6)
			# A glued ball lets go by itself after GLUE_HOLD seconds.
			if phase == Phase.PLAY:
				b["held"] += dt
				if b["held"] > GLUE_HOLD:
					_launch(b)
			continue
		var r := _ball_r(b)
		var v: Vector2 = b["v"]
		var p: Vector2 = b["p"]
		var steps := int(ceil(v.length() * dt / 1.5))
		var sdt := dt / maxf(steps, 1)
		for _s in steps:
			# X axis.
			p.x += v.x * sdt
			if p.x < FIELD_L + r:
				p.x = FIELD_L + r
				v.x = absf(v.x)
				sfx("kebncwal")
			elif p.x > FIELD_R - r:
				p.x = FIELD_R - r
				v.x = -absf(v.x)
				sfx("kebncwal")
			var hits := _bricks_hit(Rect2(p.x - r, p.y - r, 2 * r, 2 * r))
			if not hits.is_empty():
				var solid := false
				for i in hits:
					if not fire or _kind(bricks[i]) == "metal":
						solid = true
					_hit_brick(i, fire)
				if solid:
					p.x -= v.x * sdt
					v.x = -v.x
			# Y axis.
			p.y += v.y * sdt
			if p.y < FIELD_T + r:
				p.y = FIELD_T + r
				v.y = absf(v.y)
				sfx("kebncwal")
			hits = _bricks_hit(Rect2(p.x - r, p.y - r, 2 * r, 2 * r))
			if not hits.is_empty():
				var solid := false
				for i in hits:
					if not fire or _kind(bricks[i]) == "metal":
						solid = true
					_hit_brick(i, fire)
				if solid:
					p.y -= v.y * sdt
					v.y = -v.y
			# Racket.
			var hw := _rack_w() * 0.5
			if (
				v.y > 0.0
				and p.y + r >= rack_y - 4.0
				and p.y - r <= rack_y + 2.0
				and absf(p.x - rack_x) <= hw + r
			):
				var rel := clampf((p.x - rack_x) / hw, -1.0, 1.0)
				var ang := deg_to_rad(rel * 62.0)
				v = Vector2(sin(ang), -cos(ang)) * speed
				v.x += rack_vel * 0.12
				v = v.normalized() * speed
				p.y = rack_y - 4.0 - r
				if effects.has(Sp.GLUE):
					b["stuck"] = true
					b["held"] = 0.0
					b["off"] = p.x - rack_x
					sfx("kesplglu")
					break
				sfx("kebncrak")
			# Monsters.
			for m in monsters:
				if m["state"] == "alive" and p.distance_to(m["p"]) < r + 8.0:
					_kill_monster(m, 100)
					v.y = -v.y
		if b["stuck"]:
			continue
		# Keep the ball from travelling almost horizontally forever.
		if absf(v.y) < speed * 0.25:
			v.y = signf(v.y if v.y != 0.0 else -1.0) * speed * 0.25
			v = v.normalized() * speed
		b["v"] = v.normalized() * speed
		b["p"] = p
		if p.y > H + 8.0:
			lost.append(b)
	for b in lost:
		balls.erase(b)


func _tick_drops(dt: float) -> void:
	var gone := []
	var hw := _rack_w() * 0.5
	for d in drops:
		d["t"] += dt
		d["p"].y += 40.0 * dt
		var p: Vector2 = d["p"]
		if absf(p.y - rack_y) < 8.0 and absf(p.x - rack_x) < hw + 6.0:
			_apply_spell(d["s"])
			banner = SPELL_NAMES[d["s"]]
			banner_t = 1.2
			gone.append(d)
		elif p.y > H + 12.0:
			gone.append(d)
	for d in gone:
		drops.erase(d)


func _tick_shots(dt: float) -> void:
	var gone := []
	for s in shots:
		s["p"].y -= 220.0 * dt
		var p: Vector2 = s["p"]
		var w := 6.0 if s["big"] else 2.0
		var hits := _bricks_hit(Rect2(p.x - w * 0.5, p.y - 3.0, w, 6.0))
		var hit_m := false
		for m in monsters:
			if m["state"] == "alive" and p.distance_to(m["p"]) < 10.0:
				_kill_monster(m, 100)
				hit_m = true
		if not hits.is_empty() or hit_m or p.y < FIELD_T:
			for i in hits:
				if s["big"] and bricks[i] >= 0 and _destructible(bricks[i]):
					_destroy(i)
				else:
					_hit_brick(i, false)
			gone.append(s)
	for s in gone:
		shots.erase(s)


func _tick_monsters(dt: float) -> void:
	if phase != Phase.PLAY or monster_types.is_empty():
		return
	monster_timer -= dt
	var alive := 0
	for m in monsters:
		if m["state"] != "dead":
			alive += 1
	if monster_timer <= 0.0 and alive < 3:
		monster_timer = randf_range(7.0, 11.0)
		door_t = 0.0
		sfx("kenmycre")
		var ty: int = monster_types[randi() % monster_types.size()]
		monsters.append(
			{
				"p": Vector2(DOOR_X + 16, FIELD_T + 4),
				"v": Vector2(randf_range(-30, 30), randf_range(18, 30)),
				"type": ty,
				"t": 0.0,
				"state": "alive"
			}
		)
	if door_t >= 0.0:
		door_t += dt
		if door_t > 0.8:
			door_t = -1.0
	var hw := _rack_w() * 0.5
	var dead := []
	for m in monsters:
		m["t"] += dt
		if m["state"] == "dying":
			if m["t"] > 0.6:
				dead.append(m)
			continue
		var v: Vector2 = m["v"]
		var p: Vector2 = m["p"] + v * dt + Vector2(sin(m["t"] * 2.3) * 0.6, 0)
		if p.x < FIELD_L + 10 or p.x > FIELD_R - 10:
			v.x = -v.x
		if p.y < FIELD_T + 8 or p.y > RACK_Y - 4:
			v.y = -v.y
		if randf() < dt * 0.4:
			v = v.rotated(randf_range(-0.8, 0.8))
		p.x = clampf(p.x, FIELD_L + 10, FIELD_R - 10)
		p.y = clampf(p.y, FIELD_T + 8, RACK_Y - 4)
		m["v"] = v
		m["p"] = p
		if absf(p.y - rack_y) < 10.0 and absf(p.x - rack_x) < hw + 6.0:
			if m["type"] == PICUS and shields <= 0:
				_kill_monster(m, 0)
				_lose_racket()
				return
			if m["type"] == PICUS:
				shields -= 1
			_kill_monster(m, 50)
	for m in dead:
		monsters.erase(m)


func _kill_monster(m: Dictionary, pts: int) -> void:
	m["state"] = "dying"
	m["t"] = 0.0
	score += pts
	sfx("kenmydet")


func _tick_blasts(dt: float) -> void:
	var gone := []
	for bl in blasts:
		bl["t"] += dt
		if bl["t"] > 0.6:
			gone.append(bl)
	for bl in gone:
		blasts.erase(bl)


func _lose_racket() -> void:
	if phase == Phase.DYING:
		return
	phase = Phase.DYING
	phase_t = 0.0
	lives -= 1
	balls.clear()
	drops.clear()
	shots.clear()
	blasts.append(
		{
			"p": Vector2(rack_x, rack_y),
			"t": 0.0,
			"bank": "nmy",
			"a": EXPLOSION[0],
			"b": EXPLOSION[1]
		}
	)
	sfx("kerakdet")


func _level_done() -> void:
	level += 1
	if level >= LEVEL_COUNT:
		_play_cutscenes([CUT_END], Screen.NAME_ENTRY if _qualifies() else Screen.SCORES)
		return
	if level % 10 == 0:
		best_world = maxi(best_world, level / 10)
		_save()
		_play_cutscenes([CUT_WORLD], Screen.GAME)
		return
	_begin_level()


func _game_over() -> void:
	phase = Phase.OVER
	banner = "GAME OVER"
	banner_t = 99.0
	play_music("ke_go", false)
	await get_tree().create_timer(3.0).timeout
	if screen == Screen.GAME:
		go(Screen.NAME_ENTRY if _qualifies() else Screen.SCORES)


# ---------------------------------------------------------------- input


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST:
			_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_pause()


func _pause() -> void:
	if screen == Screen.GAME and (phase == Phase.PLAY or phase == Phase.READY):
		phase = Phase.PAUSED
		play_music("ke_pause", true)


func _back() -> void:
	match screen:
		Screen.MENU:
			get_tree().quit()
		Screen.GAME:
			if phase == Phase.PAUSED:
				stop_music()
				go(Screen.MENU)
			else:
				_pause()
		Screen.CUTSCENE:
			_skip()
		_:
			go(Screen.MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			touch_down = true
			touch_moved = 0.0
			touch_start = e.position
		else:
			touch_down = false
			if touch_moved < TAP_MAX_MOVE:
				_tap(e.position)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		touch_moved += e.relative.length()
		if screen == Screen.GAME and phase != Phase.PAUSED:
			_move_rack(e.relative.x * TOUCH_GAIN, e.relative.y * TOUCH_GAIN)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_LEFT:
			keys_x = -1.0 if k.pressed else 0.0
		elif k.keycode == KEY_RIGHT:
			keys_x = 1.0 if k.pressed else 0.0
		elif k.pressed and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER):
			_tap(Vector2(W * 0.5, H * 0.5))
		elif k.pressed and k.keycode == KEY_ESCAPE:
			_back()


func _tap(p: Vector2) -> void:
	match screen:
		Screen.CUTSCENE:
			_skip()
		Screen.PRESENTS:
			_play_cutscenes([CUT_INTRO], Screen.TITLE)
		Screen.TITLE:
			go(Screen.MENU)
		Screen.MENU:
			if BTN_PLAY.has_point(p):
				sfx("kebncspe")
				if best_world > 0:
					go(Screen.WORLDS)
				else:
					_start_game(0)
			elif BTN_SCORES.has_point(p):
				sfx("kebncspe")
				go(Screen.SCORES)
			elif BTN_INFO.has_point(p):
				sfx("kebncspe")
				go(Screen.INFO)
		Screen.WORLDS:
			var idx := int((p.y - 50.0) / 14.0)
			if idx >= 0 and idx <= best_world and idx < 10:
				_start_game(idx)
		Screen.INFO:
			info_page += 1
			if info_page >= _info_pages().size():
				go(Screen.MENU)
		Screen.SCORES:
			go(Screen.MENU)
		Screen.GAME:
			_action()


# ---------------------------------------------------------------- drawing


func spr(bank: String, i: int, center: Vector2, mod := Color.WHITE) -> void:
	var r: Array = Atlas.BANKS[bank][i]
	var tl := Vector2(roundf(center.x - r[2] * 0.5), roundf(center.y - r[3] * 0.5))
	draw_texture_rect_region(
		tex[bank], Rect2(tl, Vector2(r[2], r[3])), Rect2(r[0], r[1], r[2], r[3]), mod
	)


func spr_tl(bank: String, i: int, tl: Vector2) -> void:
	var r: Array = Atlas.BANKS[bank][i]
	draw_texture_rect_region(
		tex[bank], Rect2(tl, Vector2(r[2], r[3])), Rect2(r[0], r[1], r[2], r[3])
	)


func text_w(s: String) -> float:
	var w := 0.0
	for ch in s:
		var idx := ch.unicode_at(0) - 33
		if idx < 0 or idx >= 94:
			w += 6.0
		else:
			var r: Array = Atlas.BANKS["infos"][idx]
			w += maxf(r[4] + r[2], 5.0) + 1.0
	return w


func text(s: String, pos: Vector2, centered := false, mod := Color.WHITE) -> void:
	var x := pos.x - (text_w(s) * 0.5 if centered else 0.0)
	for ch in s:
		var idx := ch.unicode_at(0) - 33
		if idx < 0 or idx >= 94:
			x += 6.0
			continue
		var r: Array = Atlas.BANKS["infos"][idx]
		draw_texture_rect_region(
			tex["infos"],
			Rect2(roundf(x + r[4]), pos.y + r[5], r[2], r[3]),
			Rect2(r[0], r[1], r[2], r[3]),
			mod
		)
		x += maxf(r[4] + r[2], 5.0) + 1.0


func digits(value: int, count: int, tl: Vector2) -> void:
	var s := str(clampi(value, 0, int(pow(10, count)) - 1)).pad_zeros(count)
	for k in count:
		spr_tl("digit", int(s[k]), tl + Vector2(8 * k, 0))


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	match screen:
		Screen.CUTSCENE:
			pass
		Screen.PRESENTS:
			var pic: Texture2D = tex["pic_presents"]
			draw_texture_rect(pic, Rect2((W - 267.0) * 0.5, 0, 267, 200), false)
		Screen.TITLE:
			var pic: Texture2D = tex["pic_title"]
			var scroll := clampf((t - 1.0) / 5.0, 0.0, 1.0) * 200.0
			draw_texture_rect_region(pic, Rect2(0, 0, W, H), Rect2(0, scroll, W, H))
			if int(t * 2.0) % 2 == 0 and t > 6.0:
				text("TOUCH TO START", Vector2(W * 0.5, 184), true)
		Screen.MENU:
			draw_texture(tex["pic_menu"], Vector2.ZERO)
			var seq := [15, 16, 18, 20, 22, 24, 22, 20, 18, 16, 15, 31, 33, 35, 37, 35, 33, 31]
			spr("menu", seq[int(t * 14.0) % seq.size()], Vector2(160, 50))
		Screen.WORLDS:
			draw_texture(tex["pic_menu"], Vector2.ZERO)
			draw_rect(Rect2(40, 20, 240, 172), Color(0, 0, 0, 0.8))
			text("CHOOSE A WORLD", Vector2(W * 0.5, 28), true)
			for k in mini(best_world + 1, 10):
				text(
					"WORLD %d   LEVEL %d" % [k + 1, k * 10 + 1], Vector2(W * 0.5, 50 + 14 * k), true
				)
		Screen.INFO:
			var lines: Array = _info_pages()[info_page]
			for k in lines.size():
				text(lines[k], Vector2(W * 0.5, 8 + 14 * k), true)
			if info_page == 2 or info_page == 3:
				var first := 0 if info_page == 2 else 9
				for k in range(1, lines.size() - 2):
					var ic: Array = SPELL_ICONS[first + k - 1]
					var x := W * 0.5 - text_w(lines[k]) * 0.5 - 20.0
					spr(
						"spell", ic[0] + int(t * 8.0) % (ic[1] - ic[0] + 1), Vector2(x, 14 + 14 * k)
					)
		Screen.SCORES, Screen.NAME_ENTRY:
			draw_texture(tex["pic_score"], Vector2.ZERO)
			draw_rect(Rect2(30, 26, 260, 100), Color(0, 0, 0, 0.7))
			text("THE BEST WALL BREAKERS", Vector2(W * 0.5, 30), true)
			for k in high_scores.size():
				var row: Array = high_scores[k]
				text("%d  %s" % [k + 1, row[0]], Vector2(50, 50 + 14 * k))
				text(str(row[1]), Vector2(270 - text_w(str(row[1])), 50 + 14 * k))
			if screen == Screen.NAME_ENTRY:
				draw_rect(Rect2(60, 130, 200, 40), Color(0, 0, 0, 0.8))
				text("ENTER YOUR NAME", Vector2(W * 0.5, 133), true)
		Screen.GAME:
			_draw_game()


func _draw_game() -> void:
	var tile: int = FLOOR_TILES[level % FLOOR_TILES.size()]
	var tr: Array = Atlas.BANKS["fill"][tile]
	var y := FIELD_T
	while y < H:
		var x := FIELD_L
		while x < FIELD_R:
			var w := minf(tr[2], FIELD_R - x)
			draw_texture_rect_region(
				tex["fill"], Rect2(x, y, w, tr[3]), Rect2(tr[0], tr[1], w, tr[3])
			)
			x += tr[2]
		y += tr[3]
	spr_tl("fill", 5, Vector2(0, 16))
	spr_tl("bord", 0, Vector2(0, 16))
	spr_tl("bord", 1, Vector2(FIELD_R, 16))
	if door_t >= 0.0:
		var f := DOOR_FRAMES[0] + int(door_t / 0.8 * (DOOR_FRAMES[1] - DOOR_FRAMES[0]))
		spr_tl("nmy", mini(f, DOOR_FRAMES[1]), Vector2(DOOR_X, 16))
	# HUD panels with the digits drawn into their slots.
	spr_tl("fill", 0, Vector2(2, 0))
	spr_tl("fill", 1, Vector2(122, 0))
	spr_tl("fill", 2, Vector2(180, 0))
	digits(score, 6, Vector2(2 + 56, 4))
	digits(lives, 2, Vector2(122 + 37, 4))
	digits(maxi(score, int(high_scores[0][1])), 6, Vector2(180 + 84, 4))
	for i in bricks.size():
		if bricks[i] >= 0:
			spr_tl("brick", bricks[i], _cell_rect(i).position)
	for d in drops:
		var ic: Array = SPELL_ICONS[d["s"]]
		spr("spell", ic[0] + int(d["t"] * 8.0) % (ic[1] - ic[0] + 1), d["p"])
	for m in monsters:
		if m["state"] == "dying":
			spr("nmy", mini(EXPLOSION[0] + int(m["t"] / 0.6 * 11.0), EXPLOSION[1]), m["p"])
		else:
			var fr: Array = MONSTER_FRAMES[m["type"]]
			spr("nmy", fr[0] + int(m["t"] * 8.0) % (fr[1] - fr[0] + 1), m["p"])
	for s in shots:
		spr("spell", 30 if s["big"] else 29, s["p"])
	if phase != Phase.DYING and phase != Phase.OVER:
		_draw_rack()
	var ball_base := 6 if effects.has(Sp.FIRE) else 0
	var ball_size := 3 if effects.has(Sp.BIG) else (0 if effects.has(Sp.SMALL) else 1)
	for b in balls:
		spr("spell", ball_base + ball_size, b["p"])
	for bl in blasts:
		spr(bl["bank"], mini(bl["a"] + int(bl["t"] / 0.6 * (bl["b"] - bl["a"])), bl["b"]), bl["p"])
	if banner_t > 0.0:
		text(banner, Vector2(W * 0.5, 150), true)
	if phase == Phase.READY and banner_t <= 0.0:
		text("TOUCH TO LAUNCH", Vector2(W * 0.5, 150), true)
	if phase == Phase.PAUSED:
		draw_rect(Rect2(FIELD_L, 80, FIELD_R - FIELD_L, 40), Color(0, 0, 0, 0.7))
		text("PAUSE", Vector2(W * 0.5, 86), true)
		text("TOUCH TO GO ON", Vector2(W * 0.5, 102), true)


func _draw_rack() -> void:
	var pos := Vector2(rack_x, rack_y)
	var w := _rack_w()
	if effects.has(Sp.LASER) or effects.has(Sp.CANNON):
		spr("rack", _nearest_rack(21, 27, w), pos)
	elif effects.has(Sp.FROZEN):
		spr("rack", _rack_sprite(), pos)
		spr("rack", _nearest_rack(28, 34, w), pos)
	else:
		spr("rack", _rack_sprite(), pos)
	if effects.has(Sp.GLUE):
		spr("rack", _nearest_rack(35, 47, w), pos + Vector2(0, -4))
	if effects.has(Sp.FLY):
		spr("spell", 45 + int(t * 10.0) % 3, pos + Vector2(0, 8))
	if shields > 0:
		spr("spell", 34, pos)


func _nearest_rack(a: int, b: int, w: float) -> int:
	var best := a
	for i in range(a, b + 1):
		if absf(Atlas.BANKS["rack"][i][2] - w) < absf(Atlas.BANKS["rack"][best][2] - w):
			best = i
	return best


func _info_pages() -> Array:
	var legend := []
	for k in SPELL_NAMES.size():
		legend.append(SPELL_NAMES[k])
	return [
		[
			"THE ULTIMATE BREAK OUT",
			"",
			"Break every brick to clear a stage.",
			"100 stages in 10 worlds.",
			"",
			"Slide a finger to move the racket.",
			"Tap to launch the ball.",
			"Tap to fire when you carry a gun.",
			"",
			"Moving the racket while the ball",
			"lands gives a slide effect.",
			"",
			"TOUCH FOR MORE"
		],
		[
			"THE ENEMIES",
			"",
			"They come through the upper door.",
			"You can touch most of them.",
			"The only one that can kill you",
			"if you have no shield is",
			"the picus vulgarus.",
			"",
			"THE SHIELDS",
			"Catch the spells to get shields.",
			"A star on your racket shows",
			"that you have some.",
			"TOUCH FOR MORE"
		],
		["THE SPELLS"] + legend.slice(0, 9) + ["", "TOUCH FOR MORE"],
		["THE SPELLS"] + legend.slice(9) + ["", "TOUCH FOR MORE"],
		[
			"KRYPTON EGG",
			"",
			"Original game by Alexandre Kral",
			"PC programming by Xavier Kral",
			"Graphics by Black Ray",
			"Kral Brothers, Philippe Geurten",
			"Sound by Ryo Innagaki",
			"and Philippe Deneyer",
			"",
			"C2V 1994-1996",
			"",
			"Android remake of the Windows CD",
			"TOUCH FOR THE MENU"
		],
	]
