extends Node
## Downloads profile pictures once, crops them to a 64x64 circle and caches them.
## get_avatar() returns the cached texture or null; avatar_ready fires when it arrives.

signal avatar_ready(user_id: String, texture: Texture2D)

const SIZE := 64
const MAX_PARALLEL := 4
const MAX_CACHE := 500

var _cache := {}         # user_id -> Texture2D
var _pending := {}       # user_id -> true
var _queue: Array = []   # [user_id, url]
var _active := 0
var _placeholders := {}  # Color -> Texture2D


func get_avatar(user_id: String, url: String) -> Texture2D:
	if _cache.has(user_id):
		return _cache[user_id]
	if url != "" and not _pending.has(user_id):
		_pending[user_id] = true
		_queue.append([user_id, url])
		_pump()
	return null


func placeholder(color: Color) -> Texture2D:
	if not _placeholders.has(color):
		var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(color)
		_placeholders[color] = ImageTexture.create_from_image(circle(img))
	return _placeholders[color]


func _pump() -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		var job: Array = _queue.pop_front()
		_active += 1
		var req := HTTPRequest.new()
		req.timeout = 10.0
		add_child(req)
		req.request_completed.connect(_on_done.bind(req, job[0]))
		if req.request(job[1]) != OK:
			_finish(req, job[0], null)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		req: HTTPRequest, user_id: String) -> void:
	var tex: Texture2D = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		tex = decode(body)
	_finish(req, user_id, tex)


func _finish(req: HTTPRequest, user_id: String, tex: Texture2D) -> void:
	req.queue_free()
	_active -= 1
	_pending.erase(user_id)
	if tex:
		if _cache.size() >= MAX_CACHE:
			_cache.erase(_cache.keys()[0])
		_cache[user_id] = tex
		avatar_ready.emit(user_id, tex)
	_pump()


static func decode(body: PackedByteArray) -> Texture2D:
	if body.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	elif body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return null
	return ImageTexture.create_from_image(circle(img))


## Center-crops to a square, scales to SIZE and makes everything outside the circle transparent.
static func circle(src: Image) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var s := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var r := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d > r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > r - 1.0:
				var c := img.get_pixel(x, y)
				c.a *= r - d
				img.set_pixel(x, y, c)
	return img
