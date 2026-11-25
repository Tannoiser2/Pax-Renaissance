extends Control
## Menu principale: nuova partita (contro l'IA o in più persone sullo stesso dispositivo), online, carica, regole.

var main
var panel: Control
var n_gioc := 3
var tipi := [0, 3, 3, 3]          # 0 persona, 1 IA facile, 2 IA media, 3 IA forte
var nomi := ["", "", "", ""]
var righe_box: VBoxContainer
var bottoni_n := []
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var promo := false
var banchieri_promo := true

const TIPI := ["Persona", "IA facile", "IA media", "IA forte"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if main.menu_state.has("tipi"):
		tipi = main.menu_state["tipi"]
		n_gioc = main.menu_state["n"]
		nomi = main.menu_state["nomi"]
		promo = main.menu_state.get("promo", false)
		banchieri_promo = main.menu_state.get("banchieri_promo", true)
	var sf := TextureRect.new()
	sf.texture = load("res://assets/ui/sfondo.webp")
	sf.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(sf)
	var vel := ColorRect.new()
	vel.color = Color(0.05, 0.03, 0.02, 0.35)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", Stile.box(Color(0.10, 0.07, 0.05, 0.88), Stile.ORO, 3, 12, 30))
	c.add_child(pan)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.custom_minimum_size.x = 640
	pan.add_child(vb)
	var t := Stile.etichetta("Pax Renaissance", 86, "gotico", Stile.ORO_CHIARO)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var st := Stile.etichetta("I banchieri del Rinascimento, 1460-1530 · seconda edizione", 24, "corsivo", Stile.PERGAMENA)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(st)
	var sep := HSeparator.new()
	vb.add_child(sep)
	for b in [["Nuova partita", _pannello_nuova], ["Gioca online con gli amici", _pannello_online],
			["Carica una partita salvata", _pannello_carica], ["Regole del gioco", _regole]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(560, 62)
		bt.add_theme_font_size_override("font_size", 28)
		bt.pressed.connect(b[1])
		vb.add_child(bt)
	var cr := Stile.etichetta("Gioco di Phil e Matt Eklund (Ion Game Design). Versione digitale per la ludoteca di Stefano.", 17, "compatto", Color(0.8, 0.75, 0.65))
	cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cr.custom_minimum_size.x = 600
	vb.add_child(cr)


func _overlay(w: float) -> VBoxContainer:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.6)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	panel = vel
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vel.add_child(c)
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", Stile.box(Color(0.12, 0.08, 0.05, 0.97), Stile.ORO, 3, 12, 24))
	c.add_child(pan)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = w
	vb.add_theme_constant_override("separation", 12)
	pan.add_child(vb)
	return vb


func _testo(t: String, w: float, dim := 21) -> Label:
	var l := Stile.etichetta(t, dim, "compatto", Stile.PERGAMENA)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l

# ----------------------------------------------------------------------- nuova partita

func _pannello_nuova() -> void:
	var vb := _overlay(760)
	vb.add_child(Stile.etichetta("Nuova partita", 48, "titolo", Stile.ORO_CHIARO))
	vb.add_child(_testo("Da 1 a 4 banchieri. Ogni posto può essere una persona (sullo stesso dispositivo, con il passaggio di mano) o il computer. Le banche (Fugger, Medici, Cœur, Marchionni) si assegnano a caso; comincia chi ha i Fugger. Con 1 giocatore si gioca il solitario ufficiale contro l'avversario automatico del Libro II.", 740))
	var hn := HBoxContainer.new()
	hn.add_theme_constant_override("separation", 10)
	hn.add_child(Stile.etichetta("Giocatori:", 24, "titolo", Stile.PERGAMENA))
	bottoni_n = []
	for k in [1, 2, 3, 4]:
		var b := Button.new()
		b.text = str(k)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(80, 50)
		b.pressed.connect(func():
			n_gioc = k
			_righe())
		hn.add_child(b)
		bottoni_n.append(b)
	vb.add_child(hn)
	righe_box = VBoxContainer.new()
	righe_box.add_theme_constant_override("separation", 8)
	vb.add_child(righe_box)
	_righe()
	_opzioni_promo(vb, 740)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var go := Button.new()
	go.text = "Inizia la partita"
	go.custom_minimum_size = Vector2(400, 62)
	go.add_theme_font_size_override("font_size", 28)
	go.pressed.connect(_inizia)
	hb.add_child(go)
	var ind := Button.new()
	ind.text = "Indietro"
	ind.custom_minimum_size = Vector2(240, 62)
	ind.pressed.connect(func(): panel.queue_free())
	hb.add_child(ind)
	vb.add_child(hb)


## Casella della promo «Età della Riforma» (variante 1550) e dei suoi due banchieri.
func _opzioni_promo(vb: VBoxContainer, w: float) -> void:
	var cb := CheckBox.new()
	cb.text = "Promo «Età della Riforma» (variante 1550)"
	cb.button_pressed = promo
	cb.add_theme_font_size_override("font_size", 22)
	cb.custom_minimum_size = Vector2(w, 44)
	vb.add_child(cb)
	var spieg := _testo("Inghilterra e Sacro Romano Impero partono come teocrazie riformate, la rotta d'Occidente parte dal Mar Rosso (Trebisonda chiusa), Ungheria e Ottomani usano le nuove carte mappa (Confederazione polacco-lituana e Rumelia), 8 nuove carte di mercato, il quadrato bizantino al posto di quello ottomano e la quinta vittoria: la vittoria bizantina.", w, 18)
	vb.add_child(spieg)
	var cb2 := CheckBox.new()
	cb2.text = "Anche i banchieri promo Alvaro Mendes e Cornelius Berenberg"
	cb2.button_pressed = banchieri_promo
	cb2.add_theme_font_size_override("font_size", 20)
	cb2.custom_minimum_size = Vector2(w, 40)
	cb2.disabled = not promo
	vb.add_child(cb2)
	cb.toggled.connect(func(x):
		promo = x
		cb2.disabled = not x)
	cb2.toggled.connect(func(x): banchieri_promo = x)


func _righe() -> void:
	for i in bottoni_n.size():
		bottoni_n[i].button_pressed = int(bottoni_n[i].text) == n_gioc
	for c in righe_box.get_children():
		c.queue_free()
	if n_gioc == 1:
		var h1 := HBoxContainer.new()
		var le1 := LineEdit.new()
		le1.placeholder_text = "Il tuo nome (giochi con i Fugger)"
		le1.text = nomi[0]
		le1.max_length = 22
		le1.custom_minimum_size = Vector2(400, 52)
		le1.text_changed.connect(func(t): nomi[0] = t)
		h1.add_child(le1)
		righe_box.add_child(h1)
		righe_box.add_child(_testo("Solitario ufficiale: tu sei Fugger (3 ƒ), l'avversario automatico ha le altre tre concessioni iniziali e 4 ƒ. Le comete sono fra le ultime 8 carte di ogni mazzo. Vinci con una delle vittorie delle comete (non con quella dei mecenati); l'avversario vince se all'inizio del suo turno può dichiarare una vittoria, anche comprando una cometa, o se il mercato non si può più rifornire.", 740, 18))
		return
	for i in n_gioc:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var le := LineEdit.new()
		le.placeholder_text = "Nome (vuoto: il nome della banca)" if tipi[i] != 0 else "Nome del giocatore %d" % (i + 1)
		le.text = nomi[i]
		le.max_length = 22
		le.custom_minimum_size = Vector2(400, 52)
		le.text_changed.connect(func(t): nomi[i] = t)
		h.add_child(le)
		var ob := OptionButton.new()
		for t in TIPI:
			ob.add_item(t)
		ob.selected = tipi[i]
		ob.custom_minimum_size = Vector2(240, 52)
		ob.item_selected.connect(func(x): tipi[i] = x)
		h.add_child(ob)
		righe_box.add_child(h)


func _salva_stato() -> void:
	main.menu_state = {"tipi": tipi, "n": n_gioc, "nomi": nomi, "promo": promo, "banchieri_promo": banchieri_promo}


func _config() -> Dictionary:
	if n_gioc == 1:
		var nm1: String = nomi[0].strip_edges()
		return {"giocatori": [{"name": nm1 if nm1 != "" else "Tu", "ai": false, "bank": "Fugger"},
			{"name": "", "ai": true, "livello": 2}], "seme": 1 + randi() % 2000000000,
			"opzioni": {"banche_casuali": true, "solitario": true, "promo": promo}}
	var gg := []
	for i in n_gioc:
		var nm: String = nomi[i].strip_edges()
		if nm == "" and tipi[i] == 0:
			nm = "Tu" if i == 0 else "Giocatore %d" % (i + 1)
		gg.append({"name": nm, "ai": tipi[i] != 0, "livello": maxi(0, tipi[i] - 1)})
	return {"giocatori": gg, "seme": 1 + randi() % 2000000000, "opzioni": {"banche_casuali": true, "promo": promo,
		"banchieri_promo": promo and banchieri_promo}}


func _inizia() -> void:
	var cfg := _config()
	# tutti i posti all'IA: si guarda la partita (modalità spettatore)
	_salva_stato()
	main.start_game(cfg)

# ----------------------------------------------------------------------- online

func _pannello_online() -> void:
	var vb := _overlay(820)
	vb.add_child(Stile.etichetta("Gioca online", 48, "titolo", Stile.ORO_CHIARO))
	if n_gioc < 2:
		n_gioc = 2
	vb.add_child(_testo("Chi crea la stanza sceglie qui sotto quanti giocatori e quali posti sono persone: i posti «Persona» restano liberi per gli amici, che entrano con il codice di 4 lettere; i posti dell'IA (e quelli rimasti liberi alla partenza) li gioca il computer di chi ha creato la stanza. Si può rientrare nella partita con lo stesso codice.", 800))
	righe_box = VBoxContainer.new()
	var hn := HBoxContainer.new()
	hn.add_theme_constant_override("separation", 10)
	hn.add_child(Stile.etichetta("Giocatori:", 22, "titolo", Stile.PERGAMENA))
	bottoni_n = []
	for k in [2, 3, 4]:
		var b := Button.new()
		b.text = str(k)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(70, 46)
		b.pressed.connect(func():
			n_gioc = k
			_righe())
		hn.add_child(b)
		bottoni_n.append(b)
	vb.add_child(hn)
	vb.add_child(righe_box)
	_righe()
	_opzioni_promo(vb, 800)
	var ses: Dictionary = main.get_net().load_session()
	on_name = LineEdit.new()
	on_name.placeholder_text = "Il tuo nome"
	on_name.max_length = 20
	on_name.custom_minimum_size = Vector2(0, 52)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_crea := Button.new()
	b_crea.text = "Crea una stanza"
	b_crea.custom_minimum_size = Vector2(0, 54)
	b_crea.pressed.connect(_crea)
	vb.add_child(b_crea)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = LineEdit.new()
	on_code.placeholder_text = "Codice"
	on_code.max_length = 4
	on_code.custom_minimum_size = Vector2(220, 52)
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_entra := Button.new()
	b_entra.text = "Entra"
	b_entra.custom_minimum_size = Vector2(200, 52)
	b_entra.pressed.connect(_entra)
	row.add_child(b_entra)
	vb.add_child(row)
	on_lbl = _testo("", 800, 22)
	on_lbl.custom_minimum_size.y = 100
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = Button.new()
	on_start.text = "Inizia online"
	on_start.custom_minimum_size = Vector2(400, 58)
	on_start.pressed.connect(_avvia_online)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var bc := Button.new()
	bc.text = "Indietro"
	bc.custom_minimum_size = Vector2(260, 58)
	bc.pressed.connect(func():
		main.lobby = {}
		panel.queue_free())
	row2.add_child(bc)
	vb.add_child(row2)
	if str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _testo_posti(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parti := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var chi := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parti.append("posto %d: %s" % [int(idx) + 1, chi])
	return ", ".join(parti)


func _crea() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	tipi[0] = 0
	var seats := [0]
	for s in range(1, n_gioc):
		if tipi[s] == 0:
			seats.append(s)
	if seats.size() < 2:
		_say("Segna «Persona» almeno un posto oltre al tuo, per l'amico.")
		return
	_salva_stato()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": 0}
	net.remember_room(code, 0)
	net._save({"name": nm})
	on_code.text = code
	on_start.visible = true
	_attendi(code)


func _entra() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_comincia(room["game"], true)
		return
	on_start.visible = main.lobby["role"] == "host"
	_attendi(code)


func _attendi(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice agli amici.\n%s.\nQuando ci sono premi «Inizia online» (i posti liberi li gioca l'IA)." % [code, _testo_posti(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_comincia(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] al posto %d.\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1])
		await get_tree().create_timer(2.0).timeout


func _avvia_online() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	for i in n_gioc:
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary:
			cfg["giocatori"][i]["name"] = str(seats_db[k].get("name", cfg["giocatori"][i]["name"]))
			cfg["giocatori"][i]["ai"] = false
		else:
			cfg["giocatori"][i]["ai"] = true
			cfg["giocatori"][i]["livello"] = 2 if tipi[i] == 0 else maxi(0, tipi[i] - 1)
			if tipi[i] == 0:
				cfg["giocatori"][i]["name"] = ""
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_comincia(g, false)


func _comincia(g: Dictionary, rientro: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rientro:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)

# ----------------------------------------------------------------------- carica

func _pannello_carica() -> void:
	var vb := _overlay(760)
	vb.add_child(Stile.etichetta("Carica partita", 48, "titolo", Stile.ORO_CHIARO))
	vb.add_child(_testo("Scrivi il codice di 6 lettere ottenuto con «Salva» durante la partita. Le partite salvate stanno su Firebase e si riprendono da qualsiasi dispositivo.", 740))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = LineEdit.new()
	on_code.placeholder_text = "Codice"
	on_code.max_length = 6
	on_code.custom_minimum_size = Vector2(260, 54)
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b := Button.new()
	b.text = "Carica"
	b.custom_minimum_size = Vector2(220, 54)
	b.pressed.connect(_carica)
	row.add_child(b)
	vb.add_child(row)
	on_lbl = _testo("", 740, 22)
	on_lbl.custom_minimum_size.y = 70
	vb.add_child(on_lbl)
	var bc := Button.new()
	bc.text = "Indietro"
	bc.custom_minimum_size = Vector2(260, 54)
	bc.pressed.connect(func(): panel.queue_free())
	vb.add_child(bc)


func _carica() -> void:
	var code := on_code.text.strip_edges().to_upper()
	if code.length() != 6:
		_say("Il codice ha 6 lettere.")
		return
	_say("Carico la partita %s…" % code)
	var net: Net = main.get_net()
	var data := await net.load_game(code)
	if data.is_empty():
		_say("Partita %s non trovata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	var cfg = str_to_var(str(data.get("cfg", "")))
	var moves = str_to_var(str(data.get("moves", "[]")))
	if not (cfg is Dictionary) or not (moves is Array):
		_say("Salvataggio non valido.")
		return
	cfg["replay"] = moves
	main.start_game(cfg)
	if main.current != null:
		main.current.save_code = code


func _regole() -> void:
	var r := preload("res://scripts/ui/rules_view.gd").new()
	r.sovrapposto = true
	add_child(r)
