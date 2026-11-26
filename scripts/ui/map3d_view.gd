class_name Mappa3D
extends SubViewportContainer
## Tabellone in 3D: la mappa 2D (MappaView, senza pezzi) è disegnata in una texture stesa su un tavolo,
## i pezzi sono i modelli 3D del modulo TTS (torre, vescovo, cavaliere, pedina della banca, nave pirata).
## Mouse: trascina per spostare, tasto destro (o centrale) per ruotare e inclinare, rotella per lo zoom.
## Tocco: un dito sposta, due dita pizzicano per lo zoom e ruotano; trascinando in verticale con due dita
## si inclina la vista. Un tocco breve su una città o un confine la seleziona.

const SCALA := 0.01                 # 1 pixel della mappa = 1 cm
const ALT := 0.06                   # spessore del tabellone
const SCALA_PEZZI := 2.2
const LATO_Q := 300.0              # lato dei quadrati impero sul tavolo (pixel della mappa)
const STACCO_Q := 26.0             # distanza dei quadrati dal bordo del tabellone

var piatta: MappaView               # la mappa 2D da cui si leggono geometria, bersagli e descrizioni
var eng: PaxEngine:
	set(v):
		eng = v
		piatta.eng = v
		_firma = ""

var _vp: SubViewport
var _vp_tex: SubViewport
var cam: Camera3D
var _pezzi: Node3D
var _quadri: Node3D
var _mesh := {}
var _mat := {}
var _firma := ""
var _t_firma := 0.0

var target := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(58.0)
var dist := 19.0

var _tocchi := {}
var _press_pos := Vector2.ZERO
var _trascina := false
var _ruota := false
var _mouse_giu := false
var _pinch_d := 0.0
var _pinch_a := 0.0
var _pinch_c := Vector2.ZERO
var _hover := ""


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	# mappa piatta in una texture (dentro il viewport 3D, così non viene mostrata a schermo)
	_vp_tex = SubViewport.new()
	_vp_tex.size = Vector2i(int(MappaView.MW), int(MappaView.MH))
	_vp_tex.transparent_bg = false
	_vp_tex.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.add_child(_vp_tex)
	piatta = MappaView.new()
	piatta.solo_tavola = true
	piatta.position = Vector2.ZERO
	piatta.size = Vector2(MappaView.MW, MappaView.MH)
	_vp_tex.add_child(piatta)
	_scena()


func _ready() -> void:
	resized.connect(_camera)
	_camera()


func _scena() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.04, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.56, 0.5)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.92
	env.environment = e
	_vp.add_child(env)
	# luce morbida, calda, che non brucia i bianchi della mappa
	var sole := DirectionalLight3D.new()
	sole.light_color = Color(1.0, 0.94, 0.85)
	sole.light_energy = 0.78
	sole.shadow_enabled = true
	sole.shadow_blur = 1.5
	sole.shadow_opacity = 0.55
	sole.directional_shadow_max_distance = 40.0
	sole.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-30), 0)
	_vp.add_child(sole)
	var w := MappaView.MW * SCALA
	var h := MappaView.MH * SCALA
	var centro := Vector3(w / 2, 0, h / 2)
	target = centro
	# tavolo di noce
	var tavolo := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 3.2, h * 3.4)
	tavolo.mesh = pm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.2, 0.12, 0.07)
	mt.roughness = 0.75
	tavolo.material_override = mt
	tavolo.position = centro + Vector3(0, -0.001, 0)
	_vp.add_child(tavolo)
	# bordo del tabellone
	var bordo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w + 0.16, ALT, h + 0.16)
	bordo.mesh = bm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(0.1, 0.07, 0.05)
	mb.roughness = 0.6
	bordo.material_override = mb
	bordo.position = centro + Vector3(0, ALT / 2 - 0.002, 0)
	_vp.add_child(bordo)
	# piano della mappa con la texture
	var piano := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(w, h)
	piano.mesh = pp
	var mp := StandardMaterial3D.new()
	mp.albedo_texture = _vp_tex.get_texture()
	mp.roughness = 0.9
	mp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	piano.material_override = mp
	piano.position = centro + Vector3(0, ALT + 0.001, 0)
	piano.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(piano)
	_pezzi = Node3D.new()
	_vp.add_child(_pezzi)
	_quadri = Node3D.new()
	_vp.add_child(_quadri)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 200.0
	_vp.add_child(cam)
	for k in ["R", "B", "K", "P", "S"]:
		_mesh[k] = load("res://assets/modelli/%s.obj" % k)


func _process(delta: float) -> void:
	if eng == null or eng.S.is_empty():
		return
	_t_firma += delta
	if _t_firma < 0.15:
		return
	_t_firma = 0.0
	var f := str(eng.S["city"]) + str(eng.S["bord"]) + str(eng.S["emp"]) + str(eng.S["players"].size()) + str(piatta.evidenzia.keys()) + _hover
	if f != _firma:
		_firma = f
		_ricostruisci()


