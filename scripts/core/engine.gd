class_name PaxEngine
extends RefCounted
## Motore delle regole di Pax Renaissance (2ª edizione).
## Tutto lo stato sta nel dizionario S (serializzabile e copiabile). Ogni scelta passa da ask(): la decide
## la persona davanti al dispositivo, l'IA o la partita online, e il motore non sa chi. Dopo la
## preparazione non c'è più caso: con lo stesso seme e le stesse scelte la partita è identica ovunque.

signal decision_requested(req)
signal decision_provided(val)
signal cambiato
signal finita

var S := {}
var controller = null          # oggetto con decide(eng, p, req) -> int (anche asincrono)
var simulazione := false
var passi := 0                 # decisioni prese (per i salvataggi)
var registro: Array = []       # tutte le decisioni prese, in ordine
var ais := {}                  # posto -> IA (per i posti del computer e gli assenti online)
var ai_delay := 0.6

const RELS := ["C", "I", "R"]

# ======================================================================= preparazione

func nuova(giocatori: Array, seme: int, opzioni := {}) -> void:
	PaxDB.carica()
	var rng := RandomNumberGenerator.new()
	rng.seed = seme
	var n := giocatori.size()
	S = {"np": n, "seme": seme, "opz": opzioni, "players": [], "emp": {}, "th": {}, "city": {}, "bord": {},
		"emporio": {"W": "Trebizond", "E": "Tana"}, "mk": {"E": [], "W": []}, "deck": {"E": [], "W": []},
		"vict": {"santa": false, "imperiale": false, "globalizzazione": false, "rinascimento": false},
		"bish": {}, "cur": 0, "turno": 1, "fl": {}, "log": [], "over": false, "vincitore": -1, "motivo": "",
		"ult": {}}
	# banche: Fugger sempre per prima se in gioco
	var banche := ["Fugger", "Medici", "Coeur", "Marchionni"]
	if opzioni.get("banche_casuali", true):
		_mescola(banche, rng)
	for i in n:
		var g: Dictionary = giocatori[i]
		var bank: String = g.get("bank", banche[i])
		var nm: String = str(g.get("name", "")).strip_edges()
		if nm == "":
			nm = {"Fugger": "Jakob Fugger", "Medici": "Lorenzo de' Medici", "Coeur": "Jacques Cœur", "Marchionni": "Bartolomeo Marchionni"}[bank]
		S["players"].append({"bank": bank, "name": nm,
			"ai": g.get("ai", false), "fl": 0, "hand": [], "W": [], "E": [], "maids": [], "pawns": 10})
	# ordine dei posti: chi ha Fugger comincia
	var primo := 0
	for i in n:
		if S["players"][i]["bank"] == "Fugger":
			primo = i
	if primo == 0 and S["players"][0]["bank"] != "Fugger":
		primo = rng.randi_range(0, n - 1)
	S["cur"] = primo
	for k in n:
		S["players"][(primo + k) % n]["fl"] = 3 + k
	for e in PaxDB.ordine_imperi:
		S["emp"][e] = {"own": -1, "side": "K", "rep": [], "queen": "", "suz": ""}
		S["th"][e] = PaxDB.imp(e)["stato_iniziale"]
		var sl := []
		for x in PaxDB.slot[e]:
			sl.append("")
		S["city"][e] = sl
		# classe dominante iniziale nelle capitali
		for j in PaxDB.slot[e].size():
			var ci: int = PaxDB.slot[e][j][0]
			var sub: int = PaxDB.slot[e][j][1]
			if PaxDB.imp(e)["citta"][ci]["capitale"] and not (e == "PapalStates" and sub == 1):
				S["city"][e][j] = icona(e, j)
	for k in PaxDB.confini:
		S["bord"][k] = {"p": -1, "s": ""}
	for i in n:
		var b: String = S["players"][i]["bank"]
		for bb in PaxDB.mappa["banche"]:
			if bb["chiave"] == b:
				S["bord"][bb["confine"]]["p"] = i
				S["players"][i]["pawns"] -= 1
	# mazzi
	for lato in ["E", "W"]:
		var normali := []
		var comete := []
		for id in PaxDB.carte:
			var c: Dictionary = PaxDB.carte[id]
			if c["mazzo"] != lato:
				continue
			if c.get("cometa", false):
				comete.append(id)
			else:
				normali.append(id)
		normali.sort()
		comete.sort()
		_mescola(normali, rng)
		var fondo_n: int = 8 if n == 1 else 12
		var fondo := normali.slice(0, fondo_n) + comete
		_mescola(fondo, rng)
		var sopra: int = 4 * maxi(n, 2)
		var mazzo := normali.slice(fondo_n, fondo_n + sopra) + fondo
		# il mazzo si pesca dall'inizio dell'array
		S["deck"][lato] = mazzo
		var riga := []
		for k in 6:
			riga.append({"c": S["deck"][lato].pop_front(), "f": 0})
		S["mk"][lato] = riga
	_reset_turno()
	log_("Inizia la partita: %d giocatori. Comincia %s." % [n, pname(S["cur"])])


