class_name MappaView
extends Control
## La mappa d'Europa: tabellone originale, carte mappa delle teocrazie, città con la classe dominante,
## confini con concessioni e pirati, empori chiusi. Zoom e spostamento con mouse, rotella,
## un dito (trascinare) e due dita (pizzicare) su iPad.

signal cliccato(chiave: String)
signal info(testo: String)

const MW := 1985.0
const MH := 1155.0

var eng: PaxEngine
var evidenzia := {}            # chiave -> true (bersagli cliccabili)
var zoom := -1.0
var off := Vector2.ZERO
var _fit := 1.0
var _tex := {}
var _tocchi := {}              # indice -> posizione
var _pinch_d := 0.0
var _pinch_c := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _press_t := 0
var _trascina := false
var _mouse_giu := false
var _hover := ""
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_adatta)
	_adatta()


func _process(delta: float) -> void:
	_t += delta
	if not evidenzia.is_empty():
		queue_redraw()


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func _adatta() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	_fit = minf(size.x / MW, size.y / MH)
	if zoom < 0:
		zoom = _fit
	zoom = clampf(zoom, _fit, _fit * 5.0)
	if zoom < _fit * 1.001:
		zoom = _fit
	_limita()
	queue_redraw()


func reimposta() -> void:
	zoom = _fit
	_limita()
	queue_redraw()


func _limita() -> void:
	var w := MW * zoom
	var h := MH * zoom
	if w <= size.x:
		off.x = (size.x - w) / 2
	else:
		off.x = clampf(off.x, size.x - w, 0)
	if h <= size.y:
		off.y = (size.y - h) / 2
	else:
		off.y = clampf(off.y, size.y - h, 0)


func a_schermo(p: Vector2) -> Vector2:
	return p * zoom + off


func a_mappa(s: Vector2) -> Vector2:
	return (s - off) / zoom

# ----------------------------------------------------------------------- geometria

func slot_rect(e: String) -> Rect2:
	var d: Dictionary = PaxDB.imp(e)
	var sl: Dictionary = PaxDB.mappa["slot"]
	return Rect2(sl["x0"] + sl["dx"] * d["col"], sl["y0"] + sl["dy"] * d["riga"], sl["w"], sl["h"])


func pos_citta(e: String, j: int) -> Vector2:
	var ci: int = PaxDB.slot[e][j][0]
	var sub: int = PaxDB.slot[e][j][1]
	var c: Dictionary = PaxDB.imp(e)["citta"][ci]
	var p: Array = c["pos"]
	if c.has("pos_multi"):
		p = c["pos_multi"][sub]
	if eng != null and eng.mappa_promo(e):
		p = PaxDB.mappa["promo"]["pos_M"][e][ci]
		if e == "Ottoman" and ci == 0:
			p = [93 + 95 * sub, 98]
	var v := Vector2(p[0], p[1])
	if e == "PapalStates" and sub == 1:
		v += Vector2(58, 10)
	return slot_rect(e).position + v


func pos_confine(k: String) -> Vector2:
	var p: Array = PaxDB.confini[k]["pos"]
	return Vector2(p[0], p[1])


## Bersaglio sotto il punto (coordinate della mappa): "city:E:j", "bord:K", "emp:E" o "".
func bersaglio(m: Vector2) -> String:
	var best := ""
	var bd := 34.0
	for e in PaxDB.ordine_imperi:
		for j in PaxDB.slot[e].size():
			# posti che non esistono ora (secondo posto di Venezia, città della carta mappa promo)
			if eng != null and not eng.slot_attivo(e, j) and eng.emporio_citta(e, j) == "":
				continue
			var d := m.distance_to(pos_citta(e, j))
			if d < bd:
				bd = d
				best = "city:%s:%d" % [e, j]
	for k in PaxDB.confini:
		var d := m.distance_to(pos_confine(k))
		if d < bd + 6:
			bd = d
			best = "bord:" + k
	if best != "":
		return best
	for e in PaxDB.ordine_imperi:
		if slot_rect(e).has_point(m):
			return "emp:" + e
	return ""

