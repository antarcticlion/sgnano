# Machine の 3 言語の突き合わせ（Ruby 版、2026-11-01）。docs/machine_api.md。api.py・api.bas と同じ行を出す
M = Machine
def b(v) = v ? 1 : 0
def o(k, v) = puts("#{k}=#{v}")
M.mode = 3
o "key1", M.key_name(0x81); o "key2", M.key_name(0x41); o "key3", M.key_name(0x0D); o "key4", M.key_name(0x03)
o "tattr", M.tattr(14, 1, M::TEXT_BOLD)
o "c1", M::TEXT_BOLD; o "c2", M::PAD_A; o "c3", M::PAD_UP; o "c4", M::KEY_F12; o "c5", M::TEXT_UNDERLINE
o "c6", M::TEXT_DOUBLE_WIDTH; o "c7", M::TEXT_GRAY; o "c8", M::TEXT_CLEAR; o "c9", M::TEXT_DEFAULT
o "rgb1", M.rgb(255, 0, 0); o "rgb2", M.rgb(0, 255, 0)
o "pages", M.pages; M.write_page = 1; M.vsync; o "wp", M.write_page; M.write_page = 0; M.vsync; o "wp0", M.write_page
fb = M.fb
o "bits", fb.bits_per_pixel; o "bytes", fb.bytes_per_pixel; o "fbw", fb.width; o "fbh", fb.height
fb.clear(0); fb.pset(10, 10, 5); o "pget", fb.pget(10, 10)
fb.fill_rect(20, 20, 10, 10, 7); o "fill", fb.pget(25, 25)
fb.line(0, 50, 9, 50, 3); o "line", fb.pget(5, 50)
fb.rect(40, 40, 10, 10, 4); o "rect", fb.pget(40, 45)
fb.fill_triangle(60, 60, 80, 60, 70, 80, 6); o "tri", fb.pget(70, 65)
fb.triangle(90, 60, 110, 60, 100, 80, 2); o "tri2", fb.pget(100, 60)
fb.blit(20, 20, 10, 10, 200, 200, 0); o "blit", fb.pget(205, 205)
blk = fb.get_block(20, 20, 4, 4); fb.put_block(300, 300, 4, 4, blk); o "block", fb.pget(301, 301)
M.fb_palette(5, 255, 0, 0); o "fbpal", (M.fb_palette(5) == [255, 0, 0] ? 1 : 0)
lr = M.lowres
o "lrready", b(lr.ready?); o "lrw", lr.width; o "lrh", lr.height; o "lrtiles", b(lr.tiles > 0); o "lrpals", b(lr.palettes > 0)
lr.palette(0, 1, 255, 255, 255)
lr.pattern(300, Array.new(64) { |i| i % 2 })
lr.map(0, 1, 2, 300, 3, true, false); o "map", lr.map_get(0, 1, 2).join(",")
lr.fill_map(1, 5, 2); o "fill_map", lr.map_get(1, 0, 0)[0, 2].join(",")
lr.obj(5, 10, 20, 300, 8, 8, 1, 0); g = lr.obj_get(5); o "obj", "#{g[0]},#{g[1]},#{g[2]},#{b(g[3])}"
lr.obj_move(5, 30, 40); g = lr.obj_get(5); o "objmove", "#{g[0]},#{g[1]}"
lr.obj_hide(5); o "objhide", b(lr.obj_get(5)[3])
lr.obj_visible = true; o "objvis", b(lr.obj_visible)
lr.scroll(0, 3, 4); lr.bg_visible(0, true); lr.raster_wave(0, ([128] * 16).pack("C*"), 0); lr.backdrop(10, 0, 0, 64); lr.raster(0, 20, 0, 1, 1); lr.raster_clear
lr.clear; o "lrclear", lr.map_get(0, 1, 2)[0]
M.text_color(14, 1); o "tcolor", M.text_attr & 0xFF
M.text_put(0, 26, "XYZ", M.tattr(7)); o "tget", M.text_get(1, 26)[0]
M.locate(5, 6); c = M.cursor; o "cursor", "#{c[0]},#{c[1]}"
o "padx", M.pad_dir(0)[0]; o "pada", M.pad_axis(0, 0).to_i; o "pads", M.pad_stick(0, :left)[0].to_i; o "padb", b(M.pad_button?(0, 1))
o "clock", b(M.clock_set? == true || M.clock_set? == false)
o "vinfo", b(M.video_info[:timing].size > 0); o "sinfo", b(M.sys_info[:uptime] > 0)
o "mouse", b(M.mouse[:connected] == true || M.mouse[:connected] == false)
# PIO2（ABI 5.0）: ピンを使わない自己テスト（pull block / mov isr, osr / push block の 3 語）
pio = M::PIO2
o "pio2", b(pio.available?)
if pio.available?
  pio.sm_claim(0)
  off = pio.load([0x80A0, 0xA0C7, 0x8020])
  o "pio2load", (off >= 0 ? 1 : 0)
  pio.sm_config(0, off, 1, 0, off + 2, off, 0)
  pio.sm_enable(0, true)
  pio.sm_put(0, 0x12345678)
  got = nil
  1000.times { got = pio.sm_get(0); break if got }
  o "pio2fifo", (got == 0x12345678 ? 1 : 0)
  pio.sm_enable(0, false)
  pio.sm_unclaim(0)
end

# ADC（ABI 5.1/5.2）: 単発と、既定 L/R の 100ms 取り込み、温度。C ボードでは A6/A7 も。
adc = M::ADC
o "adcpins", adc.pins.join(",")
p0 = adc.pins[0]
v = adc.read(p0)
o "adcread", (v && v >= 0 && v <= 4095 ? 1 : 0)
t = adc.temperature
o "adctemp", (t && t > -40.0 && t < 150.0 ? 1 : 0)
r = adc.start
o "adcstart", (r == 0 ? 1 : 0)
if r == 0
  M.vsync(6)
  st = adc.stats
  o "adcframes", (st[:frames] > 0 ? 1 : 0)
  adc.stop
end
if adc.can_read?(46)
  r = adc.start(40, 41)
  o "adca6", (r == 0 ? 1 : 0)
  if r == 0
    M.vsync(6)
    st = adc.stats
    o "adca6frames", (st[:frames] > 0 ? 1 : 0)
    adc.stop
  end
end
M.mode = 7
bm = M.bitmap
o "bmready", b(bm.ready?); o "bmw", bm.width; o "bmh", bm.height
bm.pset(1, 1, 9); o "bmpget", bm.pget(1, 1)
bm.write(640, "ABC"); o "bmread", bm.read(640, 3)
bm.palette(9, 0, 255, 0); o "bmpal", (bm.palette(9) == [0, 255, 0] ? 1 : 0)
# 音楽の口（ABI 4.4、2026-11-18 に 3 言語で突き合わせ）。定数と、鳴っていないときの様子
o "musicconst", M::Music::MP3 + M::Music::OGG * 10 + M::Music::WAV * 100 + M::Music::VGM * 1000 + M::Music::LOOP * 10000
o "musicidle", b(M::Music.playing?) + b(M::Music.paused?) * 2 + M::Music.position * 4 + M::Music.length * 8 + M::Music.format * 16
M.mode = 1
puts "API-END"
