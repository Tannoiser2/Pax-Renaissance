extends SceneTree
## Fotografie dell'interfaccia (serve un display, anche virtuale: xvfb-run).
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- <cartella> [giocatori] [larghezza] [altezza] [turni]
## La persona (posto 1) lascia decidere all'IA; si fotografano le scelte la prima volta che compaiono.

var out := "/tmp/shots"
var prese := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var np := int(args[1]) if args.size() > 1 else 3
	var w := int(args[2]) if args.size() > 2 else 1920
	var h := int(args[3]) if args.size() > 3 else 1080
	var turni := int(args[4]) if args.size() > 4 else 12
	DirAccess.make_dir_recursive_absolute(out)
	_run(np, w, h, turni)


func _snap(nome: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nome])
	print("foto ", nome)


func _run(np: int, w: int, h: int, turni: int) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.8).timeout
	await _snap("menu")
	main.current._pannello_nuova()
	await _snap("nuova")
	main.current.n_gioc = 1
	main.current._righe()
	await _snap("nuova_solitario")
	main.current.n_gioc = 3
	main.current._pannello_online()
	await _snap("online")
	main.current._regole()
	await _snap("regole")
	var gg := [{"name": "Stefano", "ai": false}]
	var nomi := ["Lorenzo", "Jakob", "Jacques"]
	for i in range(1, np):
		gg.append({"name": nomi[i - 1], "ai": true, "livello": 2})
	var modo := OS.get_environment("PAX_OPZ")
	var opz := {"banche_casuali": true}
	if modo.contains("promo"):
		opz["promo"] = true
		opz["banchieri_promo"] = true
	if modo.contains("solo"):
		opz["solitario"] = true
		gg = [{"name": "Stefano", "ai": false, "bank": "Fugger"}, {"name": "", "ai": true}]
	main.start_game({"giocatori": gg, "seme": 11, "opzioni": opz})
	var g = main.current
	await process_frame
	g.eng.ai_delay = 0.0
	var n := 0
	while g.eng.S["turno"] <= turni and not g.eng.S["over"]:
		await process_frame
		if g._attesa:
			var tipo: String = g._req["tipo"]
			if not prese.has(tipo):
				prese[tipo] = true
				await _snap("%02d_%s" % [prese.size(), tipo])
			var r: int = await g.eng.ais[0].decide(g.eng, 0, g._req)
			g._scegli(r)
			n += 1
	await _snap("finale")
	# ingrandimento di una carta
	var cv := CartaView.new()
	cv.id = "PREN058".replace("PREN058", g.eng.S["mk"]["W"][2]["c"])
	g._zoom_carta(cv)
	await _snap("zoom")
	quit()
