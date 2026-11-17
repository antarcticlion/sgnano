# Screen mode 7 (MicroPython port, 2026-10-30): text (25 rows) + a 320x200 bitmap,
# 1 byte per pixel (256-color palette).  Ported from samples/ruby/mode7.rb.
# q (or ESC) ends it; it also ends after about 10 seconds.
M.mode = 7
bm = M.bitmap
ng = 0
def check(what, got, want):
    global ng
    if got != want:
        print("NG %s: got %r, want %r" % (what, got, want))
        ng += 1

check("size", [bm.width, bm.height], [320, 200])
check("text rows", M.text_rows(), 25)
bm.clear(0)
check("clear", bm.pget(319, 199), 0)
bm.pset(10, 20, 200)
check("pset", bm.pget(10, 20), 200)
check("pget outside", bm.pget(320, 0), None)
bm.fill_rect(100, 50, 8, 4, 77)
check("fill_rect inside", bm.pget(107, 53), 77)
check("fill_rect edge", bm.pget(108, 53), 0)
bm.fill_rect(-5, -5, 10, 10, 5)          # clipped at the top-left corner
check("fill_rect clip", [bm.pget(0, 0), bm.pget(4, 4), bm.pget(5, 5)], [5, 5, 0])
bm.line(0, 199, 319, 0, 9)
check("line ends", [bm.pget(0, 199), bm.pget(319, 0)], [9, 9])
bm.rect(200, 100, 20, 10, 33)
check("rect", [bm.pget(200, 100), bm.pget(219, 109), bm.pget(210, 105)], [33, 33, 0])
check("write", bm.write(320 * 150 + 10, b"\x01\x02\x03"), 3)
check("read", list(bm.read(320 * 150 + 10, 3)), [1, 2, 3])
check("write at the end", bm.write(63999, b"\x07\x08"), 1)
bm.palette(250, 255, 0, 0)
check("palette", bm.palette(250), [255, 0, 0])
check("default palette 15", bm.palette(15), [255, 255, 255])
try:
    bm.palette(256, 0, 0, 0)
    check("palette 256 raises", True, False)
except ValueError:
    pass
print("mode7 checks: all ok" if ng == 0 else "mode7 checks: %d NG" % ng)

# ---- demo ----
bm.clear(0)
for r in range(16):                      # the 256 colors as 16x16 swatches (8x6 each), at the top left
    for c in range(16):
        bm.fill_rect(c * 8, r * 6, 8, 6, r * 16 + c)
# a plasma on the right that uses colors 16..231 (the 6x6x6 cube), drawn a row at a time with write
row = bytearray(192)
for y in range(96):
    for x in range(192):
        row[x] = 16 + ((x * 3 + y * 5 + (x * y) // 40) % 216)
    bm.write(y * 320 + 128, row)
for k in range(20):
    bm.line(0, 100 + k * 5, 319, 199 - k * 5, 232 + k)
M.text_clear()
M.text_put(0, 0, "SCREEN MODE 7  320x200x8 + text 80x25", M.tattr(15, 1))
M.text_put(0, 24, "q: quit   (the bottom text row is row 24)", M.tattr(14))
t0 = M.ms()
f = 0
while True:
    k = M.key()
    if k == ord("q") or M.ms() - t0 > 10000:
        break
    M.vsync()
    f += 1
    # turn the plasma colors (16..231) round: 216 palette writes a frame
    for i in range(216):
        c = (i + f) % 216
        bm.palette(16 + i, (c * 7) % 256, (c * 3) % 256, 255 - (c * 5) % 256)
M.text_clear()
print("MODE7 done")
