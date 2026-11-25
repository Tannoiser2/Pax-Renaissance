extends Control
## Schermata di gioco: mercato, mappa, tableau dei giocatori, mano, scelte e diario.

var main
var config := {}
var eng: PaxEngine
var online = null              # OnlineSession
var umani: Array = []          # posti giocati su questo dispositivo
var vista := 0                 # di chi si mostra la mano
var replay: Array = []
var save_code := ""

var mappa: MappaView
var info_lbl: Label
var barra_lbl: Label
var mercato_W: Array = []
var mercato_E: Array = []
var mazzo_lbl := {}
var troni_box: GridContainer
var vittorie_box: HBoxContainer
var giocatori_box: VBoxContainer
var mano_box: HBoxContainer
var mano_lbl: Label
var mano_row: Control
var prompt_lbl: Label
var opzioni_box: VBoxContainer
var opzioni_scroll: ScrollContainer
var diario: RichTextLabel
var stato_lbl: Label
var zoom_layer: Control
var tenda: Control

var _req := {}
var _attesa := false
var _log_n := 0
var _chiusa := false

signal _scelta(v: int)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Stile.crea_tema()
	PaxDB.carica()
	_costruisci()
	_avvia()


# ======================================================================= costruzione

func _costruisci() -> void:
	var sfondo := TextureRect.new()
	sfondo.texture = load("res://assets/ui/sfondo.webp")
	sfondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sfondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sfondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sfondo.modulate = Color(0.45, 0.40, 0.36)
	add_child(sfondo)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var sx := VBoxContainer.new()
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sx.add_theme_constant_override("separation", 4)
	root.add_child(sx)
	# barra in alto
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 50
	bar.add_theme_constant_override("separation", 10)
	sx.add_child(bar)
	var tit := Stile.etichetta("Pax Renaissance", 30, "gotico", Stile.ORO_CHIARO)
	tit.custom_minimum_size.x = 250
	bar.add_child(tit)
	barra_lbl = Stile.etichetta("", 22, "compatto_b", Stile.PERGAMENA)
	barra_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	barra_lbl.clip_text = true
	bar.add_child(barra_lbl)
	for b in [["Regole", _apri_regole], ["Salva", _salva], ["Menu", _esci]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(110, 44)
		bt.pressed.connect(b[1])
		bar.add_child(bt)
	# mercato
	var mk := HBoxContainer.new()
	mk.add_theme_constant_override("separation", 5)
	mk.custom_minimum_size.y = 158
	sx.add_child(mk)
	for lato in ["W", "E"]:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 84
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := Stile.etichetta("Mercato\nd'Occidente" if lato == "W" else "Mercato\nd'Oriente", 16, "titolo", Stile.ORO_CHIARO)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		var dl := Stile.etichetta("", 16, "compatto", Stile.PERGAMENA)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(dl)
		mazzo_lbl[lato] = dl
		mk.add_child(col)
		for i in 6:
			var cv := CartaView.new()
			cv.custom_minimum_size = Vector2(100, 154)
			cv.premuto.connect(_clic_carta.bind("mk", lato, i))
			cv.ingrandisci.connect(_zoom_carta)
			mk.add_child(cv)
			(mercato_W if lato == "W" else mercato_E).append(cv)
		if lato == "W":
			var sp := Control.new()
			sp.custom_minimum_size.x = 6
			mk.add_child(sp)
	# centro: mappa + giocatori
	var centro := HBoxContainer.new()
	centro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centro.add_theme_constant_override("separation", 6)
	sx.add_child(centro)
	var mcol := VBoxContainer.new()
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcol.size_flags_stretch_ratio = 1.45
	mcol.add_theme_constant_override("separation", 2)
	centro.add_child(mcol)
	mappa = MappaView.new()
	mappa.custom_minimum_size = Vector2(500, 300)
	mappa.cliccato.connect(_clic_mappa)
	mappa.info.connect(func(t): info_lbl.text = t)
	mcol.add_child(mappa)
	var ib := HBoxContainer.new()
	mcol.add_child(ib)
	info_lbl = Stile.etichetta("Tocca una città o un confine per i dettagli. Rotella o due dita per lo zoom.", 17, "compatto", Stile.PERGAMENA)
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.clip_text = true
	ib.add_child(info_lbl)
	var bz := Button.new()
	bz.text = "Vista intera"
	bz.add_theme_font_size_override("font_size", 16)
	bz.pressed.connect(func(): mappa.reimposta())
	ib.add_child(bz)
	# mano, sotto la mappa
	var mrow := HBoxContainer.new()
	mrow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mrow.custom_minimum_size.y = 150
	mrow.add_theme_constant_override("separation", 6)
	mcol.add_child(mrow)
	mano_lbl = Stile.etichetta("La tua mano", 19, "compatto_b", Stile.ORO_CHIARO)
	mano_lbl.custom_minimum_size.x = 120
	mano_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mano_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mrow.add_child(mano_lbl)
	var mscroll := ScrollContainer.new()
	mscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mrow.add_child(mscroll)
	mano_box = HBoxContainer.new()
	mano_box.add_theme_constant_override("separation", 8)
	mano_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	mscroll.add_child(mano_box)
	mano_row = mrow
	mcol.resized.connect(func():
		mappa.custom_minimum_size.y = maxf(260.0, mcol.size.x * MappaView.MH / MappaView.MW)
		_aggiorna_mano())
	var gscroll := ScrollContainer.new()
	gscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	centro.add_child(gscroll)
	var gcol := VBoxContainer.new()
	gcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gcol.add_theme_constant_override("separation", 6)
	gscroll.add_child(gcol)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	gcol.add_child(trow)
	var tcol := VBoxContainer.new()
	trow.add_child(tcol)
	tcol.add_child(Stile.etichetta("Troni", 18, "titolo", Stile.ORO_CHIARO))
	troni_box = GridContainer.new()
	troni_box.columns = 5
	troni_box.add_theme_constant_override("h_separation", 3)
	troni_box.add_theme_constant_override("v_separation", 3)
	tcol.add_child(troni_box)
	var vcol := VBoxContainer.new()
	trow.add_child(vcol)
	vcol.add_child(Stile.etichetta("Vittorie", 18, "titolo", Stile.ORO_CHIARO))
	vittorie_box = HBoxContainer.new()
	vittorie_box.add_theme_constant_override("separation", 3)
	var vg := GridContainer.new()
	vg.columns = 2
	vg.add_theme_constant_override("h_separation", 3)
	vg.add_theme_constant_override("v_separation", 3)
	vcol.add_child(vg)
	vittorie_box = null
	vcol.set_meta("griglia", vg)
	giocatori_box = VBoxContainer.new()
	giocatori_box.add_theme_constant_override("separation", 6)
	gcol.add_child(giocatori_box)
	# pannello destro
	var dx := PanelContainer.new()
	dx.custom_minimum_size.x = 370
	root.add_child(dx)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	dx.add_child(dv)
	stato_lbl = Stile.etichetta("", 18, "compatto", Stile.ORO_CHIARO)
	stato_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stato_lbl.custom_minimum_size.x = 340
	dv.add_child(stato_lbl)
	prompt_lbl = Stile.etichetta("", 22, "compatto_b", Stile.ORO_CHIARO)
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_lbl.custom_minimum_size.x = 340
	dv.add_child(prompt_lbl)
	opzioni_scroll = ScrollContainer.new()
	opzioni_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	opzioni_scroll.size_flags_stretch_ratio = 1.4
	opzioni_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(opzioni_scroll)
	opzioni_box = VBoxContainer.new()
	opzioni_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opzioni_box.add_theme_constant_override("separation", 4)
	opzioni_scroll.add_child(opzioni_box)
	dv.add_child(Stile.etichetta("Diario", 20, "titolo", Stile.ORO_CHIARO))
	diario = RichTextLabel.new()
	diario.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diario.scroll_following = true
	diario.custom_minimum_size = Vector2(340, 160)
	diario.add_theme_font_size_override("normal_font_size", 17)
	diario.add_theme_font_size_override("bold_font_size", 17)
	dv.add_child(diario)
	# strati sopra
	zoom_layer = Control.new()
	zoom_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zoom_layer)


