#!/usr/bin/env python3
"""Genera data/carte.json e data/mappa.json dai dati trascritti dal modulo TTS.

Uso: python3 tools/genera_dati.py
- tools/carte_raw.txt: le 164 carte di mercato, una per riga (formato descritto in testa al file)
- le comete, la mappa, gli imperi e le rotte sono scritti qui sotto.
"""
import json, os

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

ABILITA = {
    # chiave interna -> parole che la riconoscono nel testo italiano
    'sincretismo': ['SINCRETISMO', 'COLLEGIUM TRILINGUE'],
    'est_ovest': ['SPIE DI GRITTI', "LEONE L'AFRICANO"],
    'immuni_pirati': ['IMMUNITÀ MARITTIMA', 'ARSENALE IMPERIALE'],
    'eta_oro_mamelucca': ["ETÀ DELL'ORO MAMELUCCA"],
    'soldati_schiavi': ['SOLDATI SCHIAVI'],
    'banchieri_ebrei': ['BANCHIERI EBREI'],
    'protezione_solimano': ['PROTEZIONE DI SOLIMANO'],
    'genocidio': ['GENOCIDIO'],
    'olocausto': ['OLOCAUSTO'],
    'riscatto': ['RISCATTO', 'ORO AZTECO'],
    'rappresaglie': ['RAPPRESAGLIE POPOLARI'],
    'fortificazioni': ['FORTIFICAZIONI'],
    'navigazione': ['NAVIGAZIONE ASTRONOMICA', 'CARTOGRAFIA'],
    'conta_repubblica': ['UNIVERSITÀ LAICA', 'DE RERUM NATURA'],
    'immune_apostasia': ['LA RELIGIONE COME ILLUSIONE'],
    'condottiero': ['CONDOTTIERO'],
    'mano_illimitata': ['PARTITA DOPPIA', 'STAMPA', 'STADTWECHSEL'],
    'mecenati_legge': ['UMANESIMO TEDESCO', 'RINASCIMENTO TEDESCO', 'IDEALI REPUBBLICANI'],
    'stato_cuscinetto': ['STATO CUSCINETTO'],
    'enrico_viii': ['ENRICO VIII'],
    'recinzioni': ["FINE DELL'AGRICOLTURA"],
    'galee_venezia': ['COMANDANTE DELLE GALEE'],
    'controriforma': ['CONTRORIFORMA'],
    'cifrari_medici': ['CIFRARI MEDICEI'],
    'fama_mecenate': ['FAMA DEL MECENATE'],
    'tradimento': ['TRADIMENTO PRAGMATICO'],
    'cavalieri_rodi': ['CAVALIERI DI RODI'],
    'buona_speranza': ['CAPO DI BUONA SPERANZA'],
    'borsa_londra': ['BORSA REALE DI LONDRA'],
}
ROSSE = {  # testo rosso: vale per tutti i giocatori
    'globalizzazione': 'vittoria della globalizzazione costa 2 azioni',
    'imperiale': 'vittoria imperiale costa 2 azioni',
    'santa': 'vittoria santa costa 2 azioni',
}


