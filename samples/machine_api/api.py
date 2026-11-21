# Machine の 3 言語の突き合わせ（Python 版、2026-11-01）。docs/machine_api.md。api.rb・api.bas と同じ行を出す
M = Machine()
def b(v): return 1 if v else 0
def o(k, v): print("%s=%s" % (k, v))
M.mode = 3
o("key1", M.key_name(0x81)); o("key2", M.key_name(0x41)); o("key3", M.key_name(0x0D)); o("key4", M.key_name(0x03))
o("tattr", M.tattr(14, 1, M.TEXT_BOLD))
o("c1", M.TEXT_BOLD); o("c2", M.PAD_A); o("c3", M.PAD_UP); o("c4", M.KEY_F12); o("c5", M.TEXT_UNDERLINE)
o("c6", M.TEXT_DOUBLE_WIDTH); o("c7", M.TEXT_GRAY); o("c8", M.TEXT_CLEAR); o("c9", M.TEXT_DEFAULT)
o("rgb1", M.rgb(255, 0, 0)); o("rgb2", M.rgb(0, 255, 0))
o("pages", M.pages()); M.write_page = 1; M.vsync(); o("wp", M.write_page); M.write_page = 0; M.vsync(); o("wp0", M.write_page)
fb = M.fb
o("bits", fb.bits_per_pixel); o("bytes", fb.bytes_per_pixel); o("fbw", fb.width); o("fbh", fb.height)
fb.clear(0); fb.pset(10, 10, 5); o("pget", fb.pget(10, 10))
fb.fill_rect(20, 20, 10, 10, 7); o("fill", fb.pget(25, 25))
fb.line(0, 50, 9, 50, 3); o("line", fb.pget(5, 50))
fb.rect(40, 40, 10, 10, 4); o("rect", fb.pget(40, 45))
fb.fill_triangle(60, 60, 80, 60, 70, 80, 6); o("tri", fb.pget(70, 65))
fb.triangle(90, 60, 110, 60, 100, 80, 2); o("tri2", fb.pget(100, 60))
fb.blit(20, 20, 10, 10, 200, 200, 0); o("blit", fb.pget(205, 205))
blk = fb.get_block(20, 20, 4, 4); fb.put_block(300, 300, 4, 4, blk); o("block", fb.pget(301, 301))
M.fb_palette(5, 255, 0, 0); o("fbpal", 1 if list(M.fb_palette(5)) == [255, 0, 0] else 0)
lr = M.lowres
o("lrready", b(lr.ready)); o("lrw", lr.width); o("lrh", lr.height); o("lrtiles", b(lr.tiles > 0)); o("lrpals", b(lr.palettes > 0))
lr.palette(0, 1, 255, 255, 255)
lr.pattern(300, bytes([i % 2 for i in range(64)]))
lr.map(0, 1, 2, 300, 3, True, False); m = lr.map_get(0, 1, 2); o("map", "%d,%d,%s,%s" % (m[0], m[1], "true" if m[2] else "false", "true" if m[3] else "false"))
lr.fill_map(1, 5, 2); m = lr.map_get(1, 0, 0); o("fill_map", "%d,%d" % (m[0], m[1]))
lr.obj(5, 10, 20, 300, 8, 8, 1, 0); g = lr.obj_get(5); o("obj", "%d,%d,%d,%d" % (g[0], g[1], g[2], b(g[3])))
lr.obj_move(5, 30, 40); g = lr.obj_get(5); o("objmove", "%d,%d" % (g[0], g[1]))
lr.obj_hide(5); o("objhide", b(lr.obj_get(5)[3]))
lr.obj_visible = True; o("objvis", b(lr.obj_visible))
lr.scroll(0, 3, 4); lr.bg_visible(0, True); lr.raster_wave(0, bytes([128] * 16), 0); lr.backdrop(10, 0, 0, 64); lr.raster(0, 20, 0, 1, 1); lr.raster_clear()
lr.clear(); o("lrclear", lr.map_get(0, 1, 2)[0])
M.text_color(14, 1); o("tcolor", M.text_attr() & 0xFF)
M.text_put(0, 26, "XYZ", M.tattr(7)); o("tget", M.text_get(1, 26)[0])
M.locate(5, 6); c = M.cursor(); o("cursor", "%d,%d" % (c[0], c[1]))
o("padx", M.pad_dir(0)[0]); o("pada", int(M.pad_axis(0, 0))); o("pads", int(M.pad_stick(0, "left")[0])); o("padb", b(M.pad_button(0, 1)))
o("clock", b(M.clock_set() in (True, False)))
o("vinfo", b(len(M.video_info()["timing"]) > 0)); o("sinfo", b(M.sys_info()["uptime"] > 0))
o("mouse", b(M.mouse()["connected"] in (True, False)))
# PIO2 (ABI 5.0): a pin-free self test (pull block / mov isr, osr / push block)
pio = M.PIO2
o("pio2", b(pio.available()))
if pio.available():
    pio.sm_claim(0)
    off = pio.load([0x80A0, 0xA0C7, 0x8020])
    o("pio2load", 1 if off >= 0 else 0)
    pio.sm_config(0, off, 1, 0, off + 2, off, 0)
    pio.sm_enable(0, True)
    pio.sm_put(0, 0x12345678)
    got = None
    for _ in range(1000):
        got = pio.sm_get(0)
        if got is not None:
            break
    o("pio2fifo", 1 if got == 0x12345678 else 0)
    pio.sm_enable(0, False)
    pio.sm_unclaim(0)

# ADC (ABI 5.1/5.2): single reads, a 100ms default L/R capture, and temperature. C also tests A6/A7.
adc = M.ADC
pins = adc.pins()
o("adcpins", ",".join(str(p) for p in pins))
v = adc.read(pins[0])
o("adcread", 1 if 0 <= v <= 4095 else 0)
t = adc.temperature()
o("adctemp", 1 if t is not None and -40.0 < t < 150.0 else 0)
r = adc.start()
o("adcstart", 1 if r == 0 else 0)
if r == 0:
    M.vsync(6)
    st = adc.stats()
    o("adcframes", 1 if st["frames"] > 0 else 0)
    adc.stop()
if adc.can_read(46):
    r = adc.start(40, 41)
    o("adca6", 1 if r == 0 else 0)
    if r == 0:
        M.vsync(6)
        st = adc.stats()
        o("adca6frames", 1 if st["frames"] > 0 else 0)
        adc.stop()
M.mode = 7
bm = M.bitmap
o("bmready", b(bm.ready)); o("bmw", bm.width); o("bmh", bm.height)
bm.pset(1, 1, 9); o("bmpget", bm.pget(1, 1))
bm.write(640, b"ABC"); o("bmread", bm.read(640, 3).decode())
bm.palette(9, 0, 255, 0); o("bmpal", 1 if list(bm.palette(9)) == [0, 255, 0] else 0)
# Music (ABI 4.4, checked against Ruby/BASIC on 2026-11-18): constants and the idle state
mus = M.Music
o("musicconst", mus.MP3 + mus.OGG * 10 + mus.WAV * 100 + mus.VGM * 1000 + mus.LOOP * 10000)
o("musicidle", b(mus.playing()) + b(mus.paused()) * 2 + mus.position() * 4 + mus.length() * 8 + mus.format() * 16)
M.mode = 1
print("API-END")