# ======================================================================= avvio

func _avvia() -> void:
	var gg: Array = config["giocatori"]
	eng = PaxEngine.new()
	eng.nuova(gg, int(config.get("seme", 1)), config.get("opzioni", {}))
	for i in gg.size():
		if eng.bot_solitario(i):
			eng.ais[i] = PaxSoloBot.new(2)
		elif gg[i].get("ai", false):
			eng.ais[i] = PaxAI.new(int(gg[i].get("livello", 2)))
		else:
			eng.ais[i] = PaxAI.new(2)
	replay = config.get("replay", [])
	if config.has("online"):
		online = config["online"]
		add_child(online)
		online.view = self
		umani = [online.seat]
		online.heartbeat_loop()
	else:
		for i in gg.size():
			if not gg[i].get("ai", false):
				umani.append(i)
	vista = umani[0] if not umani.is_empty() else 0
	mappa.eng = eng
	eng.controller = self
	eng.cambiato.connect(_aggiorna)
	eng.finita.connect(_fine)
	_aggiorna()
	await get_tree().process_frame
	eng.run()


## Controllore del motore: decide chi sceglie.
func decide(e: PaxEngine, p: int, req: Dictionary) -> int:
	if not replay.is_empty() and e.registro.size() < replay.size():
		return int(replay[e.registro.size()])
	if online != null:
		return await online.decide(e, p, req)
	if p in umani:
		return await chiedi(p, req)
	_aggiorna()
	_mostra_attesa(p, req)
	if eng.ai_delay > 0 and is_inside_tree():
		await get_tree().create_timer(eng.ai_delay * (0.4 if req["tipo"] != "azione" else 1.0)).timeout
	if _chiusa:
		return 0
	return await e.ais[p].decide(e, p, req)


