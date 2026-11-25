class_name PaxAI
extends RefCounted
## Giocatore artificiale. Per le azioni del turno prova ogni alternativa su una copia della partita e
## sceglie quella che porta alla posizione migliore (valutazione di vittorie, soldi, imperi, concessioni,
## carte). Le scelte minori (dove piazzare un agente, chi sacrificare…) seguono regole da giocatore esperto.

var livello := 2          # 0 facile, 1 medio, 2 forte
var profondita := 1       # 1: partita vera; 0: dentro una simulazione


func _init(l := 2) -> void:
	livello = l


func decide(eng: PaxEngine, p: int, req: Dictionary) -> int:
	var opts: Array = req["opz"]
	if opts.size() <= 1:
		return 0
	match req["tipo"]:
		"azione":
			if profondita >= 1:
				return await _scegli_azione(eng, p, opts)
			return _euristica_azione(eng, p, opts)
		"op":
			if profondita >= 1 and livello >= 1:
				return await _scegli_op(eng, p, opts)
			return _euristica_op(eng, p, opts)
		"agente":
			return _agente(eng, p, opts)
		"perdita_att":
			return _perdita_att(opts)
		"premio":
			return _premio(eng, p, opts)
		"emancipa":
			return _emancipa(eng, p, opts)
		"tassa":
			return 0 if eng.P(p)["fl"] >= 3 and opts[0]["k"] == "paga" else opts.size() - 1
		"leva":
			return _leva(eng, p, opts, req)
		"cometa":
			return _cometa(eng, p, opts)
		"liberta", "machiavelli", "pacifica":
			return opts.size() - 1 if req["tipo"] == "liberta" else 0
	return 0

# ----------------------------------------------------------------------- azioni

func _scegli_azione(eng: PaxEngine, p: int, opts: Array) -> int:
	var base := valuta(eng, p)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(eng.S["turno"]) + str(p) + str(eng.passi))
	var valori := []
	var stati := []
	for i in opts.size():
		var o: Dictionary = opts[i]
		var v: float
		var e2: PaxEngine = null
		if o["k"] == "fine":
			v = base - 0.3
		else:
			e2 = eng.clona()
			var sub := PaxAI.new(livello)
			sub.profondita = 0
			e2.controller = sub
			await e2.esegui_azione(p, o)
			v = valuta(e2, p)
			# una seconda azione ancora disponibile vale qualcosa
			if o.get("gratis", false):
				v += 0.2
		valori.append(v)
		stati.append(e2)
	# IA forte: per le azioni più promettenti guarda anche la seconda azione del turno (combinazioni come
	# comprare una cometa e dichiarare la vittoria, comprare e giocare subito una carta con evento)
	if livello >= 2 and eng.S["fl"]["azioni"] == 0:
		var ordine := range(opts.size())
		ordine.sort_custom(func(a, b): return valori[a] > valori[b])
		for n in mini(6, ordine.size()):
			var i: int = ordine[n]
			var e2: PaxEngine = stati[i]
			if e2 == null or e2.S["over"] or e2.S["cur"] != p:
				continue
			var meglio: float = valori[i]
			for o2 in e2.azioni_legali(p):
				if o2["k"] == "fine":
					continue
				var e3 := e2.clona()
				var sub3 := PaxAI.new(livello)
				sub3.profondita = 0
				e3.controller = sub3
				await e3.esegui_azione(p, o2)
				meglio = maxf(meglio, valuta(e3, p))
			# metà del guadagno della seconda azione: gli avversari possono ancora reagire
			valori[i] = valori[i] * 0.5 + meglio * 0.5
	var best := -1
	var bv := -1e18
	for i in opts.size():
		var v: float = valori[i]
		if livello == 0:
			v += rng.randf_range(-3.0, 3.0)
		elif livello == 1:
			v += rng.randf_range(-1.0, 1.0)
		if v > bv:
			bv = v
			best = i
	return maxi(best, 0)


func _euristica_azione(eng: PaxEngine, p: int, opts: Array) -> int:
	for i in opts.size():
		if opts[i]["k"] == "fine":
			return i
	return 0


func _scegli_op(eng: PaxEngine, p: int, opts: Array) -> int:
	var base := valuta(eng, p)
	var best := -1
	var bv := -1e18
	for i in opts.size():
		var o: Dictionary = opts[i]
		var v: float
		if o["k"] == "fine" or not o.has("op"):
			v = base - 0.05
		else:
			var e2 := eng.clona()
			var sub := PaxAI.new(livello)
			sub.profondita = 0
			e2.controller = sub
			await e2.esegui_op(p, o["c"], o["op"], o)
			v = valuta(e2, p)
		if v > bv:
			bv = v
			best = i
	return maxi(best, 0)


