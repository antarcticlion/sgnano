# sgnano test application in MicroPython -- mode 0: nothing on the screen (the sync is kept).
# Ported from samples/ruby/testapp/mode0.rb (2026-10-30).  M, Sound, File are in the prelude.
M.set_mode(0)

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

PAD_NAMES = {M.PAD_X: "X", M.PAD_A: "A", M.PAD_B: "B", M.PAD_Y: "Y", M.PAD_LB: "LB", M.PAD_RB: "RB",
             M.PAD_LT: "LT", M.PAD_RT: "RT", M.PAD_BACK: "BACK", M.PAD_START: "START", M.PAD_LS: "LS", M.PAD_RS: "RS"}
pad_on = False
pad_chk = 0
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
    lx, ly = M.pad_stick(0, "left")
    rx, ry = M.pad_stick(0, "right")
    return "pad 0: dir %+d %+d  left %+.2f %+.2f  right %+.2f %+.2f  %s" % (dx, dy, lx, ly, rx, ry, held)
def pad_events():
    global pad_on, pad_chk
    if not pad_on:
        pad_chk += 1
        if pad_chk % 30 != 1:
            return
        pad_on = M.pad(0) is not None
        if not pad_on:
            return
    names = dict(PAD_NAMES)
    names[M.PAD_UP] = "UP"; names[M.PAD_DOWN] = "DOWN"; names[M.PAD_LEFT] = "LEFT"; names[M.PAD_RIGHT] = "RIGHT"
    for n, name in names.items():
        if M.pad_pressed(0, n):
            print("[testapp] pad 0 %s pressed" % name)
        if M.pad_released(0, n):
            print("[testapp] pad 0 %s released" % name)

music_start()
print("keys: m music pause / resume  q / ESC quit")
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
        music_key(c)
    if M.ms() >= nxt:
        nxt += 1000
        v = M.video_info()
        print("[testapp] %s  f%d ur%d st%d rc%d  pair %d/%dus" % (
            v["timing"], v["frames"], v["underrun"], v["fifo_stall"], v["recover"], v["pair_max"][0], v["pair_max"][1]))
    pad_events()
    M.vsync()
Sound.stop()
print("bye")
