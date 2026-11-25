class_name PaxSoloBot
extends PaxAI
## Avversario automatico del solitario ufficiale (Libro II, parte O, di José Cunha e Kevin Thatcher).
## Ogni turno sceglie una «linea d'azione» (riga della tabella O8) per sostituzione cometaria o per innesco,
## poi prova l'obiettivo principale, il secondario e quello di prestigio. Un obiettivo è raggiunto se una
## mossa (comprare e giocare una carta del mercato da sinistra a destra, le operazioni d'Oriente o
## d'Occidente, una fiera, una vendita), provata su una copia della partita, ottiene l'effetto richiesto.
## Le scelte minori seguono le regole O5 (concessioni, pirati, leve, tasse, vescovi, incoronazioni).

var umano := 0


func _init(l := 2) -> void:
	livello = l


func decide(eng: PaxEngine, p: int, req: Dictionary) -> int:
	var opts: Array = req["opz"]
	if opts.size() <= 1:
		return 0
	umano = 1 - p
	match req["tipo"]:
		"azione":
			return await _azione(eng, p, opts)
		"op":
			return await _op(eng, p, opts)
		"agente":
			return _agente_bot(eng, p, opts)
		"tassa":
			# paga per non farsi reprimere, ma non spende l'ultimo fiorino (O5a)
			return 0 if eng.P(p)["fl"] >= 2 and opts[0]["k"] == "paga" else opts.size() - 1
		"leva":
			return _leva_bot(eng, p, opts)
		"premio":
			return _premio_bot(eng, p, opts)
	return await super.decide(eng, p, req)

# ----------------------------------------------------------------------- tabella O8

## Righe della tabella: [sostituzione cometaria, innesco] valutate sullo stato attuale.
func _righe(eng: PaxEngine, p: int) -> Array:
	var S := eng.S
	var h := umano
	var resta: int = 2 - S["fl"]["azioni"]
	var dom := _dominante(eng)
	var ov := [
		S["vict"].get("imperiale", false),
		S["vict"].get("rinascimento", false) and eng.conta_prestigio(p, "L") <= eng.conta_prestigio(h, "L"),
		S["vict"].get("santa", false) and _prest_suprema(eng, p) <= _prest_suprema(eng, h),
		S["vict"].get("santa", false) and _prest_suprema(eng, p) <= _prest_suprema(eng, h),
		S["vict"].get("globalizzazione", false) and eng.conta_prestigio(p, "D") <= eng.conta_prestigio(h, "D"),
		false, false]
	var tr := [
		eng.re_count(h) >= eng.re_count(p) + 2,
		eng.repubbliche(p) < eng.repubbliche(h),
		dom["credenti"] != "",
		dom["vescovi"] != "",
		eng.concessioni(h) >= eng.concessioni(p) + 2,
		resta >= 2,
		resta == 1 or eng.P(p)["fl"] < 3]
	return [ov, tr]


func _azione(eng: PaxEngine, p: int, opts: Array) -> int:
	# carta appena comprata: va giocata subito
	if not eng.P(p)["hand"].is_empty():
		return await _gioca_comprata(eng, p, opts)
	var rr := _righe(eng, p)
	var ov: Array = rr[0]
	var tr: Array = rr[1]
	var inizio := -1
	var override := false
	for i in 7:
		if ov[i] and tr[i]:
			inizio = i
			override = true
			break
	if inizio < 0:
		for i in 7:
			if tr[i]:
				inizio = i
				break
	if inizio < 0:
		inizio = 6
	for riga in range(inizio, 7):
		for obiettivo in 3:
			var k := await _prova(eng, p, opts, riga, obiettivo, override and riga == inizio)
			if k >= 0:
				return k
	# niente di utile: una fiera se possibile, altrimenti fine turno
	var f: int = await _fiera_migliore(eng, p, opts)
	if f >= 0:
		return f
	for i in opts.size():
		if opts[i]["k"] == "fine":
			return i
	return 0