func _mostra_attesa(p: int, req: Dictionary) -> void:
	prompt_lbl.text = "%s sta pensando…" % eng.pname(p)
	for c in opzioni_box.get_children():
		c.queue_free()
	mappa.evidenzia = {}
	mappa.queue_redraw()


## La persona davanti al dispositivo sceglie fra le opzioni.
func chiedi(p: int, req: Dictionary) -> int:
	if p != vista and umani.size() > 1 and online == null:
		vista = p
		await _passa_dispositivo(p)
	vista = p
	_req = req
	_attesa = true
	_aggiorna()
	_mostra_opzioni()
	var v: int = await _scelta
	_attesa = false
	_req = {}
	mappa.evidenzia = {}
	return v


## Annulla una scelta in corso (online: l'IA ha già giocato al nostro posto).
func annulla_scelta() -> void:
	if _attesa:
		_scelta.emit(-1)


func _passa_dispositivo(p: int) -> void:
	tenda = ColorRect.new()
	(tenda as ColorRect).color = Color(0.06, 0.04, 0.03, 0.97)
	tenda.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tenda)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	tenda.add_child(vb)
	var l := Stile.etichetta("Passa il dispositivo a\n%s" % eng.pname(p), 48, "titolo", Stile.ORO_CHIARO)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var b := Button.new()
	b.text = "Sono %s: mostra la mia mano" % eng.pname(p)
	b.custom_minimum_size = Vector2(520, 64)
	vb.add_child(b)
	vb.position = Vector2(-260, -100)
	await b.pressed
	tenda.queue_free()
	tenda = null

# ======================================================================= opzioni

const GRUPPI := [["buy", "Compra una carta"], ["play", "Gioca una carta"], ["ops", "Operazioni"], ["fair", "Fiere commerciali"],
	["vict", "Vittoria"], ["bathory", "Azioni speciali"], ["oratory", "Azioni speciali"], ["sell", "Vendi"], ["fine", ""]]


func _mostra_opzioni() -> void:
	for c in opzioni_box.get_children():
		c.queue_free()
	var opts: Array = _req.get("opz", [])
	prompt_lbl.text = _req.get("testo", "")
	var ev := {}
	for o in opts:
		var k: String = o.get("k", "")
		for x in _chiavi_elemento(k):
			ev[x] = true
	mappa.evidenzia = ev
	mappa.queue_redraw()
	if _req.get("tipo", "") == "azione":
		var gia := {}
		for g in GRUPPI:
			var idx := []
			for i in opts.size():
				if opts[i].get("tipo", "") == g[0]:
					idx.append(i)
			if idx.is_empty():
				continue
			if g[1] != "" and not gia.has(g[1]):
				gia[g[1]] = true
				opzioni_box.add_child(Stile.etichetta(g[1], 19, "titolo", Stile.ORO))
			for i in idx:
				_bottone_opzione(i, opts[i])
	else:
		for i in opts.size():
			_bottone_opzione(i, opts[i])
	_aggiorna_evidenze()
	opzioni_scroll.scroll_vertical = 0


func _bottone_opzione(i: int, o: Dictionary) -> void:
	var b := Button.new()
	b.text = o.get("t", "?")
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(330, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Stile.font("compatto"))
	b.add_theme_font_size_override("font_size", 19)
	if o.get("k", "") == "fine" or o.get("tipo", "") == "fine":
		b.add_theme_color_override("font_color", Color(0.95, 0.75, 0.6))
	b.pressed.connect(_scegli.bind(i))
	opzioni_box.add_child(b)


func _scegli(i: int) -> void:
	if not _attesa:
		return
	_chiudi_menu()
	_scelta.emit(i)


## Elementi dell'interfaccia legati alla chiave di un'opzione.
func _chiavi_elemento(k: String) -> Array:
	var pp := k.split(":")
	match pp[0]:
		"city", "bord", "emp":
			return [k]
		"card":
			return ["card:" + k.substr(5)]
	return []


func _opzioni_per(chiavi: Array) -> Array:
	var out := []
	var opts: Array = _req.get("opz", [])
	for i in opts.size():
		var k: String = opts[i].get("k", "")
		for c in chiavi:
			if k == c or (c.ends_with("*") and k.begins_with(c.substr(0, c.length() - 1))):
				out.append(i)
				break
	return out


