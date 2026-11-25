#!/usr/bin/env python3
"""Traduce in italiano le carte di Pax Renaissance mantenendo la grafica originale.

Uso: python3 tools/localizza_carte.py <cartella con le carte ritagliate 653x1000> [id ...]
Per ogni carta cancella (inpainting) le scritte inglesi e ridisegna i testi italiani al loro posto:
nome, testo storico, etichette e sottotitoli delle operazioni, luogo, pretendenti, one-shot, abilità.
Le carte finite vanno in assets/carte/<foglio>.webp.
"""
import json, os, sys, re, difflib
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
FONTS = os.path.join(R, 'assets', 'fonts')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def font(name, size, wght=None):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    if wght is not None:
        try:
            f.set_variation_by_axes([wght])
        except Exception:
            pass
    return f


def titolo_f(s): return font('Almendra-Bold.ttf', s)
def corpo_f(s): return font('RobotoCondensed-Italic.ttf', s, 400)
def corpo_b(s): return font('RobotoCondensed.ttf', s, 700)
def corpo_r(s): return font('RobotoCondensed.ttf', s, 500)
def sub_f(s): return font('RobotoCondensed-Italic.ttf', s, 400)


ETICHETTE = {'behead': 'Decapita', 'tax': 'Tassa', 'repress': 'Reprimi', 'vote': 'Voto', 'siege': 'Assedio',
             'corsair': 'Corsaro', 'campaign': 'Campagna', 'inq': 'Inquisitore', 'commerce': 'Commercio'}
LUOGHI = {'England': 'Inghilterra', 'France': 'Francia', 'HRE': 'Sacro\nRomano\nImpero', 'Hungary': 'Ungheria',
          'Byzantium': 'Bisanzio', 'Portugal': 'Portogallo', 'Aragon': 'Aragona', 'PapalStates': 'Stato\nPontificio',
          'Ottoman': 'Ottomani', 'Mamluk': 'Mamelucchi', 'TheEast': "L'Oriente", 'TheWest': "L'Occidente", 'Queen': ''}
PRETENDENTI = {'England': 'Inghilterra', 'France': 'Francia', 'HRE': 'Sacro\nRomano\nImpero', 'Hungary': 'Ungheria',
               'Byzantium': 'Bisanzio', 'Portugal': 'Portogallo', 'Aragon': 'Aragona', 'PapalStates': 'Stato Pont.',
               'Ottoman': 'Ottomani', 'Mamluk': 'Mamelucchi'}
SPOST = {'SpiceIslands': 'ISOLE DELLE SPEZIE', 'Novgorod': 'NOVGOROD', 'Timbuktu': 'TIMBUCTÙ', 'RedSea': 'MAR ROSSO'}
ONESHOT = {'conspiracy': ['COMPLOTTO'], 'revolt': ['RIVOLTA', 'CONTADINA'], 'crusade': ['CROCIATA'],
           'jihad': ['JIHAD'], 'reformation': ['RIFORMA'], 'apostasy': ['APOSTASIA'], 'coronation': ['INCORONAZIONE']}

# --------------------------------------------------------------------------- utilità


def hsv(a):
    return cv2.cvtColor(a, cv2.COLOR_RGB2HSV).astype(int)


def inpaint(a, mask, r=4):
    m = (mask > 0).astype(np.uint8) * 255
    if m.sum() == 0:
        return a
    m = cv2.dilate(m, np.ones((3, 3), np.uint8), iterations=3)
    return cv2.inpaint(a, m, r, cv2.INPAINT_TELEA)


def ink(a, x0, y0, x1, y1, mode):
    """Maschera dei pixel di scrittura nel rettangolo. mode: dark (scritte scure), light (chiare), red."""
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(a.shape[1], x1), min(a.shape[0], y1)
    m = np.zeros(a.shape[:2], bool)
    if x1 <= x0 or y1 <= y0:
        return m
    sub = a[y0:y1, x0:x1].astype(int)
    h = hsv(a[y0:y1, x0:x1])
    g = sub.mean(axis=2)
    s = h[:, :, 1]
    if mode == 'dark':
        k = (g < 120) & (s < 110)
    elif mode == 'darkred':
        k = ((g < 120) & (s < 110)) | (((h[:, :, 0] <= 8) | (h[:, :, 0] >= 168)) & (s > 110) & (h[:, :, 2] > 90) & (h[:, :, 2] < 235))
    elif mode == 'darkred2':
        k = ((g < 120) & (s < 110)) | (((h[:, :, 0] <= 8) | (h[:, :, 0] >= 168)) & (s > 110) & (h[:, :, 2] > 150) & (h[:, :, 2] < 235))
    elif mode == 'darknote':
        k = (g < 115) | (((h[:, :, 0] <= 14) | (h[:, :, 0] >= 165)) & (s > 100) & (h[:, :, 2] < 250))
    elif mode == 'light':
        k = (g > 140) & (s < 70)
    else:
        k = np.zeros_like(g, bool)
    m[y0:y1, x0:x1] = k
    return m


def righe(mask, x0, x1, y0, y1, minpix=2):
    """Righe che contengono scrittura."""
    return [y for y in range(max(0, y0), min(mask.shape[0], y1)) if mask[y, x0:x1].sum() >= minpix]