## Prova un obiettivo (0 principale, 1 secondario, 2 prestigio) di una riga: indice dell'azione o -1.
func _prova(eng: PaxEngine, p: int, opts: Array, riga: int, ob: int, override: bool) -> int:
	var resta: int = 2 - eng.S["fl"]["azioni"]
	var compra_ok := resta >= 2
	var ops_ok := true
	var fiera_ok := false
	var vendi_ok := false
	match [riga, ob]:
		[3, 0]:
			vendi_ok = true
		[6, 0]:
			fiera_ok = true
			vendi_ok = true
		[5, 0]:
			ops_ok = false
		[2, 0]:
			fiera_ok = true
	if riga == 6 and ob == 0:
		compra_ok = false
	if ob == 2:
		ops_ok = false
	var dom := _dominante(eng)
	# 1) comprare e giocare una carta, da sinistra a destra (a parità di posto prima l'Oriente)
	if compra_ok:
		for i in range(1, 6):
			for lato in ["E", "W"]:
				for k in opts.size():
					var o: Dictionary = opts[k]
					if o["tipo"] != "buy" or o["lato"] != lato or o["i"] != i:
						continue
					if ob == 2 and not override and i - eng.S["mk"][lato][i]["f"] > 1:
						continue
					if riga == 5 and ob == 0:
						# la carta con prestigio più a sinistra
						if eng.card(o["c"]).get("prestigio", []).is_empty():
							continue
						return k
					if await _compra_gioca_ok(eng, p, o, riga, ob, dom):
						return k
	# 2) operazioni d'Oriente o d'Occidente
	if ops_ok:
		for k in opts.size():
			var o: Dictionary = opts[k]
			if o["tipo"] != "ops":
				continue
			var e2 := _copia(eng)
			await e2.esegui_azione(p, o)
			if _raggiunto(eng, e2, p, riga, ob, dom):
				return k
	# 3) fiera
	if fiera_ok:
		var f: int = await _fiera_migliore(eng, p, opts)
		if f >= 0:
			return f
	# 4) vendita
	if vendi_ok:
		for k in opts.size():
			var o: Dictionary = opts[k]
			if o["tipo"] != "sell" or o["da"] != "t" or o["c"].begins_with("@"):
				continue
			var pr: Array = eng.prestigio(o["c"])
			if riga == 6:
				var ok := true
				for x in pr:
					if x != "P":
						ok = false
				if ok:
					return k
			elif riga == 3 and eng.S["bish"].get(o["c"], "") == dom["vescovi"] and dom["vescovi"] != "":
				return k
	return -1


func _copia(eng: PaxEngine) -> PaxEngine:
	var e2 := eng.clona()
	var sub := PaxSoloBot.new(livello)
	sub.profondita = 0
	e2.controller = sub
	return e2


## Compra la carta o["c"] e prova a giocarla in ogni variante: l'obiettivo è raggiunto?
func _compra_gioca_ok(eng: PaxEngine, p: int, o: Dictionary, riga: int, ob: int, dom: Dictionary) -> bool:
	var e1 := _copia(eng)
	await e1.esegui_azione(p, o)
	for v in e1.varianti_gioco(p, o["c"]):
		var e2 := _copia(e1)
		await e2.esegui_azione(p, v)
		if _raggiunto(eng, e2, p, riga, ob, dom):
			return true
	return false


func _gioca_comprata(eng: PaxEngine, p: int, opts: Array) -> int:
	var rr := _righe(eng, p)
	var dom := _dominante(eng)
	# una variante che raggiunge un obiettivo di qualche riga attiva
	for riga in 7:
		if not rr[1][riga]:
			continue
		for ob in 3:
			for k in opts.size():
				var o: Dictionary = opts[k]
				if o["tipo"] != "play":
					continue
				var e2 := _copia(eng)
				await e2.esegui_azione(p, o)
				if _raggiunto(eng, e2, p, riga, ob, dom):
					return k
	# altrimenti l'evento solo se conquista un impero o danneggia il giocatore almeno quanto il bot (O5h)
	var best := -1
	var bv := -1e9
	for k in opts.size():
		var o: Dictionary = opts[k]
		if o["tipo"] != "play":
			continue
		var e2 := _copia(eng)
		await e2.esegui_azione(p, o)
		var v := 0.0
		if o.get("os", "") != "":
			var preso := _imperi(e2, p) > _imperi(eng, p)
			var danno_u := _forza(eng, umano) - _forza(e2, umano)
			var danno_b := _forza(eng, p) - _forza(e2, p)
			if preso or (danno_u > 0 and danno_u >= danno_b):
				v = 10.0
			else:
				v = -10.0
		if v > bv:
			bv = v
			best = k
	return maxi(best, 0)


func _imperi(eng: PaxEngine, p: int) -> int:
	var n := 0
	for e in eng.S["emp"]:
		if eng.S["emp"][e]["own"] == p:
			n += 1
	return n


func _forza(eng: PaxEngine, p: int) -> float:
	return eng.P(p)["fl"] + eng.concessioni(p) * 2 + _imperi(eng, p) * 3 + eng.carte_tableau(p).size()


# ----------------------------------------------------------------------- obiettivi

