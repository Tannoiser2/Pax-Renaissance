#!/usr/bin/env python3
"""Disegna le pedine (sprite PNG) dai modelli 3D del modulo TTS con un piccolo rasterizzatore.
Uso: python3 tools/rendi_pezzi.py <cartella Models del modulo> <cartella di uscita>"""
import sys, glob, os, numpy as np
from PIL import Image

def load_obj(p):
    V, F = [], []
    for l in open(p, errors='ignore'):
        if l.startswith('v '):
            V.append([float(x) for x in l.split()[1:4]])
        elif l.startswith('f '):
            idx = [int(t.split('/')[0]) for t in l.split()[1:]]
            for i in range(1, len(idx) - 1):
                F.append([idx[0] - 1, idx[i] - 1, idx[i + 1] - 1])
    return np.array(V), np.array(F)

def render(V, F, color, size=256, yaw=30, pitch=18, ss=3):
    V = V - (V.min(0) + V.max(0)) / 2
    a, b = np.radians(yaw), np.radians(pitch)
    Ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(b), -np.sin(b)], [0, np.sin(b), np.cos(b)]])
    P = V @ Ry.T @ Rx.T
    S = size * ss
    sc = 0.9 * S / max(np.ptp(P[:, 0]), np.ptp(P[:, 1]))
    X = (P[:, 0] - P[:, 0].min()) * sc + (S - np.ptp(P[:, 0]) * sc) / 2
    Y = (P[:, 1].max() - P[:, 1]) * sc + (S - np.ptp(P[:, 1]) * sc) / 2
    Z = P[:, 2]
    img = np.zeros((S, S, 4))
    zb = np.full((S, S), -1e9)
    light = np.array([-0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
    col = np.array(color) / 255.0
    for f in F:
        p0, p1, p2 = P[f]
        n = np.cross(p1 - p0, p2 - p0)
        nn = np.linalg.norm(n)
        if nn == 0: continue
        n /= nn
        if n[2] < 0: n = -n
        sh = 0.38 + 0.62 * max(0, n @ light) + 0.18 * n[2] ** 8
        xs, ys, zs = X[f], Y[f], Z[f]
        x0, x1 = int(max(0, xs.min())), int(min(S - 1, xs.max()) + 1)
        y0, y1 = int(max(0, ys.min())), int(min(S - 1, ys.max()) + 1)
        if x1 <= x0 or y1 <= y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9: continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
        sub = zb[y0:y1, x0:x1]
        m &= z > sub
        sub[m] = z[m]
        img[y0:y1, x0:x1][m] = list(np.clip(col * sh, 0, 1)) + [1]
    # contorno scuro
    al = img[:, :, 3]
    im = Image.fromarray((img * 255).astype(np.uint8), 'RGBA').resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(float)
    alpha = a[:, :, 3] / 255
    from scipy.ndimage import binary_dilation
    ring = binary_dilation(alpha > 0.5, iterations=2) & ~(alpha > 0.5)
    a[ring] = [25, 20, 15, 220]
    return Image.fromarray(a.astype(np.uint8), 'RGBA')

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
M = {'R': '8E80BCB1C9FA2F7405692B', 'B': 'D3BD3E16B1718911BA1098', 'K': 'EF9661F8809FFB7EE86D3D',
     'P': '6C7482B0E9E0DEEB13C767', 'S': '5F0E1F922EBA51F1BCED0E'}
REL = {'C': (205, 175, 70), 'I': (40, 140, 125), 'R': (175, 50, 45)}
PL = {'Fugger': (45, 115, 235), 'Medici': (235, 205, 45), 'Coeur': (150, 65, 215), 'Marchionni': (65, 170, 60)}
for k, h in M.items():
    V, F = load_obj(glob.glob(os.path.join(src, '*' + h + '.obj'))[0])
    if k == 'P':
        for n, c in PL.items():
            render(V, F, c, yaw=20).save(os.path.join(dst, 'P_%s.png' % n))
    else:
        for r, c in REL.items():
            render(V, F, c, yaw=(12 if k == 'S' else 30), pitch=(-14 if k == 'S' else 15)).save(os.path.join(dst, '%s_%s.png' % (k, r)))
print('ok')