func _euristica_op(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var o: Dictionary = opts[i]
		var v := 0.0
		if o["k"] == "fine" or not o.has("op"):
			v = 0.1
		else:
			var nome: String = o["op"].split(":")[0]
			match nome:
				"commerce":
					v = 3.0
				"repress":
					v = 1.5
					if o.has("b") and eng.S["bord"][o["b"]]["p"] == p:
						v = -2.0
					elif o.has("b"):
						v = 2.5
					elif o.has("e") and eng.S["emp"][o["e"]]["own"] == p:
						v = -1.0
				"siege":
					v = 1.0
					if o.has("e") and eng.S["emp"][o["e"]]["own"] == p:
						v = -1.5
				"vote":
					v = 4.0
				"campaign":
					v = 3.5
				"behead":
					var q := eng.proprietario(o["c"])
					v = 2.5 if q != p else -5.0
				"tax":
					v = 1.0 if eng.S["bord"][o["b"]]["p"] != p else -1.0
				"corsair":
					var b: Dictionary = eng.S["bord"][o["a"]]
					v = 2.0 if b["p"] >= 0 and b["p"] != p else (-3.0 if b["p"] == p else 0.2)
				"inq":
					var q := eng.proprietario(o["a"])
					v = 1.5 if q >= 0 and q != p else (-2.0 if q == p else 0.3)
		if v > bv:
			bv = v
			best = i
	return best

# ----------------------------------------------------------------------- scelte minori

func _agente(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var o: Dictionary = opts[i]
		var k: String = o["k"]
		var v := 0.0
		if k == "no":
			v = 0.0
		elif k.begins_with("card:"):
			var dest: String = o["dest"]
			var q := eng.proprietario(dest)
			if q == p:
				v = -2.0 if eng.ops_carta(dest).size() > 0 else 0.5
			elif q >= 0:
				v = 1.0 + eng.ops_carta(dest).size()
			else:
				v = 0.3
		elif k.begins_with("city:"):
			var e: String = o["e"]
			var own: int = eng.S["emp"][e]["own"]
			var occ: String = eng.S["city"][e][o["j"]]
			v = 2.0 if own == p else (0.6 if own < 0 else -1.0)
			if occ != "":
				v -= 0.8
		elif k.begins_with("bord:"):
			var b: Dictionary = eng.S["bord"][o["b"]]
			if o.has("e") or o["t"].begins_with("Concessione"):
				v = 2.5 + _valore_confine(eng, o["b"])
				if b["p"] >= 0:
					v += 0.8 if b["p"] != p else -9.0
			else:
				# pirata
				if b["p"] == p:
					v = -9.0
				elif b["p"] >= 0:
					v = 3.0
				else:
					v = 0.5 + _valore_confine(eng, o["b"]) * 0.3
		if v > bv:
			bv = v
			best = i
	return best


func _valore_confine(eng: PaxEngine, k: String) -> float:
	var v := 0.0
	for lato in ["W", "E"]:
		var em: String = eng.S["emporio"][lato]
		var rotta: Array = PaxDB.mappa["rotte"][em]["imperi"]
		for i in range(rotta.size() - 1):
			if eng.confine_tra(rotta[i], rotta[i + 1]) == k:
				v += 1.5 - i * 0.15
	return v


func _perdita_att(opts: Array) -> int:
	var pri := {"bord": 0, "rep": 2, "conc": 3, "x": 4}
	var best := 0
	var bv := 99
	for i in opts.size():
		var t: String = opts[i]["t"]
		var v := 4
		if t.contains("pirata"):
			v = 0
		elif t.contains("represso"):
			v = 2
		elif t.contains("concessione"):
			v = 3
		elif t.contains("agente"):
			v = 5
		elif t.contains(" a "):
			v = 1
		if v < bv:
			bv = v
			best = i
	return best


func _premio(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := 0.0
	for i in range(1, opts.size()):
		var o: Dictionary = opts[i]
		var v := 2.0 + _valore_confine(eng, o["b"])
		if eng.S["bord"][o["b"]]["p"] >= 0:
			v += 0.5 if eng.P(p)["fl"] >= 3 else -3.0
		if v > bv:
			bv = v
			best = i
	return best


func _emancipa(eng: PaxEngine, p: int, opts: Array) -> int:
	for i in range(1, opts.size()):
		var o: Dictionary = opts[i]
		if o["k"].begins_with("city:"):
			return i
		if o["t"].contains(eng.pname(p)):
			return i
	return 0


func _leva(eng: PaxEngine, p: int, opts: Array, req: Dictionary) -> int:
	for i in opts.size():
		if opts[i]["t"].begins_with("Cavaliere"):
			return i
	return 0


func _cometa(eng: PaxEngine, p: int, opts: Array) -> int:
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var v: String = opts[i]["v"]
		var x := _progresso(eng, p, v)
		if x > bv:
			bv = x
			best = i
	return best

# ----------------------------------------------------------------------- valutazione

func valuta(eng: PaxEngine, p: int) -> float:
	var S := eng.S
	if S["over"]:
		return 100000.0 if S["vincitore"] == p else -100000.0
	var mio := _punteggio(eng, p)
	var altri := -1e9
	for q in S["np"]:
		if q != p:
			altri = maxf(altri, _punteggio(eng, q))
	if altri < -1e8:
		altri = 0.0
	return mio - 0.8 * altri


func _punteggio(eng: PaxEngine, p: int) -> float:
	var S := eng.S
	var pl: Dictionary = S["players"][p]
	# i fiorini valgono sempre meno quando si accumulano: l'IA li spende invece di tesaurizzarli
	var fl: float = pl["fl"]
	var v := fl if fl <= 8.0 else 8.0 + (fl - 8.0) * 0.35
	for k in S["bord"]:
		if S["bord"][k]["p"] == p:
			v += 2.0 + _valore_confine(eng, k) * 0.6
	for e in S["emp"]:
		var em: Dictionary = S["emp"][e]
		if em["own"] == p:
			v += 4.0
			v += eng.classe_dominante(e).size() * 0.6
			v -= em["rep"].size() * 0.3
	for id in eng.carte_tableau(p):
		if id.begins_with("@"):
			continue
		var c := eng.card(id)
		v += 1.5 + eng.ops_carta(id).size() * 0.5 + c.get("abilita", []).size() * 0.8
		if eng.silenziata(p, id):
			v -= 0.5 + eng.ops_carta(id).size() * 0.5
	for id in pl["hand"]:
		var c := eng.card(id)
		v += 1.8 + c.get("ops", []).size() * 0.4 + (1.0 if c.get("oneshot", "") != "" else 0.0) + c.get("prestigio", []).size() * 0.5
	for x in ["C", "I", "R", "L", "D", "P"]:
		v += eng.conta_prestigio(p, x) * 0.5
	for vt in S["vict"]:
		var peso := 2.2 if S["vict"][vt] else 0.5
		v += _progresso(eng, p, vt) * peso
		if eng.condizioni_vittoria(p, vt):
			v += 60.0 if S["vict"][vt] else 12.0
	return v


## Vantaggio verso una vittoria rispetto al miglior avversario (numero positivo = in testa).
func _progresso(eng: PaxEngine, p: int, vt: String) -> float:
	var S := eng.S
	var best_o := -1e9
	var mio := 0.0
	match vt:
		"imperiale":
			mio = eng.re_count(p) * 3.0
			for q in S["np"]:
				if q != p:
					best_o = maxf(best_o, eng.re_count(q) * 3.0)
		"globalizzazione":
			mio = eng.concessioni(p) * 1.5 + eng.conta_prestigio(p, "D") * 3.0
			for q in S["np"]:
				if q != p:
					best_o = maxf(best_o, eng.concessioni(q) * 1.5 + eng.conta_prestigio(q, "D") * 3.0)
		"rinascimento":
			mio = eng.repubbliche(p) * 3.5 + eng.conta_prestigio(p, "L") * 2.0
			for q in S["np"]:
				if q != p:
					best_o = maxf(best_o, eng.repubbliche(q) * 3.5 + eng.conta_prestigio(q, "L") * 2.0)
		"bizantina":
			var r0 := eng.religione_piu_teocrazie()
			mio = eng.re_count(p) * 3.0 + (eng.conta_prestigio(p, r0) * 2.0 if r0 != "" else 0.0)
			for q in S["np"]:
				if q != p:
					best_o = maxf(best_o, eng.re_count(q) * 3.0 + (eng.conta_prestigio(q, r0) * 2.0 if r0 != "" else 0.0))
		"santa":
			var r := eng.supremazia(p)
			if r == "":
				for x in ["C", "I", "R"]:
					mio = maxf(mio, eng.conta_prestigio(p, x) * 1.0)
				best_o = 0.0
			else:
				mio = eng.conta_prestigio(p, r) * 3.0
				for q in S["np"]:
					if q != p:
						best_o = maxf(best_o, eng.conta_prestigio(q, r) * 3.0)
	if best_o < -1e8:
		best_o = 0.0
	return mio - best_o
