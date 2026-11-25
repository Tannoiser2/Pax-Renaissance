extends SceneTree
## Partite automatiche fra IA per verificare il motore:
## godot --headless --path . -s tests/sim.gd -- [partite] [giocatori] [livello] [promo|solo|promo+solo]
## Con «solo» il posto 0 è un'IA nei panni del giocatore e il posto 1 è il bot del solitario ufficiale.


class Smista:
	var ais := {}
	func decide(eng: PaxEngine, p: int, req: Dictionary) -> int:
		return await ais[p].decide(eng, p, req)


func _init() -> void:
	_corri()


func _corri() -> void:
	var args := OS.get_cmdline_user_args()
	var partite := int(args[0]) if args.size() > 0 else 3
	var ng := int(args[1]) if args.size() > 1 else 3
	var lv := int(args[2]) if args.size() > 2 else 1
	var modo: String = args[3] if args.size() > 3 else ""
	var opz := {}
	if modo.contains("promo"):
		opz["promo"] = true
		opz["banchieri_promo"] = true
	if modo.contains("solo"):
		opz["solitario"] = true
		ng = 2
	PaxDB.carica()
	var vitt := {}
	var t0 := Time.get_ticks_msec()
	for g in partite:
		var eng := PaxEngine.new()
		var gg := []
		for i in ng:
			gg.append({"name": "IA %d" % (i + 1), "ai": true})
		eng.nuova(gg, 1000 + g, opz)
		var sm := Smista.new()
		for i in ng:
			sm.ais[i] = PaxSoloBot.new(2) if eng.bot_solitario(i) else PaxAI.new(lv)
		eng.controller = sm
		var turni := 0
		while not eng.S["over"] and turni < 400:
			var tt := Time.get_ticks_msec()
			await eng.turno()
			turni += 1
			if OS.get_environment("PAX_VERBOSE") != "":
				print("turno ", turni, " ", Time.get_ticks_msec() - tt, " ms  ", eng.S["log"][-1] if not eng.S["log"].is_empty() else "")
		var m: String = eng.S["motivo"] if eng.S["over"] else "interrotta"
		var chi := eng.pname(eng.S["vincitore"]) if eng.S["vincitore"] >= 0 else "-"
		if eng.S["vincitore"] >= 0 and eng.bot_solitario(eng.S["vincitore"]):
			chi += " [bot]"
		vitt[m] = vitt.get(m, 0) + 1
		print("partita %d: %d turni, %s, vince %s, fiorini %s" % [g, turni, m, chi,
			str(eng.S["players"].map(func(x): return x["fl"]))])
		for l in eng.S["log"].slice(maxi(0, eng.S["log"].size() - 6)):
			print("   ", l)
	print("risultati: ", vitt, " in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	quit()