func _aggiorna_evidenze() -> void:
	for lato in ["W", "E"]:
		var arr: Array = mercato_W if lato == "W" else mercato_E
		for i in 6:
			arr[i].evidenziata = _attesa and not _opzioni_per(["buy:%s:%d" % [lato, i], "mkt:%s:%d" % [lato, i]]).is_empty()
			arr[i].queue_redraw()
	for cv in mano_box.get_children():
		if cv is CartaView:
			cv.evidenziata = _attesa and not _opzioni_per(["play:%s:*" % cv.id, "sell:h:" + cv.id, "sell:m:" + cv.id]).is_empty()
	for n in _tutte_le_carte():
		var cv: CartaView = n
		var k: Array = ["card:" + cv.id, "sell:t:" + cv.id]
		if cv.id.begins_with("@"):
			k.append("emp:" + cv.id.substr(1))
		cv.evidenziata = _attesa and not _opzioni_per(k).is_empty()


func _tutte_le_carte() -> Array:
	var out := []
	for c in troni_box.get_children():
		if c is CartaView:
			out.append(c)
	for row in giocatori_box.get_children():
		for c in row.find_children("*", "CartaView", true, false):
			out.append(c)
	return out


func _clic_carta(cv: CartaView, dove: String, lato := "", i := -1) -> void:
	if not _attesa:
		_zoom_carta(cv)
		return
	var chiavi := []
	match dove:
		"mk":
			chiavi = ["buy:%s:%d" % [lato, i], "mkt:%s:%d" % [lato, i]]
		"mano":
			chiavi = ["play:%s:*" % cv.id, "sell:h:" + cv.id, "sell:m:" + cv.id]
		"tab":
			chiavi = ["card:" + cv.id, "sell:t:" + cv.id]
			if cv.id.begins_with("@"):
				chiavi.append("emp:" + cv.id.substr(1))
	var idx := _opzioni_per(chiavi)
	if idx.is_empty():
		_zoom_carta(cv)
		return
	_menu(idx, cv)


func _clic_mappa(k: String) -> void:
	if not _attesa:
		return
	var idx := _opzioni_per([k])
	if idx.is_empty():
		return
	if idx.size() == 1:
		_scegli(idx[0])
	else:
		_menu(idx, null)


var _menu_nodo: Control

func _menu(idx: Array, cv) -> void:
	_chiudi_menu()
	var opts: Array = _req.get("opz", [])
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", Stile.box(Color(0.12, 0.08, 0.05, 0.98), Stile.ORO, 2, 8, 12))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pan.add_child(vb)
	for i in idx:
		var b := Button.new()
		b.text = opts[i]["t"]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(460, 42)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", Stile.font("compatto"))
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_scegli.bind(i))
		vb.add_child(b)
	if cv != null:
		var bz := Button.new()
		bz.text = "Guarda la carta"
		bz.custom_minimum_size = Vector2(460, 40)
		bz.pressed.connect(func(): _chiudi_menu(); _zoom_carta(cv))
		vb.add_child(bz)
	var bc := Button.new()
	bc.text = "Annulla"
	bc.custom_minimum_size = Vector2(460, 40)
	bc.pressed.connect(_chiudi_menu)
	vb.add_child(bc)
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.35)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vel.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _chiudi_menu())
	add_child(vel)
	vel.add_child(pan)
	_menu_nodo = vel
	await get_tree().process_frame
	if not is_instance_valid(pan):
		return
	var mp := get_global_mouse_position()
	var ps := pan.size
	pan.position = Vector2(clampf(mp.x - ps.x / 2, 8, size.x - ps.x - 8), clampf(mp.y - 20, 8, size.y - ps.y - 8))


func _chiudi_menu() -> void:
	if _menu_nodo != null and is_instance_valid(_menu_nodo):
		_menu_nodo.queue_free()
	_menu_nodo = null

# ======================================================================= aggiornamento

