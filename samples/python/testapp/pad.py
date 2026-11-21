# Pad helpers on the device (MicroPython port, 2026-10-30).  Ported from samples/ruby/pad.rb.
# Press the buttons, move the sticks. q ends it (ESC also stops).
# Nothing is printed inside the loop: print writes at the terminal's cursor and broke the rows (2026-11-20).
NAMES = {M.PAD_X: "X", M.PAD_A: "A", M.PAD_B: "B", M.PAD_Y: "Y", M.PAD_LB: "LB", M.PAD_RB: "RB",
         M.PAD_LT: "LT", M.PAD_RT: "RT", M.PAD_BACK: "BACK", M.PAD_START: "START", M.PAD_LS: "LS", M.PAD_RS: "RS",
         M.PAD_UP: "UP", M.PAD_DOWN: "DOWN", M.PAD_LEFT: "LEFT", M.PAD_RIGHT: "RIGHT"}
M.text_clear()
M.text_put(0, 0, "pad test: press the buttons and move the sticks. q to quit", M.tattr(15, 1))
log = []
while True:
    k = M.key()
    if k == ord("q"):
        break
    M.vsync()
    for i in range(4):
        d = M.pad(i)
        if not d:
            M.text_put(0, 2 + i * 3, ljust("pad %d: --" % i, 79), M.tattr(8))
            continue
        held = " ".join([name for n, name in NAMES.items() if M.pad_button(i, n)])
        dx, dy = M.pad_dir(i)
        lx, ly = M.pad_stick(i, "left"); rx, ry = M.pad_stick(i, "right")
        M.text_put(0, 2 + i * 3, ljust("pad %d: %04X:%04X  dir [%d, %d] held %s" % (
            i, d["vid"], d["pid"], dx, dy, held), 79), M.tattr(15))
        M.text_put(0, 3 + i * 3, ljust("        left %+.2f %+.2f   right %+.2f %+.2f" % (
            lx, ly, rx, ry), 79), M.tattr(14))
        for n, name in NAMES.items():
            e = "pressed" if M.pad_pressed(i, n) else "released" if M.pad_released(i, n) else None
            if not e:
                continue
            s = "pad %d %s %s" % (i, name, e)
            log.append(s)
            while len(log) > 8:
                log.pop(0)
    for k, s in enumerate(log):
        M.text_put(0, 18 + k, ljust(s, 79), M.tattr(10))
print("PAD done")