func _mescola(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _reset_turno() -> void:
	S["fl"] = {"azioni": 0, "buy": 0, "play": 0, "sell": 0, "ops_E": false, "ops_W": false, "fair_E": false,
		"fair_W": false, "fair_free": false, "usura": []}


func clona() -> PaxEngine:
	var e := PaxEngine.new()
	e.S = S.duplicate(true)
	e.simulazione = true
	return e

# ======================================================================= utilità

func log_(t: String) -> void:
	if simulazione:
		return
	S["log"].append(t)
	if S["log"].size() > 400:
		S["log"] = S["log"].slice(S["log"].size() - 400)


func pname(p: int) -> String:
	if p < 0:
		return "nessuno"
	return S["players"][p]["name"]


func P(p: int) -> Dictionary:
	return S["players"][p]


func card(id: String) -> Dictionary:
	return PaxDB.carte.get(id, {})


func icona(e: String, j: int) -> String:
	var ci: int = PaxDB.slot[e][j][0]
	var sub: int = PaxDB.slot[e][j][1]
	var ic: Array = PaxDB.imp(e)["citta"][ci]["icone"][S["th"][e]]
	return ic[mini(sub, ic.size() - 1)]


func emporio_citta(e: String, j: int) -> String:
	return PaxDB.imp(e)["citta"][PaxDB.slot[e][j][0]]["emporio"]


func nome_citta(e: String, j: int) -> String:
	return PaxDB.imp(e)["citta"][PaxDB.slot[e][j][0]]["nome"]


## Il posto j della città è in gioco? (empori chiusi e secondo posto di Venezia)
func slot_attivo(e: String, j: int) -> bool:
	var em := emporio_citta(e, j)
	if em != "" and em != S["emporio"]["W"] and em != S["emporio"]["E"]:
		return false
	if e == "PapalStates" and PaxDB.slot[e][j][1] == 1:
		return condottieri_attivi()
	return true


func condottieri_attivi() -> bool:
	if icona("PapalStates", 0) != "K:C":
		return false
	for p in S["np"]:
		if ha_abilita(p, "condottiero"):
			return true
	return false


func citta_vuote(e: String, levy := false) -> Array:
	var out := []
	for j in S["city"][e].size():
		if S["city"][e][j] == "" and slot_attivo(e, j):
			out.append(j)
	return out


func saturo(e: String) -> bool:
	return citta_vuote(e).is_empty()


func classe_dominante(e: String) -> Array:
	var out := []
	for j in S["city"][e].size():
		if S["city"][e][j] != "":
			out.append(j)
	return out


func confini_di(e: String) -> Array:
	return PaxDB.confini_di[e]


func mare(k: String) -> bool:
	return PaxDB.confini[k]["mare"]


func altro_imp(k: String, e: String) -> String:
	var ii: Array = PaxDB.confini[k]["imperi"]
	return ii[1] if ii[0] == e else ii[0]


func adiacenti(e: String) -> Array:
	var a: Array = PaxDB.mappa["adiacenti"][e].duplicate()
	if stato_cuscinetto():
		if e == "Portugal":
			a.erase("France")
		elif e == "France":
			a.erase("Portugal")
	return a


func stato_cuscinetto() -> bool:
	for p in S["np"]:
		for id in carte_tableau(p):
			if "stato_cuscinetto" in card(id).get("abilita", []) and not silenziata(p, id):
				return true
	return false


func confine_tra(a: String, b: String) -> String:
	for k in confini_di(a):
		if altro_imp(k, a) == b:
			return k
	return ""


## Imperi che condividono un confine marittimo con e.
func vicini_mare(e: String) -> Array:
	var out := []
	for k in confini_di(e):
		if mare(k):
			out.append(altro_imp(k, e))
	return out


func concessioni(p: int) -> int:
	var n := 0
	for k in S["bord"]:
		if S["bord"][k]["p"] == p:
			n += 1
	return n


func conc_su(e: String, p: int) -> int:
	var n := 0
	for k in confini_di(e):
		if S["bord"][k]["p"] == p:
			n += 1
	return n

# ---- pezzi in gioco e riserva

func in_gioco(t: String) -> int:
	var n := 0
	var tipo := t.split(":")[0]
	if tipo == "B":
		for k in S["bish"]:
			if "B:" + S["bish"][k] == t:
				n += 1
		return n
	if tipo == "S":
		for k in S["bord"]:
			if "S:" + S["bord"][k]["s"] == t:
				n += 1
		return n
	for e in S["city"]:
		for x in S["city"][e]:
			if x == t:
				n += 1
		for x in S["emp"][e]["rep"]:
			if x == t:
				n += 1
	return n


## Prende un pezzo dalla riserva; se è finita lo toglie dai repressi o dalla mappa. false se impossibile.
func prendi_pezzo(t: String) -> bool:
	var lim: int = PaxDB.mappa["pezzi"].get(t, 99)
	if in_gioco(t) < lim:
		return true
	for e in S["emp"]:
		var r: Array = S["emp"][e]["rep"]
		var i := r.find(t)
		if i >= 0:
			r.remove_at(i)
			return true
	var tipo := t.split(":")[0]
	if tipo == "S":
		for k in S["bord"]:
			if "S:" + S["bord"][k]["s"] == t:
				S["bord"][k]["s"] = ""
				return true
		return false
	if tipo == "B":
		for k in S["bish"].keys():
			if "B:" + S["bish"][k] == t:
				S["bish"].erase(k)
				return true
		return false
	for e in S["city"]:
		var j: int = S["city"][e].find(t)
		if j >= 0:
			S["city"][e][j] = ""
			return true
	return false


## Pedone del giocatore p: dalla riserva oppure dai suoi servi.
func prendi_pedone(p: int) -> bool:
	if P(p)["pawns"] > 0:
		P(p)["pawns"] -= 1
		return true
	var t := "P:%d" % p
	for e in S["emp"]:
		var i: int = S["emp"][e]["rep"].find(t)
		if i >= 0:
			S["emp"][e]["rep"].remove_at(i)
			return true
	return false


func uccidi_token(t: String) -> void:
	if t.begins_with("P:"):
		var p := int(t.split(":")[1])
		if p >= 0 and p < S["np"]:
			P(p)["pawns"] += 1

# ======================================================================= tableau

## Carte nel tableau di p (lato W, E o entrambi): carte, imperi (@X), vassalli, regine sposate.
func carte_tableau(p: int, lato := "") -> Array:
	var out := []
	for l in (["W", "E"] if lato == "" else [lato]):
		for id in P(p)[l]:
			out.append(id)
			if id.begins_with("@"):
				var e: String = id.substr(1)
				if S["emp"][e]["queen"] != "":
					out.append(S["emp"][e]["queen"])
				for v in vassalli(e):
					out.append("@" + v)
					if S["emp"][v]["queen"] != "":
						out.append(S["emp"][v]["queen"])
	return out


func vassalli(e: String) -> Array:
	var out := []
	for v in PaxDB.ordine_imperi:
		if S["emp"][v]["suz"] == e:
			out.append(v)
	return out


func proprietario(id: String) -> int:
	if id.begins_with("@"):
		return S["emp"][id.substr(1)]["own"]
	for p in S["np"]:
		if id in carte_tableau(p):
			return p
	return -1


## Lato del tableau di una carta (W/E) per il proprietario.
func lato_carta(id: String) -> String:
	if id.begins_with("@"):
		return PaxDB.lato_imp(id.substr(1))
	var c := card(id)
	if c.get("regina", false):
		var e := sposo(id)
		if e != "":
			return PaxDB.lato_imp(e)
	return c.get("mazzo", "W")


## Impero a cui è sposata una regina ("" se nessuno).
func sposo(q: String) -> String:
	for e in S["emp"]:
		if S["emp"][e]["queen"] == q:
			return e
	return ""


## Luogo stampato di una carta del tableau.
func luogo(id: String) -> String:
	if id.begins_with("@"):
		return id.substr(1)
	var c := card(id)
	if c.get("regina", false):
		return sposo(id)
	return c.get("luogo", "")


func luoghi(id: String) -> Array:
	return PaxDB.luoghi(luogo(id))


func stesso_luogo(a: String, b: String) -> bool:
	for x in luoghi(a):
		if x in luoghi(b):
			return true
	return false


func prestigio(id: String) -> Array:
	if id.begins_with("@"):
		var e := id.substr(1)
		var d: Dictionary = PaxDB.imp(e)["re" if S["emp"][e]["side"] == "K" else "repubblica"]
		return d["prestigio"]
	return card(id).get("prestigio", [])


func ops_carta(id: String) -> Array:
	if id.begins_with("@"):
		var e := id.substr(1)
		var d: Dictionary = PaxDB.imp(e)["re" if S["emp"][e]["side"] == "K" else "repubblica"]
		return d["ops"]
	return card(id).get("ops", [])


func ha_vescovo(id: String) -> bool:
	return S["bish"].has(id)


## Una carta è silenziata se c'è un vescovo (su di lei o sulla coppia reale) e il proprietario non è immune.
func silenziata(p: int, id: String) -> bool:
	var v := ha_vescovo(id)
	if not v:
		if id.begins_with("@"):
			var q: String = S["emp"][id.substr(1)]["queen"]
			v = q != "" and ha_vescovo(q)
		elif card(id).get("regina", false):
			var e := sposo(id)
			v = e != "" and ha_vescovo("@" + e)
	if not v:
		return false
	if p >= 0:
		for x in carte_tableau(p):
			if "sincretismo" in card(x).get("abilita", []):
				return false
	return true


func ha_abilita(p: int, ab: String) -> bool:
	return conta_abilita(p, ab) > 0


func conta_abilita(p: int, ab: String) -> int:
	var n := 0
	for id in carte_tableau(p):
		if ab in card(id).get("abilita", []) and not silenziata(p, id):
			n += 1
	return n


func testo_rosso(r: String) -> bool:
	for p in S["np"]:
		for id in carte_tableau(p):
			if r in card(id).get("rosse", []) and not silenziata(p, id):
				return true
	return false


func limite_mano(p: int) -> int:
	return 99 if ha_abilita(p, "mano_illimitata") else 2


func aggiungi_tableau(p: int, id: String) -> void:
	var l := lato_carta(id)
	P(p)[l].append(id)


func togli_tableau(p: int, id: String) -> void:
	for l in ["W", "E"]:
		P(p)[l].erase(id)

# ---- prestigio e vittorie

func conta_prestigio(p: int, tipo: String, con_zitelle := true) -> int:
	var n := 0
	for id in carte_tableau(p):
		for x in prestigio(id):
			if x == tipo:
				n += 1
	if con_zitelle:
		for id in P(p)["maids"]:
			for x in card(id).get("prestigio", []):
				if x == tipo:
					n += 1
	return n


func re_count(p: int) -> int:
	var n := 0
	for e in S["emp"]:
		if S["emp"][e]["own"] == p and S["emp"][e]["side"] == "K":
			n += 1
	return n


func repubbliche(p: int) -> int:
	var n := 0
	for e in S["emp"]:
		if S["emp"][e]["own"] == p and S["emp"][e]["side"] == "R":
			n += 1
	return n + conta_abilita(p, "conta_repubblica")


## Religione suprema ("" se nessuna). p: per le abilità personali (età dell'oro, protezione di Solimano).
func supremazia(p := -1) -> String:
	var vesc := {"C": 0, "I": 0, "R": 0}
	for k in S["bish"]:
		vesc[S["bish"][k]] += 1
	var unita := {"C": 0, "I": 0, "R": 0}
	for e in S["th"]:
		var t: String = S["th"][e]
		if t == "M":
			continue
		for x in S["city"][e]:
			if x != "" and x.ends_with(":" + t):
				unita[t] += 1
		for k in confini_di(e):
			if S["bord"][k]["s"] == t:
				unita[t] += 1
	if p >= 0:
		if ha_abilita(p, "eta_oro_mamelucca"):
			vesc["I"] += conta_prestigio(p, "P")
		if ha_abilita(p, "protezione_solimano"):
			var verdi := 0
			for k in S["bord"]:
				if S["bord"][k]["s"] == "I":
					verdi += 1
			vesc["R"] += verdi
			unita["R"] += verdi
	for r in RELS:
		var altri_v := 0
		var altri_u := 0
		for q in RELS:
			if q != r:
				altri_v += vesc[q]
				altri_u += unita[q]
		if vesc[r] > altri_v and unita[r] > altri_u:
			return r
	return ""


func condizioni_vittoria(p: int, v: String) -> bool:
	var n: int = S["np"]
	match v:
		"santa":
			var r := supremazia(p)
			if r == "":
				return false
			var mio := conta_prestigio(p, r)
			if mio == 0:
				return false
			for q in n:
				if q != p and conta_prestigio(q, r) >= mio:
					return false
			return true
		"imperiale":
			var mio := re_count(p)
			var marg := 3 if n == 2 else 2
			if n == 1:
				return mio >= 3
			for q in n:
				if q != p and mio < re_count(q) + marg:
					return false
			return mio > 0
		"globalizzazione":
			var mio := concessioni(p)
			if ha_abilita(p, "navigazione"):
				mio += conta_prestigio(p, "P") * conta_abilita(p, "navigazione")
			var d := conta_prestigio(p, "D")
			if d == 0:
				return false
			for q in n:
				if q == p:
					continue
				var cq := concessioni(q)
				if ha_abilita(q, "navigazione"):
					cq += conta_prestigio(q, "P") * conta_abilita(q, "navigazione")
				if mio < cq + 2 or d <= conta_prestigio(q, "D"):
					return false
			return true
		"rinascimento":
			var rep := repubbliche(p)
			var leg := conta_prestigio(p, "L") + conta_prestigio(p, "P") * conta_abilita(p, "mecenati_legge")
			if rep == 0:
				return false
			for q in n:
				if q == p:
					continue
				var lq := conta_prestigio(q, "L") + conta_prestigio(q, "P") * conta_abilita(q, "mecenati_legge")
				if rep <= repubbliche(q) or leg < lq + 2:
					return false
			return true
	return false


func costo_vittoria(v: String) -> int:
	var rr := {"santa": "santa", "imperiale": "imperiale", "globalizzazione": "globalizzazione"}
	if rr.has(v) and testo_rosso(rr[v]):
		return 2
	return 1

# ======================================================================= decisioni

## Chiede una scelta: opts è un elenco di {t: testo, k: chiave per l'interfaccia}. Restituisce l'indice.
## Con una sola opzione non chiede nulla (lo stesso su tutti i dispositivi).
func ask(p: int, testo: String, opts: Array, tipo := "", extra := {}) -> int:
	if opts.is_empty():
		return -1
	if opts.size() == 1 and not extra.get("sempre", false):
		return 0
	var req := {"p": p, "testo": testo, "opz": opts, "tipo": tipo}
	for k in extra:
		req[k] = extra[k]
	var v
	if controller != null:
		v = await controller.decide(self, p, req)
	else:
		v = 0
	if typeof(v) != TYPE_INT or v < 0 or v >= opts.size():
		v = 0
	passi += 1
	if not simulazione:
		registro.append(v)
	return v


func si_no(p: int, testo: String, tipo := "sino") -> bool:
	return await ask(p, testo, [{"t": "Sì", "k": "si"}, {"t": "No", "k": "no"}], tipo, {"sempre": true}) == 0

# ======================================================================= ciclo di gioco

func run() -> void:
	while not S["over"]:
		await turno()
		if S["over"]:
			break
		cambiato.emit()
	finita.emit()


func turno() -> void:
	var p: int = S["cur"]
	_reset_turno()
	log_("— Turno %d: %s —" % [S["turno"], pname(p)])
	cambiato.emit()
	while not S["over"]:
		var az := azioni_legali(p)
		if az.is_empty():
			break
		var i : int = await ask(p, "Scegli un'azione (%d/2)" % mini(S["fl"]["azioni"] + 1, 2), az, "azione",
			{"sempre": true})
		var a: Dictionary = az[i]
		if a["k"] == "fine":
			break
		await esegui_azione(p, a)
		cambiato.emit()
	if S["over"]:
		return
	rifornisci_mercato()
	if S["over"]:
		return
	S["cur"] = (p + 1) % S["np"]
	S["turno"] += 1


## Elenco delle azioni possibili, già espanse nelle varianti (es. «gioca X con complotto in Y»).
func azioni_legali(p: int) -> Array:
	var out := []
	var fl: Dictionary = S["fl"]
	var usate: int = fl["azioni"]
	var resta := 2 - usate
	var pl := P(p)
	if resta > 0:
		# acquisti
		if fl["buy"] < 2:
			for lato in ["W", "E"]:
				for i in range(1, 6):
					var c: String = S["mk"][lato][i]["c"]
					if c == "" or (lato + ":" + str(i)) in fl["usura"]:
						continue
					if i > pl["fl"]:
						continue
					var com: bool = card(c).get("cometa", false)
					if not com and pl["hand"].size() >= limite_mano(p):
						continue
					out.append({"t": "Compra %s (%d ƒ)" % [PaxDB.nome_carta(c), i], "k": "buy:%s:%d" % [lato, i],
						"tipo": "buy", "lato": lato, "i": i, "c": c})
		# giocate
		if fl["play"] < 2:
			for c in pl["hand"]:
				out.append_array(varianti_gioco(p, c))
		# vendite
		if fl["sell"] < 2:
			for c in pl["hand"]:
				out.append({"t": "Vendi %s dalla mano (+2 ƒ)" % PaxDB.nome_carta(c), "k": "sell:h:" + c, "tipo": "sell", "da": "h", "c": c})
			for c in pl["maids"]:
				out.append({"t": "Vendi %s (zitella, +2 ƒ)" % PaxDB.nome_carta(c), "k": "sell:m:" + c, "tipo": "sell", "da": "m", "c": c})
			for l in ["W", "E"]:
				for c in pl[l]:
					out.append({"t": "Vendi %s (+%d ƒ)" % [PaxDB.nome_carta(c), valore_vendita(p, c)], "k": "sell:t:" + c,
						"tipo": "sell", "da": "t", "c": c})
		# operazioni
		for l in ["W", "E"]:
			if not fl["ops_" + l] and not elenco_op(p, l).is_empty():
				out.append({"t": "Esegui le operazioni d'%s" % ("Oriente" if l == "E" else "Occidente"), "k": "ops:" + l,
					"tipo": "ops", "lato": l})
		if ha_abilita(p, "est_ovest") and not fl["ops_W"] and not fl["ops_E"] and (not elenco_op(p, "W").is_empty() or not elenco_op(p, "E").is_empty()):
			out.append({"t": "Operazioni d'Oriente e d'Occidente (una sola azione)", "k": "ops:EW", "tipo": "ops", "lato": "EW"})
		# fiere
		for l in ["W", "E"]:
			if not fl["fair_" + l] and S["mk"][l][0]["c"] != "":
				out.append({"t": "Fiera commerciale d'%s" % ("Oriente" if l == "E" else "Occidente"), "k": "fair:" + l,
					"tipo": "fair", "lato": l})
		# vittoria
		for v in S["vict"]:
			if S["vict"][v] and condizioni_vittoria(p, v) and costo_vittoria(v) <= resta:
				out.append({"t": "Dichiara la %s!" % PaxDB.mappa["vittorie"][v]["nome"].to_lower(), "k": "vict:" + v,
					"tipo": "vict", "v": v})
		# azioni speciali delle carte
		for id in carte_tableau(p):
			var ab: Array = card(id).get("abilita", [])
			if silenziata(p, id):
				continue
			if "rappresaglie" in ab and sposo(id) != "":
				out.append({"t": "Scarta %s: rivolta contadina in %s" % [PaxDB.nome_carta(id), PaxDB.nome_imp(sposo(id))],
					"k": "bathory:" + id, "tipo": "bathory", "c": id})
			if "controriforma" in ab:
				for coppia in [["C", "I"], ["C", "R"], ["I", "R"]]:
					out.append({"t": "Controriforma: apostasia %s-%s" % [PaxDB.NOMI_REL[coppia[0]], PaxDB.NOMI_REL[coppia[1]]],
						"k": "oratory:" + coppia[0] + coppia[1], "tipo": "oratory", "r": coppia})
	# azioni gratuite (non consumano azioni)
	for l in ["W", "E"]:
		if not fl["ops_" + l] and ha_fortificazioni(p, l) and not elenco_op(p, l).is_empty():
			out.append({"t": "Operazioni d'%s (gratis: fortificazioni)" % ("Oriente" if l == "E" else "Occidente"),
				"k": "fops:" + l, "tipo": "ops", "lato": l, "gratis": true})
	if ha_abilita(p, "galee_venezia") and not fl["fair_free"]:
		for l in ["W", "E"]:
			if not fl["fair_" + l] and S["mk"][l][0]["c"] != "":
				out.append({"t": "Fiera d'%s (gratis: galee veneziane)" % ("Oriente" if l == "E" else "Occidente"),
					"k": "ffair:" + l, "tipo": "fair", "lato": l, "gratis": true})
	if resta <= 0 and out.is_empty():
		return []
	if usate >= 1 or out.is_empty():
		out.append({"t": "Termina il turno", "k": "fine", "tipo": "fine"})
	return out


func ha_fortificazioni(p: int, l: String) -> bool:
	for id in carte_tableau(p):
		if "fortificazioni" in card(id).get("abilita", []) and not silenziata(p, id):
			if card(id).get("mazzo", "") == l:
				return true
	return false


func valore_vendita(p: int, c: String) -> int:
	if c.begins_with("@"):
		var e := c.substr(1)
		return 4 if S["emp"][e]["queen"] != "" else 2
	if "riscatto" in card(c).get("abilita", []) and not silenziata(p, c):
		return 4
	return 2


## Varianti per giocare una carta dalla mano.
func varianti_gioco(p: int, c: String) -> Array:
	var cd := card(c)
	var nome := PaxDB.nome_carta(c)
	var out := []
	if cd.get("regina", false):
		for e in pretendenti_liberi(p, c):
			out.append({"t": "Gioca %s: sposa il re di %s" % [nome, PaxDB.nome_imp(e)], "k": "play:%s:cor:%s" % [c, e],
				"tipo": "play", "c": c, "os": "coronation", "e": e})
		out.append({"t": "Gioca %s come zitella" % nome, "k": "play:%s:maid" % c, "tipo": "play", "c": c, "os": "maid"})
		return out
	out.append({"t": "Gioca %s" % nome + (" (senza evento)" if cd["oneshot"] != "" else ""), "k": "play:%s:no" % c,
		"tipo": "play", "c": c, "os": ""})
	match cd["oneshot"]:
		"conspiracy", "revolt", "crusade", "jihad", "reformation":
			for e in PaxDB.luoghi(cd["luogo"]):
				if puo_battaglia(p, c, cd["oneshot"], e):
					out.append({"t": "Gioca %s: %s in %s" % [nome, PaxDB.NOMI_ONESHOT[cd["oneshot"]], PaxDB.nome_imp(e)],
						"k": "play:%s:os:%s" % [c, e], "tipo": "play", "c": c, "os": cd["oneshot"], "e": e})
		"tradeshift":
			if puo_spostamento(p, c):
				out.append({"t": "Gioca %s: spostamento commerciale a %s" % [nome, PaxDB.NOMI_EMPORI[cd["oneshot_arg"]]],
					"k": "play:%s:ts" % c, "tipo": "play", "c": c, "os": "tradeshift"})
		"apostasy":
			out.append({"t": "Gioca %s: apostasia %s-%s" % [nome, PaxDB.NOMI_REL[cd["oneshot_arg"][0]], PaxDB.NOMI_REL[cd["oneshot_arg"][1]]],
				"k": "play:%s:ap" % c, "tipo": "play", "c": c, "os": "apostasy"})
	return out


func pretendenti_liberi(p: int, q: String) -> Array:
	var out := []
	var enrico := ha_abilita(p, "enrico_viii")
	for e in card(q).get("pretendenti", []):
		var em: Dictionary = S["emp"][e]
		if em["side"] != "K" and em["own"] != -1:
			continue
		if em["suz"] != "" and em["own"] != p and not enrico:
			continue
		if em["own"] == -1 or em["own"] == p or enrico:
			if em["queen"] != "" and not enrico:
				continue
			if em["own"] == p and em["side"] != "K":
				continue
			out.append(e)
	return out


func puo_spostamento(p: int, c: String) -> bool:
	var arg: String = card(c)["oneshot_arg"]
	var col: String = PaxDB.mappa["rotte"][arg]["colore"]
	if S["emporio"][col] == arg:
		return false
	if arg == "SpiceIslands":
		var d := 0
		for id in carte_tableau(p):
			for x in prestigio(id):
				if x == "D":
					d += 1
		if d == 0:
			return false
	return true

# ======================================================================= esecuzione delle azioni

func esegui_azione(p: int, a: Dictionary) -> void:
	var fl: Dictionary = S["fl"]
	var costo := 0 if a.get("gratis", false) else 1
	match a["tipo"]:
		"buy":
			fl["buy"] += 1
			await compra(p, a["lato"], a["i"])
		"play":
			fl["play"] += 1
			await gioca(p, a)
		"sell":
			fl["sell"] += 1
			await vendi(p, a["c"], a["da"])
		"ops":
			if a["lato"] == "EW":
				fl["ops_W"] = true
				fl["ops_E"] = true
				await operazioni(p, "W")
				await operazioni(p, "E")
			else:
				fl["ops_" + a["lato"]] = true
				await operazioni(p, a["lato"])
		"fair":
			fl["fair_" + a["lato"]] = true
			if a.get("gratis", false):
				fl["fair_free"] = true
			await fiera(p, a["lato"])
		"vict":
			costo = costo_vittoria(a["v"])
			S["over"] = true
			S["vincitore"] = p
			S["motivo"] = PaxDB.mappa["vittorie"][a["v"]]["nome"]
			log_("%s dichiara la %s e vince la partita!" % [pname(p), S["motivo"].to_lower()])
		"bathory":
			var e := sposo(a["c"])
			log_("%s scarta %s e scatena una rivolta contadina in %s." % [pname(p), PaxDB.nome_carta(a["c"]), PaxDB.nome_imp(e)])
			scarta_carta(a["c"])
			await battaglia_civile(p, "", "revolt", e)
		"oratory":
			log_("%s proclama la Controriforma." % pname(p))
			await apostasia(p, a["r"][0], a["r"][1], "")
	fl["azioni"] += costo
	await controlla_mani()


## Se un'abilità di mano illimitata è stata persa o silenziata, si scarta fino a 2 carte.
func controlla_mani() -> void:
	for q in S["np"]:
		while P(q)["hand"].size() > limite_mano(q):
			var opts := []
			for c in P(q)["hand"]:
				opts.append({"t": "Scarta %s" % PaxDB.nome_carta(c), "k": "scarta:" + c, "c": c})
			var k: int = await ask(q, "Hai troppe carte in mano: scartane una", opts, "scarta_mano")
			P(q)["hand"].erase(opts[k]["c"])
			log_("%s scarta %s dalla mano (limite di 2 carte)." % [pname(q), PaxDB.nome_carta(opts[k]["c"])])


# ----------------------------------------------------------------------- mercato

func compra(p: int, lato: String, i: int) -> void:
	var pl := P(p)
	var altro := "E" if lato == "W" else "W"
	for j in range(0, i):
		var slot: Dictionary = S["mk"][lato][j]
		if slot["c"] != "":
			slot["f"] += 1
			S["fl"]["usura"].append(lato + ":" + str(j))
		else:
			var s2: Dictionary = S["mk"][altro][j]
			s2["f"] += 1
			if s2["c"] != "":
				S["fl"]["usura"].append(altro + ":" + str(j))
		pl["fl"] -= 1
	var sl: Dictionary = S["mk"][lato][i]
	var c: String = sl["c"]
	pl["fl"] += sl["f"]
	var spec: int = sl["f"]
	sl["c"] = ""
	sl["f"] = 0
	if card(c).get("cometa", false):
		log_("%s compra la cometa «%s» (%d ƒ)." % [pname(p), PaxDB.nome_carta(c), i])
		var inatt := []
		for v in S["vict"]:
			if not S["vict"][v]:
				inatt.append({"t": PaxDB.mappa["vittorie"][v]["nome"], "k": "vitt:" + v, "v": v})
		if not inatt.is_empty():
			var k : int = await ask(p, "La cometa attiva una vittoria: quale?", inatt, "cometa")
			S["vict"][inatt[k]["v"]] = true
			log_("Si attiva la %s." % inatt[k]["t"].to_lower())
		return
	pl["hand"].append(c)
	log_("%s compra %s per %d ƒ%s." % [pname(p), PaxDB.nome_carta(c), i, ("" if spec == 0 else " e incassa %d ƒ" % spec)])


func rifornisci_mercato() -> void:
	for lato in ["E", "W"]:
		var riga: Array = S["mk"][lato]
		# scorrimento verso sinistra
		var carte := []
		var buchi_f := []
		for i in 6:
			if riga[i]["c"] != "":
				carte.append(riga[i])
		# i fiorini dei buchi restano al loro posto e passano alla carta che arriva
		var nuova := []
		for i in 6:
			nuova.append({"c": "", "f": riga[i]["f"] if riga[i]["c"] == "" else 0})
		var k := 0
		for i in 6:
			if k < carte.size():
				nuova[i]["c"] = carte[k]["c"]
				nuova[i]["f"] += carte[k]["f"]
				k += 1
		S["mk"][lato] = nuova
	for lato in ["E", "W"]:
		var riga: Array = S["mk"][lato]
		var altro := "E" if lato == "W" else "W"
		for i in 6:
			if riga[i]["c"] == "":
				if not S["deck"][lato].is_empty():
					riga[i]["c"] = S["deck"][lato].pop_front()
				elif not S["deck"][altro].is_empty():
					riga[i]["c"] = S["deck"][altro].pop_front()
				else:
					fine_mecenati()
					return


func fine_mecenati() -> void:
	var best := -1
	var bv := -1
	for p in S["np"]:
		var v: int = conta_prestigio(p, "P") * 1000 + P(p)["fl"]
		if v > bv:
			bv = v
			best = p
	S["over"] = true
	S["vincitore"] = best
	S["motivo"] = "Vittoria dei mecenati"
	log_("I mazzi sono finiti: vince %s con il maggior prestigio di mecenate." % pname(best))

# ----------------------------------------------------------------------- vendita

func vendi(p: int, c: String, da: String) -> void:
	var v := 2
	if da == "h":
		P(p)["hand"].erase(c)
	elif da == "m":
		P(p)["maids"].erase(c)
	else:
		v = valore_vendita(p, c)
		var e := c.substr(1) if c.begins_with("@") else ""
		var ab: Array = [] if e != "" else card(c).get("abilita", [])
		var sil := silenziata(p, c)
		var oneshot_mach := ha_abilita(p, "tradimento") and e == ""
		if e != "":
			torna_trono(e, true)
		else:
			scarta_carta(c)
		P(p)["fl"] += v
		log_("%s vende %s per %d ƒ." % [pname(p), PaxDB.nome_carta(c), v])
		if not sil:
			if "recinzioni" in ab:
				await emancipa_zona(p, PaxDB.OVEST)
			if "cifrari_medici" in ab:
				await op_crittografia(p)
		if oneshot_mach and card(c).get("oneshot", "") in ["conspiracy", "revolt", "crusade", "apostasy"]:
			await machiavelli(p, c)
		return
	P(p)["fl"] += v
	log_("%s vende %s per %d ƒ." % [pname(p), PaxDB.nome_carta(c), v])


func machiavelli(p: int, c: String) -> void:
	var cd := card(c)
	if cd["oneshot"] == "apostasy":
		if await si_no(p, "Machiavellismo: eseguire l'apostasia di %s?" % cd["nome"]):
			await apostasia(p, cd["oneshot_arg"][0], cd["oneshot_arg"][1], "")
		return
	var opts := [{"t": "No", "k": "no"}]
	for e in PaxDB.luoghi(cd["luogo"]):
		if puo_battaglia(p, c, cd["oneshot"], e):
			opts.append({"t": "%s in %s" % [PaxDB.NOMI_ONESHOT[cd["oneshot"]], PaxDB.nome_imp(e)], "k": "imp:" + e, "e": e})
	var k : int = await ask(p, "Machiavellismo: eseguire l'evento di %s?" % cd["nome"], opts, "machiavelli", {"sempre": true})
	if k > 0:
		await one_shot_battaglia(p, c, cd["oneshot"], opts[k]["e"])


## Scarta una carta del tableau (non un impero): la toglie con il suo vescovo.
func scarta_carta(c: String) -> void:
	S["bish"].erase(c)
	var e := sposo(c)
	if e != "":
		S["emp"][e]["queen"] = ""
		return
	for p in S["np"]:
		togli_tableau(p, c)
		P(p)["maids"].erase(c)
		P(p)["hand"].erase(c)


## Un impero torna nel trono (vendita, decapitazione, apostasia, liberazione dei vassalli).
func torna_trono(e: String, con_regina := true) -> void:
	var em: Dictionary = S["emp"][e]
	var o: int = em["own"]
	if o >= 0:
		togli_tableau(o, "@" + e)
	for v in vassalli(e):
		torna_trono(v, true)
	em["own"] = -1
	em["suz"] = ""
	em["side"] = "K"
	if not con_regina and em["queen"] != "":
		S["bish"].erase(em["queen"])
		em["queen"] = ""

# ----------------------------------------------------------------------- gioco di una carta

func gioca(p: int, a: Dictionary) -> void:
	var c: String = a["c"]
	var cd := card(c)
	P(p)["hand"].erase(c)
	var os: String = a.get("os", "")
	if cd.get("regina", false):
		if os == "coronation":
			log_("%s gioca %s e la incorona regina: sposa il re di %s." % [pname(p), cd["nome"], PaxDB.nome_imp(a["e"])])
			await cambio_regime(p, a["e"], "coron", {"queen": c})
		else:
			P(p)["maids"].append(c)
			log_("%s gioca %s come zitella." % [pname(p), cd["nome"]])
		return
	aggiungi_tableau(p, c)
	match os:
		"":
			log_("%s gioca %s." % [pname(p), cd["nome"]])
			await piazza_agenti(p, c, false)
		"tradeshift":
			var arg: String = cd["oneshot_arg"]
			var col: String = PaxDB.mappa["rotte"][arg]["colore"]
			var vecchio: String = S["emporio"][col]
			S["emporio"][col] = arg
			log_("%s gioca %s: la rotta %s parte ora da %s (chiude %s)." % [pname(p), cd["nome"],
				"d'Oriente" if col == "E" else "d'Occidente", PaxDB.NOMI_EMPORI[arg], PaxDB.NOMI_EMPORI[vecchio]])
			# i pezzi sull'emporio chiuso diventano repressi
			var ve: String = PaxDB.mappa["rotte"][vecchio]["impero"]
			for j in S["city"][ve].size():
				if emporio_citta(ve, j) == vecchio and S["city"][ve][j] != "":
					S["emp"][ve]["rep"].append(S["city"][ve][j])
					S["city"][ve][j] = ""
			await piazza_agenti(p, c, true)
		"apostasy":
			log_("%s gioca %s e scatena l'apostasia." % [pname(p), cd["nome"]])
			await apostasia(p, cd["oneshot_arg"][0], cd["oneshot_arg"][1], c)
		_:
			log_("%s gioca %s: %s in %s." % [pname(p), cd["nome"], PaxDB.NOMI_ONESHOT[os], PaxDB.nome_imp(a["e"])])
			await one_shot_battaglia(p, c, os, a["e"])
	controlla_venezia()


## Piazzamento degli agenti di una carta. obbligo: one-shot senza battaglia (vanno piazzati se possibile).
func piazza_agenti(p: int, c: String, obbligo: bool, solo_vescovi := false, luogo_fisso := "") -> void:
	var cd := card(c)
	for ag in cd.get("agenti", []):
		var tipo: String = ag.split(":")[0]
		if solo_vescovi and tipo != "B":
			continue
		await piazza_agente(p, c, ag, obbligo, luogo_fisso)


func piazza_agente(p: int, c: String, ag: String, obbligo: bool, luogo_fisso := "") -> void:
	var cd := card(c)
	var tipo: String = ag.split(":")[0]
	var col: String = ag.split(":")[1] if ag.contains(":") else ""
	var imperi: Array = [luogo_fisso] if luogo_fisso != "" else PaxDB.luoghi(cd["luogo"])
	var opts := []
	match tipo:
		"B":
			for dest in destinazioni_vescovo_carta(c):
				opts.append({"t": "Vescovo %s su %s" % [_agg(col), _desc_posto(dest)], "k": "card:" + dest, "dest": dest})
		"K", "R":
			for e in imperi:
				for j in S["city"][e].size():
					if not slot_attivo(e, j):
						continue
					var occ: String = S["city"][e][j]
					if occ != "" and P(p)["fl"] < 1:
						continue
					var t := "%s a %s (%s)" % [PaxDB.nome_pezzo(ag).capitalize(), nome_citta(e, j), PaxDB.nome_imp(e)]
					if occ != "":
						t += " — reprime %s (1 ƒ)" % PaxDB.nome_pezzo(occ)
					opts.append({"t": t, "k": "city:%s:%d" % [e, j], "e": e, "j": j})
		"S":
			var visti := {}
			for e in imperi:
				for k in confini_di(e):
					if not mare(k) or visti.has(k):
						continue
					visti[k] = true
					var b: Dictionary = S["bord"][k]
					var t := "Pirata %s sul confine %s" % [_agg(col), _nome_confine(k)]
					if b["p"] >= 0 and not immune_pirati(b["p"]):
						t += " — affonda la concessione di %s" % pname(b["p"])
					elif b["s"] != "":
						t += " — affonda il pirata %s" % _agg(b["s"])
					opts.append({"t": t, "k": "bord:" + k, "b": k})
		"P":
			if P(p)["pawns"] <= 0:
				pass
			var visti := {}
			for e in imperi:
				for k in confini_di(e):
					if visti.has(k):
						continue
					visti[k] = true
					var b: Dictionary = S["bord"][k]
					if b["s"] != "":
						continue
					if b["p"] >= 0 and P(p)["fl"] < 1:
						continue
					var t := "Concessione sul confine %s" % _nome_confine(k)
					if b["p"] >= 0:
						t += " — reprime la concessione di %s (1 ƒ)" % pname(b["p"])
					opts.append({"t": t, "k": "bord:" + k, "b": k, "e": e})
	if opts.is_empty():
		return
	if not obbligo:
		opts.append({"t": "Non piazzare", "k": "no"})
	var i : int = await ask(p, "Agente di %s: %s" % [cd["nome"], PaxDB.nome_pezzo(ag)], opts, "agente",
		{"sempre": not obbligo, "carta": c})
	var o: Dictionary = opts[i]
	if o["k"] == "no":
		return
	match tipo:
		"B":
			if not prendi_pezzo(ag):
				return
			await metti_vescovo(p, col, o["dest"])
		"K", "R":
			var occ: String = S["city"][o["e"]][o["j"]]
			if occ != "":
				P(p)["fl"] -= 1
				S["emp"][o["e"]]["rep"].append(occ)
				S["city"][o["e"]][o["j"]] = ""
			if prendi_pezzo(ag):
				S["city"][o["e"]][o["j"]] = ag
				log_("%s piazza un %s a %s." % [pname(p), PaxDB.nome_pezzo(ag), nome_citta(o["e"], o["j"])])
		"S":
			metti_pirata(col, o["b"])
		"P":
			var b: Dictionary = S["bord"][o["b"]]
			if b["p"] >= 0:
				P(p)["fl"] -= 1
				var serf_e: String = o["e"]
				S["emp"][serf_e]["rep"].append("P:%d" % b["p"])
				log_("La concessione di %s diventa servo in %s." % [pname(b["p"]), PaxDB.nome_imp(serf_e)])
				b["p"] = -1
			if prendi_pedone(p):
				b["p"] = p
				log_("%s apre una concessione sul confine %s." % [pname(p), _nome_confine(o["b"])])


func immune_pirati(p: int) -> bool:
	return p >= 0 and ha_abilita(p, "immuni_pirati")


func metti_pirata(col: String, k: String) -> void:
	if not prendi_pezzo("S:" + col):
		return
	var b: Dictionary = S["bord"][k]
	if b["s"] != "":
		log_("Il pirata %s affonda il pirata %s." % [_agg(col), _agg(b["s"])])
	b["s"] = col
	if b["p"] >= 0 and not immune_pirati(b["p"]):
		log_("Un pirata affonda la concessione di %s sul confine %s." % [pname(b["p"]), _nome_confine(k)])
		P(b["p"])["pawns"] += 1
		b["p"] = -1
	else:
		log_("Un pirata %s si piazza sul confine %s." % [_agg(col), _nome_confine(k)])


func _agg(col: String) -> String:
	return {"C": "d'oro", "I": "verde", "R": "rosso"}.get(col, col)


func _nome_confine(k: String) -> String:
	var ii: Array = PaxDB.confini[k]["imperi"]
	var n: String = PaxDB.confini[k]["nome"]
	return "%s–%s%s" % [PaxDB.nome_imp(ii[0]), PaxDB.nome_imp(ii[1]), (" (%s)" % n if n != "" else "")]


func _desc_posto(dest: String) -> String:
	if dest.begins_with("@"):
		var e := dest.substr(1)
		var o: int = S["emp"][e]["own"]
		return ("%s (trono)" % PaxDB.nome_imp(e)) if o < 0 else "%s di %s" % [PaxDB.nome_imp(e), pname(o)]
	var o := proprietario(dest)
	return "%s%s" % [PaxDB.nome_carta(dest), (" di " + pname(o)) if o >= 0 else ""]


## Carte e troni dove si può mettere il vescovo di una carta appena giocata.
func destinazioni_vescovo_carta(c: String) -> Array:
	var out := [c]
	var ll := PaxDB.luoghi(card(c)["luogo"])
	for p in S["np"]:
		for id in carte_tableau(p):
			if id == c:
				continue
			for x in luoghi(id):
				if x in ll:
					out.append(id)
					break
	for e in S["emp"]:
		if S["emp"][e]["own"] < 0 and e in ll:
			out.append("@" + e)
	return out


func metti_vescovo(p: int, col: String, dest: String) -> void:
	if S["bish"].has(dest):
		log_("Dieta di Worms: i due vescovi su %s si eliminano." % PaxDB.nome_carta(dest))
		S["bish"].erase(dest)
		return
	S["bish"][dest] = col
	log_("Un vescovo %s arriva su %s." % [_agg(col), _desc_posto(dest)])
	# pacificazione
	if dest.begins_with("@"):
		var e := dest.substr(1)
		var rep: Array = S["emp"][e]["rep"]
		if not rep.is_empty():
			var opts := [{"t": "Nessuno", "k": "no"}]
			for i in rep.size():
				opts.append({"t": "Elimina il represso %s" % _desc_token(rep[i]), "k": "rep:%s:%d" % [e, i], "i": i})
			var k : int = await ask(p, "Pacificazione in %s: eliminare un pezzo represso?" % PaxDB.nome_imp(e), opts, "pacifica", {"sempre": true})
			if k > 0:
				var t: String = rep[opts[k]["i"]]
				rep.remove_at(opts[k]["i"])
				uccidi_token(t)
				log_("Il vescovo pacifica un %s represso." % _desc_token(t))


func _desc_token(t: String) -> String:
	if t.begins_with("P:"):
		return "servo di " + pname(int(t.split(":")[1]))
	return PaxDB.nome_pezzo(t)

# ----------------------------------------------------------------------- battaglie

func puo_battaglia(p: int, c: String, os: String, e: String) -> bool:
	if os in PaxDB.REL_GUERRA:
		var r: String = PaxDB.REL_GUERRA[os]
		return not difensori_religione(e, r).is_empty()
	return true


func credenti_carta(c: String) -> String:
	var cols := {}
	for ag in card(c).get("agenti", []):
		if ag.contains(":"):
			cols[ag.split(":")[1]] = true
	if cols.size() == 1:
		return cols.keys()[0]
	return ""


## Difensori in una guerra di religione: classe dominante eretica e pirati eretici sui confini.
func difensori_religione(e: String, r: String) -> Array:
	var out := []
	for j in S["city"][e].size():
		var t: String = S["city"][e][j]
		if t != "" and not t.ends_with(":" + r):
			out.append({"t": t, "src": "city", "e": e, "j": j})
	for k in confini_di(e):
		var s: String = S["bord"][k]["s"]
		if s != "" and s != r:
			out.append({"t": "S:" + s, "src": "bord", "b": k})
	return out


func one_shot_battaglia(p: int, c: String, os: String, e: String) -> void:
	if os in ["conspiracy", "revolt"]:
		await battaglia_civile(p, c, os, e)
	else:
		await guerra_religione(p, c, os, e)


func battaglia_civile(p: int, c: String, os: String, e: String) -> void:
	var att := []
	if c != "":
		for ag in card(c).get("agenti", []):
			if ag.begins_with("B"):
				continue
			if ag == "P":
				att.append({"t": "P:%d" % p, "src": "agente"})
			else:
				att.append({"t": ag, "src": "agente"})
	for k in confini_di(e):
		var b: Dictionary = S["bord"][k]
		if b["s"] != "":
			att.append({"t": "S:" + b["s"], "src": "bord", "b": k})
		if os == "revolt" and b["p"] == p:
			att.append({"t": "P:%d" % p, "src": "conc", "b": k})
	var rep: Array = S["emp"][e]["rep"]
	for i in rep.size():
		var t: String = rep[i]
		if os == "conspiracy" and (t.begins_with("K:") or t.begins_with("R:")):
			att.append({"t": t, "src": "rep", "i": i})
		if os == "revolt" and t.begins_with("P:"):
			att.append({"t": t, "src": "rep", "i": i})
	var dif := []
	for j in S["city"][e].size():
		if S["city"][e][j] != "":
			dif.append({"t": S["city"][e][j], "src": "city", "e": e, "j": j})
	var vinto : bool = await battaglia(p, e, att, dif)
	if vinto:
		await cambio_regime(p, e, "civil", {})
	if c != "":
		await piazza_agenti(p, c, true, true)


func guerra_religione(p: int, c: String, os: String, e: String) -> void:
	var r: String = PaxDB.REL_GUERRA[os]
	var att := []
	for ag in card(c).get("agenti", []):
		if ag.begins_with("B") or ag.begins_with("P"):
			continue
		att.append({"t": ag, "src": "agente"})
	for k in confini_di(e):
		if S["bord"][k]["s"] == r:
			att.append({"t": "S:" + r, "src": "bord", "b": k})
	for j in S["city"][e].size():
		if S["city"][e][j] != "" and S["city"][e][j].ends_with(":" + r):
			att.append({"t": S["city"][e][j], "src": "city", "e": e, "j": j})
	var rodi := r == "C" and ha_abilita(p, "cavalieri_rodi")
	for a in adiacenti(e):
		for j in S["city"][a].size():
			var t: String = S["city"][a][j]
			if t == "K:" + r or (rodi and t == "R:C"):
				att.append({"t": t, "src": "city", "e": a, "j": j})
	var dif := difensori_religione(e, r)
	var vinto : bool = await battaglia(p, e, att, dif)
	if vinto:
		S["th"][e] = r
		log_("%s diventa una teocrazia %s." % [PaxDB.nome_imp(e), PaxDB.NOMI_REL[r]])
		controlla_venezia()
		await cambio_regime(p, e, "relig", {})
	await piazza_agenti(p, c, true, true)


## Battaglia: ogni attaccante uccide un difensore e muore. Vince chi attacca se resta almeno un attaccante.
## L'attaccante sceglie tutte le perdite. Gli agenti e i repressi sopravvissuti si piazzano nell'impero.
func battaglia(p: int, e: String, att: Array, dif: Array) -> bool:
	var n := mini(att.size(), dif.size())
	log_("Battaglia in %s: %d attaccanti contro %d difensori." % [PaxDB.nome_imp(e), att.size(), dif.size()])
	# perdite dei difensori
	var morti_d := []
	if att.size() >= dif.size():
		morti_d = dif.duplicate()
	else:
		var rest := dif.duplicate()
		for x in n:
			var opts := []
			for d in rest:
				opts.append({"t": "Uccidi %s%s" % [PaxDB.nome_pezzo(d["t"]), _dove(d)], "k": _chiave_pezzo(d)})
			var k : int = await ask(p, "Scegli il difensore da uccidere", opts, "perdita_dif")
			morti_d.append(rest[k])
			rest.remove_at(k)
	var morti_a := []
	var resta := att.duplicate()
	if n >= att.size():
		morti_a = att.duplicate()
		resta = []
	else:
		for x in n:
			var opts := []
			var viste := {}
			var idx := []
			for i in resta.size():
				var a: Dictionary = resta[i]
				var key: String = a["t"] + "|" + a["src"] + "|" + str(a.get("b", "")) + str(a.get("e", "")) + str(a.get("j", ""))
				if a["src"] in ["agente", "rep"]:
					key = a["t"] + "|" + a["src"]
				if viste.has(key):
					continue
				viste[key] = true
				opts.append({"t": "Sacrifica %s%s" % [_desc_att(a), _dove(a)], "k": _chiave_pezzo(a)})
				idx.append(i)
			var k : int = await ask(p, "Scegli l'attaccante che cade", opts, "perdita_att")
			morti_a.append(resta[idx[k]])
			resta.remove_at(idx[k])
	# applica le perdite
	var rep_da_togliere := []
	for d in morti_d:
		_togli_pezzo(d, rep_da_togliere, e)
	for a in morti_a:
		_togli_pezzo(a, rep_da_togliere, e)
	var vinto := resta.size() > 0
	log_("%s: %s." % [PaxDB.nome_imp(e), "gli attaccanti vincono" if vinto else "l'attacco fallisce"])
	# sopravvissuti da piazzare (agenti e repressi usati come attaccanti)
	var da_piazzare := []
	var rep_usati := []
	for a in resta:
		if a["src"] == "agente":
			da_piazzare.append([a["t"], true])
		elif a["src"] == "rep":
			da_piazzare.append([a["t"], false])
			rep_usati.append(a["i"])
	rep_usati.append_array(rep_da_togliere)
	rep_usati.sort()
	rep_usati.reverse()
	for i in rep_usati:
		S["emp"][e]["rep"].remove_at(i)
	for x in da_piazzare:
		await piazza_sopravvissuto(p, e, x[0], x[1])
	return vinto


func _desc_att(a: Dictionary) -> String:
	match a["src"]:
		"agente":
			return "l'agente " + PaxDB.nome_pezzo(a["t"])
		"rep":
			return "il represso " + _desc_token(a["t"])
		"conc":
			return "la tua concessione"
	return PaxDB.nome_pezzo(a["t"])


func _dove(a: Dictionary) -> String:
	match a["src"]:
		"city":
			return " a " + nome_citta(a["e"], a["j"])
		"bord", "conc":
			return " sul confine " + _nome_confine(a["b"])
	return ""


func _chiave_pezzo(a: Dictionary) -> String:
	match a["src"]:
		"city":
			return "city:%s:%d" % [a["e"], a["j"]]
		"bord", "conc":
			return "bord:" + a["b"]
	return "x"


func _togli_pezzo(a: Dictionary, rep_idx: Array, e: String) -> void:
	match a["src"]:
		"city":
			S["city"][a["e"]][a["j"]] = ""
		"bord":
			S["bord"][a["b"]]["s"] = ""
		"conc":
			S["bord"][a["b"]]["p"] = -1
			uccidi_token(a["t"])
		"rep":
			rep_idx.append(a["i"])
			uccidi_token(a["t"])
		"schiavo":
			var rr: Array = S["emp"]["Mamluk"]["rep"]
			var ii := rr.find(a["t"])
			if ii >= 0:
				rr.remove_at(ii)
			uccidi_token(a["t"])
		"agente":
			pass


func piazza_sopravvissuto(p: int, e: String, t: String, da_riserva: bool) -> void:
	var tipo := t.split(":")[0]
	var opts := []
	if tipo == "K" or tipo == "R":
		for j in citta_vuote(e):
			opts.append({"t": "%s a %s" % [PaxDB.nome_pezzo(t).capitalize(), nome_citta(e, j)], "k": "city:%s:%d" % [e, j], "j": j})
	elif tipo == "S":
		for k in confini_di(e):
			if mare(k) and S["bord"][k]["s"] == "" and S["bord"][k]["p"] < 0:
				opts.append({"t": "Pirata sul confine " + _nome_confine(k), "k": "bord:" + k, "b": k})
	elif tipo == "P":
		for k in confini_di(e):
			if S["bord"][k]["s"] == "" and S["bord"][k]["p"] < 0:
				opts.append({"t": "Concessione sul confine " + _nome_confine(k), "k": "bord:" + k, "b": k})
	if opts.is_empty():
		if tipo == "P":
			if not da_riserva or prendi_pedone(int(t.split(":")[1])):
				S["emp"][e]["rep"].append(t)
		elif tipo != "S" and prendi_pezzo(t):
			S["emp"][e]["rep"].append(t)
		return
	var k : int = await ask(p, "Dove si piazza il sopravvissuto (%s)?" % _desc_token(t), opts, "sopravvissuto")
	var o: Dictionary = opts[k]
	if tipo == "K" or tipo == "R":
		if prendi_pezzo(t):
			S["city"][e][o["j"]] = t
	elif tipo == "S":
		if prendi_pezzo(t):
			S["bord"][o["b"]]["s"] = t.split(":")[1]
	else:
		var q := int(t.split(":")[1])
		if not da_riserva or prendi_pedone(q):
			S["bord"][o["b"]]["p"] = q

# ----------------------------------------------------------------------- cambio di regime

## how: coron, vote, civil, relig, campaign. extra: queen, suz (per le campagne).
func cambio_regime(p: int, e: String, how: String, extra: Dictionary) -> void:
	var em: Dictionary = S["emp"][e]
	var o: int = em["own"]
	# un sovrano che subisce un cambio di regime perde i vassalli
	for v in vassalli(e):
		torna_trono(v, true)
		log_("%s torna libero nel suo trono." % PaxDB.nome_imp(v))
	if how == "campaign":
		var suz: String = extra["suz"]
		if o >= 0:
			togli_tableau(o, "@" + e)
			if em["queen"] != "":
				S["bish"].erase(em["queen"])
				em["queen"] = ""
			S["bish"].erase("@" + e)
		em["own"] = p
		em["suz"] = suz
		em["side"] = "K"
		log_("%s diventa vassallo di %s." % [PaxDB.nome_imp(e), PaxDB.nome_imp(suz)])
	elif o == p and how != "coron":
		# uomo di paglia: si gira il quadrato
		if em["queen"] != "":
			S["bish"].erase(em["queen"])
			em["queen"] = ""
		S["bish"].erase("@" + e)
		if em["suz"] != "":
			em["suz"] = ""
			em["side"] = "R"
			P(p)[PaxDB.lato_imp(e)].append("@" + e)
		else:
			em["side"] = "R" if em["side"] == "K" else "K"
		log_("%s diventa %s." % [PaxDB.nome_imp(e), "una repubblica" if em["side"] == "R" else "un regno"])
	else:
		if o >= 0 and o != p:
			togli_tableau(o, "@" + e)
			if em["queen"] != "":
				S["bish"].erase(em["queen"])
				em["queen"] = ""
			S["bish"].erase("@" + e)
			log_("%s strappa %s a %s." % [pname(p), PaxDB.nome_imp(e), pname(o)])
		elif o < 0:
			log_("%s prende %s dal trono." % [pname(p), PaxDB.nome_imp(e)])
		if how == "coron" and em["queen"] != "" and em["queen"] != extra.get("queen", ""):
			S["bish"].erase(em["queen"])
			em["queen"] = ""
		var gia_mio: bool = o == p
		em["own"] = p
		em["suz"] = ""
		em["side"] = "K"
		if how == "coron":
			em["queen"] = extra["queen"]
		if not gia_mio:
			P(p)[PaxDB.lato_imp(e)].append("@" + e)
	await concessione_premio(p, e)
	await emancipa(p, e)
	if how == "vote" and S["th"][e] != "M":
		if await si_no(p, "Libertà dorata: rendere %s uno stato medievale (non teocratico)?" % PaxDB.nome_imp(e), "liberta"):
			S["th"][e] = "M"
			log_("Libertà dorata: %s non è più una teocrazia." % PaxDB.nome_imp(e))
			controlla_venezia()


func concessione_premio(p: int, e: String) -> void:
	var opts := [{"t": "Nessuna concessione", "k": "no"}]
	if P(p)["pawns"] > 0 or true:
		for k in confini_di(e):
			var b: Dictionary = S["bord"][k]
			if b["s"] != "":
				continue
			if b["p"] < 0:
				opts.append({"t": "Concessione sul confine " + _nome_confine(k), "k": "bord:" + k, "b": k})
			elif b["p"] != p and P(p)["fl"] >= 1:
				opts.append({"t": "Concessione su %s reprimendo %s (1 ƒ)" % [_nome_confine(k), pname(b["p"])], "k": "bord:" + k, "b": k})
	if opts.size() == 1:
		return
	var k : int = await ask(p, "Cambio di regime in %s: nuova concessione?" % PaxDB.nome_imp(e), opts, "premio", {"sempre": true})
	if k == 0:
		return
	var bb: Dictionary = S["bord"][opts[k]["b"]]
	if bb["p"] >= 0:
		P(p)["fl"] -= 1
		S["emp"][e]["rep"].append("P:%d" % bb["p"])
		bb["p"] = -1
	if prendi_pedone(p):
		bb["p"] = p
		log_("%s apre una concessione sul confine %s." % [pname(p), _nome_confine(opts[k]["b"])])


func emancipa(p: int, e: String) -> void:
	var rep: Array = S["emp"][e]["rep"]
	var tentativi := 0
	while not rep.is_empty() and tentativi < 20:
		tentativi += 1
		var opts := [{"t": "Basta così", "k": "no"}]
		for i in rep.size():
			var t: String = rep[i]
			if t.begins_with("P:"):
				for k in confini_di(e):
					if S["bord"][k]["s"] == "" and S["bord"][k]["p"] < 0:
						opts.append({"t": "Emancipa il %s sul confine %s" % [_desc_token(t), _nome_confine(k)], "k": "bord:" + k, "i": i, "b": k})
			else:
				for j in citta_vuote(e):
					opts.append({"t": "Emancipa il %s a %s" % [PaxDB.nome_pezzo(t), nome_citta(e, j)], "k": "city:%s:%d" % [e, j], "i": i, "j": j})
		if opts.size() == 1:
			return
		var k : int = await ask(p, "Emancipazione in %s" % PaxDB.nome_imp(e), opts, "emancipa", {"sempre": true})
		if k == 0:
			return
		var o: Dictionary = opts[k]
		var t: String = rep[o["i"]]
		rep.remove_at(o["i"])
		if o.has("b"):
			S["bord"][o["b"]]["p"] = int(t.split(":")[1])
		else:
			S["city"][e][o["j"]] = t
		log_("Un %s viene emancipato in %s." % [_desc_token(t), PaxDB.nome_imp(e)])


func emancipa_zona(p: int, imperi: Array) -> void:
	for e in imperi:
		if not S["emp"][e]["rep"].is_empty():
			await emancipa(p, e)


func controlla_venezia() -> void:
	# senza condottieri attivi Venezia ospita un solo pezzo
	if not condottieri_attivi():
		var c: Array = S["city"]["PapalStates"]
		if c.size() > 1 and c[1] != "":
			if c[0] == "":
				c[0] = c[1]
			c[1] = ""

# ----------------------------------------------------------------------- apostasia

func apostasia(p: int, r1: String, r2: String, c: String) -> void:
	log_("Apostasia: chi ha prestigio %s e %s scarta quelle carte." % [PaxDB.NOMI_PRESTIGIO[r1], PaxDB.NOMI_PRESTIGIO[r2]])
	if c != "":
		var pr: Array = card(c).get("prestigio", [])
		if r1 in pr or r2 in pr:
			await piazza_agenti(p, c, true)
			c = ""
	for q in S["np"]:
		if ha_abilita(q, "immune_apostasia"):
			continue
		var tab := carte_tableau(q)
		var ha1 := false
		var ha2 := false
		for id in tab:
			var pr := prestigio(id)
			if r1 in pr:
				ha1 = true
			if r2 in pr:
				ha2 = true
		if not (ha1 and ha2):
			continue
		for id in tab:
			var pr := prestigio(id)
			if not (r1 in pr or r2 in pr):
				continue
			if id.begins_with("@"):
				if S["emp"][id.substr(1)]["own"] == q:
					torna_trono(id.substr(1), true)
					log_("%s perde %s per apostasia." % [pname(q), PaxDB.nome_carta(id)])
			elif card(id).get("regina", false):
				var e := sposo(id)
				if e != "" and S["emp"][e]["own"] == q:
					torna_trono(e, true)
					log_("%s perde la coppia reale di %s per apostasia." % [pname(q), PaxDB.nome_imp(e)])
			else:
				scarta_carta(id)
				log_("%s scarta %s per apostasia." % [pname(q), PaxDB.nome_carta(id)])
	if c != "":
		await piazza_agenti(p, c, true)

# ----------------------------------------------------------------------- fiere commerciali

func fiera(p: int, lato: String) -> void:
	var slot: Dictionary = S["mk"][lato][0]
	var c: String = slot["c"]
	slot["c"] = ""
	var prof: int = slot["f"] + (1 if S["np"] <= 2 else 2)
	slot["f"] = 0
	var em: String = S["emporio"][lato]
	var rotta: Array = PaxDB.mappa["rotte"][em]["imperi"]
	log_("%s convoca la fiera d'%s (scarta %s): %d ƒ di profitti, partenza da %s." % [pname(p),
		"Oriente" if lato == "E" else "Occidente", PaxDB.nome_carta(c), prof, PaxDB.NOMI_EMPORI[em]])
	if prof <= 0:
		return
	prof -= 1
	P(p)["fl"] += 1
	if prof <= 0:
		return
	var levate := [rotta[0]]
	var spezie := em == "SpiceIslands"
	for i in range(rotta.size() - 1):
		var k := confine_tra(rotta[i], rotta[i + 1])
		var b: Dictionary = S["bord"][k]
		var preso := false
		if b["p"] >= 0:
			var q: int = b["p"]
			var molt := 1 + conta_abilita(q, "fama_mecenate")
			if spezie:
				molt += conta_abilita(q, "buona_speranza")
			var x := mini(molt, prof)
			prof -= x
			P(q)["fl"] += x
			preso = true
			log_("La concessione di %s sul confine %s incassa %d ƒ." % [pname(q), _nome_confine(k), x])
		elif b["s"] != "":
			prof -= 1
			preso = true
			log_("Un pirata sul confine %s prende 1 ƒ." % _nome_confine(k))
		if prof <= 0 and preso:
			break
		levate.append(rotta[i + 1])
	slot["f"] = prof
	for e in levate:
		var vuote := []
		for j in citta_vuote(e):
			vuote.append(j)
		if vuote.is_empty():
			continue
		var opts := []
		for j in vuote:
			var t := icona(e, j)
			opts.append({"t": "%s a %s (%s)" % [PaxDB.nome_pezzo(t).capitalize(), nome_citta(e, j), PaxDB.nome_imp(e)], "k": "city:%s:%d" % [e, j], "j": j})
		var k : int = await ask(p, "Leva in %s: dove?" % PaxDB.nome_imp(e), opts, "leva")
		var j2: int = opts[k]["j"]
		var t2 := icona(e, j2)
		if prendi_pezzo(t2):
			S["city"][e][j2] = t2
			log_("Leva in %s: un %s a %s." % [PaxDB.nome_imp(e), PaxDB.nome_pezzo(t2), nome_citta(e, j2)])

# ======================================================================= operazioni

## Elenco di tutte le operazioni eseguibili ora nel lato l: [{c, op, bersagli...}] (senza i bersagli).
func elenco_op(p: int, l: String, usate := []) -> Array:
	var out := []
	for id in carte_tableau(p, l):
		if id in usate:
			continue
		var sil := silenziata(p, id)
		var ops := ops_carta(id)
		for op in ops:
			if sil and not op.begins_with("inq"):
				continue
			if not bersagli_op(p, id, op).is_empty():
				out.append({"c": id, "op": op})
	return out


## Bersagli di un'operazione: elenco di opzioni {t, k, ...}.
func bersagli_op(p: int, id: String, op: String) -> Array:
	var nome: String = op.split(":")[0]
	var arg: String = op.split(":")[1] if op.contains(":") else ""
	var out := []
	var ll := luoghi(id)
	match nome:
		"commerce":
			for i in 6:
				if S["mk"][arg][i]["f"] > 0:
					out.append({"t": "Prendi 1 ƒ dal mercato d'%s (posto %d)" % ["Oriente" if arg == "E" else "Occidente", i + 1],
						"k": "mkt:%s:%d" % [arg, i], "lato": arg, "i": i})
		"behead":
			var gen: bool = "genocidio" in card(id).get("abilita", [])
			var olo: bool = "olocausto" in card(id).get("abilita", [])
			for q in S["np"]:
				for t in carte_tableau(q):
					if t == id:
						continue
					var ok := false
					for x in luoghi(t):
						if x in ll:
							ok = true
					if not ok:
						continue
					if gen and not (lato_carta(t) == "E" and S["bish"].get(t, "") in ["I", "R"]):
						continue
					if olo and not (lato_carta(t) == "W" and S["bish"].get(t, "") in ["R", "C"]):
						continue
					out.append({"t": "Decapita %s (%s)" % [PaxDB.nome_carta(t), pname(q)], "k": "card:" + t, "c": t})
		"tax":
			for e in ll:
				if not _leva_possibile(e):
					continue
				for k in confini_di(e):
					if S["bord"][k]["p"] >= 0:
						out.append({"t": "Tassa la concessione di %s su %s (leva in %s)" % [pname(S["bord"][k]["p"]), _nome_confine(k), PaxDB.nome_imp(e)],
							"k": "bord:" + k, "b": k, "e": e})
		"repress":
			for e in ll:
				for j in S["city"][e].size():
					var t: String = S["city"][e][j]
					if t != "" and t.split(":")[0] in arg:
						out.append({"t": "Reprimi %s a %s (+1 ƒ)" % [PaxDB.nome_pezzo(t), nome_citta(e, j)], "k": "city:%s:%d" % [e, j], "e": e, "j": j})
				if "P" in arg:
					for k in confini_di(e):
						if S["bord"][k]["p"] >= 0:
							out.append({"t": "Reprimi la concessione di %s su %s (+1 ƒ, servo in %s)" % [pname(S["bord"][k]["p"]), _nome_confine(k), PaxDB.nome_imp(e)],
								"k": "bord:" + k, "b": k, "e": e})
		"vote":
			for e in S["emp"]:
				var em: Dictionary = S["emp"][e]
				if em["own"] < 0 or em["suz"] != "" or PaxDB.lato_imp(e) != arg:
					continue
				if not maggioranza(p, e):
					continue
				var costo := costo_voto(p, e)
				if costo > P(p)["fl"]:
					continue
				out.append({"t": "Voto in %s (%d ƒ)" % [PaxDB.nome_imp(e), costo], "k": "emp:" + e, "e": e})
		"corsair":
			for e in ll:
				for k in confini_di(e):
					if S["bord"][k]["s"] != arg or not mare(k):
						continue
					var dests := {}
					var zone := [e] + vicini_mare(e)
					for z in zone:
						for k2 in confini_di(z):
							if k2 != k and mare(k2) and S["bord"][k2]["s"] != arg:
								dests[k2] = true
					for k2 in dests:
						var t := "Pirata %s da %s a %s" % [_agg(arg), _nome_confine(k), _nome_confine(k2)]
						var b2: Dictionary = S["bord"][k2]
						if b2["p"] >= 0 and not immune_pirati(b2["p"]):
							t += " (affonda %s)" % pname(b2["p"])
						elif b2["s"] != "":
							t += " (affonda il pirata %s)" % _agg(b2["s"])
						out.append({"t": t, "k": "bord:" + k2, "da": k, "a": k2})
		"siege":
			var visti := {}
			for e in ll:
				for j in S["city"][e].size():
					var t: String = S["city"][e][j]
					if t != "":
						out.append({"t": "Assedio: uccidi %s a %s" % [PaxDB.nome_pezzo(t), nome_citta(e, j)], "k": "city:%s:%d" % [e, j], "e": e, "j": j})
				for k in confini_di(e):
					if S["bord"][k]["s"] != "" and not visti.has(k):
						visti[k] = true
						out.append({"t": "Assedio: affonda il pirata %s su %s" % [_agg(S["bord"][k]["s"]), _nome_confine(k)], "k": "bord:" + k, "b": k})
		"campaign":
			if not id.begins_with("@"):
				return []
			var e := id.substr(1)
			if S["emp"][e]["side"] != "K":
				return []
			var cav := cavalieri_campagna(p, e)
			if cav <= 0 or cav > P(p)["fl"]:
				return []
			for d in adiacenti(e):
				var od: int = S["emp"][d]["own"]
				if od == p:
					continue
				out.append({"t": "Campagna da %s contro %s (%d cavalieri, %d ƒ, %d difensori)" % [PaxDB.nome_imp(e), PaxDB.nome_imp(d), cav, cav, classe_dominante(d).size()],
					"k": "emp:" + d, "e": d})
		"inq":
			for src in S["bish"]:
				if S["bish"][src] != arg:
					continue
				for dest in destinazioni_inquisitore(src):
					var t := "Sposta il vescovo %s da %s a %s" % [_agg(arg), _desc_posto(src), _desc_posto(dest)]
					if S["bish"].has(dest):
						t += " (Dieta di Worms)"
					out.append({"t": t, "k": "card:" + dest, "da": src, "a": dest})
	return out


func _leva_possibile(e: String) -> bool:
	return not citta_vuote(e).is_empty()


func cavalieri_campagna(p: int, e: String) -> int:
	var n := 0
	for t in S["city"][e]:
		if t.begins_with("K:"):
			n += 1
	if e == "Mamluk" and ha_abilita(p, "soldati_schiavi"):
		for t in S["emp"]["Mamluk"]["rep"]:
			if t.begins_with("P:"):
				n += 1
	return n


func maggioranza(p: int, e: String) -> bool:
	var mio := conc_su(e, p) * (1 + conta_abilita(p, "fama_mecenate"))
	if mio == 0:
		return false
	for q in S["np"]:
		if q != p and conc_su(e, q) >= mio:
			return false
	return true


func costo_voto(p: int, e: String) -> int:
	var c: int = S["emp"][e]["rep"].size()
	if ha_abilita(p, "banchieri_ebrei"):
		c -= conta_prestigio(p, "P", false)
	return maxi(0, c)


## Destinazioni di un vescovo spostato con l'inquisitore.
func destinazioni_inquisitore(src: String) -> Array:
	var out := []
	var in_trono: bool = src.begins_with("@") and S["emp"][src.substr(1)]["own"] < 0
	var o := proprietario(src)
	# adiacenti nello stesso tableau
	if o >= 0 and not in_trono:
		for d in adiacenti_tableau(o, src):
			out.append(d)
	# stesso luogo, in qualsiasi tableau o trono
	for q in S["np"]:
		for id in carte_tableau(q):
			if id != src and not (id in out) and stesso_luogo(src, id):
				out.append(id)
	if not in_trono:
		for e in S["emp"]:
			if S["emp"][e]["own"] < 0 and ("@" + e) != src and e in luoghi(src) and not (("@" + e) in out):
				out.append("@" + e)
	return out


func adiacenti_tableau(p: int, id: String) -> Array:
	var out := []
	# vassalli e sovrani
	if id.begins_with("@"):
		var e := id.substr(1)
		var suz: String = S["emp"][e]["suz"]
		if suz != "":
			out.append("@" + suz)
			for v in vassalli(suz):
				if v != e:
					out.append("@" + v)
			# a destra e sinistra del sovrano
			id = "@" + suz
		else:
			for v in vassalli(e):
				out.append("@" + v)
	var q := sposo(id) if not id.begins_with("@") else ""
	if q != "":
		id = "@" + q
	for l in ["W", "E"]:
		var lst: Array = P(p)[l]
		var i := lst.find(id)
		if i < 0:
			continue
		if i > 0:
			out.append(lst[i - 1])
		if i < lst.size() - 1:
			out.append(lst[i + 1])
	var out2 := []
	for x in out:
		if x != id and not (x in out2):
			out2.append(x)
	return out2


func operazioni(p: int, l: String) -> void:
	var usate := []
	var fatte := 0
	while not S["over"]:
		var opts := []
		for x in elenco_op(p, l, usate):
			for b in bersagli_op(p, x["c"], x["op"]):
				var o: Dictionary = b.duplicate()
				o["c"] = x["c"]
				o["op"] = x["op"]
				o["t"] = "%s — %s: %s" % [PaxDB.nome_carta(x["c"]), PaxDB.NOMI_OP[x["op"].split(":")[0]], b["t"]]
				opts.append(o)
		if opts.is_empty():
			break
		if fatte > 0:
			opts.append({"t": "Fine delle operazioni", "k": "fine"})
		var k : int = await ask(p, "Operazioni d'%s: scegli" % ("Oriente" if l == "E" else "Occidente"), opts, "op", {"sempre": true, "lato": l})
		var o: Dictionary = opts[k]
		if o["k"] == "fine":
			break
		usate.append(o["c"])
		fatte += 1
		await esegui_op(p, o["c"], o["op"], o)
		cambiato.emit()


func esegui_op(p: int, id: String, op: String, b: Dictionary) -> void:
	var nome: String = op.split(":")[0]
	var arg: String = op.split(":")[1] if op.contains(":") else ""
	match nome:
		"commerce":
			S["mk"][b["lato"]][b["i"]]["f"] -= 1
			P(p)["fl"] += 1
			log_("%s usa il commercio di %s: +1 ƒ." % [pname(p), PaxDB.nome_carta(id)])
		"behead":
			var t: String = b["c"]
			log_("%s fa decapitare %s con %s." % [pname(p), PaxDB.nome_carta(t), PaxDB.nome_carta(id)])
			if t.begins_with("@"):
				torna_trono(t.substr(1), false)
				# l'assassino muore
				if id.begins_with("@"):
					torna_trono(id.substr(1), true)
				else:
					scarta_carta(id)
				log_("L'assassino (%s) viene ucciso." % PaxDB.nome_carta(id))
			else:
				scarta_carta(t)
		"tax":
			var k: String = b["b"]
			var e: String = b["e"]
			var q: int = S["bord"][k]["p"]
			var opts := []
			if P(q)["fl"] >= 1:
				opts.append({"t": "Paga 1 ƒ", "k": "paga"})
			opts.append({"t": "Lascia reprimere la concessione", "k": "reprimi"})
			var sc : int = await ask(q, "Tassa di %s su %s: cosa fai?" % [pname(p), _nome_confine(k)], opts, "tassa")
			if opts[sc]["k"] == "paga":
				P(q)["fl"] -= 1
				log_("%s paga la tassa di 1 ƒ." % pname(q))
			else:
				S["bord"][k]["p"] = -1
				S["emp"][e]["rep"].append("P:%d" % q)
				log_("La concessione di %s viene repressa in %s." % [pname(q), PaxDB.nome_imp(e)])
			var vuote := citta_vuote(e)
			if not vuote.is_empty():
				var lo := []
				for j in vuote:
					lo.append({"t": "%s a %s" % [PaxDB.nome_pezzo(icona(e, j)).capitalize(), nome_citta(e, j)], "k": "city:%s:%d" % [e, j], "j": j})
				var kk : int = await ask(q, "Leva della tassa in %s: dove?" % PaxDB.nome_imp(e), lo, "leva")
				var j: int = lo[kk]["j"]
				var tt := icona(e, j)
				if prendi_pezzo(tt):
					S["city"][e][j] = tt
					log_("Leva in %s: un %s a %s." % [PaxDB.nome_imp(e), PaxDB.nome_pezzo(tt), nome_citta(e, j)])
		"repress":
			if b.has("j"):
				var t: String = S["city"][b["e"]][b["j"]]
				S["city"][b["e"]][b["j"]] = ""
				S["emp"][b["e"]]["rep"].append(t)
				log_("%s reprime un %s a %s (+1 ƒ)." % [pname(p), PaxDB.nome_pezzo(t), nome_citta(b["e"], b["j"])])
			else:
				var q: int = S["bord"][b["b"]]["p"]
				S["bord"][b["b"]]["p"] = -1
				S["emp"][b["e"]]["rep"].append("P:%d" % q)
				log_("%s reprime la concessione di %s: diventa servo in %s (+1 ƒ)." % [pname(p), pname(q), PaxDB.nome_imp(b["e"])])
			P(p)["fl"] += 1
		"vote":
			var e: String = b["e"]
			var costo := costo_voto(p, e)
			P(p)["fl"] -= costo
			log_("%s vince il voto in %s (%d ƒ)." % [pname(p), PaxDB.nome_imp(e), costo])
			await cambio_regime(p, e, "vote", {})
		"corsair":
			S["bord"][b["da"]]["s"] = ""
			var bb: Dictionary = S["bord"][b["a"]]
			if bb["s"] != "":
				log_("Il corsaro affonda il pirata %s." % _agg(bb["s"]))
			bb["s"] = arg
			if bb["p"] >= 0 and not immune_pirati(bb["p"]):
				log_("Il corsaro affonda la concessione di %s su %s." % [pname(bb["p"]), _nome_confine(b["a"])])
				P(bb["p"])["pawns"] += 1
				bb["p"] = -1
			else:
				log_("Un pirata %s si sposta su %s." % [_agg(arg), _nome_confine(b["a"])])
		"siege":
			if b.has("j"):
				log_("%s assedia %s: muore un %s." % [pname(p), nome_citta(b["e"], b["j"]), PaxDB.nome_pezzo(S["city"][b["e"]][b["j"]])])
				S["city"][b["e"]][b["j"]] = ""
			else:
				log_("%s affonda un pirata su %s." % [pname(p), _nome_confine(b["b"])])
				S["bord"][b["b"]]["s"] = ""
		"campaign":
			var e := id.substr(1)
			var d: String = b["e"]
			var att := []
			for j in S["city"][e].size():
				if S["city"][e][j].begins_with("K:"):
					att.append({"t": S["city"][e][j], "src": "city", "e": e, "j": j})
			if e == "Mamluk" and ha_abilita(p, "soldati_schiavi"):
				var rr: Array = S["emp"]["Mamluk"]["rep"]
				for i in rr.size():
					if rr[i].begins_with("P:"):
						att.append({"t": rr[i], "src": "schiavo", "i": i})
			P(p)["fl"] -= att.size()
			var dif := []
			for j in S["city"][d].size():
				if S["city"][d][j] != "":
					dif.append({"t": S["city"][d][j], "src": "city", "e": d, "j": j})
			log_("%s lancia la campagna di %s contro %s." % [pname(p), PaxDB.nome_imp(e), PaxDB.nome_imp(d)])
			var vinto : bool = await battaglia(p, d, att, dif)
			if vinto:
				var suz := e
				if S["emp"][e]["suz"] != "":
					suz = S["emp"][e]["suz"]
				await cambio_regime(p, d, "campaign", {"suz": suz})
		"inq":
			var src: String = b["da"]
			var col: String = S["bish"][src]
			S["bish"].erase(src)
			log_("%s sposta un vescovo %s su %s." % [pname(p), _agg(col), _desc_posto(b["a"])])
			await metti_vescovo(p, col, b["a"])
	controlla_venezia()


## Cifrari medicei: un'operazione politica da una carta di un avversario.
func op_crittografia(p: int) -> void:
	var opts := [{"t": "Nessuna", "k": "no"}]
	for q in S["np"]:
		if q == p:
			continue
		for id in carte_tableau(q):
			if silenziata(q, id):
				continue
			for op in ops_carta(id):
				if op.split(":")[0] in ["behead", "tax", "repress", "vote"]:
					for b in bersagli_op(p, id, op):
						var o: Dictionary = b.duplicate()
						o["c"] = id
						o["op"] = op
						o["t"] = "%s di %s — %s" % [PaxDB.nome_carta(id), pname(q), b["t"]]
						opts.append(o)
	var k : int = await ask(p, "Cifrari medicei: un'operazione politica dall'avversario", opts, "op", {"sempre": true})
	if k > 0:
		await esegui_op(p, opts[k]["c"], opts[k]["op"], opts[k])

# ======================================================================= salvataggio

func dati_salvataggio() -> Dictionary:
	return {"registro": registro.duplicate()}