func _aggiorna() -> void:
	if eng == null or eng.S.is_empty():
		return
	var S := eng.S
	var cur: int = S["cur"]
	var fl: Dictionary = S["fl"]
	barra_lbl.text = "Turno %d — tocca a %s — azioni usate: %d di 2" % [S["turno"], eng.pname(cur), mini(fl["azioni"], 2)]
	var attive := []
	for v in S["vict"]:
		if S["vict"][v]:
			attive.append(PaxDB.mappa["vittorie"][v]["nome"].to_lower())
	var sup := eng.supremazia()
	stato_lbl.text = "Vittorie attive: %s.  Religione suprema: %s." % [", ".join(attive) if not attive.is_empty() else "nessuna",
		PaxDB.NOMI_REL[sup] if sup != "" else "nessuna"]
	# mercato
	for lato in ["W", "E"]:
		var arr: Array = mercato_W if lato == "W" else mercato_E
		for i in 6:
			var sl: Dictionary = S["mk"][lato][i]
			var cv: CartaView = arr[i]
			if sl["c"] == "":
				cv.id = ""
			elif i == 0:
				cv.id = "retro_" + PaxDB.carte[sl["c"]]["mazzo"]
			else:
				cv.id = sl["c"]
			cv.fiorini = sl["f"]
			cv.etichetta = "Fiera" if i == 0 else "%d ƒ" % i
			cv.queue_redraw()
		mazzo_lbl[lato].text = "Mazzo: %d" % S["deck"][lato].size()
	_aggiorna_troni()
	_aggiorna_vittorie()
	_aggiorna_giocatori()
	_aggiorna_mano()
	mappa.queue_redraw()
	var log: Array = S["log"]
	if log.size() < _log_n:
		_log_n = 0
		diario.clear()
	while _log_n < log.size():
		var t: String = log[_log_n]
		if t.begins_with("—"):
			diario.append_text("[b][color=#e8c66a]%s[/color][/b]\n" % t)
		else:
			diario.append_text(t + "\n")
		_log_n += 1
	if _attesa:
		_aggiorna_evidenze()


func _aggiorna_troni() -> void:
	for c in troni_box.get_children():
		c.queue_free()
	for e in PaxDB.ordine_imperi:
		var cv := CartaView.new()
		cv.id = "@" + e
		var em: Dictionary = eng.S["emp"][e]
		cv.custom_minimum_size = Vector2(72, 72)
		cv.nome_sotto = PaxDB.nome_imp(e).replace("Sacro Romano Impero", "S. R. Impero").replace("Impero ottomano", "Ottomani").replace("Stato Pontificio", "Stato Pont.")
		if em["own"] >= 0:
			cv.scura = true
			cv.lato_imp = em["side"]
			cv.cornice = Stile.COLORI_BANCA.get(eng.P(em["own"])["bank"], Color.WHITE)
		else:
			cv.vescovo = eng.S["bish"].get("@" + e, "")
			cv.repressi = _sprite_repressi(em["rep"])
			cv.regina = ""
			if em["queen"] != "":
				cv.etichetta = "sposato"
		cv.tooltip_text = _testo_impero(e)
		cv.premuto.connect(_clic_carta.bind("tab"))
		cv.ingrandisci.connect(_zoom_carta)
		troni_box.add_child(cv)


func _aggiorna_vittorie() -> void:
	var g: GridContainer = troni_box.get_parent().get_parent().get_child(1).get_meta("griglia")
	for c in g.get_children():
		c.queue_free()
	for v in eng.S["vict"]:
		var tr := TextureRect.new()
		var att: bool = eng.S["vict"][v]
		tr.texture = load("res://assets/ui/vitt_%s_%s.webp" % [v, "B" if att else "A"])
		tr.custom_minimum_size = Vector2(66, 66)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.modulate = Color.WHITE if att else Color(0.6, 0.6, 0.6)
		tr.tooltip_text = "%s (%s): %s" % [PaxDB.mappa["vittorie"][v]["nome"], PaxDB.mappa["vittorie"][v]["sotto"], "ATTIVA" if att else "non ancora attiva"]
		g.add_child(tr)


func _sprite_repressi(rep: Array) -> Array:
	var out := []
	for t in rep:
		if t.begins_with("P:"):
			out.append("P_" + eng.P(int(t.split(":")[1]))["bank"])
		else:
			out.append(t.replace(":", "_"))
	return out