func queue_redraw_tutto() -> void:
	piatta.queue_redraw()
	_firma = ""

# ----------------------------------------------------------------------- pezzi

func _materiale(col: Color) -> StandardMaterial3D:
	var k := col.to_html()
	if not _mat.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.45
		m.metallic = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_mat[k] = m
	return _mat[k]


func a_mondo(m: Vector2) -> Vector3:
	return Vector3(m.x * SCALA, ALT, m.y * SCALA)


func _pezzo(tipo: String, col: Color, m: Vector2, rot: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh[tipo]
	mi.material_override = _materiale(col)
	mi.position = a_mondo(m)
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * SCALA_PEZZI
	_pezzi.add_child(mi)


## Rettangolo (in pixel della mappa, anche fuori dal tabellone) del quadrato impero sul tavolo: la fila del
## nord sta sopra il tabellone, quella del sud sotto, ognuno in colonna con la sua regione (come nel modulo TTS).
func rett_quadrato(e: String) -> Rect2:
	var r := piatta.slot_rect(e)
	var cx := r.position.x + r.size.x / 2
	var y := -STACCO_Q - LATO_Q if r.position.y < MappaView.MH / 2 else MappaView.MH + STACCO_Q
	return Rect2(cx - LATO_Q / 2, y, LATO_Q, LATO_Q)


func _quadrati() -> void:
	for c in _quadri.get_children():
		c.queue_free()
	var S := eng.S
	for e in PaxDB.ordine_imperi:
		var em: Dictionary = S["emp"][e]
		var r := rett_quadrato(e)
		var centro := a_mondo(r.get_center())
		centro.y = 0.0
		# cornice: colore della banca che lo possiede, altrimenti legno scuro; oro se evidenziato o indicato
		var col := Color(0.12, 0.08, 0.05)
		if em["own"] >= 0:
			col = Stile.COLORI_BANCA.get(S["players"][em["own"]]["bank"], col)
		if piatta.evidenzia.has("emp:" + e) or _hover == "emp:" + e:
			col = Color(1.0, 0.84, 0.3)
		var bordo := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x * SCALA + 0.16, 0.05, r.size.y * SCALA + 0.16)
		bordo.mesh = bm
		bordo.material_override = _materiale(col)
		bordo.position = centro + Vector3(0, 0.025, 0)
		_quadri.add_child(bordo)
		var piano := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(r.size.x * SCALA, r.size.y * SCALA)
		piano.mesh = pm
		var nome: String = e
		if e == "Ottoman" and PaxDB.promo_attiva:
			nome = "OttomanP"
		var tx := CartaView.texture("res://assets/imperi/%s_%s.webp" % [nome, em["side"]])
		var m := StandardMaterial3D.new()
		m.albedo_texture = tx
		m.roughness = 0.95
		m.metallic_specular = 0.2
		# toni un po' smorzati (il giallo dei quadrati brucia sotto la luce); un vassallo è più scuro
		m.albedo_color = Color(0.86, 0.84, 0.8) if em["suz"] == "" else Color(0.62, 0.6, 0.58)
		piano.material_override = m
		piano.position = centro + Vector3(0, 0.052, 0)
		piano.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_quadri.add_child(piano)


func _ricostruisci() -> void:
	_quadrati()
	for c in _pezzi.get_children():
		c.queue_free()
	var S := eng.S
	for e in PaxDB.ordine_imperi:
		for j in S["city"][e].size():
			var t: String = S["city"][e][j]
			if t == "":
				continue
			var p := piatta.pos_citta(e, j)
			_pezzo(t[0], Stile.COLORI_REL[t[2]], p, float((hash(e) + j * 37) % 628) / 100.0)
	for k in S["bord"]:
		var b: Dictionary = S["bord"][k]
		var c := piatta.pos_confine(k)
		var ang := float(hash(k) % 628) / 100.0
		if b["p"] >= 0:
			var col: Color = Stile.COLORI_BANCA.get(S["players"][b["p"]]["bank"], Color.WHITE)
			_pezzo("P", col, c + (Vector2(-18, 0) if b["s"] != "" else Vector2.ZERO), ang)
		if b["s"] != "":
			_pezzo("S", Stile.COLORI_REL[b["s"]], c + (Vector2(24, 6) if b["p"] >= 0 else Vector2.ZERO), ang)

# ----------------------------------------------------------------------- camera

func _camera() -> void:
	pitch = clampf(pitch, deg_to_rad(22.0), deg_to_rad(89.0))
	dist = clampf(dist, 2.2, 26.0)
	var w := MappaView.MW * SCALA
	var h := MappaView.MH * SCALA
	target.x = clampf(target.x, 0.0, w)
	target.z = clampf(target.z, -(LATO_Q + STACCO_Q) * SCALA, h + (LATO_Q + STACCO_Q) * SCALA)
	target.y = ALT
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)


