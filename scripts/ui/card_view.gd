class_name CartaView
extends Control
## Una carta (o un quadrato impero) disegnata con i segnalini sopra: fiorini, vescovo, pezzi repressi,
## regina sposata, bordo evidenziato quando è cliccabile. Tocco = scelta; tasto destro o tocco lungo = ingrandisci.

signal premuto(cv: CartaView)
signal ingrandisci(cv: CartaView)

var id := ""                 # id carta, "@Impero", "retro_W"/"retro_E"
var lato_imp := "K"          # per gli imperi: K re, R repubblica
var fiorini := 0
var vescovo := ""            # colore del vescovo
var repressi: Array = []
var regina := ""
var cornice := Color(0, 0, 0, 0)
var evidenziata := false
var scura := false
var etichetta := ""
var nome_sotto := ""
var _t := 0.0
var _press := 0
var _press_pos := Vector2.ZERO
var _lungo := false

static var _cache := {}


static func texture(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	if evidenziata:
		_t += delta
		queue_redraw()
	if _press > 0 and not _lungo and Time.get_ticks_msec() - _press > 550:
		_lungo = true
		ingrandisci.emit(self)


func percorso() -> String:
	if id.begins_with("@"):
		return "res://assets/imperi/%s_%s.webp" % [id.substr(1), lato_imp]
	if id.begins_with("retro"):
		return "res://assets/carte/%s.webp" % id
	var c: Dictionary = PaxDB.carte.get(id, {})
	return "res://assets/carte/%s.webp" % c.get("img", "")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var area := r
	if regina != "" and id.begins_with("@"):
		# coppia reale: la regina spunta a destra del re
		var qw := size.y * 0.653
		var qt := texture("res://assets/carte/%s.webp" % PaxDB.carte[regina]["img"])
		var qr := Rect2(Vector2(size.x - qw, 0), Vector2(qw, size.y))
		if qt:
			draw_texture_rect(qt, qr, false)
		area = Rect2(Vector2.ZERO, Vector2(size.x - qw * 0.55, size.y))
		area.size.x = minf(area.size.x, size.y)
	var t := texture(percorso())
	if t:
		draw_texture_rect(t, area, false, Color(0.55, 0.55, 0.55) if scura else Color.WHITE)
	else:
		draw_rect(area, Color(0.3, 0.25, 0.2))
	if cornice.a > 0:
		draw_rect(r.grow(-1), cornice, false, 4.0)
	if evidenziata:
		var a := 0.55 + 0.45 * sin(_t * 5.0)
		draw_rect(r.grow(-2), Color(1.0, 0.85, 0.3, a), false, 5.0)
	var s := size.y / 200.0
	if vescovo != "":
		var bt := texture("res://assets/pezzi/B_%s.png" % vescovo)
		if bt:
			var h := 70.0 * s
			var w := h * bt.get_width() / bt.get_height()
			draw_texture_rect(bt, Rect2(Vector2(area.size.x * 0.5 - w / 2, size.y * 0.12), Vector2(w, h)), false)
	if not repressi.is_empty():
		var x := 4.0
		var h := 34.0 * s
		draw_rect(Rect2(0, size.y - h - 6, area.size.x, h + 6), Color(0, 0, 0, 0.45))
		for tk in repressi:
			var nome: String = tk
			var pt := texture("res://assets/pezzi/%s.png" % nome)
			if pt:
				var w := h * pt.get_width() / pt.get_height()
				if tk.begins_with("S"):
					w = h * 1.4
				draw_texture_rect(pt, Rect2(Vector2(x, size.y - h - 3), Vector2(w, h)), false)
				x += w * 0.75 + 1
			if x > area.size.x - 10:
				break
	if fiorini > 0:
		var c := Vector2(size.x * 0.5, size.y * 0.80)
		var rad := maxf(15.0, 22.0 * s)
		draw_circle(c, rad, Color(0.93, 0.76, 0.25))
		draw_arc(c, rad, 0, TAU, 28, Color(0.45, 0.30, 0.08), 2.5)
		var f := Stile.font("compatto_b")
		var fs := int(rad * 1.25)
		draw_string(f, c + Vector2(-rad, fs * 0.36), str(fiorini), HORIZONTAL_ALIGNMENT_CENTER, rad * 2, fs, Color(0.25, 0.15, 0.03))
	if nome_sotto != "":
		var f := Stile.font("compatto_b")
		var fs := 13
		draw_rect(Rect2(0, size.y - fs - 5, size.x, fs + 5), Color(0, 0, 0, 0.65))
		draw_string(f, Vector2(0, size.y - 4), nome_sotto, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Stile.PERGAMENA)
	if etichetta != "":
		var f := Stile.font("compatto_b")
		var fs := int(maxf(14.0, 20.0 * s))
		var w := size.x
		draw_rect(Rect2(0, 0, w, fs + 6), Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(0, fs), etichetta, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Stile.ORO_CHIARO)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			ingrandisci.emit(self)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = Time.get_ticks_msec()
				_press_pos = mb.position
				_lungo = false
			else:
				if _press > 0 and not _lungo:
					premuto.emit(self)
				_press = 0
			accept_event()
	elif ev is InputEventMouseMotion and _press > 0:
		if (ev as InputEventMouseMotion).position.distance_to(_press_pos) > 16:
			_press = 0
