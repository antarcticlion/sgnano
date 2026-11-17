# Speed table for docs/sgnano_python_guide.md (2026-11-01): the same items as samples/ruby/bench.rb
# in screen mode 1 (no FB), 2 (RGB555 FB shown) and 4 (CLUT4 FB shown).
M = Machine()

def t(label, f):
    t0 = M.ms()
    f()
    print("BENCH %d %s: %d ms" % (M.mode, label, M.ms() - t0))

def loop100k():
    i = 0
    while i < 100000:
        i += 1

for m in (1, 2, 4):
    M.mode = m
    t("while 100k", loop100k)
    if m == 1:
        continue
    fb = M.fb
    c = 7 if m == 4 else M.rgb(255, 255, 0)
    def pset10k():
        for i in range(10000): fb.pset(i % 640, (i // 640) % 480, c)
    def fill1000():
        for i in range(1000): fb.fill_rect((i * 7) % 576, (i * 5) % 432, 64, 48, c)
    def line1000():
        for i in range(1000): fb.line(0, 0, 639, i % 480, c)
    def ftri1000():
        for i in range(1000):
            x = (i * 7) % 576; y = (i * 5) % 432
            fb.fill_triangle(x, y, x + 63, y, x, y + 47, c)
    def ftrifull():
        for i in range(100): fb.fill_triangle(0, 0, 639, 0, 0, 479, c)
    def tri1000():
        for i in range(1000): fb.triangle(0, 0, 639, 240, 100, 479, c)
    def blit1000():
        for i in range(1000): fb.blit(0, 0, 64, 48, (i * 7) % 576, (i * 5) % 432)
    def blitkey1000():
        for i in range(1000): fb.blit(0, 0, 64, 48, (i * 7) % 576, (i * 5) % 432, None, 0)
    blk = [None]
    def get1000():
        for i in range(1000): blk[0] = fb.get_block(0, 0, 64, 48)
    def put1000():
        for i in range(1000): fb.put_block((i * 7) % 576, (i * 5) % 432, 64, 48, blk[0])
    def clear100():
        for i in range(100): fb.clear(0)
    t("pset 10k", pset10k); t("fill_rect 64x48 1000", fill1000); t("line full 1000", line1000)
    t("fill_triangle 64x48 1000", ftri1000); t("fill_triangle full 100", ftrifull); t("triangle 1000", tri1000)
    t("blit 64x48 1000", blit1000); t("blit 64x48 key 1000", blitkey1000)
    t("get_block 64x48 1000", get1000); t("put_block 64x48 1000", put1000); t("clear 100", clear100)
M.mode = 1
print("BENCH done")
