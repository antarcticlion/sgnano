# sgnano test application in MicroPython -- mode 4: text + lowres + CLUT4 framebuffer.
# Ported from samples/ruby/testapp/mode3.rb (2026-10-30).  M, Sound, File are in the prelude.
# Keys: m music pause, t text on/off, pad move objects (A: middle), v speed 1/4 1/2 1, l lowres on/off,
#       b BG planes, o objects, O object load test, S scroll, F font table, f bold font. q or ESC ends it.
import math
M.mode = 4

# ---- text demo and status rows ----
TA = M.TEXT_BG_TRANSPARENT
def tput(row, s, fg):
    s = s[:74]
    M.text_put(2, row, ljust(s, 74), M.tattr(fg, 0, TA))
def text_demo(help):
    M.text_clear(M.TEXT_CLEAR)
    M.text_put(2, 0, "sgnano  ABCabc012  ｱｲｳｴｵ  あいう漢字ＡＢＣ", M.tattr(15, 0, TA))
    for i in range(16):
        M.text_put(2 + i, 1, " ", M.tattr(0, i))
    M.text_put(19, 1, help[:59], M.tattr(7, 0, TA))

ROW_VIDEO = 3; ROW_FRAME = 4; ROW_SYS = 5; ROW_USB = 6; ROW_KBD = 8; ROW_ECHO = 9
ROW_MOUSE = 10; ROW_MSC = 12; ROW_PAD = 16; ROW_PADUI = 20
echo = ""; keys_n = 0
def status_video(v):
    tput(ROW_VIDEO, "%-22s mode %-16s fb %-6s %d.%03dkHz %.2fHz" % (
        v["timing"], v["mode_name"], v["fb"], v["line_hz"] // 1000, v["line_hz"] % 1000, v["frame_hz"]), 11)
def status_frame(v):
    pm = v["pair_max"]
    tput(ROW_FRAME, "f%-8d ur%-5d st%-5d rc%-3d lt%d/%d  pair %d/%dus" % (
        v["frames"], v["underrun"], v["fifo_stall"], v["recover"], v["late_start"], v["late_render"], pm[0], pm[1]), 11)
def status_sys(s):
    tput(ROW_SYS, "up %ds  mem free %dK (max %dK)  python" % (
        s["uptime"], s["mem_free"] // 1024, s["mem_largest"] // 1024), 10)
def status_usb(s):
    tput(ROW_USB, "usb dev %d hub %d  pad %d  reinit %d wedged %d" % (
        s["usb_devices"], s["hubs"], s["pads"], s["usb_reinit"], s["usb_wedged"]), 10)
def status_kbd(s):
    l = s["kbd_leds"]
    tput(ROW_KBD, "kbd %s %04X:%04X n=%-5d led %s%s%s" % (
        "ok " if s["keyboard"] else "-- ", s["kbd_vid"], s["kbd_pid"], keys_n,
        "N" if (l & 1) else "-", "C" if (l & 2) else "-", "S" if (l & 4) else "-"), 14)
    tput(ROW_ECHO, echo, 15)
def status_mouse():
    m = M.mouse()
    b = m["buttons"]
    tput(ROW_MOUSE, "mouse %s  btn %s%s%s" % (
        "ok" if m["connected"] else "--", "L" if (b & 1) else "-", "M" if (b & 4) else "-", "R" if (b & 2) else "-"), 14)
    tput(ROW_MOUSE + 1, "x %+7d  y %+7d  wheel %+5d" % (
        max(-999999, min(m["x"], 999999)), max(-999999, min(m["y"], 999999)), max(-999999, min(m["wheel"], 999999))), 15)
def status_msc(k):
    d = M.storage(k)
    tput(ROW_MSC + k, "msc%d %s %s %dMB" % (k, d["vendor"], d["product"], d["mb"]) if d else "msc%d --" % k, 10)
AXIS = ("X", "Y", "Z", "Rx", "Ry", "Rz")
def status_pad(k, pd):
    if pd:
        s = "p%d %04X:%04X h%d" % (k, pd["vid"], pd["pid"], pd["hat"])
        for i, a in enumerate(pd["axes"]):
            if a:
                s += " %s%+4d" % (AXIS[i], a)
        n = pd["buttons_n"]
        if n > 0:
            s += " "
            for i in range(min(n, 20)):
                s += str((i % 9) + 1) if ((pd["buttons"] >> i) & 1) else "."
        tput(ROW_PAD + k, s, 14)
    else:
        tput(ROW_PAD + k, "p%d --" % k, 14)
slow = 0
def status_tick():
    global slow
    k = slow % 11
    slow += 1
    v = M.video_info(); s = M.sys_info()
    if k == 0: status_video(v)
    elif k == 1: status_sys(s)
    elif k == 2: status_usb(s)
    elif k < 7: status_msc(k - 3)
    status_frame(v)
    status_kbd(s)
    status_mouse()
    if s["pads"] > 0 or k >= 7:
        for p in range(4):
            pd = M.pad(p)
            if pd or k == 7 + p:
                status_pad(p, pd)
def key_echo(c):
    global echo, keys_n
    keys_n += 1
    echo += chr(c) if 0x20 <= c < 0x7F else "."
    if len(echo) > 60:
        echo = echo[-60:]

KEY_ROW = 21
def key_help(list):
    M.text_put(2, KEY_ROW, "-- keys " + "-" * 66, M.tattr(8, 0, TA))
    for i, (k, d) in enumerate(list):
        x = 2 + (i % 2) * 38; y = KEY_ROW + 1 + i // 2
        M.text_put(x, y, rjust(k, 7), M.tattr(14, 0, TA))
        M.text_put(x + 8, y, d[:29], M.tattr(7, 0, TA))

# ---- test pattern on the framebuffer ----
BARS = ((31, 31, 31), (31, 31, 0), (0, 31, 31), (0, 31, 0), (31, 0, 31), (31, 0, 0), (0, 0, 31), (0, 0, 0))
def c8(v): return v * 255 // 31
def draw_pattern():
    fb = M.fb
    bits = fb.bits_per_pixel
    if bits == 16:
        def col(r, g, b): return M.rgb(c8(r), c8(g), c8(b))
        bar = [col(*c) for c in BARS]
        def grad(band, v):
            return (col(v, 0, 0), col(0, v, 0), col(0, 0, v), col(v, v, v))[band]
        border = col(31, 31, 31)
    else:
        for i, c in enumerate(BARS):
            M.fb_palette(i, c8(c[0]), c8(c[1]), c8(c[2]))
        bar = list(range(8))
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
        fb.fill_rect(i * 80, 0, 80, 240, bar[i])
    if bits == 4:
        for i in range(16):
            fb.fill_rect(i * 40, 240, 40, 240, i)
    else:
        for band in range(4):
            for v in range(32):
                fb.fill_rect(v * 20, 240 + band * 60, 20, 60, grad(band, v))
    fb.rect(0, 0, 640, 480, border)

# ---- lowres demo ----
LR = M.lowres
FONT8 = (
    "00000000000000003030302020002000505000000000000050f8505050f850002078a07028f0200000c8d02058980000"
    "60a040a0a890780020200000000000003040404040403000601010101010600020a8702070a82000002020f820200000"
    "0000000000101020000000f80000000000000000000010000008102040800000708898a8c8887000206020202020f800"
    "708808708080f800708808700888700030509090f8101000f88080f008887000708880f088887000f808102020202000"
    "708888708888700070888878088870000030300000303000003030000030306010204080402010000000f800f8000000"
    "402010081020400070880830200030007088a8a8b8807800708888f888888800f08888f08888f0007088808080887000"
    "f08888888888f000f88080f08080f800f88080f080808000708880b888887800888888f8888888007020202020207000"
    "08080808088870008890a0c0a0908800808080808080f80088d8a8888888880088c8c8a8989888007088888888887000"
    "f08888f08080800070888888a8906800f08888f0888888007088807008887000f8202020202020008888888888887000"
    "888888505020200088888888a8d8880088885020508888008888502020202000f80810204080f8007040404040407000"
    "888850f820f8200070101010101070002050880000000000000000000000f80080402000000000000000689888887800"
    "8080f0888888f0000000708880887000080878888888780000007088f8807800102020f82020200000007888887808f0"
    "808080f08888880020002020202020000800080808080870808890a0e090880020202020202030000000f0a8a8a8a800"
    "0000f08888888800000070888888700000b0c88888f0808000788888780808060000b8c080808000000078807008f000"
    "2020f82020202000000088888888780000008888885020000000a8a8a8a85800000088502050880000888888780808f0"
    "0000f8102040f80018202040202018002020200020202000c02020102020c000000040a810000000"
)
SPR = (340, 336, 320, 256)
SINT = [int(127 * math.sin(2 * math.pi * i / 64)) for i in range(64)]
WAVE0 = bytes([int(128 + 96 * math.sin(2 * math.pi * i / 512)) for i in range(512)])
font_bold = False
labels = {}
lr_on = True
table = False
scroll = True
sx0 = 0
bg = 3
obj_demo = 0
obj_count = 24
pox = 0; poy = 0
odiv = 4; oph = 0.0; olast = 0
t0 = 0; ph = 0; wphase = 0; wave_on = False
keylab = None
KEYLAB_ROW = 1

def load_font(bold):
    global font_bold
    font_bold = bold
    LR.pattern(0, [128] * 64)
    for code in range(0x20, 0x7F):
        o = (code - 0x20) * 16
        data = []
        for y in range(8):
            r = int(FONT8[o + y * 2:o + y * 2 + 2], 16)
            if bold:
                r |= r >> 1
            for x in range(8):
                data.append(127 if (r & (0x80 >> x)) != 0 else 128)
        LR.pattern(code, data)
def ramp(pal, r, g, b):
    for c in range(128):
        LR.palette(pal, c, r * 255 // 31 * c // 127, g * 255 // 31 * c // 127, b * 255 // 31 * c // 127)
def disc(tile, size):
    c = size // 2; rr = c * c
    data = []
    for i in range(size * size):
        x = i % size - c; y = i // size - c; d = x * x + y * y
        data.append(128 if d >= rr else 127 - d * 127 // rr)
    LR.pattern(tile, data)
PLUS = ord("+"); DASH = ord("-"); BAR = ord("|"); SP = ord(" ")
def grid_code(tx, ty):
    if tx % 8 == 0:
        return PLUS if ty % 8 == 0 else BAR
    elif ty % 8 == 0:
        return DASH
    return SP
def grid_row(ty):
    for tx in range(64):
        LR.map(0, tx, ty, grid_code(tx, ty), 4, tx >= 32, ty >= 32)
def build_bg0():
    global labels
    for ty in range(64):
        grid_row(ty)
    labels = {}
MSG = ("SGNANO LOWRES BG PLANE  ", "320x240 CLUT7 128COLORS ", "64x64 TILEMAP 8x8 TILE  ",
       "SCROLL WRAPS AT 512PIX  ", "PALETTE 64 x 128 COLORS ", "TWO CORES RENDER PAIRS  ")
MSGW = []
for line in MSG:
    ln = len(line)
    row = []
    for p in range(ln):
        if line[p] == " ":
            row.append((SP, SP, -1))
        else:
            s = p; e = p
            while s > 0 and line[s - 1] != " ":
                s -= 1
            while e + 1 < ln and line[e + 1] != " ":
                e += 1
            word = sum(1 for i in range(s) if line[i] != " " and (i == 0 or line[i - 1] == " "))
            row.append((ord(line[p]), ord(line[s + e - p]), word))
    MSGW.append(row)
def build_map():
    for ty in range(64):
        w = MSGW[ty % len(MSG)]; ln = len(w); pal = ty % 4
        for tx in range(64):
            c = w[(tx + ty) % ln]
            k = 0 if c[2] < 0 else (c[2] + ty) % 4
            if k == 1:
                LR.map(1, tx, ty, c[1], pal, True, False)
            else:
                LR.map(1, tx, ty, c[0], pal, False, k == 3)
    build_bg0()
def build_font_table():
    LR.fill_map(1, 0x20)
    hexd = "0123456789ABCDEF"
    for n in range(16):
        LR.map(1, 3 + n * 2, 1, ord(hexd[n]), 1)
        LR.map(1, 1, 3 + n, ord(hexd[n]), 1)
    for r in range(16):
        for c in range(16):
            LR.map(1, 3 + c * 2, 3 + r, r * 16 + c, 0)
def setup_objects(heavy):
    global obj_demo, obj_count
    n = 128 if heavy else obj_count
    for i in range(128):
        if i >= n:
            LR.obj_hide(i)
            continue
        k = 3 if heavy else i % 4
        w = 8 << k
        LR.obj(i, 0, 0, SPR[k], w, w, 1 + i % 5, i % 3)
        if heavy:
            LR.obj_move(i, 96 + (i % 8) * 4, 72 + (i // 8 % 8) * 4)
    LR.obj_visible = True
    obj_demo = 2 if heavy else 1
def speed_key(c):
    global odiv
    if c != ord("v"):
        return False
    odiv = 4 if odiv == 1 else odiv // 2
    return True
def pad_objects():
    global pox, poy
    lx, ly = M.pad_stick(0, "left")
    dx, dy = M.pad_dir(0)
    vx = (lx * 4 if lx != 0.0 else dx * 3) / odiv
    vy = (ly * 4 if ly != 0.0 else dy * 3) / odiv
    pox = max(-150, min(pox + vx, 150)); poy = max(-110, min(poy + vy, 110))
    if M.pad_pressed(0, M.PAD_A):
        pox = 0; poy = 0
def move_objects(ph):
    ox = int(pox); oy = int(poy)
    for i in range(obj_count):
        w = 8 << (i % 4)
        a = ph * (1 + (i & 3)) / 2.0 + i * 5
        b = ph * (1 + ((i >> 2) & 3)) / 3.0 + i * 11
        ai = int(a); af = a - ai
        bi = int(b); bf = b - bi
        sa = SINT[ai & 63] + (SINT[(ai + 1) & 63] - SINT[ai & 63]) * af
        sb = SINT[bi & 63] + (SINT[(bi + 1) & 63] - SINT[bi & 63]) * bf
        LR.obj_move(i, int(round(160 - w // 2 + ox + sa * 140 / 127)),
                       int(round(120 - w // 2 + oy + sb * 100 / 127)))
def label_update(lines, row=1):
    global labels
    col = ((sx0 >> 3) + 1) & 63
    if labels.get(row) == [col, lines]:
        return
    for r in range(row, row + len(lines)):
        grid_row(r)
    for r, s in enumerate(lines):
        for i, ch in enumerate(s[:31]):
            LR.map(0, (col + i) & 63, row + r, ord(ch), 0)
    labels[row] = [col, list(lines)]
def lowres_init(light):
    global lr_on, table, scroll, sx0, bg, t0, ph, wphase, wave_on, olast, oph
    LR.bg_visible(0, False); LR.bg_visible(1, False); LR.obj_visible = False
    ramp(0, 31, 31, 31); ramp(1, 8, 31, 12); ramp(2, 31, 22, 6); ramp(3, 10, 18, 31); ramp(4, 31, 10, 10)
    load_font(False)
    disc(256, 64); disc(320, 32); disc(336, 16); disc(340, 8)
    build_map()
    lr_on = True; table = False; scroll = True; sx0 = 0
    if light:
        bg = 1; show_bg()
    else:
        bg = 3; show_bg()
        setup_objects(False)
    t0 = M.ms(); ph = 0; wphase = 0; wave_on = False
    olast = M.ms(); oph = 0.0
def lowres_tick(label):
    global ph, sx0, wphase, wave_on, oph, olast
    if scroll and not table:
        ph = (M.ms() - t0) * 60 // 1000
        sx0 = (512 - ph // 4) & 511
        LR.scroll(1, ph & 511, (ph // 4) & 511)
        LR.scroll(0, sx0, 0)
        LR.raster_wave(0, WAVE0, wphase)
        wphase = (wphase + 1) % 512
        wave_on = True
    elif wave_on:
        LR.raster_clear()
        wave_on = False
    now = M.ms()
    oph += (now - olast) * 60 / 1000.0 / odiv
    olast = now
    if obj_demo == 1:
        pad_objects()
        move_objects(oph)
    if not table:
        label_update(label)
        if keylab:
            label_update(keylab, KEYLAB_ROW)
def show_bg():
    LR.bg_visible(0, lr_on and (bg & 1) != 0 and not table)
    LR.bg_visible(1, lr_on and (bg & 2) != 0)
def lowres_key(c):
    global lr_on, bg, table, obj_demo, obj_count, scroll, t0, font_bold
    if c == ord("l"):
        lr_on = not lr_on; show_bg(); LR.obj_visible = lr_on and obj_demo != 0
    elif c == ord("b"):
        bg = (bg + 1) % 4; show_bg()
    elif c == ord("f"):
        load_font(not font_bold)
    elif c == ord("F"):
        table = not table
        if table:
            build_font_table(); LR.scroll(1, 0, 0)
        else:
            build_map()
        show_bg()
    elif c == ord("o"):
        if obj_demo != 1:
            obj_count = 24; setup_objects(False)
        elif obj_count >= 128:
            obj_demo = 0; LR.obj_visible = False
        else:
            obj_count = min(obj_count * 2, 128); setup_objects(False)
    elif c == ord("O"):
        if obj_demo == 2:
            obj_demo = 0; LR.obj_visible = False
        else:
            setup_objects(True)
    elif c == ord("S"):
        scroll = not scroll; t0 = M.ms() - ph * 1000 // 60
    else:
        return False
    return True

# ---- music ----
SONG = "WTF4CH.mid"
def music_start():
    if File.exist(SONG):
        Sound.play(SONG, True)
        print("music: %s (%.1f s, repeated; m pauses)" % (SONG, Sound.length() / 1000.0))
    else:
        print("music: %s is not in %s -- no music" % (SONG, Dir.pwd()))
def music_key(c):
    if c == ord("m") and Sound.playing():
        Sound.resume() if Sound.paused() else Sound.pause()

# ---- the pad (pad 0) ----
PAD_NAMES = {M.PAD_X: "X", M.PAD_A: "A", M.PAD_B: "B", M.PAD_Y: "Y", M.PAD_LB: "LB", M.PAD_RB: "RB",
             M.PAD_LT: "LT", M.PAD_RT: "RT", M.PAD_BACK: "BACK", M.PAD_START: "START", M.PAD_LS: "LS", M.PAD_RS: "RS"}
pad_on = False; pad_chk = 0
def pad_line(short):
    global pad_on, pad_chk
    pad_chk += 1
    if pad_chk % 30 == 1:
        pad_on = M.pad(0) is not None
    if not pad_on:
        return "PAD --" if short else "pad 0: not connected (the F310 needs the D switch)"
    dx, dy = M.pad_dir(0)
    held = " ".join([name for n, name in PAD_NAMES.items() if M.pad_button(0, n)])
    sp = "1" if odiv == 1 else "1/%d" % odiv
    if short:
        return "PAD %+d %+d %s V%s" % (dx, dy, held, sp)
    lx, ly = M.pad_stick(0, "left"); rx, ry = M.pad_stick(0, "right")
    return "pad 0: dir %+d %+d  left %+.2f %+.2f  right %+.2f %+.2f  %s  (speed %s)" % (
        dx, dy, lx, ly, rx, ry, held, sp)

# ---- main loop ----
music_start()
M.text_visible = True
text_demo("m=music t=text pad=move v=speed l=lowres b=BG o=objects O=object S=scroll F=font f=bold q=quit")
for p in range(4):
    status_pad(p, None)
for k in range(4):
    status_msc(k)
key_help((("m", "music pause / resume"), ("t", "text plane on / off"), ("pad", "move the objects (A: middle)"),
          ("v", "object speed 1/4, 1/2, 1"), ("l", "lowres on / off"), ("b", "BG planes (0, 1, both, none)"),
          ("o", "objects (24 .. 128, off)"), ("O", "object load test"), ("S", "scroll on / off"),
          ("F", "font table"), ("f", "bold font"), ("q / ESC", "quit")))
draw_pattern()
lowres_init(False)
lab = None
quit = False
while not quit:
    while True:
        c = M.key()
        if c is None:
            break
        if c == ord("q"):
            quit = True
        else:
            music_key(c)
            key_echo(c)
            if c == ord("t"):
                M.text_visible = not M.text_visible
            if not speed_key(c):
                lowres_key(c)
    if lab is None:
        v = M.video_info(); lab = [v["timing"].upper(), "MODE " + v["mode_name"].upper()]
    lowres_tick(lab)
    status_tick()
    tput(ROW_PADUI, pad_line(False), 11)
    M.vsync()
LR.clear()
Sound.stop()
print("bye")
