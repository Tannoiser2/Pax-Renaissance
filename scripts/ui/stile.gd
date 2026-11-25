class_name Stile
extends RefCounted
## Tema grafico: pergamena, noce scuro e oro, font rinascimentali.

const ORO := Color(0.86, 0.70, 0.36)
const ORO_CHIARO := Color(0.98, 0.88, 0.60)
const NOCE := Color(0.16, 0.11, 0.08)
const NOCE_2 := Color(0.24, 0.17, 0.12)
const PERGAMENA := Color(0.93, 0.87, 0.74)
const INCHIOSTRO := Color(0.17, 0.12, 0.09)
const ROSSO := Color(0.62, 0.16, 0.12)
const COLORI_BANCA := {"Fugger": Color(0.22, 0.47, 0.92), "Medici": Color(0.93, 0.80, 0.18),
	"Coeur": Color(0.62, 0.30, 0.86), "Marchionni": Color(0.27, 0.68, 0.25)}
const COLORI_REL := {"C": Color(0.86, 0.72, 0.30), "I": Color(0.18, 0.58, 0.52), "R": Color(0.72, 0.20, 0.17)}

static var _font_cache := {}
static var tema: Theme


static func font(nome: String) -> Font:
	if _font_cache.has(nome):
		return _font_cache[nome]
	var f: Font
	match nome:
		"titolo":
			f = load("res://assets/fonts/Almendra-Bold.ttf")
		"titolo_r":
			f = load("res://assets/fonts/Almendra-Regular.ttf")
		"gotico":
			f = load("res://assets/fonts/UnifrakturMaguntia.ttf")
		"testo":
			f = load("res://assets/fonts/EBGaramond.ttf")
		"corsivo":
			f = load("res://assets/fonts/EBGaramond-Italic.ttf")
		"compatto":
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/fonts/RobotoCondensed.ttf")
			fv.variation_opentype = {"wght": 500}
			f = fv
		"compatto_b":
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/fonts/RobotoCondensed.ttf")
			fv.variation_opentype = {"wght": 700}
			f = fv
		_:
			f = load("res://assets/fonts/EBGaramond.ttf")
	_font_cache[nome] = f
	return f


static func box(bg: Color, bordo := ORO, spess := 2, raggio := 6, margine := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bordo
	s.set_border_width_all(spess)
	s.set_corner_radius_all(raggio)
	s.content_margin_left = margine
	s.content_margin_right = margine
	s.content_margin_top = margine * 0.6
	s.content_margin_bottom = margine * 0.6
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	return s


static func crea_tema() -> Theme:
	if tema != null:
		return tema
	var t := Theme.new()
	t.default_font = font("testo")
	t.default_font_size = 22
	t.set_color("font_color", "Label", PERGAMENA)
	# pulsanti
	t.set_stylebox("normal", "Button", box(Color(0.30, 0.20, 0.13), Color(0.70, 0.55, 0.30), 2, 6, 12))
	t.set_stylebox("hover", "Button", box(Color(0.42, 0.29, 0.17), ORO_CHIARO, 2, 6, 12))
	t.set_stylebox("pressed", "Button", box(Color(0.62, 0.45, 0.18), ORO_CHIARO, 3, 6, 12))
	t.set_stylebox("disabled", "Button", box(Color(0.22, 0.18, 0.15), Color(0.4, 0.35, 0.3), 1, 6, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font("titolo"))
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", ORO_CHIARO)
	t.set_color("font_hover_color", "Button", Color(1, 0.96, 0.82))
	t.set_color("font_pressed_color", "Button", Color(1, 0.97, 0.88))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.5))
	t.set_stylebox("panel", "Panel", box(Color(0.13, 0.09, 0.06, 0.94), Color(0.55, 0.42, 0.24), 2, 8))
	t.set_stylebox("panel", "PanelContainer", box(Color(0.13, 0.09, 0.06, 0.94), Color(0.55, 0.42, 0.24), 2, 8, 10))
	# campi di testo
	t.set_stylebox("normal", "LineEdit", box(Color(0.95, 0.90, 0.78), Color(0.55, 0.42, 0.24), 2, 4, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0.98, 0.94, 0.84), ORO, 2, 4, 8))
	t.set_color("font_color", "LineEdit", INCHIOSTRO)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.36, 0.28))
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_stylebox("normal", "OptionButton", box(Color(0.30, 0.20, 0.13), Color(0.70, 0.55, 0.30), 2, 6, 10))
	t.set_stylebox("hover", "OptionButton", box(Color(0.42, 0.29, 0.17), ORO_CHIARO, 2, 6, 10))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.22, 0.14, 0.09), ORO, 2, 6, 10))
	t.set_font("font", "OptionButton", font("compatto"))
	t.set_font_size("font_size", "OptionButton", 22)
	t.set_color("font_color", "OptionButton", ORO_CHIARO)
	t.set_font("font", "PopupMenu", font("compatto"))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.16, 0.11, 0.08), ORO, 2, 4, 6))
	t.set_color("font_color", "PopupMenu", PERGAMENA)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.95, 0.8))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.45, 0.32, 0.18), ORO, 0, 2, 4))
	t.set_font("normal_font", "RichTextLabel", font("compatto"))
	t.set_font("bold_font", "RichTextLabel", font("compatto_b"))
	t.set_font("italics_font", "RichTextLabel", font("corsivo"))
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	t.set_color("default_color", "RichTextLabel", PERGAMENA)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.15, 0.10, 0.07), ORO, 1, 4, 8))
	t.set_font("font", "TooltipLabel", font("compatto"))
	t.set_font_size("font_size", "TooltipLabel", 19)
	t.set_color("font_color", "TooltipLabel", PERGAMENA)
	t.set_font("font", "CheckBox", font("compatto"))
	t.set_font_size("font_size", "CheckBox", 22)
	t.set_color("font_color", "CheckBox", PERGAMENA)
	tema = t
	return t


static func etichetta(testo: String, dim := 22, nome_font := "testo", col := PERGAMENA) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_override("font", font(nome_font))
	l.add_theme_font_size_override("font_size", dim)
	l.add_theme_color_override("font_color", col)
	return l
