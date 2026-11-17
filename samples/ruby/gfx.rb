# Primitive drawing (2026-11-13, SPEC_gfx.md): the Machine drawing methods checked with pget.
# FrameBuffer (mode 2 = RGB555, mode 3 = CLUT8), Bitmap (mode 7) and Machine::Image.
# The same checks are in samples/python/gfx.py and samples/basic/gfx.bas.
M = Machine
$ng = 0
def check(name, cond)
  puts "#{cond ? 'ok' : 'NG'} #{name}"
  $ng += 1 unless cond
end

M.mode = 2
fb = M.fb
fb.clear
white = fb.rgb(31, 31, 31); red = fb.rgb(31, 0, 0); blue = fb.rgb(0, 0, 31); green = fb.rgb(0, 31, 0)

# --- closed shapes: outline with the pen, inside with the brush; right and bottom are not included ---
fb.pen(white).brush(red)
fb.rectangle(10, 10, 50, 40)
check "rectangle outline", fb.pget(10, 10) == white && fb.pget(49, 39) == white && fb.pget(50, 40) == 0
check "rectangle inside", fb.pget(30, 25) == red
fb.pen(white, 1, M::PS_NULL).brush(blue)
fb.ellipse(100, 10, 200, 90)
check "ellipse without a pen", fb.pget(150, 50) == blue && fb.pget(101, 11) == 0 && fb.pget(100, 50) == blue
fb.pen(green).brush(0, M::BS_NULL)
fb.round_rect(220, 10, 300, 70, 30, 30)
check "round rect: hollow, corners cut", fb.pget(260, 10) == green && fb.pget(260, 40) == 0 && fb.pget(220, 10) == 0
fb.pen(white, 1, M::PS_NULL).brush(red)
fb.polygon([[320, 10], [400, 10], [360, 70]])
check "polygon", fb.pget(360, 30) == red && fb.pget(330, 60) == 0
fb.pie(420, 10, 520, 110, 520, 60, 470, 10)   # right to top: the upper right quarter
check "pie", fb.pget(495, 35) == red && fb.pget(445, 85) == 0
fb.fill_rule(M::FILL_EVENODD)
fb.polygon([540, 10, 620, 10, 620, 90, 540, 90, 560, 30, 600, 30, 600, 70, 560, 70, 560, 30, 540, 10])
fb.fill_rule(M::FILL_NONZERO)

# --- lines and curves ---
fb.pen(white)
fb.move_to(10, 120).line_to(100, 120)
check "move_to / line_to", fb.pget(10, 120) == white && fb.pget(100, 120) == white
fb.polyline([[10, 130], [60, 130], [60, 160]])
check "polyline", fb.pget(60, 145) == white
fb.poly_bezier([10, 230, 40, 170, 90, 170, 120, 230])
check "poly_bezier ends", fb.pget(10, 230) == white && fb.pget(120, 230) == white
fb.pen(green, 9).pen_ext(M::CAP_FLAT, M::JOIN_MITER)
fb.move_to(150, 140).line_to(300, 140)
check "wide pen (9)", fb.pget(200, 136) == green && fb.pget(200, 144) == green && fb.pget(200, 146) == 0
fb.pen(white, 1, M::PS_DASH)
fb.move_to(150, 170).line_to(400, 170)
check "dashed pen", fb.pget(150, 170) == white && fb.pget(170, 170) != white

# --- path with a matrix (PostScript-like): a unit square scaled by 40 and moved ---
fb.pen(white, 1, M::PS_NULL).brush(blue).matrix(40.0, 0.0, 0.0, 40.0, 450.0, 150.0)
fb.begin_path.path_move_to(0, 0).path_line_to(1, 0).path_line_to(1, 1).path_line_to(0, 1).close_path.fill_path
fb.reset_matrix
check "path through the matrix", fb.pget(450, 150) == blue && fb.pget(489, 189) == blue && fb.pget(490, 190) != blue
fb.begin_path.path_move_to(560.5, 150).path_quad_to(620, 150, 620, 200).path_cubic_to(620, 230, 560, 230, 560, 200).close_path
fb.brush(green).fill_path
check "quad and cubic path", fb.pget(600, 190) == green

# --- anti-aliasing (RGB555 mixes the edge) ---
fb.aa(true).brush(white).pen(0, 1, M::PS_NULL)
fb.ellipse(10, 250, 110, 330)
fb.aa(false)
edge = (250..330).map { |y| fb.pget(10 + 50 - Math.sqrt([2500 - ((y - 290) * 50.0 / 40) ** 2, 0].max).round, y) }
check "anti-aliased edge has in-between colours", edge.any? { |v| v != 0 && v != white }

# --- text ---
fb.font(M::FONT_ROM, 32).text_color(white)
fb.bk(M::BK_TRANSPARENT)
fb.text_out(150, 260, "Ag")
w, h = fb.text_extent("Ag")
check "text_extent", w > 0 && h == 32
check "text_out draws", (150...150 + w).any? { |x| (260...292).any? { |y| fb.pget(x, y) == white } }
r = fb.draw_text("one two three four", 300, 260, 380, 400, M::DT_WORDBREAK | M::DT_CALCRECT)
check "draw_text CALCRECT", r.is_a?(Array) && r[3] > 260 + 32
fb.font(M::FONT_8X8, 8)
hgt = fb.draw_text("left\ncentre\nright", 400, 260, 480, 300, M::DT_CENTER)
check "draw_text lines", hgt == 24

# --- images: create, draw into, bitblt / stretch_blt to the FB ---
im = M::Image.new(16, 16)
check "image size", im.width == 16 && im.height == 16
im.clear(blue)
im.pen(red).brush(red).rectangle(4, 4, 12, 12)
fb.bitblt(10, 350, 16, 16, im)
check "bitblt from an image", fb.pget(10, 350) == blue && fb.pget(18, 358) == red
fb.stretch_blt(40, 350, 32, 32, im, 0, 0, 16, 16)
check "stretch_blt x2", fb.pget(40, 350) == blue && fb.pget(56, 366) == red && fb.pget(71, 381) == blue
fb.bitblt(80, 350, 16, 16, im, 0, 0, M::SRCCOPY, blue)   # blue is transparent
check "transparent key", fb.pget(80, 350) == 0 && fb.pget(88, 358) == red
fb.draw_dib(100, 350, 4, 1, "\xFF\x00\x00\x00\xFF\x00\x00\x00\xFF\xFF\xFF\xFF", M::DIB_RGB888, 4, 1)
check "draw_dib RGB888", fb.pget(100, 350) == fb.rgb(31, 0, 0) && fb.pget(103, 350) == fb.rgb(31, 31, 31)
im.free

# --- CLUT8 (mode 3) and the bitmap (mode 7): skipped when the mode cannot be opened (SRAM) ---
def try_mode(m)
  M.mode = m
  true
rescue => e
  puts "skip mode #{m}: #{e.message}"
  false
end
if try_mode(3)
  fb.clear(0)
  fb.pen(15).brush(4)
  fb.rectangle(10, 10, 30, 30)
  check "CLUT8 rectangle", fb.pget(10, 10) == 15 && fb.pget(20, 20) == 4
end
if try_mode(7)
  bm = M.bitmap
  bm.clear(0)
  bm.pen(15).brush(9).ellipse(100, 50, 220, 150)
  check "bitmap ellipse", bm.pget(160, 100) == 9 && bm.pget(100, 100) == 15
end
M.mode = 1
puts $ng == 0 ? "gfx: all ok" : "gfx: #{$ng} NG"