## Religione dominante per credenti (unità nelle sue teocrazie più di tutte le altre insieme) e per vescovi.
func _dominante(eng: PaxEngine) -> Dictionary:
	var unita := {"C": 0, "I": 0, "R": 0}
	var vesc := {"C": 0, "I": 0, "R": 0}
	for e in eng.S["th"]:
		var t: String = eng.S["th"][e]
		if t == "M":
			continue
		for x in eng.S["city"][e]:
			if x != "" and x.ends_with(":" + t):
				unita[t] += 1
	for k in eng.S["bish"]:
		vesc[eng.S["bish"][k]] += 1
	var out := {"credenti": "", "vescovi": "", "teocrazie": eng.religione_piu_teocrazie()}
	for r in ["C", "I", "R"]:
		var au := 0
		var av := 0
		for q in ["C", "I", "R"]:
			if q != r:
				au += unita[q]
				av += vesc[q]
		if unita[r] > au:
			out["credenti"] = r
		if vesc[r] > av:
			out["vescovi"] = r
	return out


func _prest_suprema(eng: PaxEngine, p: int) -> int:
	var r := eng.supremazia()
	if r == "":
		r = _dominante(eng)["credenti"]
	if r == "":
		return 0
	return eng.conta_prestigio(p, r)


func _rossa(eng: PaxEngine, p: int, v: String) -> int:
	var n := 0
	for id in eng.carte_tableau(p):
		if v in eng.card(id).get("rosse", []):
			n += 1
	return n


func _pezzi_regni(eng: PaxEngine, q: int, lato: String) -> int:
	var n := 0
	for e in eng.S["emp"]:
		var em: Dictionary = eng.S["emp"][e]
		if em["own"] == q and em["side"] == lato:
			for x in eng.S["city"][e]:
				if x != "":
					n += 1
			n += 10
	return n


func _pezzi_teocrazie(eng: PaxEngine, r: String, stessa: bool) -> int:
	var n := 0
	for e in eng.S["th"]:
		if eng.S["th"][e] != r:
			continue
		for x in eng.S["city"][e]:
			if x != "" and (x.ends_with(":" + r) == stessa):
				n += 1
	return n


func _teocrazie(eng: PaxEngine, r: String) -> int:
	var n := 0
	for e in eng.S["th"]:
		if eng.S["th"][e] == r:
			n += 1
	return n


func _vescovi_bot(eng: PaxEngine, p: int, r: String, stessa: bool) -> int:
	var n := 0
	for id in eng.carte_tableau(p):
		var b: String = eng.S["bish"].get(id, "")
		if b != "" and ((b == r) == stessa):
			n += 1
	return n


## L'obiettivo (riga, ob) è raggiunto passando dallo stato a allo stato b?
func _raggiunto(a: PaxEngine, b: PaxEngine, p: int, riga: int, ob: int, dom: Dictionary) -> bool:
	if b.S["over"]:
		return b.S["vincitore"] == p
	var h := umano
	var dc: String = dom["credenti"]
	var dv: String = dom["vescovi"]
	var dt: String = dom["teocrazie"] if dom["teocrazie"] != "" else (dc if dc != "" else dv)
	match [riga, ob]:
		[0, 0]:
			return b.re_count(h) < a.re_count(h) or b.re_count(p) > a.re_count(p)
		[0, 1]:
			return _pezzi_regni(b, h, "K") < _pezzi_regni(a, h, "K")
		[0, 2]:
			return _rossa(b, p, "imperiale") > _rossa(a, p, "imperiale")
		[1, 0]:
			return b.repubbliche(h) < a.repubbliche(h) or b.repubbliche(p) > a.repubbliche(p)
		[1, 1]:
			return _pezzi_regni(b, h, "R") < _pezzi_regni(a, h, "R") or b.conta_prestigio(p, "L") > a.conta_prestigio(p, "L")
		[1, 2]:
			return b.conta_prestigio(p, "L") > a.conta_prestigio(p, "L")
		[2, 0]:
			if dc == "":
				return false
			return _pezzi_teocrazie(b, dc, true) < _pezzi_teocrazie(a, dc, true) or _pezzi_teocrazie(b, dc, false) > _pezzi_teocrazie(a, dc, false)
		[2, 1], [3, 1]:
			return _rossa(b, p, "santa") > _rossa(a, p, "santa")
		[2, 2], [3, 2]:
			var r := dc if riga == 2 else dv
			return r != "" and b.conta_prestigio(p, r) > a.conta_prestigio(p, r)
		[3, 0]:
			if dv == "":
				return false
			var va := 0
			var vb := 0
			for k in a.S["bish"]:
				if a.S["bish"][k] == dv:
					va += 1
			for k in b.S["bish"]:
				if b.S["bish"][k] == dv:
					vb += 1
			return vb < va or _vescovi_bot(b, p, dv, false) > _vescovi_bot(a, p, dv, false)
		[4, 0]:
			return b.concessioni(h) < a.concessioni(h) or b.concessioni(p) > a.concessioni(p)
		[4, 1]:
			return _rossa(b, p, "globalizzazione") > _rossa(a, p, "globalizzazione")
		[4, 2]:
			return b.conta_prestigio(p, "D") > a.conta_prestigio(p, "D")
		[5, 1], [6, 1]:
			if dt == "":
				return false
			var piu_altre := false
			for r in ["C", "I", "R"]:
				if r != dt and _teocrazie(b, r) > _teocrazie(a, r):
					piu_altre = true
			return _teocrazie(b, dt) < _teocrazie(a, dt) or piu_altre
		[5, 2]:
			return dt != "" and b.conta_prestigio(p, dt) > a.conta_prestigio(p, dt) and b.conta_prestigio(p, dt) >= b.conta_prestigio(h, dt)
		[6, 2]:
			return dt != "" and b.conta_prestigio(p, dt) > a.conta_prestigio(p, dt)
		[6, 0]:
			# operazioni di commercio
			return b.P(p)["fl"] > a.P(p)["fl"]
	return false