def carte():
    out = []
    for riga in open(os.path.join(R, 'tools', 'carte_raw.txt'), encoding='utf-8'):
        riga = riga.rstrip('\n')
        if not riga.startswith('PREN'):
            continue
        p = riga.split('|')
        assert len(p) == 12, (len(p), riga[:60])
        cid, foglio, mazzo, nen, nit, luogo, prest, ops, oneshot, agenti, abil, testo = p
        c = {'id': cid, 'img': foglio, 'mazzo': mazzo, 'nome_en': nen, 'nome': nit, 'luogo': luogo,
             'promo': cid.endswith(('P', 'PW', 'PE')),
             'prestigio': list(prest), 'ops': [], 'sottotitoli': [], 'pretendenti': [],
             'oneshot': '', 'oneshot_arg': '', 'agenti': [], 'abilita': [], 'rosse': [],
             'testo_abilita': abil.replace('\\n', '\n').lstrip('!'), 'testo': testo.replace('\\n', '\n')}
        for o in [x for x in ops.split(';') if x]:
            if o.startswith('suitors:'):
                c['pretendenti'] = o[8:].split(',')
                continue
            op, _, sub = o.partition('~')
            c['ops'].append(op)
            c['sottotitoli'].append(sub)
        if oneshot:
            k, _, arg = oneshot.partition(':')
            c['oneshot'] = k
            c['oneshot_arg'] = arg
        if agenti:
            c['agenti'] = agenti.split(',')
        if c['pretendenti']:
            c['regina'] = True
        # abilità: righe separate da \n; quelle che iniziano con ! sono «testo rosso»
        for parte in abil.split('\\n'):
            if not parte:
                continue
            if parte.startswith('!'):
                for k, v in ROSSE.items():
                    if v in parte:
                        c['rosse'].append(k)
                if 'STATO CUSCINETTO' in parte:
                    c['abilita'].append('stato_cuscinetto')
                continue
            trovata = False
            for k, parole in ABILITA.items():
                if any(parte.startswith(w) for w in parole):
                    c['abilita'].append(k)
                    trovata = True
            assert trovata, parte
        out.append(c)
    comete = [
        ('COMET1', '53000', 'E', 'Copernicus', 'Copernico e la rivoluzione eliocentrica',
         "Niccolò Copernico, matematico e astronomo, formulò un modello eliocentrico dell'universo che metteva il Sole al centro. La Terra divenne così un pianeta come gli altri, soggetto alle leggi planetarie. Come consigliere della dieta reale prussiana, Copernico formulò anche la moderna teoria quantitativa della moneta."),
        ('COMET2', '53001', 'E', 'Nostradamus', "L'astrologia di Nostradamus",
         "La prima edizione del libro «Le Profezie» uscì nel 1555. L'autore, uno speziale francese noto per la sua «pillola di rose» contro la peste, non fu condannato perché l'Inquisizione colpiva solo la magia, non le profezie o l'astrologia. La regina Caterina de' Medici lo nominò astrologo e medico di corte."),
        ('COMET3', '53500', 'W', "Halley's Comet", "Il papa «scomunica» la cometa di Halley del 1456",
         "«Una cometa chiomata e infuocata apparve per diversi giorni. Mentre gli studiosi predicevano una grande peste, carestie o qualche grande disastro, papa Callisto decretò preghiere di supplica per alcuni giorni, per placare l'ira di Dio, così che, se una calamità minacciava l'umanità, fosse interamente rivolta contro i Turchi, nemici del nome cristiano.»"),
        ('COMET4', '53501', 'W', 'Regiomontanus', 'Regiomontano e la cometa del 1472',
         "L'astronomo e astrologo Regiomontano di Norimberga calcolò la dimensione e la distanza dalla Terra di questa cometa usando l'angolo di parallasse."),
    ]
    for cid, img, mazzo, nen, nit, testo in comete:
        out.append({'id': cid, 'img': img, 'mazzo': mazzo, 'nome_en': nen, 'nome': nit, 'luogo': '',
                    'prestigio': [], 'ops': [], 'sottotitoli': [], 'pretendenti': [], 'oneshot': '',
                    'oneshot_arg': '', 'agenti': [], 'abilita': [], 'rosse': [], 'cometa': True,
                    'testo_abilita': "Quando la compri: scartala E attiva una carta Vittoria inattiva.",
                    'testo': testo})
    return out