# ----------------------------------------------------------------------- disegno

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.05, 0.04, 0.35))
	var bt := tex("res://assets/mappa/tabellone.webp")
	if bt:
		draw_texture_rect(bt, Rect2(off, Vector2(MW, MH) * zoom), false)
	if eng == null:
		return
	var S := eng.S
	# carte mappa delle teocrazie cambiate
	for e in PaxDB.ordine_imperi:
		var th: String = S["th"][e]
		if th != PaxDB.imp(e)["stato_iniziale"] or eng.mappa_promo(e):
			var t := tex("res://assets/mappa/%s_%s.webp" % [e, "P" if eng.mappa_promo(e) else th])
			if t:
				var r := slot_rect(e)
				draw_texture_rect(t, Rect2(a_schermo(r.position), r.size * zoom), false)
	# empori chiusi (dischi)
	for e in PaxDB.ordine_imperi:
		for j in PaxDB.slot[e].size():
			var em := eng.emporio_citta(e, j)
			if em == "" or em == S["emporio"]["W"] or em == S["emporio"]["E"]:
				continue
			var bianco: bool = PaxDB.mappa["rotte"][em]["colore"] == "W"
			var c := a_schermo(pos_citta(e, j))
			draw_circle(c, 30 * zoom, Color(0.95, 0.93, 0.88) if bianco else Color(0.08, 0.07, 0.07))
			draw_arc(c, 30 * zoom, 0, TAU, 32, Color(0.3, 0.25, 0.2), 2.0 * zoom + 1)
			draw_line(c + Vector2(-14, -14) * zoom, c + Vector2(14, 14) * zoom, Color(0.6, 0.15, 0.1), 4 * zoom)
			draw_line(c + Vector2(14, -14) * zoom, c + Vector2(-14, 14) * zoom, Color(0.6, 0.15, 0.1), 4 * zoom)
	# proprietari degli imperi (stendardo sul titolo)
	for e in PaxDB.ordine_imperi:
		var em: Dictionary = S["emp"][e]
		if em["own"] < 0:
			continue
		var r := slot_rect(e)
		var bank: String = S["players"][em["own"]]["bank"]
		var col: Color = Stile.COLORI_BANCA.get(bank, Color.WHITE)
		var p0 := a_schermo(r.position + Vector2(r.size.x - 44, r.size.y * (0.0 if PaxDB.imp(e)["riga"] == 0 else 1.0) + (34 if PaxDB.imp(e)["riga"] == 0 else -78)))
		var pr := Rect2(p0, Vector2(38, 44) * zoom)
		draw_rect(pr, col)
		draw_rect(pr, Color(0.1, 0.08, 0.05), false, 2)
		var f := Stile.font("titolo")
		var lett := "R" if em["side"] == "K" else "Rep"
		if em["suz"] != "":
			lett = "V"
		draw_string(f, pr.position + Vector2(0, pr.size.y * 0.72), lett, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, int(22 * zoom), Color(0.1, 0.07, 0.04))
	# città
	for e in PaxDB.ordine_imperi:
		for j in S["city"][e].size():
			var t: String = S["city"][e][j]
			if t == "":
				continue
			_pezzo(t, a_schermo(pos_citta(e, j)), 60)
	# confini
	for k in S["bord"]:
		var b: Dictionary = S["bord"][k]
		var c := a_schermo(pos_confine(k))
		if b["p"] >= 0 and b["s"] != "":
			_pezzo("P:" + S["players"][b["p"]]["bank"], c + Vector2(-20, 0) * zoom, 56)
			_pezzo("S:" + b["s"], c + Vector2(26, 6) * zoom, 50)
		elif b["p"] >= 0:
			_pezzo("P:" + S["players"][b["p"]]["bank"], c, 60)
		elif b["s"] != "":
			_pezzo("S:" + b["s"], c, 54)
	# evidenziazioni
	var puls := 0.5 + 0.5 * sin(_t * 5.0)
	for key in evidenzia:
		var col := Color(1.0, 0.85, 0.3, 0.55 + 0.4 * puls)
		if key.begins_with("city:"):
			var pp: PackedStringArray = key.split(":")
			var c := a_schermo(pos_citta(pp[1], int(pp[2])))
			draw_arc(c, 32 * zoom + 3, 0, TAU, 40, col, 4.0)
		elif key.begins_with("bord:"):
			var c := a_schermo(pos_confine(key.substr(5)))
			draw_arc(c, 30 * zoom + 3, 0, TAU, 40, col, 4.0)
		elif key.begins_with("emp:"):
			var r := slot_rect(key.substr(4))
			draw_rect(Rect2(a_schermo(r.position), r.size * zoom), col, false, 4.0)
	if _hover != "":
		var c := Vector2.ZERO
		if _hover.begins_with("city:"):
			var pp: PackedStringArray = _hover.split(":")
			c = a_schermo(pos_citta(pp[1], int(pp[2])))
			draw_arc(c, 30 * zoom, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
		elif _hover.begins_with("bord:"):
			c = a_schermo(pos_confine(_hover.substr(5)))
			draw_arc(c, 28 * zoom, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)


func _pezzo(t: String, c: Vector2, alt: float) -> void:
	var nome := t.replace(":", "_")
	var tx := tex("res://assets/pezzi/%s.png" % nome)
	if tx == null:
		draw_circle(c, 10 * zoom, Color.WHITE)
		return
	var h := alt * zoom
	var w := h * tx.get_width() / tx.get_height()
	if t.begins_with("S:"):
		w = alt * 1.5 * zoom
		h = w * tx.get_height() / tx.get_width()
	draw_texture_rect(tx, Rect2(c - Vector2(w / 2, h * 0.62), Vector2(w, h)), false)

# ----------------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zooma(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zooma(1.0 / 1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_giu = true
				_trascina = false
				_press_pos = mb.position
			else:
				if _mouse_giu and not _trascina:
					_clic(mb.position)
				_mouse_giu = false
		accept_event()
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		var mm := ev as InputEventMouseMotion
		if _mouse_giu and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _trascina or mm.position.distance_to(_press_pos) > 8:
				_trascina = true
				off += mm.relative
				_limita()
				queue_redraw()
		else:
			var h := bersaglio(a_mappa(mm.position))
			if h != _hover:
				_hover = h
				info.emit(descrivi(h))
				queue_redraw()
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_tocchi[st.index] = st.position
			if _tocchi.size() == 1:
				_press_pos = st.position
				_press_t = Time.get_ticks_msec()
				_trascina = false
			elif _tocchi.size() == 2:
				_trascina = true
				var v: Array = _tocchi.values()
				_pinch_d = (v[0] as Vector2).distance_to(v[1])
				_pinch_c = ((v[0] as Vector2) + (v[1] as Vector2)) / 2
		else:
			if _tocchi.size() == 1 and not _trascina and st.position.distance_to(_press_pos) < 14:
				_clic(st.position)
			_tocchi.erase(st.index)
			if _tocchi.size() == 1:
				_trascina = true
		accept_event()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_tocchi[sd.index] = sd.position
		if _tocchi.size() == 1:
			if _trascina or sd.position.distance_to(_press_pos) > 12:
				_trascina = true
				off += sd.relative
				_limita()
				queue_redraw()
		elif _tocchi.size() >= 2:
			var v: Array = _tocchi.values()
			var d := (v[0] as Vector2).distance_to(v[1])
			var c := ((v[0] as Vector2) + (v[1] as Vector2)) / 2
			if _pinch_d > 0:
				off += c - _pinch_c
				_zooma(d / _pinch_d, c)
			_pinch_d = d
			_pinch_c = c
		accept_event()
	elif ev is InputEventMagnifyGesture:
		var mg := ev as InputEventMagnifyGesture
		_zooma(mg.factor, mg.position)
		accept_event()
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		off -= pg.delta * 8
		_limita()
		queue_redraw()
		accept_event()


func _zooma(f: float, at: Vector2) -> void:
	var m := a_mappa(at)
	zoom = clampf(zoom * f, _fit, _fit * 5.0)
	off = at - m * zoom
	_limita()
	queue_redraw()


func _clic(pos: Vector2) -> void:
	var k := bersaglio(a_mappa(pos))
	if k != "":
		info.emit(descrivi(k))
		cliccato.emit(k)


func descrivi(k: String) -> String:
	if eng == null or k == "":
		return ""
	var S := eng.S
	if k.begins_with("city:"):
		var pp: PackedStringArray = k.split(":")
		var e := pp[1]
		var j := int(pp[2])
		var t: String = S["city"][e][j]
		var s := "%s (%s): " % [eng.nome_citta(e, j), PaxDB.nome_imp(e)]
		if not eng.slot_attivo(e, j):
			return s + "emporio chiuso"
		s += ("città vuota, leva: " + PaxDB.nome_pezzo(eng.icona(e, j))) if t == "" else PaxDB.nome_pezzo(t)
		return s
	if k.begins_with("bord:"):
		var kk := k.substr(5)
		var b: Dictionary = S["bord"][kk]
		var s := "Confine %s%s: " % [eng._nome_confine(kk), " (marittimo)" if eng.mare(kk) else " (terrestre)"]
		var parti := []
		if b["p"] >= 0:
			parti.append("concessione di " + eng.pname(b["p"]))
		if b["s"] != "":
			parti.append("pirata " + eng._agg(b["s"]))
		return s + (", ".join(parti) if not parti.is_empty() else "libero")
	if k.begins_with("emp:"):
		var e := k.substr(4)
		var em: Dictionary = S["emp"][e]
		var th: String = S["th"][e]
		var s := "%s — %s" % [PaxDB.nome_imp(e), "medievale" if th == "M" else "teocrazia " + PaxDB.NOMI_REL[th]]
		if em["own"] >= 0:
			s += ", di %s (%s)" % [eng.pname(em["own"]), "re" if em["side"] == "K" else "repubblica"]
		else:
			s += ", nel trono"
		if not em["rep"].is_empty():
			s += ", %d repressi" % em["rep"].size()
		return s
	return ""
