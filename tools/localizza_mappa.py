#!/usr/bin/env python3
"""Traduce in italiano i nomi sul tabellone e sulle carte mappa (imperi e città).
Uso: python3 tools/localizza_mappa.py
Lavora su assets/mappa/*_orig.webp (copie originali) e scrive le versioni tradotte accanto."""
import os, glob, json
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
M = os.path.join(R, 'assets', 'mappa')
CINZEL = os.path.join(R, 'tools', 'Cinzel.ttf')
FELL = os.path.join(R, 'assets', 'fonts', 'IMFellEnglish.ttf')

# empire: [(x0, y0, x1, y1, testo, stile)] in coordinate della carta mappa (337x514)
# stile: T titolo su fascia chiara, TW titolo su fascia scura, C città
SOST = {
    'England': [(126, 14, 272, 56, 'INGHILTERRA', 'T'), (88, 150, 200, 182, 'LONDRA', 'C')],
    'France': [(130, 14, 248, 56, 'FRANCIA', 'T'), (22, 376, 100, 406, 'PARIGI', 'C'), (218, 450, 280, 482, 'Lione', 'C')],
    'HRE': [(102, 6, 280, 64, 'SACRO ROMANO\nIMPERO', 'T'), (62, 176, 152, 208, 'Lubecca', 'C'),
            (14, 376, 132, 408, 'Norimberga', 'C')],
    'Hungary': [(130, 14, 286, 56, 'UNGHERIA', 'TW')],
    'Byzantium': [(120, 14, 304, 56, 'BISANZIO', 'TW'), (202, 363, 326, 394, 'Trebisonda', 'C')],
    'Portugal': [(158, 462, 322, 502, 'PORTOGALLO', 'T'), (10, 368, 84, 430, 'Isole delle\nSpezie', 'C')],
    'Aragon': [(134, 462, 268, 502, 'ARAGONA', 'T'), (246, 290, 332, 320, 'Algeri', 'C'),
               (196, 408, 318, 438, 'Timbuctù', 'C')],
    'PapalStates': [(104, 462, 300, 502, 'STATO PONTIFICIO', 'T'), (12, 16, 110, 46, 'VENEZIA', 'C')],
    'Ottoman': [(124, 462, 288, 502, 'OTTOMANI', 'TW'), (98, 14, 322, 46, 'COSTANTINOPOLI', 'C'),
                (38, 298, 126, 328, 'Modone', 'C'), (236, 161, 328, 192, 'Rodi', 'C')],
    'Mamluk': [(144, 464, 290, 504, 'MAMELUCCHI', 'TW'), (34, 226, 122, 256, 'Cipro', 'C'),
               (112, 318, 198, 348, 'IL CAIRO', 'C'), (266, 270, 320, 332, 'Mar\nRosso', 'C')],
}


def font(path, size, wght=None):
    f = ImageFont.truetype(path, size)
    if wght:
        try:
            f.set_variation_by_axes([wght])
        except Exception:
            pass
    return f


def traduci(img, sost, dx=0, dy=0):
    a = np.asarray(img.convert('RGB')).copy()
    mask = np.zeros(a.shape[:2], np.uint8)
    for x0, y0, x1, y1, testo, st in sost:
        x0, x1, y0, y1 = x0 + dx, x1 + dx, y0 + dy, y1 + dy
        sub = a[y0:y1, x0:x1].astype(int)
        g = sub.mean(axis=2)
        sat = sub.max(axis=2) - sub.min(axis=2)
        if st == 'TW':
            k = g > 150
        elif st == 'T':
            k = (g < 140) & (sat < 60)
        else:
            k = (g < 120) & (sat < 90)
        mask[y0:y1, x0:x1] = k.astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=2)
    a = cv2.inpaint(a, mask, 5, cv2.INPAINT_TELEA)
    im = Image.fromarray(a)
    d = ImageDraw.Draw(im)
    for x0, y0, x1, y1, testo, st in sost:
        x0, x1, y0, y1 = x0 + dx, x1 + dx, y0 + dy, y1 + dy
        righe = testo.split('\n')
        w, h = x1 - x0, y1 - y0
        if st in ('T', 'TW'):
            mk = lambda s: font(CINZEL, s, 700)
            col = (245, 242, 235) if st == 'TW' else (40, 32, 28)
            smax = 30
        else:
            mk = lambda s: font(FELL, s)
            col = (70, 55, 45)
            smax = 26
        for s in range(smax, 9, -1):
            f = mk(s)
            ok = all(d.textbbox((0, 0), r, font=f)[2] <= w + 6 for r in righe) and len(righe) * s * 1.0 <= h + 4
            if ok:
                break
        tot = len(righe) * s
        for i, r in enumerate(righe):
            bb = d.textbbox((0, 0), r, font=f)
            tx = x0 + (w - (bb[2] - bb[0])) / 2 - bb[0]
            ty = y0 + (h - tot) / 2 + i * s - bb[1] + (s - (bb[3] - bb[1])) / 2
            if st == 'C':
                d.text((tx, ty), r, font=f, fill=col, stroke_width=2, stroke_fill=(214, 196, 160))
            else:
                d.text((tx, ty), r, font=f, fill=col)
    return im


def main():
    mp = json.load(open(os.path.join(R, 'data', 'mappa.json')))
    sl = mp['slot']
    tab = Image.open(os.path.join(R, 'tools', 'mappa_orig', 'tabellone_orig.webp'))
    for e, d in mp['imperi'].items():
        dx = sl['x0'] + sl['dx'] * d['col']
        dy = sl['y0'] + sl['dy'] * d['riga']
        tab = traduci(tab, SOST[e], dx, dy)
    tab.save(os.path.join(M, 'tabellone.webp'), quality=88)
    for f in glob.glob(os.path.join(R, 'tools', 'mappa_orig', '*_orig.webp')):
        b = os.path.basename(f)
        if b.startswith(("tabellone", "promo_")):
            continue
        e = b.split('_')[0]
        im = traduci(Image.open(f), SOST[e])
        im.save(os.path.join(M, b.replace('_orig.webp', '.webp')), quality=90)
    print('fatto')


if __name__ == '__main__':
    main()
