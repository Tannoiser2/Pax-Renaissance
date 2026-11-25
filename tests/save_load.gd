extends SceneTree
## Il salvataggio è il registro delle scelte: rigiocandolo con lo stesso seme si deve ritrovare la stessa partita.

class Rigioca:
	var mosse: Array
	var i := 0
	func decide(_e, _p, _r) -> int:
		i += 1
		return int(mosse[i - 1]) if i - 1 < mosse.size() else 0


class Smista:
	var ais := {}
	func decide(eng: PaxEngine, p: int, req: Dictionary) -> int:
		return await ais[p].decide(eng, p, req)


func _init() -> void:
	_corri()


func _corri() -> void:
	PaxDB.carica()
	var ok1 := await _prova([{"name": "A", "ai": true}, {"name": "B", "ai": true}, {"name": "C", "ai": true}], {})
	var ok2 := await _prova([{"name": "A", "ai": true}, {"name": "B", "ai": true}, {"name": "C", "ai": true}], {"promo": true, "banchieri_promo": true})
	var ok3 := await _prova([{"name": "A", "ai": true, "bank": "Fugger"}, {"name": "B", "ai": true}], {"solitario": true, "promo": true})
	quit(0 if ok1 and ok2 and ok3 else 1)


func _prova(gg: Array, opz: Dictionary) -> bool:
	var e := PaxEngine.new()
	e.nuova(gg, 4242, opz)
	var sm := Smista.new()
	for i in gg.size():
		sm.ais[i] = PaxSoloBot.new(2) if e.bot_solitario(i) else PaxAI.new(1)
	e.controller = sm
	for t in 15:
		if e.S["over"]:
			break
		await e.turno()
	var reg: Array = str_to_var(var_to_str(e.registro))
	var e2 := PaxEngine.new()
	e2.nuova(gg, 4242, opz)
	var r := Rigioca.new()
	r.mosse = reg
	e2.controller = r
	while r.i < reg.size() and not e2.S["over"]:
		await e2.turno()
	var a := var_to_str([e.S["players"], e.S["city"], e.S["bord"], e.S["mk"]])
	var b := var_to_str([e2.S["players"], e2.S["city"], e2.S["bord"], e2.S["mk"]])
	print("SALVATAGGIO ", opz, " ", "OK" if a == b else "DIVERSO", " (", reg.size(), " scelte)")
	return a == b