# ----------------------------------------------------------------------- scelte minori (O5)

func _op(eng: PaxEngine, p: int, opts: Array) -> int:
	# commercio sempre; per le altre operazioni sceglie quella che danneggia di più il giocatore
	var best := -1
	var bv := 0.0
	for i in opts.size():
		var o: Dictionary = opts[i]
		if o["k"] == "fine" or not o.has("op"):
			continue
		var nome: String = o["op"].split(":")[0]
		if nome == "commerce":
			# priorità: fiorini su un posto vuoto del mercato, poi la carta scoperta più a sinistra
			var v: float = 50.0 - float(o.get("i", 0))
			if eng.S["mk"][o.get("lato", "W")][o.get("i", 0)]["c"] == "":
				v += 20.0
			if v > bv:
				bv = v
				best = i
			continue
		var e2 := _copia(eng)
		await e2.esegui_op(p, o["c"], o["op"], o)
		var d := (_forza(eng, umano) - _forza(e2, umano)) - (_forza(eng, p) - _forza(e2, p)) * 0.8
		if nome == "campaign":
			d += (_imperi(e2, p) - _imperi(eng, p)) * 4.0
		if d > bv:
			bv = d
			best = i
	if best < 0:
		for i in opts.size():
			if opts[i]["k"] == "fine":
				return i
		return 0
	return best


func _fiera_migliore(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := -1
	var bv := -1e9
	for k in opts.size():
		var o: Dictionary = opts[k]
		if o["tipo"] != "fair":
			continue
		var e2 := _copia(eng)
		await e2.esegui_azione(p, o)
		var v: float = (e2.P(p)["fl"] - eng.P(p)["fl"]) * 100.0 - (e2.P(umano)["fl"] - eng.P(umano)["fl"]) * 10.0
		if o["lato"] == "E":
			v += 1.0
		if v > bv:
			bv = v
			best = k
	return best


func _agente_bot(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var o: Dictionary = opts[i]
		var k: String = o["k"]
		var v := 0.0
		if k == "no":
			v = 0.0
		elif k.begins_with("bord:"):
			var b: Dictionary = eng.S["bord"][o["b"]]
			if b["p"] == p:
				v = -100.0
			elif b["p"] == umano:
				v = 50.0 + _valore_confine(eng, o["b"])
			else:
				v = 5.0 + _valore_confine(eng, o["b"])
		elif k.begins_with("city:"):
			# cavalieri e torri solo negli imperi del bot
			v = 3.0 if eng.S["emp"][o["e"]]["own"] == p else -5.0
		elif k.begins_with("card:"):
			# vescovi sulla carta che gioca (la più recente del suo tableau)
			var dest: String = o["dest"]
			if eng.proprietario(dest) == p:
				var tab: Array = eng.carte_tableau(p)
				v = 10.0 + float(tab.find(dest))
			else:
				v = -1.0
		if v > bv:
			bv = v
			best = i
	return best


func _leva_bot(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var o: Dictionary = opts[i]
		if not o.has("k") or not str(o["k"]).begins_with("city:"):
			continue
		var parti: PackedStringArray = str(o["k"]).split(":")
		var e: String = parti[1]
		var j := int(parti[2])
		var t := eng.icona(e, j)
		var r := t.split(":")[1]
		var v := 0.0
		if eng.S["th"][e] == r:
			v -= 10.0
		var presente := false
		for x in eng.S["city"][e]:
			if x != "" and x.ends_with(":" + r):
				presente = true
		if not presente:
			v += 3.0
		if t.begins_with("R"):
			v += 1.0
		if v > bv:
			bv = v
			best = i
	return best


func _premio_bot(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := 0.0
	for i in range(1, opts.size()):
		var o: Dictionary = opts[i]
		var b: Dictionary = eng.S["bord"][o["b"]]
		var v := 2.0 + _valore_confine(eng, o["b"])
		if b["p"] == umano:
			v += 20.0
		elif b["p"] == p:
			v = -100.0
		if v > bv:
			bv = v
			best = i
	return best
