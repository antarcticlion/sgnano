# sgnano test application in MicroPython -- mode 1: text only.  Ported from mode1.rb (2026-10-30).
M.set_mode(1)
TA = M.TEXT_BG_TRANSPARENT
def tput(row, s, fg):
    s = s[:74]
    M.text_put(2, row, s + " " * (74 - len(s)), M.tattr(fg, 0, TA))

def text_demo():
    M.text_clear(M.TEXT_CLEAR)
    M.text_put(2, 0, "sgnano  ABCabc012  ｱｲｳｴｵ  あいう漢字ＡＢＣ", M.tattr(15, 0, TA))
    for i in range(16):
        M.text_put(2 + i, 1, " ", M.tattr(0, i))
    M.text_put(19, 1, "m music  q quit", M.tattr(7, 0, TA))

ROW_VIDEO = 3; ROW_FRAME = 4; ROW_SYS = 5; ROW_USB = 6; ROW_KBD = 8; ROW_ECHO = 9
ROW_MOUSE = 10; ROW_MSC = 12; ROW_PAD = 16; ROW_PADUI = 20
echo = ""
keys_n = 0
def status_video(v):
    tput(ROW_VIDEO, "%-22s mode %-16s fb %-6s %d.%03dkHz %.2fHz" % (
        v["timing"], v["mode_name"], v["fb"], v["line_hz"] // 1000, v["line_hz"] % 1000, v["frame_hz"]), 11)
def status_frame(v):
    pm = v["pair_max"]
    tput(ROW_FRAME, "f%-8d ur%-5d st%-5d rc%-3d lt%d/%d  pair %d/%dus" % (
        v["frames"], v["underrun"], v["fifo_stall"], v["recover"], v["late_start"], v["late_render"], pm[0], pm[1]), 11)
def status_sys(s):
    tput(ROW_SYS, "up %ds  mem free %dK (max %dK)" % (s["uptime"], s["mem_free"] // 1024, s["mem_largest"] // 1024), 10)
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
def status_pad(k):
    pd = M.pad(k)
    if not pd:
        tput(ROW_PAD + k, "p%d --" % k, 14)
        return
    s = "p%d %04X:%04X h%d" % (k, pd["vid"], pd["pid"], pd["hat"])
    for i, a in enumerate(pd["axes"]):
        if a:
            s += " %s%+4d" % (("X", "Y", "Z", "Rx", "Ry", "Rz")[i], a)
    n = pd["buttons_n"]
    if n > 0:
        s += " "
        for i in range(min(n, 20)):
            s += str((i % 9) + 1) if ((pd["buttons"] >> i) & 1) else "."
    tput(ROW_PAD + k, s, 14)

def key_echo(c):
    global echo, keys_n
    keys_n += 1
    echo += chr(c) if 0x20 <= c < 0x7F else "."
    if len(echo) > 60:
        echo = echo[-60:]

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

text_demo()
music_start()
print("keys: m music pause  q / ESC quit")
slow = 0
nxt = M.ms()
quit = False
while not quit:
    while True:
        c = M.key()
        if c is None:
            break
        if c == ord("q"):
            quit = True
            break
        key_echo(c)
        music_key(c)
    v = M.video_info()
    s = M.sys_info()
    k = slow % 11
    slow += 1
    if k == 0: status_video(v)
    elif k == 1: status_sys(s)
    elif k == 2: status_usb(s)
    elif k < 7: status_msc(k - 3)
    status_frame(v)
    status_kbd(s)
    status_mouse()
    if s["pads"] > 0 or k >= 7:
        for p in range(4):
            if M.pad(p) or k == 7 + p:
                status_pad(p)
    M.vsync()
Sound.stop()
print("bye")