def blocco(mask, x0, x1, y0, y1, gap=7, start_max=25, minpix=2):
    """Primo blocco di righe di testo a partire da y0 (righe contigue con buchi <= gap)."""
    rr = righe(mask, x0, x1, y0, y1, minpix)
    if not rr or rr[0] - y0 > start_max:
        return None
    top = bot = rr[0]
    for y in rr[1:]:
        if y - bot > gap:
            break
        bot = y
    cols = np.where(mask[top:bot + 1, x0:x1].any(axis=0))[0]
    return [x0 + int(cols.min()), top, x0 + int(cols.max()), bot]


def ocr_parole(a, x0, y0, x1, y1, scala=2, psm='11'):
    """Parole riconosciute da tesseract nel rettangolo: [(testo, x0, y0, x1, y1)] in coordinate della carta."""
    import subprocess, tempfile
    crop = Image.fromarray(a[y0:y1, x0:x1]).resize(((x1 - x0) * scala, (y1 - y0) * scala))
    with tempfile.NamedTemporaryFile(suffix='.png') as tf:
        crop.save(tf.name)
        out = subprocess.run(['tesseract', tf.name, '-', '--psm', psm, 'tsv'], capture_output=True, text=True).stdout
    res = []
    for l in out.splitlines():
        p = l.split('\t')
        if len(p) == 12 and p[11].strip() and p[10] != 'conf' and float(p[10]) > 25:
            lx, ty, w, h = (int(v) for v in p[6:10])
            res.append((p[11].strip(), x0 + lx // scala, y0 + ty // scala, x0 + (lx + w) // scala, y0 + (ty + h) // scala))
    return res


def ocr_righe(a, x0, y0, x1, y1, scala=2):
    """Righe di testo riconosciute: [(testo, x0, y0, x1, y1)] in coordinate della carta."""
    import subprocess, tempfile
    crop = Image.fromarray(a[y0:y1, x0:x1]).resize(((x1 - x0) * scala, (y1 - y0) * scala))
    with tempfile.NamedTemporaryFile(suffix='.png') as tf:
        crop.save(tf.name)
        out = subprocess.run(['tesseract', tf.name, '-', '--psm', '6', 'tsv'], capture_output=True, text=True).stdout
    rows = {}
    for l in out.splitlines():
        p = l.split('\t')
        if len(p) == 12 and p[11].strip() and p[10] != 'conf' and float(p[10]) > 10:
            key = (p[2], p[3], p[4])
            lx, ty, w, h = (int(v) for v in p[6:10])
            rows.setdefault(key, []).append((p[11].strip(), lx, ty, lx + w, ty + h))
    res = []
    for k, ws in rows.items():
        parole = [(w[0], x0 + w[1] // scala, y0 + w[2] // scala, x0 + w[3] // scala, y0 + w[4] // scala) for w in ws]
        res.append(parole)
    res.sort(key=lambda r: min(w[2] for w in r))
    return res


def text_w(d, t, f):
    b = d.textbbox((0, 0), t, font=f)
    return b[2] - b[0]


def wrap(d, text, f, widths):
    """Spezza il testo in righe; widths(i) dà la larghezza della riga i."""
    out = []
    for par in text.split('\n'):
        words = par.split(' ')
        cur = ''
        for w in words:
            t = (cur + ' ' + w).strip()
            if text_w(d, t, f) <= widths(len(out)) or cur == '':
                cur = t
            else:
                out.append(cur)
                cur = w
        out.append(cur)
        out.append(None)  # fine paragrafo
    if out and out[-1] is None:
        out.pop()
    return out


def draw_center(d, cx, y, t, f, fill, stroke=0, sfill=None):
    w = text_w(d, t, f)
    d.text((cx - w / 2, y), t, font=f, fill=fill, stroke_width=stroke, stroke_fill=sfill)


def fit(d, lines, fmaker, maxw, maxh, smax, smin, lh=1.08):
    """Dimensione più grande del font perché tutte le righe stiano nel riquadro."""
    for s in range(smax, smin - 1, -1):
        f = fmaker(s)
        if all(text_w(d, l, f) <= maxw for l in lines) and len(lines) * s * lh <= maxh:
            return f, s
    return fmaker(smin), smin


def fit_wrap(d, text, fmaker, maxw, maxh, smax, smin, lh=1.12):
    for s in range(smax, smin - 1, -1):
        f = fmaker(s)
        ls = wrap(d, text, f, lambda i: maxw)
        if len(ls) * s * lh <= maxh and all(l is None or text_w(d, l, f) <= maxw for l in ls):
            return f, s, ls
    f = fmaker(smin)
    return f, smin, wrap(d, text, f, lambda i: maxw)


# --------------------------------------------------------------------------- carte


def carica_raw():
    righe_ = {}
    for r in open(os.path.join(R, 'tools', 'carte_raw.txt'), encoding='utf-8'):
        p = r.rstrip('\n').split('|')
        if len(p) == 12 and p[0].startswith('PREN'):
            righe_[p[1]] = p
    return righe_


def trova_box(a):
    m = ((a.min(axis=2) > 205) & ((a.max(axis=2).astype(int) - a.min(axis=2)) < 32)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    cand = [st[i] for i in range(1, n) if st[i][4] > 50000 and 330 < st[i][2] < 470 and st[i][1] > 150]
    if not cand:
        return None
    b = max(cand, key=lambda b: b[4])
    x0, y0, x1, y1 = int(b[0]), int(b[1]), int(b[0] + b[2]), int(b[1] + b[3])
    h = hsv(a)
    g = (h[:, :, 1] > 70) & (h[:, :, 0] >= 12) & (h[:, :, 0] <= 35) & (h[:, :, 2] > 90)
    rows = [y for y in range(y0 + 15, y0 + 115) if g[y, x0:x1].mean() > 0.25]
    if rows:
        last = rows[0]
        for y in rows[1:]:
            if y - last > 3:
                break
            last = y
        main = last + 3
    else:
        main = y0 + 50
    return [x0, y0, x1, y1, main]


def medaglione(a, x0, y0, x1):
    """Medaglione rotondo (uomo vitruviano, ritratti) a cavallo del bordo destro in alto del riquadro."""
    zx0, zy0 = x1 - 170, y0 - 80
    g = cv2.cvtColor(a[zy0:y0 + 120, zx0:x1 + 30], cv2.COLOR_RGB2GRAY)
    g = cv2.medianBlur(g, 5)
    cs = cv2.HoughCircles(g, cv2.HOUGH_GRADIENT, dp=1.2, minDist=80, param1=110, param2=38, minRadius=38, maxRadius=70)
    if cs is None:
        return None
    best = None
    for cx, cy, r in cs[0]:
        X, Y = zx0 + cx, zy0 + cy
        ring = np.zeros(a.shape[:2], np.uint8)
        cv2.circle(ring, (int(X), int(Y)), int(r), 1, 4)
        hs_ = hsv(a)
        if hs_[:, :, 1][ring > 0].mean() < 45:
            continue
        if X > x1 - 140 and Y < y0 + 90 and Y + r > y0:
            if best is None or r > best[2]:
                best = (int(X), int(Y), int(r))
    return best


def sigilli(a, escludi, west):
    """Sigilli di ceralacca rossi (in testa alle note delle abilità)."""
    h = hsv(a)
    xs = (440, 653) if west else (0, 215)
    m = (((h[:, :, 0] <= 10) | (h[:, :, 0] >= 165)) & (h[:, :, 1] > 90) & (h[:, :, 2] > 50)).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    out = []
    for i in range(1, n):
        x, y, w, hh, ar = st[i]
        if 18 <= w <= 64 and 18 <= hh <= 64 and ar > 250 and y > 150 and ar / (w * hh) > 0.55 and 0.6 < w / hh < 1.6:
            cx, cy = x + w / 2, y + hh / 2
            if not (xs[0] <= cx <= xs[1]):
                continue
            py = int(y + hh + 14)
            if py >= a.shape[0]:
                continue
            pz = h[py:py + 24, max(0, int(cx) - 40):int(cx) + 40].reshape(-1, 3)
            br = pz[pz[:, 2] > np.percentile(pz[:, 2], 60)]
            if not (np.percentile(pz[:, 2], 80) > 170 and 10 <= np.median(br[:, 0]) <= 40):
                continue
            if any(e[0] - 6 <= cx <= e[0] + e[2] + 6 and e[1] - 6 <= cy <= e[1] + e[3] + 6 for e in escludi):
                continue
            out.append([int(x), int(y), int(w), int(hh)])
    out.sort(key=lambda s: s[1])
    return out


def localizza(path, c, raw, icone):
    from det import find
    a = np.asarray(Image.open(path).convert('RGB')).copy()
    west = c['mazzo'] == 'W'
    queen = bool(c.get('pretendenti'))
    bx0, bx1 = (478, 630) if west else (22, 175)      # nastro delle operazioni
    banner_ink = 'dark' if west else 'light'
    ops = c['ops']
    ic = find(a, ops, west, queen) if ops else []
    ic = [b for b in ic if b]
    box = trova_box(a)
    seals = sigilli(a, ic, west)
    abil_lines = [l for l in raw[10].split('\\n') if l] if raw else []
    jobs = []   # (tipo, rect, dati) da disegnare dopo l'inpainting
    mask = np.zeros(a.shape[:2], bool)

    # --- note delle abilità (prima, così le altre zone le possono evitare)
    note_rects = []
    for i, sg in enumerate(seals):
        cx = sg[0] + sg[2] // 2
        top = sg[1] + sg[3] // 2 + 4
        lx, rx = max(4, cx - 84), min(a.shape[1] - 4, cx + 84)
        nxt = [q[1] for q in seals if q[1] > sg[1] + 20]
        ylim = min(nxt) - 4 if nxt else min(a.shape[0] - 4, top + 360)
        ws = ocr_parole(a, lx, top, rx, ylim, 2, '6')
        ws = [w for w in ws if (w[4] - w[2]) >= 8 and re.search('[A-Za-z0-9]', w[0])]
        ws.sort(key=lambda w: w[2])
        sel = []
        for w in ws:
            if not sel:
                if w[2] - top > 60:
                    break
                sel.append(w)
            elif w[2] - max(q[4] for q in sel) <= 52:
                sel.append(w)
            else:
                break
        if not sel:
            continue
        ty0 = min(w[2] for w in sel) - 3
        ty1 = max(w[4] for w in sel) + 3
        mm = ink(a, lx + 14, ty1, rx - 14, ylim, 'darknote')
        for yy in righe(mm, lx + 14, rx - 14, ty1, ylim, 3):
            if yy - ty1 > 30:
                break
            ty1 = yy + 3
        m = ink(a, lx + 2, ty0, rx - 2, ty1, 'darknote')
        m[sg[1] - 4:sg[1] + sg[3] + 6, sg[0] - 6:sg[0] + sg[2] + 6] = False
        mask[ty0:ty1, lx + 2:rx - 2] |= m[ty0:ty1, lx + 2:rx - 2]
        testo = abil_lines[i] if i < len(abil_lines) else ''
        note_rects.append([lx, sg[1], rx, ty1])
        jobs.append(('nota', [lx + 8, max(ty0 + 2, sg[1] + sg[3] + 4), rx - 6, ty1], testo))
    if len(note_rects) != len(abil_lines):
        print('  ! note trovate', len(note_rects), 'attese', len(abil_lines), c['nome_en'])

    def in_note(y0, y1, x0=bx0, x1=bx1):
        return any(not (y1 < r[1] or y0 > r[3] or x1 < r[0] or x0 > r[2]) for r in note_rects)

    # --- etichette delle operazioni
    for op, b in zip(ops, ic):
        x, y, w, h = b
        k = op.split(':')[0]
        if k == 'repress':
            yy0, yy1 = y + int(h * 0.08), y + int(h * 0.52)
        elif k == 'commerce':
            yy0, yy1 = y + int(h * 0.30), y + int(h * 0.70)
        else:
            yy0, yy1 = y + int(h * 0.50), y + int(h * 0.93)
        el = np.zeros(a.shape[:2], np.uint8)
        cv2.ellipse(el, (x + w // 2, y + h // 2), (w // 2 - 6, h // 2 - 5), 0, 0, 360, 1, -1)
        sub = a[yy0:yy1, x + 8:x + w - 8].astype(int)
        hs = hsv(a[yy0:yy1, x + 8:x + w - 8])
        if k == 'commerce':
            t = (sub.mean(axis=2) > 215) | (sub.mean(axis=2) < 105)
        else:
            t = (hs[:, :, 2] > 165) & (hs[:, :, 1] < 150)
        mm = np.zeros(a.shape[:2], bool)
        mm[yy0:yy1, x + 8:x + w - 8] = t
        mm &= el.astype(bool)
        mask |= mm
        jobs.append(('op', [x, yy0, x + w, yy1], k))

    # --- sottotitoli delle operazioni
    for j, (op, b) in enumerate(zip(ops, ic)):
        x, y, w, h = b
        y0 = y + h - 2
        ylim = ic[j + 1][1] - 2 if j + 1 < len(ic) else min(y0 + 118, 830)
        for r_ in note_rects:
            if r_[1] > y0 and not (r_[2] < x or r_[0] > x + w):
                ylim = min(ylim, r_[1] - 1)
        sx0, sx1 = max(bx0 - 6, x - 6), min(bx1 + 6, x + w + 6)
        m = ink(a, sx0, y0, sx1, ylim, banner_ink)
        bl = blocco(m, sx0, sx1, y0, ylim, gap=(14 if j + 1 < len(ic) else 42), start_max=32, minpix=2)
        if bl and not in_note(bl[1], bl[3], bl[0], bl[2]):
            mask[bl[1]:bl[3] + 1, bl[0]:bl[2] + 1] |= m[bl[1]:bl[3] + 1, bl[0]:bl[2] + 1]
            sub = c['sottotitoli'][j] if j < len(c['sottotitoli']) else ''
            jobs.append(('sub', [sx0 + 4, bl[1], sx1 - 4, bl[3]], sub))

    # --- luogo (sotto lo stemma in testa al nastro)
    if not queen:
        first = min([b[1] for b in ic] + [330])
        hs = hsv(a)
        dia = (hs[:, :, 1] > 90) & (hs[:, :, 0] >= 5) & (hs[:, :, 0] <= 25) & (hs[:, :, 2] > 80)
        rows = [yy for yy in range(150, first) if dia[yy, bx0:bx1].sum() > 25]
        if rows:
            first = min(first, rows[0])
        cx0, cx1 = (505, 618) if west else (36, 156)
        m = ink(a, cx0, 112, cx1, first - 2, banner_ink)
        rr = righe(m, cx0, cx1, 128, first - 2, 3)
        if rr:
            blocks = []
            cur = [rr[0], rr[0]]
            for yy in rr[1:]:
                if yy - cur[1] > 4:
                    blocks.append(cur)
                    cur = [yy, yy]
                else:
                    cur[1] = yy
            blocks.append(cur)
            blocks = [bk for bk in blocks if bk[1] - bk[0] >= 4]
            if blocks:
                yt0, yt1 = blocks[0][0], blocks[-1][1]
                mask[yt0:yt1 + 1, bx0:bx1] |= m[yt0:yt1 + 1, bx0:bx1]
                jobs.append(('luogo', [bx0, yt0, bx1, yt1], LUOGHI.get(c['luogo'], c['luogo'])))

    # --- pretendenti delle regine («Suitors» trovato con l'OCR)
    if queen:
        head = []
        for sc, psm in ((2, '11'), (3, '11'), (2, '6'), (3, '4')):
            ws = ocr_parole(a, max(0, bx0 - 12), 150, min(653, bx1 + 12), 960, sc, psm)
            head = [w for w in ws if re.search('u[il1]t[o0]r|s[uv]it|uitor|itors|SUIT', w[0], re.I)]
            if head:
                break
        if head:
            top = head[0][2] - 6
            m = ink(a, bx0 - 4, top, bx1 + 4, 905, banner_ink)
            rr = righe(m, bx0, bx1, top, 905, 3)
            bot = top
            for yy in rr:
                if yy - bot > 34 and bot > top + 20:
                    break
                bot = yy
            mask[top:bot + 4, bx0 - 4:bx1 + 4] |= m[top:bot + 4, bx0 - 4:bx1 + 4]
            jobs.append(('pret', [bx0, top + 4, bx1, bot], c['pretendenti']))
        else:
            ystart = max([b[1] + b[3] + 50 for b in ic] + [250])
            m = ink(a, bx0 - 4, ystart, bx1 + 4, 905, banner_ink)
            rr = [yy for yy in righe(m, bx0, bx1, ystart, 905, 3) if not in_note(yy, yy)]
            bls = []
            for yy in rr:
                if bls and yy - bls[-1][1] <= 34:
                    bls[-1][1] = yy
                else:
                    bls.append([yy, yy])
            bls = [b for b in bls if b[1] - b[0] >= 60]
            if bls:
                top, bot = bls[-1]
                mask[top:bot + 4, bx0 - 4:bx1 + 4] |= m[top:bot + 4, bx0 - 4:bx1 + 4]
                jobs.append(('pret', [bx0, top + 2, bx1, bot], c['pretendenti']))
            else:
                print('  ! pretendenti non trovati', c['nome_en'])

    # --- one-shot (cartiglio in basso)
    if c.get('oneshot') and c['oneshot'] != 'jihad':
        sx0, sx1 = (205, 470)
        m = ink(a, sx0, 838, sx1, 945, 'darkred2')
        # niente rombo del prestigio richiesto (colorato) né sfondo pallido
        rr = righe(m, sx0, sx1, 838, 945, 3)
        if rr:
            lines = []
            cur = [rr[0], rr[0]]
            for yy in rr[1:]:
                if yy - cur[1] > 3:
                    lines.append(cur)
                    cur = [yy, yy]
                else:
                    cur[1] = yy
            lines.append(cur)
            lines = [l for l in lines if l[1] - l[0] >= 6]
            if lines and c['oneshot'] == 'apostasy':
                lines = lines[:1]
                m[lines[0][1] + 2:, :] = False
            if lines:
                y0, y1 = lines[0][0], lines[-1][1]
                cols = np.where(m[y0:y1 + 1, sx0:sx1].any(axis=0))[0]
                xx0, xx1 = sx0 + cols.min(), sx0 + cols.max()
                if c['oneshot'] == 'tradeshift' and len(lines) >= 3:
                    l3 = lines[-1]
                    m[l3[0]:l3[1] + 1, 346:sx1] = False
                    lines[-1] = l3
                mask[y0:y1 + 1, xx0:xx1 + 1] |= m[y0:y1 + 1, xx0:xx1 + 1]
                jobs.append(('oneshot', [xx0, y0, xx1, y1, [l for l in lines]], c))

    # --- nome e testo storico
    if box:
        x0, y0, x1, y1, main = box
        wh = (a.min(axis=2) > 196)
        cols = np.where(wh[y0 + 1:y0 + 3, x0:x1].any(axis=0))[0] + x0
        if len(cols):
            lx, rx = int(np.percentile(cols, 2)), int(np.percentile(cols, 98))
        else:
            lx, rx = x0 + 60, x1 - 60
        if rx - lx < 150:
            cxb = (x0 + x1) // 2
            lx, rx = cxb - 128, cxb + 128
        tcx = (lx + rx) / 2
        rows = ocr_righe(a, x0 + 8, max(0, y0 - 6), x1 - 8, min(y1 - 10, y0 + 150))
        target = [re.sub('[^a-z0-9]', '', t.lower()) for t in c['nome_en'].split()]
        target = [t for t in target if t]

        target = target + [''.join(target)]

        def buona(t):
            return any(difflib.SequenceMatcher(None, t, q).ratio() >= 0.72 for q in target)
        acc = []
        for r in rows:
            toks = []
            for w in r:
                t = re.sub('[^a-z0-9]', '', w[0].lower())
                if len(t) >= 2 and lx - 10 <= (w[1] + w[3]) / 2 <= rx + 10:
                    toks.append((t, w))
            ytop = min(w[2] for w in r)
            if not toks:
                if acc:
                    break
                continue
            good = [w for t, w in toks if buona(t)]
            if good and len(good) >= 0.6 * len(toks) and (not acc or ytop - acc[-1][1] < 18):
                acc.append([min(w[2] for w in good), max(w[4] for w in good), lx - 4, rx + 4])
            elif acc or ytop > main + 30:
                break
        if not acc:
            # ripiego: le prime righe di parole tutte dentro la linguetta
            for r in rows:
                dentro = [w for w in r if lx - 10 <= w[1] and w[3] <= rx + 10 and len(re.sub('[^A-Za-z]', '', w[0])) >= 2]
                fuori = [w for w in r if not (lx - 10 <= w[1] and w[3] <= rx + 10) and len(re.sub('[^A-Za-z]', '', w[0])) >= 3]
                ytop = min(w[2] for w in r)
                if dentro and not fuori and ytop < main + 20 and (not acc or ytop - acc[-1][1] < 14):
                    acc.append([min(w[2] for w in dentro), max(w[4] for w in dentro), lx, rx])
                elif acc:
                    break
        if not acc and main - y0 > 18:
            acc = [[y0 + 4, main - 3, lx, rx]]
        if acc:
            ty0, ty1 = min(acc[0][0] - 3, y0 + 5), acc[-1][1] + 4
            tx0, tx1 = lx + 3, rx - 3
            title_bottom = ty1
            m = ink(a, tx0, ty0, tx1, ty1, 'dark')
            mask[ty0:ty1, tx0:tx1] |= m[ty0:ty1, tx0:tx1]
            jobs.append(('nome', [tx0, ty0 + 2, tx1, ty1 - 2, lx + 8, rx - 8], c['nome']))
        else:
            print('  ! nome non trovato', c['nome_en'])
        if acc:
            # righe inglesi rimaste fra il titolo e il riquadro (titoli su due righe)
            g = a.astype(int).mean(axis=2)
            sat = a.max(axis=2).astype(int) - a.min(axis=2)
            for yy in range(title_bottom + 1, main + 12):
                riga_crema = ((g[yy, x0 + 12:x1 - 12] > 200) & (sat[yy, x0 + 12:x1 - 12] < 40)).mean()
                if riga_crema > 0.45:
                    scuri = (g[yy, x0 + 8:x1 - 8] < 150) & (sat[yy, x0 + 8:x1 - 8] < 90)
                    mask[yy, x0 + 8:x1 - 8] |= scuri
            main = max(main, title_bottom - 4)
        jobs.append(('testo', [x0, main, x1, y1], c['testo']))

    a_orig = a.copy()
    a = inpaint(a, mask)
    img = Image.fromarray(a)
    d = ImageDraw.Draw(img)

    # riquadro del testo: si ridipinge l'interno (crema uniforme) evitando stemmi e medaglioni colorati
    for kind, rect, data in jobs:
        if kind != 'testo':
            continue
        x0, y0, x1, y1 = rect
        arr = np.asarray(img).copy()
        ix0, iy0, ix1, iy1 = x0 + 9, y0 + 7, x1 - 9, y1 - 9
        sub = arr[iy0:iy1, ix0:ix1].astype(int)
        hs = hsv(arr[iy0:iy1, ix0:ix1])
        col = ((hs[:, :, 1] > 60) & (sub.mean(axis=2) < 235)).astype(np.uint8)
        col = cv2.morphologyEx(col, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        col = cv2.dilate(col, np.ones((7, 7), np.uint8))
        sep = ((hs[:, :, 1] > 30) & (sub.mean(axis=2) < 230)).astype(np.uint8)
        sep = cv2.morphologyEx(sep, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        sep = cv2.morphologyEx(sep, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
        sep = cv2.morphologyEx(sep, cv2.MORPH_CLOSE, np.ones((11, 11), np.uint8))
        col = np.maximum(col, sep)
        n, lab, st, _ = cv2.connectedComponentsWithStats(col)
        prot = []
        for i in range(1, n):
            x, y, w, h, ar = st[i]
            if ar > 300 and h > 20 and w > 20:
                prot.append([ix0 + x - 4, iy0 + y - 4, ix0 + x + w + 4, iy0 + y + h + 4])
        # medaglione in alto a destra (uomo vitruviano) o ritratti sovrapposti
        circ = medaglione(a_orig, x0, y0, x1)
        if circ is not None:
            ccx, ccy, cr = circ
            prot.append([ccx - cr - 4, ccy - cr - 4, ccx + cr + 4, ccy + cr + 4])
        crem = sub[(hs[:, :, 1] < 30) & (sub.mean(axis=2) > 200)]
        bg = tuple(int(v) for v in np.median(crem, axis=0)) if len(crem) else (238, 235, 225)
        keep = np.zeros((iy1 - iy0, ix1 - ix0), np.uint8)
        for i in range(1, n):
            x, y, w, h, ar = st[i]
            if ar > 300 and h > 20 and w > 20:
                comp = (lab == i).astype(np.uint8)
                # riempie i buchi interni del componente (figure con zone chiare)
                cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                cv2.drawContours(keep, cnts, -1, 1, -1)
        keep = cv2.dilate(keep, np.ones((5, 5), np.uint8))
        fillm = keep == 0
        for p in prot:
            if p[0] >= ix1 - 140 and p[1] <= iy0 + 10:
                fillm[max(0, p[1] - iy0):max(0, p[3] - iy0), max(0, p[0] - ix0):max(0, p[2] - ix0)] = False
        region = arr[iy0:iy1, ix0:ix1]
        region[fillm] = bg
        arr[iy0:iy1, ix0:ix1] = region
        img = Image.fromarray(arr)
        d = ImageDraw.Draw(img)
        # testo con rientri accanto ai riquadri protetti
        pad = 6
        tx0, tx1 = ix0 + pad, ix1 - pad
        ty0, ty1 = iy0 + 4, iy1 - 2
        best = None
        for s in range(22, 12, -1):
            f = corpo_f(s)
            lh = int(s * 1.13)

            def wfun(i, lh=lh):
                yy = ty0 + i * lh
                l, r = tx0, tx1
                for p in prot:
                    if p[1] - 2 <= yy + lh and p[3] >= yy:
                        if p[0] - ix0 < (ix1 - ix0) / 2:
                            l = max(l, p[2] + 4)
                        else:
                            r = min(r, p[0] - 4)
                return r - l
            ls = wrap(d, data, f, wfun)
            hh = sum(lh if l is not None else int(lh * 0.45) for l in ls)
            if hh <= ty1 - ty0:
                best = (f, s, lh, ls)
                break
        if best is None:
            f = corpo_f(13)
            lh = 14
            best = (f, 13, lh, wrap(d, data, f, lambda i: tx1 - tx0))
        f, s, lh, ls = best
        yy = ty0
        i = 0
        for l in ls:
            if l is None:
                yy += int(lh * 0.45)
                continue
            l0 = tx0
            for p in prot:
                if p[1] - 2 <= yy + lh and p[3] >= yy and p[0] - ix0 < (ix1 - ix0) / 2:
                    l0 = max(l0, p[2] + 4)
            d.text((l0, yy), l, font=f, fill=(38, 34, 30))
            yy += lh
            i += 1

    for kind, rect, data in jobs:
        if kind == 'nome':
            x0, y0, x1, y1, lx, rx = rect
            arr = np.asarray(img).copy()
            zona = arr[y0 - 4:y1 + 4, x0:x1].reshape(-1, 3)
            chiari = zona[zona.min(axis=1) > 190]
            if len(chiari) > 20:
                bg = np.median(chiari, axis=0).astype(np.uint8)
                arr[y0 - 4:y1 + 4, x0:x1] = bg
                img = Image.fromarray(arr)
                d = ImageDraw.Draw(img)
            cx = (lx + rx) / 2
            maxw = rx - lx - 6
            hbox = max(y1 - y0, 26)
            lines = [data]
            f, s = fit(d, lines, titolo_f, maxw, hbox * 1.25, 30, 14)
            if (s < 22 or hbox > 46) and ' ' in data:
                ws = data.split(' ')
                best = None
                for k in range(1, len(ws)):
                    l1, l2 = ' '.join(ws[:k]), ' '.join(ws[k:])
                    m_ = max(text_w(d, l1, titolo_f(22)), text_w(d, l2, titolo_f(22)))
                    if best is None or m_ < best[0]:
                        best = (m_, [l1, l2])
                f2, s2 = fit(d, best[1], titolo_f, maxw, max(hbox, 46) * 1.1, 28, 13, 1.0)
                if s2 > s + 2 or hbox > 46:
                    lines, f, s = best[1], f2, s2
            hh = len(lines) * s * 1.0
            for i, l in enumerate(lines):
                bb = d.textbbox((0, 0), l, font=f)
                yc = (y0 + y1) / 2 - hh / 2 + i * s + s / 2
                d.text((cx - (bb[2] - bb[0]) / 2 - bb[0], yc - (bb[1] + bb[3]) / 2), l, font=f, fill=(30, 26, 22))
        elif kind == 'op':
            x0, y0, x1, y1 = rect
            t = ETICHETTE[data]
            f, s = fit(d, [t], titolo_f, (x1 - x0) * 0.78, (y1 - y0) * 1.05, 34, 14)
            bb = d.textbbox((0, 0), t, font=f)
            cy = (y0 + y1) / 2
            if data == 'commerce':
                d.text(((x0 + x1) / 2 - (bb[2] - bb[0]) / 2 - bb[0], cy - (bb[1] + bb[3]) / 2), t, font=f,
                       fill=(255, 250, 225), stroke_width=2, stroke_fill=(120, 85, 20))
            else:
                d.text(((x0 + x1) / 2 - (bb[2] - bb[0]) / 2 - bb[0], cy - (bb[1] + bb[3]) / 2), t, font=f,
                       fill=(246, 232, 170), stroke_width=1, stroke_fill=(60, 30, 40))
        elif kind == 'sub':
            x0, y0, x1, y1 = rect
            col = (60, 55, 50) if west else (215, 212, 205)
            f, s, ls = fit_wrap(d, data, sub_f, x1 - x0, max(y1 - y0 + 26, 34), 19, 11, 1.0)
            ls = [l for l in ls if l is not None]
            for i, l in enumerate(ls):
                draw_center(d, (x0 + x1) / 2, y0 - 2 + i * s, l, f, col)
        elif kind == 'luogo':
            x0, y0, x1, y1 = rect
            col = (25, 22, 20) if west else (240, 238, 232)
            lines = data.split('\n')
            f, s = fit(d, lines, lambda z: font('RobotoCondensed.ttf', z, 600), x1 - x0 - 10, max(y1 - y0 + 8, 24) * 1.0, 22, 11, 1.0)
            hh = len(lines) * s
            ytop = (y0 + y1) / 2 - hh / 2 - 2
            for i, l in enumerate(lines):
                draw_center(d, (x0 + x1) / 2, ytop + i * s, l, f, col)
        elif kind == 'pret':
            x0, y0, x1, y1 = rect
            col = (25, 22, 20) if west else (240, 238, 232)
            fh = corpo_b(19)
            d.text((x0 + 8, y0), 'PRETENDENTI', font=fh, fill=col)
            f = corpo_r(19)
            yy = y0 + 25
            for p in data:
                ls = wrap(d, PRETENDENTI[p].replace('\n', ' '), f, lambda i: x1 - x0 - 26)
                for k, l in enumerate([l for l in ls if l]):
                    if k == 0:
                        d.text((x0 + 8, yy), '•', font=f, fill=col)
                    d.text((x0 + 20, yy), l, font=f, fill=col)
                    yy += 20
        elif kind == 'oneshot':
            x0, y0, x1, y1, lines = rect
            cc = data
            cx = (x0 + x1) / 2 if cc["oneshot"] != "tradeshift" else (x0 + x1) / 2
            if cc['oneshot'] == 'tradeshift':
                arg = cc['oneshot_arg']
                tl = ['SPOSTAMENTO COMMERCIALE:', SPOST.get(arg, arg)]
                if len(lines) >= 3:
                    tl.append('RICHIESTO:')
            elif cc['oneshot'] == 'apostasy':
                tl = ['APOSTASIA']
            else:
                tl = list(ONESHOT[cc['oneshot']])
            if len(tl) == 1:
                yc = (lines[0][0] + lines[-1][1]) / 2 if cc['oneshot'] != 'apostasy' else (lines[0][0] + lines[0][1]) / 2
                hh = lines[-1][1] - lines[0][0] if cc['oneshot'] != 'apostasy' else lines[0][1] - lines[0][0]
                f, s = fit(d, tl, titolo_f, 205, max(hh * 1.4, 22), 30, 12)
                bb = d.textbbox((0, 0), tl[0], font=f)
                d.text((cx - (bb[2] - bb[0]) / 2 - bb[0], yc - (bb[1] + bb[3]) / 2), tl[0], font=f, fill=(48, 40, 34))
            else:
                for i, t in enumerate(tl):
                    li = lines[min(i, len(lines) - 1)]
                    if len(tl) == 2 and len(lines) == 1:
                        li = [lines[0][0] + i * (lines[0][1] - lines[0][0]) // 2, lines[0][0] + (i + 1) * (lines[0][1] - lines[0][0]) // 2]
                    hh = li[1] - li[0] + 2
                    big = (cc['oneshot'] == 'revolt') or (i == 1)
                    fm = titolo_f if big else (lambda z: corpo_b(z))
                    colr = (150, 35, 30) if t == 'RICHIESTO:' else (48, 40, 34)
                    f, s = fit(d, [t], fm, 210 if t != 'RICHIESTO:' else 120, max(hh * 1.5, 14), 30, 9)
                    bb = d.textbbox((0, 0), t, font=f)
                    xx = cx - (bb[2] - bb[0]) / 2 - bb[0]
                    if t == 'RICHIESTO:':
                        xx = x0
                    d.text((xx, (li[0] + li[1]) / 2 - (bb[1] + bb[3]) / 2), t, font=f, fill=colr)
        elif kind == 'nota':
            x0, y0, x1, y1 = rect
            testo = data
            rosso = testo.startswith('!')
            testo = testo.lstrip('!')
            col = (165, 30, 25) if rosso else (30, 26, 22)
            if ':' in testo and not rosso:
                head, body = testo.split(':', 1)
                head = head.strip() + ':'
                body = body.strip()
            else:
                head, body = '', testo
            maxh = (y1 - y0) + 12
            for s in range(20, 9, -1):
                fh = corpo_b(s)
                fb = corpo_r(s)
                lsh = wrap(d, head, fh, lambda i: x1 - x0) if head else []
                lsb = wrap(d, body, fb, lambda i: x1 - x0)
                if (len(lsh) + len(lsb)) * s * 1.02 <= maxh:
                    break
            yy = y0
            for l in lsh:
                d.text((x0, yy), l, font=fh, fill=col)
                yy += s * 1.02
            for l in lsb:
                if l is None:
                    continue
                d.text((x0, yy), l, font=fb, fill=col)
                yy += s * 1.02
    return img


def main():
    src = sys.argv[1]
    only = sys.argv[2:]
    carte = json.load(open(os.path.join(R, 'data', 'carte.json'), encoding='utf-8'))
    raw = carica_raw()
    out = os.path.join(R, 'assets', 'carte')
    os.makedirs(out, exist_ok=True)
    for c in carte:
        if c.get('cometa'):
            continue
        if only and c['img'] not in only:
            continue
        img = localizza(os.path.join(src, c['img'] + '.jpg'), c, raw.get(c['img']), None)
        img.save(os.path.join(out, c['img'] + '.webp'), quality=84)
    print('fatto')


if __name__ == '__main__':
    main()
