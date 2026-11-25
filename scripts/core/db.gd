class_name PaxDB
extends RefCounted
## Dati del gioco (carte, mappa, imperi, rotte), letti una volta sola dai file JSON di data/.

static var carte := {}          # id -> carta
static var mappa := {}
static var ordine_imperi: Array = []
static var confini := {}        # chiave -> confine
static var confini_di := {}     # impero -> [chiavi dei confini]
static var slot := {}           # impero -> [[indice città, sotto-posto]]
static var caricato := false
static var promo_attiva := false   # partita in corso con la promo «Età della Riforma» (immagini)

const EST := ["Hungary", "Byzantium", "Ottoman", "Mamluk"]
const OVEST := ["England", "France", "HRE", "Portugal", "Aragon", "PapalStates"]
const RELIGIONI := ["C", "I", "R"]
const NOMI_REL := {"C": "cattolica", "I": "islamica", "R": "riformata"}
const NOMI_REL_PL := {"C": "cattolici", "I": "islamici", "R": "riformati"}
const NOMI_PRESTIGIO := {"C": "cattolico", "I": "islamico", "R": "riformato", "L": "legge", "D": "scoperta", "P": "mecenate"}
const NOMI_PEZZO := {"K": "cavaliere", "R": "torre", "B": "vescovo", "S": "pirata", "P": "pedone"}
const NOMI_OP := {"behead": "Decapita", "tax": "Tassa", "repress": "Reprimi", "vote": "Voto", "siege": "Assedio",
	"corsair": "Corsaro", "campaign": "Campagna", "inq": "Inquisitore", "commerce": "Commercio"}
const NOMI_ONESHOT := {"conspiracy": "complotto", "revolt": "rivolta contadina", "crusade": "crociata",
	"jihad": "jihad", "reformation": "riforma", "apostasy": "apostasia", "coronation": "incoronazione",
	"tradeshift": "spostamento commerciale"}
const REL_GUERRA := {"crusade": "C", "jihad": "I", "reformation": "R"}
const NOMI_EMPORI := {"Trebizond": "Trebisonda", "RedSea": "Mar Rosso", "SpiceIslands": "Isole delle Spezie",
	"Tana": "Tana", "Novgorod": "Novgorod", "Timbuktu": "Timbuctù"}
const NOMI_LUOGO := {"TheEast": "l'Oriente", "TheWest": "l'Occidente"}


static func carica() -> void:
	if caricato:
		return
	var cc = JSON.parse_string(FileAccess.get_file_as_string("res://data/carte.json"))
	for c in cc:
		carte[c["id"]] = c
	mappa = JSON.parse_string(FileAccess.get_file_as_string("res://data/mappa.json"))
	ordine_imperi = mappa["ordine"]
	for e in ordine_imperi:
		confini_di[e] = []
	for b in mappa["confini"]:
		confini[b["chiave"]] = b
		for e in b["imperi"]:
			confini_di[e].append(b["chiave"])
	for e in ordine_imperi:
		var l := []
		var citta: Array = mappa["imperi"][e]["citta"]
		for i in citta.size():
			var n: int = citta[i]["icone"]["M"].size()
			for k in n:
				l.append([i, k])
		if e == "PapalStates":
			l.append([0, 1])       # secondo posto di Venezia (condottieri)
		slot[e] = l
	caricato = true


static func imp(e: String) -> Dictionary:
	return mappa["imperi"][e]


static func nome_imp(e: String) -> String:
	if e == "TheEast" or e == "TheWest":
		return NOMI_LUOGO[e]
	return mappa["imperi"][e]["nome"] if mappa["imperi"].has(e) else e


static func lato_imp(e: String) -> String:
	return "E" if e in EST else "W"


## Imperi indicati da un luogo stampato.
static func luoghi(l: String) -> Array:
	if l == "TheEast":
		return EST.duplicate()
	if l == "TheWest":
		return OVEST.duplicate()
	if l == "" or l == "Queen":
		return []
	return [l]


static func nome_carta(id: String) -> String:
	if id.begins_with("@"):
		return nome_imp(id.substr(1))
	return carte[id]["nome"] if carte.has(id) else id


static func nome_pezzo(t: String) -> String:
	# t = "K:C" ecc.
	var p := t.split(":")
	var n: String = NOMI_PEZZO.get(p[0], p[0])
	if p.size() > 1 and NOMI_REL.has(p[1]):
		var rosso := "rossa" if p[0] == "R" else "rosso"
		return "%s %s" % [n, {"C": "d'oro", "I": "verde", "R": rosso}[p[1]]]
	return n


## «un cavaliere rosso», «una torre d'oro».
static func un_pezzo(t: String) -> String:
	return ("una " if t.begins_with("R:") else "un ") + nome_pezzo(t)
