#!/usr/bin/env python3
"""Controlla che ogni carattere usato nei testi del gioco esista nei font (niente quadratini).

Uso: python3 tools/controlla_glifi.py
- i font dei testi (Roboto Condensed, EB Garamond) devono avere tutti i caratteri degli script e dei dati
  (nomi delle carte, testi, diario);
- i font decorativi (Almendra, Unifraktur, IM Fell) si usano solo per titoli fissi e nomi dei giocatori:
  devono avere i caratteri delle stringhe degli script e le lettere accentate italiane.
Esce con errore se manca qualcosa.
"""
import glob, os, re, sys
from fontTools.ttLib import TTFont

R = os.path.join(os.path.dirname(__file__), '..')
script = []
for f in glob.glob(R + '/scripts/**/*.gd', recursive=True):
    src = open(f, encoding='utf-8').read()
    script += re.findall(r'"((?:[^"\\\n]|\\.)*)"', src)
    script += re.findall(r'"""(.*?)"""', src, re.S)
dati = []
for f in glob.glob(R + '/data/*.json'):
    dati.append(open(f, encoding='utf-8').read())
c_script = set(''.join(script)) - set('\n\t\r') | set('àèéìòùÀÈÉÌÒÙ')
c_tutti = c_script | (set(''.join(dati)) - set('\n\t\r'))
TESTO = ('RobotoCondensed', 'EBGaramond')
# caratteri volutamente assenti nei titoli: ƒ (i fiorini si scrivono sempre con Roboto)
errori = 0
for font in sorted(glob.glob(R + '/assets/fonts/*.ttf')):
    cmap = TTFont(font).getBestCmap()
    nome = os.path.basename(font)
    car = c_tutti if nome.startswith(TESTO) else c_script - set('ƒ')
    manca = sorted(ch for ch in car if ord(ch) not in cmap and ord(ch) > 31)
    if manca:
        print(f'{nome}: mancano {"".join(manca)!r}')
        errori += 1
    else:
        print(f'{nome}: tutti i {len(car)} caratteri presenti')
sys.exit(1 if errori else 0)
