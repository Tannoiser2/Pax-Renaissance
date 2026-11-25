extends Control
## Le regole in breve (2ª edizione), in italiano.

var sovrapposto := false

const TESTO := """[b]Lo scopo[/b]
Sei un banchiere del Rinascimento (1460-1530): finanzi re e repubbliche, viaggi di scoperta, congiure, jihad e inquisizioni. Quattro vittorie decidono il futuro dell'Occidente: [b]imperiale[/b], [b]della globalizzazione[/b], [b]santa[/b] e [b]del Rinascimento[/b]. All'inizio sono tutte inattive: si attivano quando qualcuno compra una delle quattro [b]comete[/b], mescolate in fondo ai mazzi d'Oriente e d'Occidente.

[b]Il turno[/b]
Fai 1 o 2 azioni, poi il mercato si rifornisce. Comprare, giocare e vendere si possono fare due volte; le altre azioni una volta per turno.
• [b]Compra[/b] una carta scoperta del mercato: il costo è la sua posizione (1, 2, 3, 4 o 5 fiorini). Metti 1 fiorino su ogni carta alla sua sinistra nella stessa fila e prendi i fiorini che c'erano sulla carta comprata (speculazione). Non puoi comprare una carta su cui hai appena messo un fiorino. In mano tieni al massimo 2 carte.
• [b]Gioca[/b] una carta dalla mano nel tuo tableau: le carte d'Occidente (nastro bianco) a sinistra della tua plancia, quelle d'Oriente (nastro nero) a destra. Puoi piazzare i suoi [b]agenti[/b] nel suo luogo: cavalieri e torri nelle città (se la città è occupata paghi 1 fiorino per reprimere il pezzo che c'era), pedoni come concessioni sui confini (reprimere una concessione costa 1 fiorino), pirati sui confini marittimi (affondano quello che trovano), vescovi su una carta o un trono dello stesso luogo.
• [b]Evento (one-shot)[/b]: se la carta ha la bomba puoi scatenarne l'evento; in quel caso gli agenti vanno piazzati per forza.
• [b]Vendi[/b] una carta (dalla mano, dal tableau o una zitella) per 2 fiorini.
• [b]Operazioni d'Oriente / d'Occidente[/b]: ogni carta di quel lato del tableau può usare una delle sue operazioni.
• [b]Fiera commerciale d'Oriente / d'Occidente[/b]: scarta la carta coperta in testa alla fila del mercato.
• [b]Dichiara la vittoria[/b], se una vittoria attiva ha le sue condizioni soddisfatte.

[b]Le operazioni[/b]
• [b]Commercio[/b]: prendi 1 fiorino da una carta della fila indicata del mercato.
• [b]Decapita[/b]: scarta una carta di qualsiasi tableau con lo stesso luogo (mai sé stessa). Se decapiti un impero, torna nel suo trono e la carta che ha decapitato muore.
• [b]Tassa[/b]: colpisce una concessione sui confini dell'impero: il proprietario paga 1 fiorino o la lascia reprimere, poi piazza una leva in una città vuota dell'impero.
• [b]Reprimi[/b]: togli dalla mappa un pezzo del tipo indicato nel luogo della carta e mettilo sul quadrato dell'impero come represso (un pedone diventa servo). Guadagni 1 fiorino.
• [b]Voto[/b]: se hai più concessioni di tutti sui confini di un impero che sta in un tableau (d'Oriente o d'Occidente come indicato), paghi 1 fiorino per ogni represso e provochi un cambio di regime. Su un tuo impero il voto gira re e repubblica. In una teocrazia puoi applicare la [i]libertà dorata[/i] e renderla medievale.
• [b]Corsaro[/b]: sposta un pirata del colore indicato verso un altro confine marittimo dello stesso impero o di uno vicino per mare; affonda quello che trova.
• [b]Assedio[/b]: uccidi una torre, un cavaliere o un pirata nel luogo della carta.
• [b]Campagna[/b] (solo sui re): tutti i cavalieri dell'impero attaccano un impero adiacente (anche in diagonale) che non è tuo; paghi 1 fiorino per cavaliere. Se vinci, l'impero diventa tuo vassallo.
• [b]Inquisitore[/b]: sposta un vescovo del colore indicato su una carta adiacente dello stesso tableau o su qualsiasi carta o trono con lo stesso luogo. Due vescovi sulla stessa carta si eliminano (Dieta di Worms); un vescovo che arriva su un impero con repressi può eliminarne uno. Un vescovo [b]silenzia[/b] la carta: restano solo le operazioni di inquisitore, niente abilità.

[b]Fiere commerciali[/b]
Ai fiorini della carta scartata se ne aggiungono 1 (in 2 giocatori) o 2 (in 3-4 giocatori): sono i profitti. Chi convoca la fiera ne prende 1, poi il viaggio segue la rotta (bianca d'Occidente o nera d'Oriente) dall'emporio aperto: ogni concessione sui confini attraversati prende 1 fiorino, ogni pirata ne manda 1 in Cina. Quando i profitti finiscono il viaggio si ferma. Ogni impero raggiunto riceve una [b]leva[/b] in una città vuota, del tipo e colore disegnati sulla città.

[b]Gli eventi[/b]
• [b]Spostamento commerciale[/b]: sposta il disco che chiude l'emporio indicato sull'emporio aperto dello stesso colore: la rotta cambia partenza. Verso le Isole delle Spezie serve già un prestigio di scoperta nel tableau.
• [b]Incoronazione[/b] (regine): la regina sposa un re ancora libero fra i suoi pretendenti, nel trono o nel tuo tableau: prendi l'impero. Altrimenti la giochi come [i]zitella[/i] sotto la plancia (conta solo il suo prestigio).
• [b]Complotto[/b]: attaccano gli agenti della carta, i pirati sui confini e le torri e i cavalieri repressi dell'impero, contro tutta la classe dominante.
• [b]Rivolta contadina[/b]: attaccano gli agenti, le tue concessioni sui confini, i pirati e i servi (pedoni repressi).
• [b]Crociata, jihad, riforma[/b]: i credenti (agenti, pirati, classe dominante del colore e cavalieri del colore negli imperi adiacenti) contro gli eretici; serve almeno un eretico. Se vinci l'impero diventa una teocrazia di quella religione.
• [b]Apostasia[/b]: chi ha nel tableau prestigio di entrambe le religioni indicate scarta tutte quelle carte.
In battaglia ogni attaccante elimina un difensore e muore con lui; chi attacca sceglie le perdite e vince se resta almeno un attaccante.

[b]Cambio di regime[/b]
Incoronazione, voto, guerre civili e di religione vittoriose: prendi il quadrato dell'impero (dal trono o da un avversario) sul lato del re, puoi aprire una concessione sui suoi confini ed emancipare i repressi. Attaccare un tuo impero (uomo di paglia) lo trasforma in [b]repubblica[/b].

[b]Le vittorie[/b]
• [b]Imperiale[/b] (Carlo V): almeno 2 re in più di ogni avversario (3 in due giocatori), vassalli compresi.
• [b]Della globalizzazione[/b] (Colombo): almeno 2 concessioni più di ogni avversario e più prestigio di scoperta di ognuno.
• [b]Del Rinascimento[/b] (Leonardo): più repubbliche di ogni avversario e almeno 2 prestigi di legge più di ognuno.
• [b]Santa[/b] (Torquemada): una religione è suprema se ha più vescovi in gioco delle altre due insieme e più pezzi del suo colore nelle sue teocrazie delle altre due insieme (i pirati contano per le teocrazie che toccano). Vince chi ha più prestigio di quella religione di ogni avversario.
• Se i mazzi finiscono vince chi ha più prestigio di [b]mecenate[/b] (a parità, più fiorini).

[b]In questa versione digitale[/b]
Tocca le carte e la mappa evidenziate per scegliere, oppure usa i pulsanti a destra. Tasto destro o tocco lungo su una carta per ingrandirla con il testo completo. Rotella, pizzico a due dita o trascinamento per muovere la mappa.
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vel := ColorRect.new()
	vel.color = Color(0, 0, 0, 0.75)
	vel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vel)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 60)
	add_child(m)
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", Stile.box(Color(0.93, 0.88, 0.76), Stile.ORO, 4, 10, 30))
	m.add_child(pan)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pan.add_child(vb)
	var h := HBoxContainer.new()
	vb.add_child(h)
	var t := Stile.etichetta("Regole in breve", 44, "gotico", Stile.INCHIOSTRO)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var b := Button.new()
	b.text = "Chiudi"
	b.custom_minimum_size = Vector2(180, 52)
	b.pressed.connect(queue_free)
	h.add_child(b)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", Stile.font("testo"))
	rt.add_theme_font_override("bold_font", Stile.font("titolo"))
	rt.add_theme_font_override("italics_font", Stile.font("corsivo"))
	rt.add_theme_font_size_override("normal_font_size", 24)
	rt.add_theme_font_size_override("bold_font_size", 24)
	rt.add_theme_font_size_override("italics_font_size", 24)
	rt.add_theme_color_override("default_color", Stile.INCHIOSTRO)
	rt.text = TESTO
	vb.add_child(rt)
