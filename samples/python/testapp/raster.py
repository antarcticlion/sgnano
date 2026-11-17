# Raster operation list demo (MicroPython port, 2026-10-30).  Ported from samples/ruby/raster.rb.
# Two uint8_t sine tables (512 and 384 entries, 128 = no move). Each frame the start position advances by 1
# (mod 512 / 384) and the values are copied to every display line: BG0 uses the 512 table, BG1 the 384 table.
# 3/4/5/6 mode, r raster list, b BG planes, o/O objects, v speed, S scroll, q/ESC ends.
import math
lr = M.lowres
mode = 5
raster_on = True
scroll_on = True
bg_mask = 3
obj_count = 24
obj_demo = 1
odiv = 4
pox = 0.0; poy = 0.0
oph = 0.0
ph0 = 0; ph1 = 0
sy0 = 0; sy1 = 0; sx1 = 0

TAB0 = bytes([int(128 + 96 * math.sin(2 * math.pi * i / 512)) for i in range(512)])
TAB1 = bytes([int(128 + 96 * math.sin(2 * math.pi * i / 384 + 0.8)) for i in range(384)])

# BG0: one mesh cell is 4x4 map tiles = 32x32 pixels (a 2-pixel border; the inside is transparent).
# BG1: one mesh cell is one 8x8 tile (a 1-pixel grid; the gaps are transparent).
COARSE = [(1 if (i % 32 < 2 or i % 32 >= 30 or i // 32 < 2 or i // 32 >= 30) else 128) for i in range(32 * 32)]
FINE = [(2 if ((i % 8) == 0 or (i // 8) == 0) else 128) for i in range(64)]
DISC_TILE = (340, 336, 320, 256)          # 8, 16, 32, 64 (tile = 64-byte unit)
DISC_SIZE = (8, 16, 32, 64)
SINT = [int(127 * math.sin(2 * math.pi * i / 64)) for i in range(64)]
BARS = ((31, 31, 31), (31, 31, 0), (0, 31, 31), (0, 31, 0), (31, 0, 31), (31, 0, 0), (0, 0, 31), (0, 0, 0))

def c8(v): return v * 255 // 31

def draw_fb_pattern():
    fb = M.fb
    bits = fb.bits_per_pixel
    for i, c in enumerate(BARS):
        M.fb_palette(i, c8(c[0]), c8(c[1]), c8(c[2]))
    if bits == 8:
        for v in range(32):
            M.fb_palette(8 + v, c8(v), 0, 0); M.fb_palette(40 + v, 0, c8(v), 0)
            M.fb_palette(72 + v, 0, 0, c8(v)); M.fb_palette(104 + v, c8(v), c8(v), c8(v))
        M.fb_palette(136, 255, 255, 255)
        def grad(band, v): return 8 + band * 32 + v
        border = 136
    else:
        for i in range(8):
            v = c8(i * 31 // 7); M.fb_palette(8 + i, v, v, v)
        def grad(band, v): return 8 + v
        border = 0
    for i in range(8):
        fb.fill_rect(i * 80, 0, 80, 240, i)
    if bits == 4:
        for i in range(16):
            fb.fill_rect(i * 40, 240, 40, 240, i)
    else:
        for band in range(4):
            for v in range(32):
                fb.fill_rect(v * 20, 240 + band * 60, 20, 60, grad(band, v))
    fb.rect(0, 0, 640, 480, border)

def ramp(pal, r, g, b):                    # 128 colours from dark to bright
    for c in range(128):
        lr.palette(pal, c, r * 255 // 31 * c // 127, g * 255 // 31 * c // 127, b * 255 // 31 * c // 127)

def disc(tile, size):                      # bright centre, darker edge, transparent outside
    c = size // 2; rr = c * c
    lr.pattern(tile, [128 if ((i % size - c) ** 2 + (i // size - c) ** 2) >= rr
                      else 127 - ((i % size - c) ** 2 + (i // size - c) ** 2) * 127 // rr
                      for i in range(size * size)])

def setup_lowres():
    lr.clear()
    lr.pattern(0, [128] * 64)              # transparent tile for the inside of the coarse mesh
    lr.pattern(3, COARSE)                  # 32x32 = 16 tiles
    lr.pattern(2, FINE)
    lr.fill_map(0, 0, 0)
    for ty in range(64):                   # a 32x32 mesh block every 4x4 map tiles
        for tx in range(64):
            if tx % 4 == 0 and ty % 4 == 0:
                lr.map(0, tx, ty, 3, 0)
    lr.fill_map(1, 2, 0)
    # mesh palettes 8..15 (the raster CLUT base keeps objects on 1..5)
    for p in range(8):
        lr.palette(8 + p, 1, 255, 40 + p * 12, 0)
        lr.palette(8 + p, 2, 0, 120 + p * 8, 255 - p * 12)
        lr.palette(8 + p, 3, 240, 240, 240)
    # objects: the five ramps (white, green, orange, blue, red)
    ramp(1, 31, 31, 31); ramp(2, 8, 31, 12); ramp(3, 31, 22, 6); ramp(4, 10, 18, 31); ramp(5, 31, 10, 10)
    for k, size in enumerate(DISC_SIZE):
        disc(DISC_TILE[k], size)

def setup_raster_static():
    lr.raster_clear()
    y = 0
    while y < 480:
        a = math.sin(2 * math.pi * y / 240)
        lr.backdrop(y, int(64 + 48 * a), 24, int(128 - 64 * a))
        lr.raster(0, y, 8 + (y // 12) % 8, 0, 0)
        lr.raster(1, y, 8 + (y // 6) % 8, 0, 0)
        y += 1

def setup_objects(count, heavy=False):
    for i in range(128):
        lr.obj_hide(i)
    for i in range(count):
        k = 3 if heavy else i % 4
        w = DISC_SIZE[k]
        lr.obj(i, 160 - w // 2, 120 - w // 2, DISC_TILE[k], w, w, 1 + (i % 5), i % 3)
        if heavy:
            lr.obj_move(i, 96 + (i % 8) * 4, 72 + (i // 8 % 8) * 4)
    lr.obj_visible = True

def show_bg(mask):
    lr.bg_visible(0, (mask & 1) != 0)
    lr.bg_visible(1, (mask & 2) != 0)

def pad_objects():
    global pox, poy
    lx, ly = M.pad_stick(0, "left")
    dx, dy = M.pad_dir(0)
    vx = (lx * 4 if lx != 0.0 else dx * 3) / odiv
    vy = (ly * 4 if ly != 0.0 else dy * 3) / odiv
    pox = max(-150.0, min(pox + vx, 150.0))
    poy = max(-110.0, min(poy + vy, 110.0))
    if M.pad_pressed(0, M.PAD_A):
        pox = 0.0; poy = 0.0

def move_objects(ph):
    if obj_count == 0:
        return
    ox = int(pox); oy = int(poy)
    for i in range(obj_count):
        w = DISC_SIZE[i % 4]
        # Keep the phase fractional and interpolate between SINT entries (same as mode4-6).
        # At 1/4 speed the objects still move every frame.
        a = ph * (1 + (i & 3)) / 2.0 + i * 5
        b = ph * (1 + ((i >> 2) & 3)) / 3.0 + i * 11
        ai = int(a); af = a - ai
        bi = int(b); bf = b - bi
        sa = SINT[ai & 63] + (SINT[(ai + 1) & 63] - SINT[ai & 63]) * af
        sb = SINT[bi & 63] + (SINT[(bi + 1) & 63] - SINT[bi & 63]) * bf
        lr.obj_move(i, int(round(160 - w // 2 + ox + sa * 140 / 127)),
                       int(round(120 - w // 2 + oy + sb * 100 / 127)))

def help_text(mode):
    if mode == 6:
        return
    M.text_clear(M.TEXT_CLEAR)
    M.text_put(1, 1, "RASTER 3-6: mode  r: list  b: BG  o/O: objects  v: speed  S: scroll  q: quit",
               M.tattr(15, 0, M.TEXT_BG_TRANSPARENT))

def start_mode(n, raster_on, bg_mask):
    global obj_count, obj_demo
    M.mode = n
    M.text_visible = (n != 6)
    if n == 3 or n == 4:
        draw_fb_pattern()
    setup_lowres()
    obj_count = 24; obj_demo = 1
    setup_objects(24)
    if raster_on:
        setup_raster_static()
    else:
        lr.raster_clear()
    show_bg(bg_mask)
    help_text(n)
    print("raster: mode %d (raster %s)" % (n, "on" if raster_on else "off"))

start_mode(mode, raster_on, bg_mask)
oph = 0.0
olast = M.ms()
while True:
    k = M.key()
    k = -1 if k is None else k
    if k == 113 or k == 27:
        break
    if 51 <= k <= 54:
        mode = k - 48
        start_mode(mode, raster_on, bg_mask)
    elif k == 114:                             # r
        raster_on = not raster_on
        if raster_on:
            setup_raster_static()
        else:
            lr.raster_clear()
        help_text(mode)
        print("raster: list %s" % ("on" if raster_on else "off"))
    elif k == 98:                              # b
        bg_mask = (bg_mask + 1) & 3
        show_bg(bg_mask)
        print("raster: BG %d" % bg_mask)
    elif k == 111:                             # o
        if obj_count == 0:
            obj_count = 24; obj_demo = 1
        elif obj_count >= 128:
            obj_count = 0; obj_demo = 0; lr.obj_visible = False
        else:
            obj_count *= 2
            if obj_count > 128: obj_count = 128
            obj_demo = 1
        if obj_count > 0:
            setup_objects(obj_count)
        print("raster: objects #%d" % obj_count)
    elif k == 79:                              # O: load test
        if obj_demo == 2:
            obj_count = 24; obj_demo = 1; setup_objects(24)
        else:
            obj_count = 128; obj_demo = 2; setup_objects(128, True)
        print("raster: load test %s" % ("on" if obj_demo == 2 else "off"))
    elif k == 118:                             # v
        odiv = 1 if odiv == 1 else odiv // 2
        print("raster: speed 1/%d" % odiv)
    elif k == 83:                              # S
        scroll_on = not scroll_on
        print("raster: scroll %s" % ("on" if scroll_on else "off"))
    if scroll_on:
        if raster_on:
            lr.raster_wave(0, TAB0, ph0)
            lr.raster_wave(1, TAB1, ph1)
            ph0 = (ph0 + 1) % 512
            ph1 = (ph1 + 1) % 384
        # BG0 scrolls up (sy grows); BG1 scrolls down (sy shrinks) and right (sx shrinks) by one dot
        lr.scroll(0, 0, sy0)
        lr.scroll(1, sx1, sy1)
        sy0 = (sy0 + 2) & 511
        sy1 = (sy1 - 2) & 511
        sx1 = (sx1 - 1) & 511
    now = M.ms()
    oph += (now - olast) * 60 / 1000.0 / odiv
    olast = now
    if obj_count > 0 and obj_demo == 1:
        pad_objects()
        move_objects(oph)
    M.vsync()
lr.clear()                                # lowres raster list (backdrop / CLUT / scroll) back to defaults
M.mode = 2                                # the framebuffer is left untouched
print("bye")
