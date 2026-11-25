import numpy as np, cv2, json
from PIL import Image
COL={'behead':'P','tax':'P','repress':'P','vote':'P','siege':'R','corsair':'R','campaign':'R','inq':'B','commerce':'G'}
def masks(a):
    hsv=cv2.cvtColor(a,cv2.COLOR_RGB2HSV)
    h,s,v=hsv[:,:,0].astype(int),hsv[:,:,1].astype(int),hsv[:,:,2].astype(int)
    return {'P':(h>=120)&(h<=150)&(s>70)&(v>50),
            'R':((h<=8)|(h>=170))&(s>110)&(v>60),
            'B':(h>=98)&(h<=118)&(s>110)&(v>70),
            'G':(h>=14)&(h<=32)&(s>120)&(v>120)}
def blobs(m, x0, x1, ymin, k):
    m=m.astype(np.uint8).copy(); m[:, :x0]=0; m[:,x1:]=0; m[:ymin]=0; m[905:]=0
    m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,np.ones((7,7),np.uint8))
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((k,k),np.uint8))
    n,lab,st,_=cv2.connectedComponentsWithStats(m)
    return [st[i] for i in range(1,n) if st[i][2]>=110 and st[i][3]>=70 and st[i][4]>4000]
def find(a, ops, west, queen=False):
    M=masks(a)
    x0,x1=(470,653) if west else (0,185)
    out=[]; ymin=0 if queen else 105
    for op in ops:
        k=COL[op.split(':')[0]]
        best=None
        for ker in (5,11,17,25):
            cand=[b for b in blobs(M[k],x0,x1,ymin,ker) if b[3]<=135 and b[2]<=190]
            if cand:
                cand.sort(key=lambda b:b[1]); best=cand[0]; break
        if best is None: out.append(None); continue
        b=best; out.append([int(b[0]),int(b[1]),int(b[2]),int(b[3])]); ymin=int(b[1]+b[3]-10)
    return out