func _aggiorna_giocatori() -> void:
	for c in giocatori_box.get_children():
		c.queue_free()
	var S := eng.S
	for k in S["np"]:
		var p: int = (vista + k) % S["np"]
		var pl: Dictionary = S["players"][p]
		var pan := PanelContainer.new()
		var col: Color = Stile.COLORI_BANCA.get(pl["bank"], Color.WHITE)
		var bg := Color(0.13, 0.09, 0.06, 0.94)
		pan.add_theme_stylebox_override("panel", Stile.box(bg, col if p != S["cur"] else Stile.ORO_CHIARO, 3 if p == S["cur"] else 2, 8, 8))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		pan.add_child(vb)
		var testa := HBoxContainer.new()
		testa.add_theme_constant_override("separation", 8)
		vb.add_child(testa)
		var sw := ColorRect.new()
		sw.color = col
		sw.custom_minimum_size = Vector2(18, 26)
		testa.add_child(sw)
		var banca: String = pl["bank"] if pl.get("promo_bank", "") == "" else pl["promo_bank"]
		if pl.get("solo_bot", false):
			banca += ", automa"
		var nome := Stile.etichetta("%s (%s)%s" % [pl["name"], banca.replace("Coeur", "Cœur"), "  (di turno)" if p == S["cur"] else ""], 20, "titolo", Stile.ORO_CHIARO)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nome.clip_text = true
		testa.add_child(nome)
		var pres := []
		for x in ["C", "I", "R", "L", "D", "P"]:
			var n := eng.conta_prestigio(p, x)
			if n > 0:
				pres.append("%s %d" % [PaxDB.NOMI_PRESTIGIO[x], n])
		var riga2 := Stile.etichetta("%d ƒ · %d concessioni · mano %d · %d re · %d repubbliche%s" % [pl["fl"], eng.concessioni(p), pl["hand"].size(),
			eng.re_count(p), eng.repubbliche(p), (" · prestigio: " + ", ".join(pres)) if not pres.is_empty() else ""], 16, "compatto", Stile.PERGAMENA)
		riga2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		riga2.custom_minimum_size.x = 300
		vb.add_child(riga2)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 3)
		flow.add_theme_constant_override("v_separation", 3)
		vb.add_child(flow)
		var west: Array = pl["W"].duplicate()
		west.reverse()
		for id in west:
			_aggiungi_tableau(flow, p, id)
		var plac := TextureRect.new()
		plac.texture = load("res://assets/ui/banca_%s.webp" % (pl["bank"] if pl.get("promo_bank", "") == "" else pl["promo_bank"]))
		plac.custom_minimum_size = Vector2(58, 82)
		plac.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plac.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		plac.tooltip_text = "Plancia della banca %s: a sinistra l'Occidente, a destra l'Oriente." % banca
		flow.add_child(plac)
		for id in pl["E"]:
			_aggiungi_tableau(flow, p, id)
		for id in pl["maids"]:
			var cv := _cv_tab(id, p)
			cv.scura = true
			cv.etichetta = "zitella"
			flow.add_child(cv)
		giocatori_box.add_child(pan)


func _cv_tab(id: String, p: int) -> CartaView:
	var cv := CartaView.new()
	cv.id = id
	cv.custom_minimum_size = Vector2(56, 86)
	cv.vescovo = eng.S["bish"].get(id, "")
	cv.premuto.connect(_clic_carta.bind("tab"))
	cv.ingrandisci.connect(_zoom_carta)
	return cv


func _aggiungi_tableau(flow: Control, p: int, id: String) -> void:
	if id.begins_with("@"):
		var e := id.substr(1)
		var em: Dictionary = eng.S["emp"][e]
		var cv := _cv_tab(id, p)
		cv.lato_imp = em["side"]
		cv.repressi = _sprite_repressi(em["rep"])
		cv.regina = em["queen"]
		cv.custom_minimum_size = Vector2(86 + (40 if em["queen"] != "" else 0), 86)
		cv.tooltip_text = _testo_impero(e)
		if em["queen"] != "" and eng.S["bish"].has(em["queen"]):
			cv.vescovo = eng.S["bish"][em["queen"]]
		flow.add_child(cv)
		for v in eng.vassalli(e):
			var vv := _cv_tab("@" + v, p)
			vv.custom_minimum_size = Vector2(70, 70)
			vv.etichetta = "vassallo"
			vv.repressi = _sprite_repressi(eng.S["emp"][v]["rep"])
			vv.regina = eng.S["emp"][v]["queen"]
			if vv.regina != "":
				vv.custom_minimum_size.x = 104
			vv.tooltip_text = _testo_impero(v)
			flow.add_child(vv)
	else:
		var cv := _cv_tab(id, p)
		cv.tooltip_text = PaxDB.nome_carta(id)
		flow.add_child(cv)


func _aggiorna_mano() -> void:
	if eng == null or eng.S.is_empty():
		return
	for c in mano_box.get_children():
		c.queue_free()
	var pl: Dictionary = eng.P(vista)
	mano_lbl.text = "Mano di\n%s\n%d ƒ" % [pl["name"], pl["fl"]]
	if online == null and not (vista in umani):
		mano_lbl.text = "Mano di\n%s" % pl["name"]
	for id in pl["hand"]:
		var cv := CartaView.new()
		cv.id = id
		var hh := clampf(mano_row.size.y - 8, 140.0, 420.0) if mano_row != null else 145.0
		cv.custom_minimum_size = Vector2(hh * 0.653, hh)
		cv.premuto.connect(_clic_carta.bind("mano"))
		cv.ingrandisci.connect(_zoom_carta)
		if not (vista in umani) and online == null:
			cv.id = "retro_" + PaxDB.carte[id]["mazzo"]
		mano_box.add_child(cv)
	if pl["hand"].is_empty():
		mano_box.add_child(Stile.etichetta("(nessuna carta in mano)", 18, "corsivo", Stile.PERGAMENA))

