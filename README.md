# Pax Renaissance — versione digitale

Versione digitale di **Pax Renaissance, seconda edizione** (Phil e Matt Eklund, Ion Game Design) per la ludoteca:
banchieri del Rinascimento (1460-1530) che finanziano re e repubbliche, viaggi di scoperta, congiure, crociate,
jihad e inquisizioni. Si gioca su https://tannoiser2.github.io/Pax-Renaissance/

## Cosa c'è

- **Regole complete della 2ª edizione**: mercato d'Oriente e d'Occidente con speculazione e usura, mano di 2 carte,
  le 9 operazioni (commercio, decapita, tassa, reprimi, voto, corsaro, assedio, campagna, inquisitore), fiere
  commerciali con profitti, pirati e leve, tutti gli eventi (spostamento commerciale, incoronazione e zitelle,
  complotto, rivolta contadina, crociata, jihad, riforma, apostasia), battaglie, cambi di regime con concessione ed
  emancipazione, uomo di paglia e repubbliche, vassalli, vescovi e silenziamento, Dieta di Worms e pacificazione,
  teocrazie e libertà dorata, condottieri a Venezia, comete e le quattro vittorie più quella dei mecenati.
- **Tutte le abilità delle carte**: stampa e partita doppia (mano illimitata), sincretismo, riscatto, fortificazioni,
  galee veneziane, spie di Gritti, Capo di Buona Speranza, fama del mecenate, cifrari medicei, machiavellismo,
  controriforma, Enrico VIII, stato cuscinetto, i testi rossi che rendono più care le vittorie, e le altre.
- **168 carte tradotte in italiano con la grafica originale**: nomi, testi storici, operazioni e loro sottotitoli,
  luoghi, eventi, pretendenti, abilità (`tools/localizza_carte.py`). Anche il tabellone e le 40 carte mappa
  hanno i nomi in italiano (`tools/localizza_mappa.py`).
- **IA** a tre livelli: per ogni azione prova le alternative su una copia della partita e valuta la posizione
  (vittorie attive, imperi, concessioni, prestigio, fiorini, carte). L'IA forte guarda anche la seconda azione
  del turno; i fiorini accumulati valgono sempre meno, così l'IA spende e punta alle vittorie.
- **Solitario ufficiale** (Libro II, parte O): avversario automatico che segue la tabella O8 (linee d'azione,
  sostituzione cometaria, obiettivi principale/secondario/di prestigio) e le regole O5 (`scripts/core/solo_bot.gd`).
- **Promo «Età della Riforma»** (variante 1550): 8 carte di mercato tradotte, carte mappa della Confederazione
  polacco-lituana e della Rumelia, quadrato bizantino, banchieri Alvaro Mendes e Cornelius Berenberg, vittoria bizantina.
- **Più persone sullo stesso dispositivo** (con il passaggio di mano), **online** con gli amici e **salvataggi**.
- **Tabellone in 3D** (pulsante «Vista 2D/3D», la scelta resta memorizzata): la mappa è stesa su un tavolo e i pezzi
  sono i modelli 3D del modulo TTS (`assets/modelli`, `scripts/ui/map3d_view.gd`). Mouse: trascina per spostare,
  tasto destro per ruotare e inclinare, rotella per lo zoom. iPad: un dito sposta, due dita pizzicano e ruotano,
  trascinando in verticale con due dita si inclina la vista.
- Vista 2D con zoom e spostamento: rotella e trascinamento col mouse, un dito per spostare e due dita per lo zoom su iPad.

## Online e salvataggi (Firebase)

Usa il progetto Firebase comune della ludoteca con la struttura «stanze con mosse», già coperta dalla regola comune:

- `paxrenaissance/rooms/<CODICE di 4>`: la stanza; la partita è il registro delle scelte (`acts/0`, `acts/1`, …).
  Tutti i dispositivi applicano le stesse scelte con lo stesso seme. I posti dell'IA li gioca chi ha creato la
  stanza; chi tace per un minuto viene sostituito dall'IA finché non rientra.
- `paxrenaissance/partite/<CODICE di 6>`: le partite salvate con «Salva» (configurazione e registro delle scelte).

## Struttura

```
data/carte.json, data/mappa.json   dati del gioco (generati da tools/genera_dati.py)
scripts/core/engine.gd             motore delle regole (stato serializzabile, decisioni con ask())
scripts/core/ai.gd                 intelligenza artificiale
scripts/ui/                        menu, tavolo di gioco, mappa, carte, regole
scripts/net/                       Firebase e partita online in lockstep
assets/                            carte tradotte, mappa, quadrati impero, pedine (rese dai modelli 3D del modulo), font
tools/                             script per dati e grafica (non entrano nel gioco)
tests/                             prove automatiche
```

## Prove

```
godot --headless --path . -s tests/sim.gd -- 10 4 2        # 10 partite fra IA, 4 giocatori, livello forte
godot --headless --path . -s tests/sim.gd -- 8 2 1 promo+solo   # solitario con la promo (anche: promo, solo)
godot --headless --path . -s tests/save_load.gd            # il salvataggio ricostruisce la stessa partita
python3 tests/firebase_mock.py 8765 & ...                  # due istanze online sul finto Firebase (tests/online_play.gd,
                                                           # RT_DB_URL=…/db RT_AUTH_URL=…/signup e RT_SESSION diversi)
xvfb-run godot --path . -s tests/shot.gd -- /tmp/foto 3 1920 1080 10   # fotografie dell'interfaccia
python3 tools/controlla_glifi.py                           # nessun carattere mancante nei font
```

## Pubblicazione

Il workflow **Pubblica** (`.github/workflows/pages.yml`) costruisce la versione web con Godot 4.7 e la mette su
GitHub Pages. Non parte a ogni modifica: si avvia a mano (Actions → Pubblica → Run workflow) oppure con un commit
che nel messaggio contiene `[pubblica]`. La cartella `ludoteca/` presenta il gioco nella ludoteca.

Materiale grafico dal modulo ufficiale di Tabletop Simulator; font Almendra, EB Garamond, Roboto Condensed,
UnifrakturMaguntia e IM Fell (licenza OFL).
