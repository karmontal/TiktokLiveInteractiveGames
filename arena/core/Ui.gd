extends RefCounted
## Shared drawing helpers: 720x720 square, Cairo font, right-to-left text, the house colors.

const W := 720.0
const H := 720.0
const FONT_PATH := "res://assets/fonts/Cairo.ttf"

const BG := Color("#0f0b24")
const CARD := Color("#1c1645")
const PANEL := Color("#241d55")
const BAR := Color("#07051a")
const AVATAR_BG := Color("#3a2f7a")
const ACCENT := Color("#ffd23f")
const GOOD := Color("#3ddc84")
const GOOD_BG := Color("#14532d")
const LIKE := Color("#ff6b8f")
const BLUE := Color("#7cc4ff")
const PURPLE := Color("#c084fc")
const MUTED := Color(1, 1, 1, 0.75)
const MEDALS := [Color("#ffd23f"), Color("#cbd5e1"), Color("#f0a868")]

static var _fonts := {}


static func font(weight: int) -> FontVariation:
	if not _fonts.has(weight):
		var f := FontVariation.new()
		f.base_font = load(FONT_PATH)
		f.variation_opentype = {"weight": weight}
		_fonts[weight] = f
	return _fonts[weight]


static func root(parent: Node) -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = Theme.new()
	c.theme.default_font = font(500)
	parent.add_child(c)
	return c


static func layer(parent: Node) -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## One line of right-to-left text, trimmed with "…" if too long. height 0 = fit the font.
static func label(parent: Node, text: String, font_size: int, pos: Vector2, width: float,
		color := Color.WHITE, weight := 500, align := HORIZONTAL_ALIGNMENT_CENTER, height := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, height if height > 0.0 else font_size * 1.7)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_RTL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if weight != 500:
		l.add_theme_font_override("font", font(weight))
	parent.add_child(l)
	return l


## Multi-line text that wraps inside the box.
static func paragraph(parent: Node, text: String, font_size: int, pos: Vector2, box: Vector2,
		color := Color.WHITE, weight := 500) -> Label:
	var l := label(parent, text, font_size, pos, box.x, color, weight, HORIZONTAL_ALIGNMENT_CENTER, box.y)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = false
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return l


static func panel(parent: Node, color: Color, pos: Vector2, panel_size: Vector2, radius := 0,
		border := Color(0, 0, 0, 0), border_width := 0) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_width)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = panel_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


static func restyle(p: Panel, color: Color, border := Color(0, 0, 0, 0), border_width := 0) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width)


static func rect(parent: Node, color: Color, pos: Vector2, rect_size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = rect_size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Round profile picture with a colored ring and the first letter until the picture loads.
static func avatar(parent: Node, pos: Vector2, diameter: float, ring: Color, ring_width := 4) -> Panel:
	var holder := panel(parent, AVATAR_BG, pos, Vector2(diameter, diameter), int(diameter / 2), ring, ring_width)
	var tex := TextureRect.new()
	tex.name = "Tex"
	tex.position = Vector2(ring_width, ring_width)
	tex.size = Vector2(diameter - ring_width * 2, diameter - ring_width * 2)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tex)
	var initial := label(holder, "", int(diameter * 0.42), Vector2.ZERO, diameter, Color.WHITE, 800,
			HORIZONTAL_ALIGNMENT_CENTER, diameter)
	initial.name = "Initial"
	return holder


static func set_avatar(holder: Panel, user: Dictionary, texture: Texture2D) -> void:
	holder.set_meta("uid", str(user.get("id", "")))
	var tex: TextureRect = holder.get_node("Tex")
	var initial: Label = holder.get_node("Initial")
	tex.texture = texture
	tex.visible = texture != null
	initial.text = str(user.get("name", "?")).left(1).to_upper()
	initial.visible = texture == null


## 12345 -> "12,345"
static func number(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