# ======================================================================= ingrandimento

func _zoom_carta(cv: CartaView) -> void:
	if cv.id == "" or cv.id.begins_with("retro"):
		return
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.78)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	vel.add_child(hb)
	var h := minf(size.y * 0.86, 760.0)
	var img := CartaView.new()
	img.id = cv.id
	img.lato_imp = cv.lato_imp
	img.regina = cv.regina
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cv.id.begins_with("@"):
		img.custom_minimum_size = Vector2(h * 0.8 + (h * 0.5 if cv.regina != "" else 0.0), h * 0.8)
	else:
		img.custom_minimum_size = Vector2(h * 0.653, h)
	hb.add_child(img)
	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(minf(560, size.x - img.custom_minimum_size.x - 80), 0)
	hb.add_child(pan)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(pan.custom_minimum_size.x - 24, 100)
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("bold_font_size", 22)
	rt.add_theme_font_size_override("italics_font_size", 21)
	rt.text = _scheda(cv.id)
	pan.add_child(rt)
	await get_tree().process_frame
	if is_instance_valid(hb):
		hb.position = (size - hb.size) / 2
	vel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			vel.queue_free())


func _testo_impero(e: String) -> String:
	var em: Dictionary = eng.S["emp"][e]
	var s := PaxDB.nome_imp(e)
	if em["own"] >= 0:
		s += " — di %s (%s)" % [eng.pname(em["own"]), "re" if em["side"] == "K" else "repubblica"]
	else:
		s += " — nel trono"
	if em["queen"] != "":
		s += ", regina: " + PaxDB.nome_carta(em["queen"])
	if not em["rep"].is_empty():
		s += ", %d repressi" % em["rep"].size()
	return s


func _scheda(id: String) -> String:
	if id.begins_with("@"):
		var e := id.substr(1)
		var em: Dictionary = eng.S["emp"][e]
		var s := ""
		for lato in ["re", "repubblica"]:
			var d: Dictionary = PaxDB.imp(e)[lato]
			var ops := []
			for i in d["ops"].size():
				ops.append(_nome_op(d["ops"][i]) + ((" (" + d["sotto"][i] + ")") if i < d["sotto"].size() and d["sotto"][i] != "" else ""))
			var pr := []
			for x in d["prestigio"]:
				pr.append(PaxDB.NOMI_PRESTIGIO[x])
			s += "[b]%s — %s[/b]\n%s\nOperazioni: %s\nPrestigio: %s\n\n" % [PaxDB.nome_imp(e), "lato re" if lato == "re" else "lato repubblica",
				d["nome"], ", ".join(ops) if not ops.is_empty() else "nessuna", ", ".join(pr) if not pr.is_empty() else "nessuno"]
		s += _testo_impero(e)
		return s
	var c: Dictionary = PaxDB.carte[id]
	var s := "[b]%s[/b]  [i](%s)[/i]\n" % [c["nome"], c["nome_en"]]
	if c.get("cometa", false):
		return s + "\n" + c["testo_abilita"] + "\n\n[i]" + c["testo"] + "[/i]"
	s += "Mazzo: %s.  " % ("Oriente" if c["mazzo"] == "E" else "Occidente")
	if c.get("regina", false):
		var pr := []
		for e in c["pretendenti"]:
			pr.append(PaxDB.nome_imp(e))
		s += "Regina. Pretendenti: %s.\n" % ", ".join(pr)
	else:
		s += "Luogo: %s.\n" % PaxDB.nome_imp(c["luogo"])
	if not c["prestigio"].is_empty():
		var pr := []
		for x in c["prestigio"]:
			pr.append(PaxDB.NOMI_PRESTIGIO[x])
		s += "Prestigio: %s.\n" % ", ".join(pr)
	if not c["ops"].is_empty():
		var ops := []
		for i in c["ops"].size():
			ops.append("%s (%s)" % [_nome_op(c["ops"][i]), c["sottotitoli"][i]])
		s += "Operazioni: %s.\n" % "; ".join(ops)
	if c["oneshot"] != "":
		var os: String = PaxDB.NOMI_ONESHOT[c["oneshot"]]
		if c["oneshot"] == "tradeshift":
			os += " verso " + PaxDB.NOMI_EMPORI[c["oneshot_arg"]]
		elif c["oneshot"] == "apostasy":
			os += " " + PaxDB.NOMI_REL[c["oneshot_arg"][0]] + "-" + PaxDB.NOMI_REL[c["oneshot_arg"][1]]
		s += "Evento (one-shot): %s.\n" % os
	if not c["agenti"].is_empty():
		var ag := []
		for a in c["agenti"]:
			ag.append("concessione" if a == "P" else PaxDB.nome_pezzo(a))
		s += "Agenti: %s.\n" % ", ".join(ag)
	if c["testo_abilita"] != "":
		s += "[b]Abilità:[/b] %s\n" % c["testo_abilita"]
	s += "\n[i]%s[/i]" % c["testo"]
	return s


