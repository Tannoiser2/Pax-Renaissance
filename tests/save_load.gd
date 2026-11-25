extends SceneTree
## Il salvataggio è il registro delle scelte: rigiocandolo con lo stesso seme si deve ritrovare la stessa partita.

class Rigioca:
	var mosse: Array
	var i := 0
	func decide(_e, _p, _r) -> int:
		i += 1
		return int(mosse[i - 1]) if i - 1 < mosse.size() else 0


func _init() -> void:
	_corri()


func _corri() -> void:
	PaxDB.carica()
	var gg := [{"name": "A", "ai": true}, {"name": "B", "ai": true}, {"name": "C", "ai": true}]
	var e := PaxEngine.new()
	e.nuova(gg, 4242, {})
	e.controller = PaxAI.new(1)
	for t in 15:
		if e.S["over"]:
			break
		await e.turno()
	var reg: Array = str_to_var(var_to_str(e.registro))
	var e2 := PaxEngine.new()
	e2.nuova(gg, 4242, {})
	var r := Rigioca.new()
	r.mosse = reg
	e2.controller = r
	while r.i < reg.size() and not e2.S["over"]:
		await e2.turno()
	var a := var_to_str([e.S["players"], e.S["city"], e.S["bord"], e.S["mk"]])
	var b := var_to_str([e2.S["players"], e2.S["city"], e2.S["bord"], e2.S["mk"]])
	print("SALVATAGGIO ", "OK" if a == b else "DIVERSO", " (", reg.size(), " scelte)")
	quit(0 if a == b else 1)
