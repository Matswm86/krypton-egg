extends RefCounted
## Plays an Autodesk FLI (0xAF11) animation, the format of the eight 320x200
## cutscenes on the Krypton Egg CD. Frames decode into an 8-bit index image;
## the palette goes into a 256x1 texture and fli_palette.gdshader maps the two.

var data: PackedByteArray
var width := 320
var height := 200
var frame_count := 0
var frame_time := 1.0 / 70.0
var frame := 0
var pos := 128
var pix := PackedByteArray()
var pal := PackedByteArray()
var index_tex: ImageTexture
var pal_tex: ImageTexture
var _clock := 0.0


func open(path: String) -> bool:
	data = FileAccess.get_file_as_bytes(path)
	if data.size() < 128 or data.decode_u16(4) != 0xAF11:
		push_error("not a FLI file: %s" % path)
		return false
	frame_count = data.decode_u16(6)
	width = data.decode_u16(8)
	height = data.decode_u16(10)
	# FLI speed counts 1/70 s ticks. Clamp to 30 fps so a speed-1 loop stays watchable.
	frame_time = maxf(data.decode_u16(16) / 70.0, 1.0 / 30.0)
	pix.resize(width * height)
	pix.fill(0)
	pal.resize(768)
	pal.fill(0)
	index_tex = ImageTexture.create_from_image(
		Image.create_from_data(width, height, false, Image.FORMAT_L8, pix)
	)
	pal_tex = ImageTexture.create_from_image(
		Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, pal)
	)
	rewind()
	return true


func rewind() -> void:
	frame = 0
	pos = 128
	_clock = 0.0
	_decode_next()


## Advance by dt seconds; returns false once the last frame has been shown.
func advance(dt: float) -> bool:
	_clock += dt
	var changed := false
	while _clock >= frame_time:
		_clock -= frame_time
		if frame >= frame_count:
			return false
		_decode_next()
		changed = true
	if changed:
		index_tex.update(Image.create_from_data(width, height, false, Image.FORMAT_L8, pix))
	return true


func _decode_next() -> void:
	var fsize := data.decode_u32(pos)
	var chunks := data.decode_u16(pos + 6)
	var q := pos + 16
	for _c in chunks:
		var csize := data.decode_u32(q)
		var ctype := data.decode_u16(q + 4)
		var c := q + 6
		match ctype:
			11, 4:
				_color(c, 4 if ctype == 11 else 1)
			12:
				_delta_lc(c)
			13:
				pix.fill(0)
			15:
				_brun(c)
			16:
				for i in width * height:
					pix[i] = data[c + i]
		q += csize
	pos += fsize
	frame += 1


func _color(c: int, scale: int) -> void:
	var packets := data.decode_u16(c)
	c += 2
	var idx := 0
	for _p in packets:
		idx += data[c]
		var cnt := data[c + 1]
		if cnt == 0:
			cnt = 256
		c += 2
		for k in cnt:
			for ch in 3:
				pal[(idx + k) * 3 + ch] = mini(255, data[c + ch] * scale)
			c += 3
		idx += cnt
	pal_tex.update(Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, pal))


func _brun(c: int) -> void:
	for y in height:
		c += 1
		var x := 0
		var row := y * width
		while x < width:
			var cnt := data.decode_s8(c)
			c += 1
			if cnt > 0:
				var v := data[c]
				c += 1
				for k in cnt:
					pix[row + x + k] = v
				x += cnt
			else:
				for k in -cnt:
					pix[row + x + k] = data[c + k]
				c -= cnt
				x -= cnt


func _delta_lc(c: int) -> void:
	var y0 := data.decode_u16(c)
	var lines := data.decode_u16(c + 2)
	c += 4
	for y in range(y0, y0 + lines):
		var packets := data[c]
		c += 1
		var x := 0
		var row := y * width
		for _p in packets:
			x += data[c]
			var cnt := data.decode_s8(c + 1)
			c += 2
			if cnt > 0:
				for k in cnt:
					pix[row + x + k] = data[c + k]
				c += cnt
				x += cnt
			else:
				var v := data[c]
				c += 1
				for k in -cnt:
					pix[row + x + k] = v
				x -= cnt