func _nome_op(op: String) -> String:
	var p := op.split(":")
	var n: String = PaxDB.NOMI_OP[p[0]]
	if p.size() > 1:
		match p[0]:
			"commerce", "vote":
				n += " d'Oriente" if p[1] == "E" else " d'Occidente"
			"inq", "corsair":
				n += " " + {"C": "cattolico", "I": "islamico", "R": "riformato"}[p[1]]
			"repress":
				var t := []
				for ch in p[1]:
					t.append({"P": "pedoni", "R": "torri", "K": "cavalieri"}[ch])
				n += " (" + ", ".join(t) + ")"
	return n

# ======================================================================= fine, salvataggi, menu

func _fine() -> void:
	_aggiorna()
	if online != null:
		online.finish()
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.7)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	var pan := PanelContainer.new()
	vel.add_child(pan)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pan.add_child(vb)
	var w: int = eng.S["vincitore"]
	var t := Stile.etichetta("%s" % eng.S["motivo"], 40, "gotico", Stile.ORO_CHIARO)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var l := Stile.etichetta("Vince %s (banca %s)." % [eng.pname(w), eng.P(w)["bank"]] if w >= 0 else "Partita finita.", 30, "titolo", Stile.PERGAMENA)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var b := Button.new()
	b.text = "Torna al menu"
	b.custom_minimum_size = Vector2(360, 60)
	b.pressed.connect(func(): main.show_menu())
	vb.add_child(b)
	var b2 := Button.new()
	b2.text = "Guarda il tavolo"
	b2.custom_minimum_size = Vector2(360, 54)
	b2.pressed.connect(func(): vel.queue_free())
	vb.add_child(b2)
	await get_tree().process_frame
	pan.position = (size - pan.size) / 2


func _salva() -> void:
	if online != null:
		_avviso("La partita online è già salvata nella stanza: per rientrare usa il codice della stanza.")
		return
	var cfg := config.duplicate()
	cfg.erase("online")
	cfg.erase("replay")
	var net: Net = main.get_net()
	_avviso("Salvo la partita…")
	var code: String = await net.save_game({"cfg": var_to_str(cfg), "moves": var_to_str(eng.registro)}, save_code)
	if code == "":
		_avviso("Non riesco a salvare: %s" % net.last_error)
		return
	save_code = code
	_avviso("Partita salvata con il codice %s: dal menu «Carica partita» la riprendi su qualsiasi dispositivo." % code)


func _avviso(t: String) -> void:
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", Stile.box(Color(0.10, 0.07, 0.05, 0.97), Stile.ORO, 2, 8, 16))
	var l := Stile.etichetta(t, 22, "compatto", Stile.PERGAMENA)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 620
	pan.add_child(l)
	add_child(pan)
	await get_tree().process_frame
	pan.position = Vector2((size.x - pan.size.x) / 2, 70)
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(pan):
		pan.queue_free()


func _apri_regole() -> void:
	var r := preload("res://scripts/ui/rules_view.gd").new()
	r.sovrapposto = true
	add_child(r)


func _esci() -> void:
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.6)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	var pan := PanelContainer.new()
	vel.add_child(pan)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pan.add_child(vb)
	var l := Stile.etichetta("La partita in corso si chiude." + (" Online puoi rientrare con lo stesso codice." if online != null else " Se vuoi riprenderla più tardi, salvala prima con «Salva»."), 22, "compatto", Stile.PERGAMENA)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	vb.add_child(l)
	var b := Button.new()
	b.text = "Torna al menu"
	b.custom_minimum_size = Vector2(300, 56)
	b.pressed.connect(func():
		_chiusa = true
		main.show_menu())
	vb.add_child(b)
	var b2 := Button.new()
	b2.text = "Continua a giocare"
	b2.custom_minimum_size = Vector2(300, 56)
	b2.pressed.connect(func(): vel.queue_free())
	vb.add_child(b2)
	await get_tree().process_frame
	pan.position = (size - pan.size) / 2

# ======================================================================= online (chiamate dalla sessione)

func online_waiting(s: int, slow: bool) -> void:
	if s >= 0:
		prompt_lbl.text = "Aspetto la mossa di %s…%s" % [eng.pname(s), " (è lento: se non torna gioca l'IA)" if slow else ""]
		for c in opzioni_box.get_children():
			c.queue_free()


func online_status(t: String) -> void:
	info_lbl.text = t


func online_caught_up() -> void:
	_aggiorna()


func online_cancel_decision(t: String) -> void:
	_avviso(t)
	annulla_scelta()
