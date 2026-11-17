# Pen tablet (MicroPython port, 2026-10-30).  Ported from samples/ruby/tablet.rb.
# Draw with the pen, the pressure sets the size. The eraser (the back of the pen) erases.
# Pad button 1 clears the page, pad button 2 changes the color, the wheel changes the size.
# The pen buttons pick the color too (1 = red, 2 = blue). q ends it (ESC also stops).
M.mode = 2
fb = M.fb
fb.clear()
colors = [M.rgb(255, 255, 255), M.rgb(255, 80, 80), M.rgb(80, 160, 255), M.rgb(120, 255, 120), M.rgb(255, 220, 60)]
ci = 0
size = 6
last = None
pad_was = 0
M.text_clear()
while True:
    k = M.key()
    if k == ord("q"):
        break
    M.vsync()
    t = M.tablet()
    if not t["connected"]:
        M.text_put(0, 0, ljust("no tablet -- plug a Wacom Graphire / Bamboo in", 79), M.tattr(14))
        continue
    pad = t["pad"]
    if (pad & 1) != 0 and (pad_was & 1) == 0:
        fb.clear()
        last = None
    if (pad & 2) != 0 and (pad_was & 2) == 0:
        ci = (ci + 1) % len(colors)
    pad_was = pad
    size = max(1, min(6 + t["wheel"], 30))
    x = t["x"] * 640 // (t["x_max"] or 1)
    y = t["y"] * 480 // (t["y_max"] or 1)
    if t["proximity"] and t["tip"]:
        r = 1 + size * t["pressure"] // (t["pressure_max"] or 1)
        if t["tool"] == "eraser":
            color = 0
        elif t["button1"]:
            color = colors[1]
        elif t["button2"]:
            color = colors[2]
        else:
            color = colors[ci]
        if t["tool"] == "eraser":
            r = size * 2
        if last:
            # 前の点からいまの点まで、間を埋める
            n = max(abs(x - last[0]), abs(y - last[1]), 1) // max(r // 2, 1)
            if n < 1:
                n = 1
            for k in range(n):
                px = last[0] + (x - last[0]) * (k + 1) // n
                py = last[1] + (y - last[1]) * (k + 1) // n
                fb.fill_rect(px - r // 2, py - r // 2, r, r, color)
        else:
            fb.fill_rect(x - r // 2, y - r // 2, r, r, color)
        last = (x, y)
    else:
        last = None
    tool = str(t["tool"]) if t["proximity"] else "-"
    M.text_put(0, 0, ljust("%s %s  tool %-6s x %5d y %5d  pressure %3d  tip %d b1 %d b2 %d  pad %d  wheel %+d  size %d" % (
        t["name"], "ready" if t["ready"] else "(switching)", tool, t["x"], t["y"], t["pressure"],
        1 if t["tip"] else 0, 1 if t["button1"] else 0, 1 if t["button2"] else 0, pad, t["wheel"], size), 79),
        M.tattr(15))
M.text_clear()
print("TABLET done")
