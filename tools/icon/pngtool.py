"""Minimal pure-Python PNG reader/writer (no Pillow on this machine)."""
import struct, zlib

def _chunks(raw):
    i = 8
    while i < len(raw):
        ln, typ = struct.unpack(">I4s", raw[i:i+8])
        yield typ, raw[i+8:i+8+ln]
        i += 12 + ln

def read_png(path):
    raw = open(path, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n"
    ihdr = None; idat = b""; plte = None; trns = None
    for typ, data in _chunks(raw):
        if typ == b"IHDR": ihdr = data
        elif typ == b"IDAT": idat += data
        elif typ == b"PLTE": plte = data
        elif typ == b"tRNS": trns = data
    w, h, bd, ct, cm, fl, il = struct.unpack(">IIBBBBB", ihdr)
    assert bd == 8 and il == 0, f"only 8-bit non-interlaced supported (got bd={bd} il={il})"
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    data = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = data[pos]; pos += 1
        line = bytearray(data[pos:pos+stride]); pos += stride
        if f == 1:
            for i in range(nch, stride): line[i] = (line[i] + line[i-nch]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-nch] if i >= nch else 0
                b = prev[i]
                c = prev[i-nch] if i >= nch else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y*stride:(y+1)*stride] = line
        prev = line
    # expand to RGBA
    rgba = bytearray(w*h*4)
    if ct == 6:
        rgba[:] = out
    elif ct == 2:
        for i in range(w*h):
            rgba[i*4:i*4+3] = out[i*3:i*3+3]; rgba[i*4+3] = 255
    elif ct == 0:
        for i in range(w*h):
            v = out[i]; rgba[i*4:i*4+3] = bytes((v, v, v)); rgba[i*4+3] = 255
    elif ct == 4:
        for i in range(w*h):
            v = out[i*2]; rgba[i*4:i*4+3] = bytes((v, v, v)); rgba[i*4+3] = out[i*2+1]
    elif ct == 3:
        pal = [(plte[i*3], plte[i*3+1], plte[i*3+2]) for i in range(len(plte)//3)]
        for i in range(w*h):
            r, g, b = pal[out[i]]
            rgba[i*4:i*4+4] = bytes((r, g, b, trns[out[i]] if trns and out[i] < len(trns) else 255))
    return w, h, rgba

def write_png(path, w, h, rgba, level=9):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)  # filter none
        raw += rgba[y*stride:(y+1)*stride]
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), level))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)

def resize_box(w, h, rgba, nw, nh):
    """Area-average (box) resample; premultiplied to avoid dark halos."""
    out = bytearray(nw*nh*4)
    xr = w / nw; yr = h / nh
    for oy in range(nh):
        y0, y1 = int(oy*yr), max(int(oy*yr)+1, int((oy+1)*yr))
        for ox in range(nw):
            x0, x1 = int(ox*xr), max(int(ox*xr)+1, int((ox+1)*xr))
            r = g = b = a = n = 0
            for y in range(y0, y1):
                base = y*w*4
                for x in range(x0, x1):
                    i = base + x*4
                    al = rgba[i+3]
                    r += rgba[i]*al; g += rgba[i+1]*al; b += rgba[i+2]*al
                    a += al; n += 1
            o = (oy*nw+ox)*4
            if a:
                out[o] = r//a; out[o+1] = g//a; out[o+2] = b//a
            out[o+3] = a//n
    return out
