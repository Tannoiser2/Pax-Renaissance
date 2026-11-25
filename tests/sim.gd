extends SceneTree
## Partite automatiche fra IA per verificare il motore: godot --headless --path . -s tests/sim.gd -- [partite] [giocatori] [livello]

func _init() -> void:
	_corri()


func _corri() -> void:
	var args := OS.get_cmdline_user_args()
	var partite := int(args[0]) if args.size() > 0 else 3
	var ng := int(args[1]) if args.size() > 1 else 3
	var lv := int(args[2]) if args.size() > 2 else 1
	PaxDB.carica()
	var vitt := {}
	var t0 := Time.get_ticks_msec()
	for g in partite:
		var eng := PaxEngine.new()
		var gg := []
		for i in ng:
			gg.append({"name": "IA %d" % (i + 1), "ai": true})
		eng.nuova(gg, 1000 + g, {})
		var ai := PaxAI.new(lv)
		eng.controller = ai
		var turni := 0
		while not eng.S["over"] and turni < 400:
			var tt := Time.get_ticks_msec()
			await eng.turno()
			turni += 1
			if OS.get_environment("PAX_VERBOSE") != "":
				print("turno ", turni, " ", Time.get_ticks_msec() - tt, " ms  ", eng.S["log"][-1] if not eng.S["log"].is_empty() else "")
		var m: String = eng.S["motivo"] if eng.S["over"] else "interrotta"
		vitt[m] = vitt.get(m, 0) + 1
		print("partita %d: %d turni, %s, vince %s, fiorini %s" % [g, turni, m, eng.pname(eng.S["vincitore"]),
			str(eng.S["players"].map(func(x): return x["fl"]))])
		for l in eng.S["log"].slice(maxi(0, eng.S["log"].size() - 6)):
			print("   ", l)
	print("risultati: ", vitt, " in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	quit()
