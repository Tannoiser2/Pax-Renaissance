extends SceneTree
## Prova del gioco online: due istanze (chi crea la stanza e un amico; il terzo posto lo gioca l'IA
## dell'host) giocano una partita sul finto Firebase (tests/firebase_mock.py), con le decisioni delle
## persone prese dall'IA. PAX_ROLE=host|guest, PAX_CODEFILE=file per il codice della stanza.
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0
var ai := PaxAI.new(1)


func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("PAX_ROLE")
	var cf := OS.get_environment("PAX_CODEFILE")
	var menu = main.current
	menu.n_gioc = 3
	menu.tipi = [0, 0, 2, 2]
	menu._pannello_online()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await menu._crea()
		var code: String = main.lobby.get("code", "")
		print("PAXTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._avvia_online()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._entra()
	var limite := int(OS.get_environment("PAX_TURNI")) if OS.get_environment("PAX_TURNI") != "" else 10
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 900000:
			print("PAXTEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("eng" in view) or view.eng == null or view.eng.S.is_empty():
			continue
		var e: PaxEngine = view.eng
		e.ai_delay = 0.0
		if view._attesa and not view._req.is_empty():
			var r: int = await ai.decide(e, view._req["p"], view._req)
			view._scegli(r)
		if e.S["over"] or e.S["turno"] > limite:
			await _wait(1.0)
			var impronta := str(hash(var_to_str(e.S["players"]) + var_to_str(e.S["city"]) + var_to_str(e.S["bord"])))
			print("PAXTEST impronta turno ", e.S["turno"], " mosse ", view.online.n, " | ", impronta)
			quit(0)
			return
