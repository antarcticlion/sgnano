# Screen mode 3 (2026-10-17): CLUT8 framebuffer (1 byte a pixel, palette 0..255) and the lowres plane (Machine.lowres).
# Checks with pget / map_get / obj_get; the results are printed at the end.
$res = []
def check(name, cond) = $res << [name, cond]
M = Machine
M.mode = 3
check "mode 3", M.mode == 3
fb = M.fb
check "CLUT8: 1 byte a pixel", fb.bytes_per_pixel == 1
# default palette: 6x6x6 color cube, then 40 grays
check "default palette: 0 is black", M.fb_palette(0) == [0, 0, 0]
check "default palette: 215 is white", M.fb_palette(215) == [255, 255, 255]
check "default palette: 5 is blue", M.fb_palette(5)[2] == 255 && M.fb_palette(5)[0] == 0
M.fb_palette(250, 255, 128, 0)
p250 = M.fb_palette(250)
check "fb_palette set / get", p250[0] == 255 && p250[2] == 0 && p250[1] > 120 && p250[1] < 136
# drawing with color numbers
fb.clear(0)
fb.pset(10, 10, 200)
check "pset / pget", fb.pget(10, 10) == 200 && fb.pget(11, 10) == 0
fb.fill_rect(100, 100, 50, 30, 17)
check "fill_rect", fb.pget(100, 100) == 17 && fb.pget(149, 129) == 17 && fb.pget(150, 100) == 0
fb.line(0, 200, 639, 200, 33)
check "line", fb.pget(0, 200) == 33 && fb.pget(639, 200) == 33
fb.rect(300, 300, 20, 10, 44)
check "rect", fb.pget(300, 300) == 44 && fb.pget(319, 309) == 44 && fb.pget(310, 305) == 0
fb.fill_triangle(400, 10, 380, 60, 420, 60, 99)
check "fill_triangle", fb.pget(400, 40) == 99
b = fb.get_block(100, 100, 4, 2)
check "get_block: 1 byte a pixel", b.bytesize == 8 && b.getbyte(0) == 17
fb.put_block(500, 400, 4, 2, b)
check "put_block", fb.pget(503, 401) == 17
fb.blit(100, 100, 50, 30, 200, 250)
check "blit", fb.pget(200, 250) == 17 && fb.pget(249, 279) == 17
fb.fill_rect(260, 250, 10, 10, 5)
fb.blit(100, 100, 20, 20, 255, 245, nil, 17)          # 17 is transparent
check "blit with a transparent color", fb.pget(265, 255) == 5
check "clear", (fb.clear(3); fb.pget(320, 240) == 3)

# lowres plane
lr = M.lowres
check "lowres ready", lr.ready? && lr.width == 320 && lr.height == 240
check "lowres tiles / palettes", lr.tiles >= 512 && lr.tiles % 512 == 0 && lr.palettes == 64   # 512..2048 tiles (what the free SRAM allows)
lr.palette(1, 1, 255, 0, 0)
lr.palette(1, 2, 0, 255, 0)
tile = Array.new(64) { |i| (i / 8 + i % 8) % 2 == 0 ? 1 : 2 }   # a checker of colors 1 and 2
check "pattern from an Array", lr.pattern(1, tile) == 64
check "pattern from a String", lr.pattern(2, ([128] * 64).pack("C*")) == 64   # a transparent tile
lr.map(0, 3, 4, 1, 1, true, false)
check "map / map_get", lr.map_get(0, 3, 4) == [1, 1, true, false]
lr.fill_map(1, 2)
check "fill_map", lr.map_get(1, 63, 63) == [2, 0, false, false]
lr.scroll(0, 600, -1)
lr.bg_visible(1, false)
lr.obj_visible = true
sprite = Array.new(16 * 16) { |i| x = i % 16; y = i / 16; (x - 7.5)**2 + (y - 7.5)**2 < 49 ? 1 : 128 }   # a round ball
lr.pattern(10, sprite)
lr.obj(0, 100, 50, 10, 16, 16, 1, 0, false, false)
check "obj / obj_get", lr.obj_get(0) == [100, 50, 10, true]
lr.obj_move(0, 120, 60)
check "obj_move", lr.obj_get(0)[0, 2] == [120, 60]
lr.obj_hide(0)
check "obj_hide", lr.obj_get(0)[3] == false
lr.clear
check "clear: maps back to tile 0", lr.map_get(0, 3, 4)[0] == 0
begin
  lr.obj(0, 0, 0, 0, 12, 8)
  check "obj refuses width 12", false
rescue ArgumentError
  check "obj refuses width 12", true
end
begin
  M.fb_palette(256, 0, 0, 0)
  check "fb_palette refuses 256", false
rescue ArgumentError
  check "fb_palette refuses 256", true
end
M.mode = 2
check "back to mode 2: 2 bytes a pixel", fb.bytes_per_pixel == 2
ng = 0
$res.each { |n, ok| puts "#{ok ? 'ok' : 'NG'} #{n}"; ng += 1 unless ok }
puts ng == 0 ? "all ok" : "#{ng} NG"
