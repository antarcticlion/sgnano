# Screen modes 4, 5 and 6 (2026-10-17).
#   4: text + lowres + CLUT4 framebuffer (4 bits a pixel, colors 0..15, the PC-98 16 colors by default)
#   5: text + lowres (no framebuffer on the screen)
#   6: lowres only (320x240 native timing; the text plane is not shown, the output goes to the UART log)
# Checks with pget / map_get / obj_get; the results are printed at the end.
$res = []
def check(name, cond) = $res << [name, cond]
M = Machine
fb = M.fb

# ---- mode 4: CLUT4 ----
M.mode = 4
check "mode 4", M.mode == 4
check "CLUT4: 4 bits a pixel", fb.bits_per_pixel == 4 && fb.bytes_per_pixel == 1
check "default palette: 0 is black, 15 is white", M.fb_palette(0) == [0, 0, 0] && M.fb_palette(15) == [255, 255, 255]
check "default palette: 9 is bright blue", M.fb_palette(9) == [0, 0, 255]
fb.clear(0)
fb.pset(10, 10, 12)
fb.pset(11, 10, 3)
check "pset / pget: two pixels in a byte", fb.pget(10, 10) == 12 && fb.pget(11, 10) == 3 && fb.pget(12, 10) == 0
fb.pset(20, 20, 31)
check "pset keeps the low 4 bits", fb.pget(20, 20) == 15
fb.fill_rect(101, 100, 50, 3, 7)                   # odd left edge, even right edge (101..150)
check "fill_rect: the edges", fb.pget(100, 100) == 0 && fb.pget(101, 100) == 7 && fb.pget(150, 102) == 7 && fb.pget(151, 100) == 0
fb.line(0, 200, 639, 200, 9)
check "line", fb.pget(0, 200) == 9 && fb.pget(639, 200) == 9 && fb.pget(320, 201) == 0
fb.rect(300, 300, 21, 11, 4)
check "rect", fb.pget(300, 300) == 4 && fb.pget(320, 310) == 4 && fb.pget(310, 305) == 0
fb.fill_triangle(400, 10, 380, 60, 420, 60, 5)
check "fill_triangle", fb.pget(400, 40) == 5 && fb.pget(370, 40) == 0
b = fb.get_block(101, 100, 4, 2)
check "get_block: a byte a pixel", b.bytesize == 8 && b.getbyte(0) == 7 && b.getbyte(7) == 7
fb.put_block(501, 400, 4, 2, b)
check "put_block at an odd x", fb.pget(500, 400) == 0 && fb.pget(501, 400) == 7 && fb.pget(504, 401) == 7 && fb.pget(505, 400) == 0
fb.blit(100, 100, 52, 3, 200, 250)                 # even to even: a byte at a time
check "blit (even)", fb.pget(201, 250) == 7 && fb.pget(250, 252) == 7 && fb.pget(200, 250) == 0
fb.blit(100, 100, 52, 3, 301, 250)                 # even to odd: a pixel at a time
check "blit (odd)", fb.pget(302, 250) == 7 && fb.pget(351, 252) == 7 && fb.pget(301, 250) == 0
fb.fill_rect(400, 250, 10, 10, 2)
fb.blit(100, 99, 20, 20, 395, 245, nil, 0)         # 0 is transparent
check "blit with a transparent color", fb.pget(400, 250) == 2 && fb.pget(402, 246) == 7
fb.blit(101, 100, 10, 1, 103, 100)                 # overlapping, to the right
check "blit overlapping", (103..112).all? { |x| fb.pget(x, 100) == 7 }
M.fb_palette(1, 255, 128, 0)
check "fb_palette in mode 4", M.fb_palette(1)[0] == 255 && M.fb_palette(1)[2] == 0
check "clear", (fb.clear(6); fb.pget(320, 240) == 6 && fb.pget(639, 479) == 6)
lr = M.lowres
check "mode 4: lowres ready", lr.ready? && lr.tiles >= 512

# ---- mode 5: text + lowres ----
M.mode = 5
check "mode 5", M.mode == 5
check "mode 5: the framebuffer is RGB555 (not shown)", fb.bits_per_pixel == 16
check "mode 5: lowres ready", lr.ready? && lr.palettes == 64
lr.palette(0, 1, 255, 255, 0)
lr.pattern(1, Array.new(64, 1))
lr.map(0, 1, 1, 1)
check "mode 5: map", lr.map_get(0, 1, 1)[0] == 1
lr.obj(3, 50, 60, 1, 8, 8, 0, 0, false, false)
check "mode 5: obj", lr.obj_get(3) == [50, 60, 1, true]

# ---- mode 6: lowres only ----
M.mode = 6
check "mode 6", M.mode == 6
check "mode 6: lowres ready", lr.ready? && lr.width == 320 && lr.height == 240
check "mode 6: the text plane is not shown", M.text_visible? == false
lr.scroll(0, 8, 8)
check "mode 6: map kept", lr.map_get(0, 1, 1)[0] == 1
lr.clear

M.mode = 2
check "back to mode 2: 16 bits a pixel", fb.bits_per_pixel == 16
ng = 0
$res.each { |n, ok| puts "#{ok ? 'ok' : 'NG'} #{n}"; ng += 1 unless ok }
puts ng == 0 ? "all ok" : "#{ng} NG"