## Vista iniziale: tutto il tabellone, un po' inclinato.
func reimposta() -> void:
	target = Vector3(MappaView.MW * SCALA / 2, ALT, MappaView.MH * SCALA / 2 + 0.2)
	yaw = 0.0
	pitch = deg_to_rad(58.0)
	pitch = deg_to_rad(62.0)
	# distanza che fa stare tutto il tabellone nell'inquadratura (col bordo anteriore più vicino)
	var asp := size.x / maxf(size.y, 1.0)
	var tv := tan(deg_to_rad(cam.fov / 2))
	var th := tv * asp
	var prof := (MappaView.MH + 2 * (LATO_Q + STACCO_Q)) * SCALA
	dist = maxf(MappaView.MW * SCALA / 2 / th, prof / 2 / tv) * 1.12
	_camera()


## Punto del tabellone (coordinate della mappa) sotto un punto dello schermo, o null.
func a_mappa(s: Vector2) -> Variant:
	var o := cam.project_ray_origin(s)
	var d := cam.project_ray_normal(s)
	if absf(d.y) < 1e-5:
		return null
	var t := (ALT - o.y) / d.y
	if t < 0:
		return null
	var p := o + d * t
	return Vector2(p.x / SCALA, p.z / SCALA)


func _sposta(da: Vector2, a: Vector2) -> void:
	var p0: Variant = a_mappa(da)
	var p1: Variant = a_mappa(a)
	if p0 == null or p1 == null:
		return
	var dd: Vector2 = (p0 - p1) * SCALA
	target += Vector3(dd.x, 0, dd.y)
	_camera()


func _zooma(f: float) -> void:
	dist /= f
	_camera()

# ----------------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zooma(1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zooma(1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_giu = true
				_trascina = false
				_press_pos = mb.position
			else:
				if _mouse_giu and not _trascina:
					_clic(mb.position)
				_mouse_giu = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_ruota = mb.pressed
		accept_event()
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		var mm := ev as InputEventMouseMotion
		if _ruota:
			yaw -= mm.relative.x * 0.008
			pitch += mm.relative.y * 0.006
			_camera()
		elif _mouse_giu and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _trascina or mm.position.distance_to(_press_pos) > 8:
				_trascina = true
				_sposta(mm.position - mm.relative, mm.position)
		else:
			_aggiorna_hover(mm.position)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_tocchi[st.index] = st.position
			if _tocchi.size() == 1:
				_press_pos = st.position
				_trascina = false
			elif _tocchi.size() == 2:
				_trascina = true
				_inizia_pinch()
		else:
			if _tocchi.size() == 1 and not _trascina and st.position.distance_to(_press_pos) < 14:
				_clic(st.position)
			_tocchi.erase(st.index)
			if _tocchi.size() == 1:
				_trascina = true
		accept_event()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		var prima: Vector2 = _tocchi.get(sd.index, sd.position)
		_tocchi[sd.index] = sd.position
		if _tocchi.size() == 1:
			if _trascina or sd.position.distance_to(_press_pos) > 12:
				_trascina = true
				_sposta(prima, sd.position)
		elif _tocchi.size() >= 2:
			var v: Array = _tocchi.values()
			var a: Vector2 = v[0]
			var b: Vector2 = v[1]
			var d := a.distance_to(b)
			var ang := (b - a).angle()
			var c := (a + b) / 2
			if _pinch_d > 0:
				_zooma(d / _pinch_d)
				yaw += wrapf(ang - _pinch_a, -PI, PI)
				pitch += (c.y - _pinch_c.y) * 0.006
				_camera()
			_pinch_d = d
			_pinch_a = ang
			_pinch_c = c
		accept_event()
	elif ev is InputEventMagnifyGesture:
		_zooma((ev as InputEventMagnifyGesture).factor)
		accept_event()
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		var c := size / 2
		_sposta(c, c - pg.delta * 8)
		accept_event()


func _inizia_pinch() -> void:
	var v: Array = _tocchi.values()
	var a: Vector2 = v[0]
	var b: Vector2 = v[1]
	_pinch_d = a.distance_to(b)
	_pinch_a = (b - a).angle()
	_pinch_c = (a + b) / 2


func _aggiorna_hover(pos: Vector2) -> void:
	var m: Variant = a_mappa(pos)
	var h := "" if m == null else _bersaglio(m)
	if h != _hover:
		_hover = h
		piatta._hover = h
		piatta.info.emit(piatta.descrivi(h))
		piatta.queue_redraw()


func _bersaglio(m: Vector2) -> String:
	for e in PaxDB.ordine_imperi:
		if rett_quadrato(e).has_point(m):
			return "emp:" + e
	return piatta.bersaglio(m)


func _clic(pos: Vector2) -> void:
	var m: Variant = a_mappa(pos)
	if m == null:
		return
	var k := _bersaglio(m)
	if k != "":
		piatta.info.emit(piatta.descrivi(k))
		piatta.cliccato.emit(k)
