# sgnano test application in MicroPython -- mode 2: text + RGB555 framebuffer.
# Ported from samples/ruby/testapp/mode2.rb (2026-10-30).  M, Sound, File are in the prelude.
# Keys: m music pause, t text on/off. q or ESC ends it.
M.mode = 2

# ---- text demo and status rows ----
TA = M.TEXT_BG_TRANSPARENT
def tput(row, s, fg):                    # a row from column 2, padded to column 76
    s = s[:74]
    M.text_put(2, row, s + " " * (74 - len(s)), M.tattr(fg, 0, TA))
def text_demo(help):
    M.text_clear(M.TEXT_CLEAR)           # transparent: the graphics show through
    M.text_put(2, 0, "sgnano  ABCabc012  ｱｲｳｴｵ  あいう漢字ＡＢＣ", M.tattr(15, 0, TA))
    for i in range(16):
        M.text_put(2 + i, 1, " ", M.tattr(0, i))   # the 16 colors as the background of blank cells
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
    tput(ROW_MOUSE + 1, "x %+7d  y %+7d  wheel %+5d" % (m["x"], m["y"], m["wheel"]), 15)
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
def status_tick():                       # rows that change slowly, one a frame in turn
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
def key_echo(c):                         # the keys typed, at the bottom of the keyboard rows
    global echo, keys_n
    keys_n += 1
    echo += chr(c) if 0x20 <= c < 0x7F else "."
    if len(echo) > 60:
        echo = echo[-60:]

# ---- the keys at the bottom of the screen ----
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
        else:                            # CLUT4: 8..15 = 8 grays, the frame is color 0 (white)
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

# ---- the pad (pad 0): what is pressed now, for the screen ----
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
    if short:
        return "PAD %+d %+d %s" % (dx, dy, held)
    lx, ly = M.pad_stick(0, "left"); rx, ry = M.pad_stick(0, "right")
    return "pad 0: dir %+d %+d  left %+.2f %+.2f  right %+.2f %+.2f  %s" % (dx, dy, lx, ly, rx, ry, held)

# ---- main loop ----
music_start()
M.text_visible = True
text_demo("m=music t=text q=quit")
for p in range(4):
    status_pad(p, None)
for k in range(4):
    status_msc(k)
key_help((("m", "music pause / resume"), ("t", "text plane on / off"), ("q / ESC", "quit")))
draw_pattern()
quit = False
while not quit:
    while True:
        c = M.key()
        if c is None:
            break
        if c == ord("q"):
            quit = True
            break
        music_key(c)
        key_echo(c)
        if c == ord("t"):
            M.text_visible = not M.text_visible
    status_tick()
    tput(ROW_PADUI, pad_line(False), 11)
    M.vsync()
Sound.stop()
print("bye")