# ---------------------------------------------------------------- mappa
# icone delle città: K/R + colore (C oro cattolico, I verde islamico, R rosso riformato)
# per ogni impero: stati M (medievale), C, I, R; ogni città ha una lista di icone (Costantinopoli 3)
IMPERI = [
    # chiave, nome, lato, riga, colonna, stato iniziale, città [(nome, emporio, capitale, {stato: [icone]})]
    ('England', 'Inghilterra', 'W', 0, 0, 'M', [
        ('Londra', '', True, {'M': ['R:C'], 'C': ['K:C'], 'R': ['K:R'], 'I': ['R:I']}),
        ('Bordeaux', '', False, {'M': ['K:C'], 'C': ['K:C'], 'R': ['K:R'], 'I': ['R:I']})]),
    ('France', 'Francia', 'W', 0, 1, 'M', [
        ('Bruges', '', False, {'M': ['R:C'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Parigi', '', True, {'M': ['K:C'], 'C': ['K:C'], 'R': ['K:R'], 'I': ['R:I']}),
        ('Lione', '', False, {'M': ['K:C'], 'C': ['K:C'], 'R': ['K:R'], 'I': ['R:I']})]),
    ('HRE', 'Sacro Romano Impero', 'W', 0, 2, 'M', [
        ('Lubecca', '', False, {'M': ['R:C'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Novgorod', 'Novgorod', False, {'M': ['R:R'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Norimberga', '', False, {'M': ['K:R'], 'C': ['R:C'], 'R': ['K:R'], 'I': ['R:I']}),
        ('Vienna', '', True, {'M': ['R:C'], 'C': ['K:C'], 'R': ['K:R'], 'I': ['K:I']})]),
    ('Hungary', 'Ungheria', 'E', 0, 3, 'M', [
        ('Buda', '', True, {'M': ['K:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['K:I']}),
        ('Varna', '', False, {'M': ['K:R'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']}),
        # Kiev esiste solo sulla carta mappa promo della Confederazione polacco-lituana
        ('Kiev', '', False, {'M': ['K:C'], 'C': ['K:C'], 'R': ['K:C'], 'I': ['K:C']})]),
    ('Byzantium', 'Bisanzio', 'E', 0, 4, 'M', [
        ('Tana', 'Tana', True, {'M': ['K:I'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['K:I']}),
        ('Caffa', '', False, {'M': ['K:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Trebisonda', 'Trebizond', False, {'M': ['R:R'], 'C': ['R:C'], 'R': ['K:R'], 'I': ['K:I']})]),
    ('Portugal', 'Portogallo', 'W', 1, 0, 'M', [
        ('Toledo', '', True, {'M': ['K:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Granada', '', False, {'M': ['R:I'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['K:I']}),
        ('Isole delle Spezie', 'SpiceIslands', False, {'M': ['R:C'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']})]),
    ('Aragon', 'Aragona', 'W', 1, 1, 'M', [
        ('Valencia', '', True, {'M': ['K:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Algeri', '', False, {'M': ['R:I'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['K:I']}),
        ('Timbuctù', 'Timbuktu', False, {'M': ['R:I'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['K:I']})]),
    ('PapalStates', 'Stato Pontificio', 'W', 1, 2, 'C', [
        ('Venezia', '', True, {'M': ['K:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['R:I']})]),
    ('Ottoman', 'Impero ottomano', 'E', 1, 3, 'M', [
        ('Costantinopoli', '', True, {'M': ['R:I', 'K:I', 'K:I'], 'C': ['R:C', 'K:C', 'K:C'],
                                      'R': ['R:R', 'K:R', 'K:R'], 'I': ['R:I', 'R:I', 'K:I']}),
        ('Modone', '', False, {'M': ['R:R'], 'C': ['R:C'], 'R': ['R:R'], 'I': ['R:I']}),
        ('Rodi', '', False, {'M': ['R:C'], 'C': ['K:C'], 'R': ['R:R'], 'I': ['R:I']})]),
    ('Mamluk', 'Mamelucchi', 'E', 1, 4, 'I', [
        ('Cipro', '', False, {'M': ['R:C'], 'C': ['R:C'], 'R': ['K:R'], 'I': ['R:C']}),
        ('Il Cairo', '', True, {'M': ['R:I'], 'C': ['R:C'], 'R': ['K:R'], 'I': ['R:I']}),
        ('Mar Rosso', 'RedSea', False, {'M': ['R:I'], 'C': ['R:C'], 'R': ['K:R'], 'I': ['R:I']})]),
]

# lato re / lato repubblica dei quadrati impero: prestigio e ops
QUADRATI = {
    'England': ({'nome': 'Edoardo IV, casa di York', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Guerra delle Due Rose']},
                {'nome': 'Parlamento inglese', 'prestigio': ['L'], 'ops': ['vote:W', 'commerce:W'], 'sotto': ['Camera dei Comuni', '']}),
    'France': ({'nome': 'Luigi XI il Ragno, casa di Valois', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Stato accentrato']},
               {'nome': 'Stati generali di Borgogna', 'prestigio': [], 'ops': ['commerce:W'], 'sotto': ['Grande Privilegio']}),
    'HRE': ({'nome': 'Federico III, casa d\'Asburgo', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Guerra boema']},
            {'nome': 'Reichstag, la dieta imperiale', 'prestigio': ['L'], 'ops': ['vote:W', 'commerce:W'], 'sotto': ['Riforma imperiale', '']}),
    'Hungary': ({'nome': 'Mattia Corvino, re d\'Ungheria', 'prestigio': ['P'], 'ops': ['campaign'], 'sotto': ['Esercito Nero']},
                {'nome': 'Sejm polacco-lituano', 'prestigio': ['L'], 'ops': ['vote:E', 'commerce:E'], 'sotto': ['Privilegio di Mielnik', '']}),
    'Byzantium': ({'nome': 'Davide Comneno, basileus di Trebisonda', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Despina Khatun degli Ak Koyunlu']},
                  {'nome': 'Confederazione dei turcomanni della Pecora Bianca', 'prestigio': [], 'ops': ['commerce:E'], 'sotto': ['Caterino Zeno, inviato di Venezia']}),
    'Portugal': ({'nome': 'Enrico il Navigatore', 'prestigio': ['D'], 'ops': ['campaign'], 'sotto': ['Invenzione della caravella']},
                 {'nome': 'Cortes generali di Castiglia', 'prestigio': ['D'], 'ops': ['commerce:W'], 'sotto': ['Fueros']}),
    'Aragon': ({'nome': 'Giovanni il Senzafede, re d\'Aragona', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Guerra civile di Navarra']},
               {'nome': 'Aurea Repubblica Ambrosiana', 'prestigio': ['L'], 'ops': ['vote:W', 'commerce:W'], 'sotto': ['Università di Pavia', '']}),
    'PapalStates': ({'nome': 'Papa Giulio II', 'prestigio': ['P', 'C'], 'ops': ['campaign'], 'sotto': ['Lega Santa']},
                    {'nome': 'Signoria fiorentina', 'prestigio': ['L'], 'ops': ['vote:W', 'commerce:W'], 'sotto': ['Equilibrio dei poteri', '']}),
    'Ottoman': ({'nome': 'Maometto II il Conquistatore', 'prestigio': ['I'], 'ops': ['campaign'], 'sotto': ['Conquista dell\'Europa orientale']},
                {'nome': 'Il sistema ottomano dei millet', 'prestigio': ['I'], 'ops': ['commerce:E'], 'sotto': ['Tolleranza dei dhimmi']}),
    'Mamluk': ({'nome': 'Qa\'it Bay della dinastia burji', 'prestigio': ['P'], 'ops': ['campaign'], 'sotto': ['Schiavi mamelucchi']},
               {'nome': 'Il beylik di Karaman', 'prestigio': ['I'], 'ops': ['commerce:E'], 'sotto': ['Congiura occidentale']}),
}

# confini: chiave, imperi, marittimo, nome (escutcheon delle banche)
CONFINI = [
    ('England-France', ['England', 'France'], True, ''),
    ('France-HRE', ['France', 'HRE'], True, 'Augusta'),
    ('HRE-Hungary', ['HRE', 'Hungary'], False, ''),
    ('Hungary-Byzantium', ['Hungary', 'Byzantium'], True, ''),
    ('Portugal-Aragon', ['Portugal', 'Aragon'], True, ''),
    ('Aragon-PapalStates', ['Aragon', 'PapalStates'], True, 'Firenze'),
    ('PapalStates-Ottoman', ['PapalStates', 'Ottoman'], True, ''),
    ('Ottoman-Mamluk', ['Ottoman', 'Mamluk'], True, 'Alessandria'),
    ('England-Portugal', ['England', 'Portugal'], True, 'Lisbona'),
    ('France-Aragon', ['France', 'Aragon'], False, ''),
    ('HRE-PapalStates', ['HRE', 'PapalStates'], False, ''),
    ('Hungary-Ottoman', ['Hungary', 'Ottoman'], True, ''),
    ('Byzantium-Mamluk', ['Byzantium', 'Mamluk'], False, ''),
]

# rotte commerciali: per ogni emporio, la sequenza degli imperi attraversati (i confini sono fra imperi consecutivi)
ROTTE = {
    'Trebizond': {'colore': 'W', 'impero': 'Byzantium', 'nome': 'Trebisonda',
                  'imperi': ['Byzantium', 'Hungary', 'Ottoman', 'PapalStates', 'Aragon', 'Portugal', 'England', 'France', 'HRE']},
    'RedSea': {'colore': 'W', 'impero': 'Mamluk', 'nome': 'Mar Rosso',
               'imperi': ['Mamluk', 'Ottoman', 'PapalStates', 'Aragon', 'Portugal', 'England', 'France', 'HRE']},
    'SpiceIslands': {'colore': 'W', 'impero': 'Portugal', 'nome': 'Isole delle Spezie',
                     'imperi': ['Portugal', 'England', 'France', 'HRE']},
    'Tana': {'colore': 'E', 'impero': 'Byzantium', 'nome': 'Tana',
             'imperi': ['Byzantium', 'Hungary', 'Ottoman', 'Mamluk']},
    'Novgorod': {'colore': 'E', 'impero': 'HRE', 'nome': 'Novgorod',
                 'imperi': ['HRE', 'France', 'England', 'Portugal', 'Aragon', 'PapalStates', 'Ottoman', 'Mamluk']},
    'Timbuktu': {'colore': 'E', 'impero': 'Aragon', 'nome': 'Timbuctù',
                 'imperi': ['Aragon', 'PapalStates', 'Ottoman', 'Mamluk']},
}

BANCHE = [
    {'chiave': 'Fugger', 'nome': 'Fugger', 'colore': 'blu', 'rgb': [0.16, 0.45, 0.92], 'confine': 'France-HRE'},
    {'chiave': 'Medici', 'nome': 'Medici', 'colore': 'giallo', 'rgb': [0.93, 0.80, 0.18], 'confine': 'Aragon-PapalStates'},
    {'chiave': 'Coeur', 'nome': 'Cœur', 'colore': 'viola', 'rgb': [0.60, 0.25, 0.85], 'confine': 'Ottoman-Mamluk'},
    {'chiave': 'Marchionni', 'nome': 'Marchionni', 'colore': 'verde', 'rgb': [0.25, 0.68, 0.24], 'confine': 'England-Portugal'},
]


POS_CITTA = {'England': [(217, 210), (272, 455)], 'France': [(156, 183), (61, 316), (243, 408)],
             'HRE': [(102, 136), (238, 133), (61, 323), (238, 371)], 'Hungary': [(65, 401), (201, 418), (258, 140)],
             'Byzantium': [(105, 126), (44, 326), (272, 455)], 'Portugal': [(246, 178), (268, 302), (115, 465)],
             'Aragon': [(68, 153), (255, 364), (99, 408)], 'PapalStates': [(129, 75)],
             'Ottoman': [(133, 75), (80, 258), (272, 228)], 'Mamluk': [(153, 217), (129, 401), (275, 398)]}
POS_CONFINI = {'England-France': (401, 300), 'France-HRE': (795, 166), 'HRE-Hungary': (1189, 300),
               'Hungary-Byzantium': (1583, 480), 'Portugal-Aragon': (401, 900), 'Aragon-PapalStates': (795, 816),
               'PapalStates-Ottoman': (1189, 944), 'Ottoman-Mamluk': (1582, 948), 'England-Portugal': (165, 578),
               'France-Aragon': (560, 578), 'HRE-PapalStates': (954, 578), 'Hungary-Ottoman': (1440, 578),
               'Byzantium-Mamluk': (1780, 578)}


def mappa():
    imperi = {}
    for k, nome, lato, r, c, st, citta in IMPERI:
        imperi[k] = {'nome': nome, 'lato': lato, 'riga': r, 'col': c, 'stato_iniziale': st,
                     'citta': [{'nome': n, 'emporio': e, 'capitale': cap, 'icone': ic} for n, e, cap, ic in citta],
                     're': QUADRATI[k][0], 'repubblica': QUADRATI[k][1]}
        for cc, pp in zip(imperi[k]['citta'], POS_CITTA[k]):
            cc['pos'] = list(pp)
            if cc['nome'] == 'Kiev':
                cc['solo_promo'] = True
    imperi['Ottoman']['citta'][0]['pos_multi'] = [[46, 75], [139, 75], [221, 75]]
    # adiacenza: confine o diagonale
    adiac = {k: [] for k in imperi}
    for a in imperi:
        for b in imperi:
            if a != b and abs(imperi[a]['riga'] - imperi[b]['riga']) <= 1 and abs(imperi[a]['col'] - imperi[b]['col']) <= 1:
                adiac[a].append(b)
    return {
        'imperi': imperi,
        'ordine': [x[0] for x in IMPERI],
        'confini': [{'chiave': k, 'imperi': i, 'mare': m, 'nome': n, 'pos': list(POS_CONFINI[k])} for k, i, m, n in CONFINI],
        'slot': {'x0': 36, 'y0': 34, 'dx': 394, 'dy': 574, 'w': 337, 'h': 514},
        'rotte': ROTTE,
        'adiacenti': adiac,
        'banche': BANCHE,
        'empori_iniziali': {'W': 'Trebizond', 'E': 'Tana'},
        'vittorie': {
            'santa': {'nome': 'Vittoria santa', 'sotto': 'Torquemada'},
            'imperiale': {'nome': 'Vittoria imperiale', 'sotto': 'Carlo V'},
            'globalizzazione': {'nome': 'Vittoria della globalizzazione', 'sotto': 'Colombo'},
            'rinascimento': {'nome': 'Vittoria del Rinascimento', 'sotto': 'Leonardo'},
            'bizantina': {'nome': 'Vittoria bizantina', 'sotto': 'Filotea di Atene'},
        },
        # promo «Età della Riforma» (variante 1550): carte mappa di partenza alternative per Ungheria e
        # Ottomani (le città che non esistono negli altri stati restano vuote e inattive), quadrato ottomano,
        # banchieri, quinta carta vittoria
        'promo': {
            'icone_M': {'Hungary': [['K:C'], ['K:R'], ['K:C']], 'Ottoman': [['R:R', 'K:R'], ['R:R'], ['R:C']]},
            'pos_M': {'Hungary': [[80, 386], [210, 410], [258, 140]], 'Ottoman': [[93, 98], [80, 258], [275, 232]]},
            'quadrato_ottomano': (
                {'nome': 'Basileus Basilio Megas Comneno', 'prestigio': [], 'ops': ['campaign'], 'sotto': ['Esercito comneno']},
                {'nome': 'Synkletos bizantino', 'prestigio': ['L'], 'ops': [], 'sotto': []}),
            'banche': [
                {'chiave': 'Mendes', 'nome': 'Mendes', 'persona': 'Alvaro Mendes', 'confine': 'Hungary-Ottoman'},
                {'chiave': 'Berenberg', 'nome': 'Berenberg', 'persona': 'Cornelius Berenberg', 'confine': 'England-France'},
            ],
        },
        'pezzi': {'R:C': 10, 'R:I': 7, 'R:R': 7, 'K:C': 10, 'K:I': 7, 'K:R': 7,
                  'B:C': 5, 'B:I': 5, 'B:R': 5, 'S:C': 6, 'S:I': 4, 'S:R': 3},
    }


if __name__ == '__main__':
    cc = carte()
    json.dump(cc, open(os.path.join(R, 'data', 'carte.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    json.dump(mappa(), open(os.path.join(R, 'data', 'mappa.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    from collections import Counter
    print(len(cc), 'carte', Counter(c['mazzo'] for c in cc))
    print('oneshot', Counter(c['oneshot'] for c in cc))
    print('abilita', Counter(a for c in cc for a in c['abilita']))
    print('ops', Counter(o for c in cc for o in c['ops']))
